# Proxmox + Terraform + K3s Automation Guide

This guide explains how to use the Terraform configuration in `infra/terraform-prod/main.tf` to automatically provision a Virtual Machine on your Proxmox server (Thinkpad L14) and install K3s.

## 1. Prerequisites (What you need before running Terraform)

### A. What is a "Cloud-Init Template"? (And why you can't use an ISO)
A standard ISO file (like `debian-13.5.0-amd64-netinst.iso`) is an **installation CD**. If Terraform boots a VM from an ISO, the VM will just sit at the "Select Language" screen waiting for a human to click buttons. Terraform cannot click through installers.

A **Cloud-Init Template** is a pre-installed, "blank slate" hard drive image provided by OS vendors. When it boots, it looks for a configuration file (which Terraform provides) that injects your username, SSH keys, and network settings instantly. 

We will use the **Debian 12 Cloud Image** (since Debian 13 is not officially released as stable yet) instead of the ISO you downloaded. Debian is perfectly fine for K3s, ArgoCD, and Docker.

### B. Create the Debian Cloud-Init Template in Proxmox (One-time setup)
You will need to run these commands in the **Proxmox Shell** (on the Thinkpad web interface) to download the Debian 12 cloud image and turn it into a template named `debian-12-cloudinit`:

```bash
# 1. Download the Debian 12 Generic Cloud image
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
### If output is stuck in "HTTP request sent, awaiting response...", try:
curl -4 -LO https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2

# 1.5 FIX: Inject QEMU Guest Agent into the image BEFORE creating the VM
# Without this, Proxmox cannot see the VM's IP address, and Terraform hangs forever.
apt update && apt install libguestfs-tools -y
virt-customize -a debian-12-generic-amd64.qcow2 --install qemu-guest-agent

# 2. Create a new VM (ID 9000)
qm create 9000 --name "debian-12-cloudinit" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# 3. Import the downloaded disk to local-lvm storage
qm importdisk 9000 debian-12-generic-amd64.qcow2 local-lvm

# 4. Attach the disk to the VM
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0

# 5. Add a Cloud-Init CD-ROM drive
qm set 9000 --ide2 local-lvm:cloudinit

# 6. Set boot disk and enable QEMU Guest Agent
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --agent enabled=1

# 7. Convert the VM into a reusable template
qm template 9000
```

### C. Prepare your Mac (Estifen's Machine)
1. Install Terraform:
   ```bash
   brew install terraform
   ```
2. **SSH Keys:** You can 100% reuse the SSH key pair you created for the `cloud-in-a-box` Azure VM. An SSH key is just a cryptographic identity; it doesn't care if it's logging into Azure or Proxmox. Ensure your public key (`~/.ssh/id_rsa.pub`) and private key (`~/.ssh/id_rsa`) are available.

---

## 2. How to Run the Automation

Navigate to the terraform directory on your Mac:
```bash
cd /Users/Estifen.Abrea/Projects/gemini/prototypes/just_put_it/infra/terraform-prod
```

### Step 1: Initialize Terraform
This downloads the required Proxmox plugins.
```bash
terraform init
```

### Step 2: Create a `terraform.tfvars` file (DO NOT COMMIT THIS FILE)
Create a file named `terraform.tfvars` in the same directory. This holds your secrets so you don't type them every time.

```hcl
proxmox_host         = "192.168.X.X" # Replace with your Thinkpad's IP
proxmox_token_id     = "terraform-prov@pve!terraform-token" # Replace with your Token ID
proxmox_token_secret = "YOUR-SECRET-UUID-HERE" # Replace with your Token Value
ssh_public_key       = "ssh-rsa AAAAB3Nza... estifen@macbook" # Paste the contents of ~/.ssh/id_rsa.pub
```

### Step 3: Plan the Deployment
This shows you what Terraform *will* do without actually doing it.
```bash
terraform plan
```

### Step 4: Apply and Build!
```bash
terraform apply
```
Type `yes` when prompted. 
**What happens next?**
1. Terraform connects to the Proxmox API.
2. It clones `debian-12-cloudinit`.
3. It sets the RAM to 2GB and Disk to 32GB.
4. It boots the VM. Cloud-Init injects your user (`estifen`) and your SSH key.
5. Terraform waits for the VM to get an IP address.
6. Terraform connects via SSH and runs the K3s installation script.

---

## 3. ArgoCD Deployment (Next Steps)
The current `main.tf` successfully stands up Kubernetes. Deploying ArgoCD via Terraform is possible using the `helm` provider, but it requires Terraform to securely extract the `/etc/rancher/k3s/k3s.yaml` file from the VM first. 

To maintain the "System Owner" step-by-step approach, we establish the Infrastructure (K3s) first, verify it, and then add the ArgoCD layer.