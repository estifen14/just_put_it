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

# --- Virtual Machine Resource ---
resource "proxmox_virtual_environment_vm" "k3s_prod_node" {
  name      = "just-put-it-k3s-prod"
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
    dedicated = 2048
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
        address = "dhcp" # Uses your home router to assign an IP
      }
    }
    user_account {
      username = "estifen" # The username that will be created inside the VM
      keys     = [var.ssh_public_key]
    }
  }

  # --- Automated K3s Installation via SSH ---
  connection {
    type        = "ssh"
    user        = "estifen"
    private_key = file("~/.ssh/id_rsa_azure") # Reusing existing Azure SSH key
    # BPG provider exports the IP address differently
    host        = self.ipv4_addresses[1][0] 
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to finish background setup...'",
      "cloud-init status --wait",
      "echo 'Installing K3s (Lightweight Kubernetes)...'",
      "curl -sfL https://get.k3s.io | sh -",
      "echo 'K3s installation complete!'",
      "sudo k3s kubectl get nodes"
    ]
  }
}
