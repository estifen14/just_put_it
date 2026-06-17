terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.70.1" # Using the modern bpg provider compatible with Proxmox 8 and 9
    }
  }
}

provider "proxmox" {
  endpoint = "https://${var.proxmox_host}:8006/"
  insecure = true # Required if using Proxmox default self-signed cert
  
  # bpg/proxmox uses a combined token string: USER@REALM!TOKENID=UUID
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  
  # NEW: SSH config is required by the BPG provider to upload Snippet files to Proxmox
  ssh {
    agent = false # Explicitly set to false so it uses the key file below instead of your Mac's agent
    username = "root" 
    private_key = file("~/.ssh/id_rsa_azure") # Provide the private key path directly
  }
}

# --- Variables ---
variable "proxmox_host" {
  type        = string
  description = "IP address of your Thinkpad L14 Proxmox server"
}

variable "proxmox_token_id" {
  type        = string
  description = "API Token ID (e.g., user@pve!token_name)"
}

variable "proxmox_token_secret" {
  type        = string
  description = "API Token Secret Value"
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "Your Mac's public SSH key content (starts with ssh-rsa or ssh-ed25519)"
}

variable "k3s_cluster_secret" {
  type        = string
  description = "A strong random password used to connect worker nodes to the master node."
  sensitive   = true
}

# =====================================================================
# CLOUD-INIT SNIPPETS (The Industry Standard Bootstrap)
# =====================================================================

# 1. Generate the Cloud-Init file for the MASTER node
resource "proxmox_virtual_environment_file" "master_cloud_config" {
  content_type = "snippets"
  datastore_id = "local" # The default storage location in Proxmox that accepts snippets
  node_name    = "pve"

  source_raw {
    data = <<-EOF
    #cloud-config
    runcmd:
      - echo "Bootstrapping K3S Master Node..."
      - curl -sfL https://get.k3s.io | K3S_TOKEN=${var.k3s_cluster_secret} sh -s - server --cluster-init
      - sleep 15
      - echo "Setting up ArgoCD in the cluster..."
      - k3s kubectl create namespace argocd
      - k3s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
    EOF
    
    file_name = "k3s-master-setup.yaml"
  }
}

# 2. Generate the Cloud-Init file for the WORKER node
resource "proxmox_virtual_environment_file" "worker_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data = <<-EOF
    #cloud-config
    runcmd:
      - curl -sfL https://get.k3s.io | K3S_URL=https://192.168.100.205:6443 K3S_TOKEN=${var.k3s_cluster_secret} sh -
    EOF
    
    file_name = "k3s-worker-setup.yaml"
  }
}

# =====================================================================
# 1. K3S MASTER NODE (Control Plane)
# =====================================================================
resource "proxmox_virtual_environment_vm" "k3s_prod_master" {
  name      = "just-put-it-k3s-master"
  node_name = "pve" # Default Proxmox node name
  
  agent {
    enabled = true
  }

  # Clone the Debian 12 template we created (VM ID 9000)
  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = 2
    # FIX for Kernel Panic: Pass through the host CPU features directly to the VM
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
  }

  network_device {
    bridge = "vmbr0"
  }

  # FIX for Kernel Panic: Cloud-Init images require a Serial Port to output boot logs.
  # Without this, the early-boot resize script crashes and brings down 'init' with it.
  serial_device {}

  vga {
    type = "serial0"
  }

  # --- Cloud-Init Configuration ---
  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.205/24" 
        gateway = "192.168.100.1" # Ensure this matches your home router's IP
      }
    }
    
    # Let Terraform natively handle the user and SSH key injection
    user_account {
      username = "estifen" # The username that will be created inside the VM
      keys     = [var.ssh_public_key]
    }
    
    # Inject our custom scripts via vendor_data so we don't overwrite the user_account
    vendor_data_file_id = proxmox_virtual_environment_file.master_cloud_config.id
  }
}

# =====================================================================
# 2. K3S WORKER NODE (Data Plane)
# =====================================================================
resource "proxmox_virtual_environment_vm" "k3s_prod_worker_1" {
  # This ensures Terraform builds the Master FIRST. The worker needs the master to be alive.
  depends_on = [proxmox_virtual_environment_vm.k3s_prod_master]

  name      = "just-put-it-k3s-worker-1"
  node_name = "pve"
  
  agent { enabled = true }

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory { dedicated = 4096 }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
  }

  network_device { bridge = "vmbr0" }
  serial_device {}
  vga { type = "serial0" }

  initialization {
    ip_config {
      ipv4 {
        # Worker gets a different Static IP
        address = "192.168.100.206/24"
        gateway = "192.168.100.1"
      }
    }

    user_account {
      username = "estifen"
      keys     = [var.ssh_public_key]
    }
    
    vendor_data_file_id = proxmox_virtual_environment_file.worker_cloud_config.id
  }
}
