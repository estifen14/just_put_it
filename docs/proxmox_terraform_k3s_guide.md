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

# NEW: The shared secret used to join the Worker to the Master
k3s_cluster_secret   = "SuperSecretK3sPassword123!" 
```

### Step 3: Setup Snippets and SSH Access (One-time setup)
**Step 3.1: By default, Proxmox does not allow you to upload Snippet files.**
**You must enable Snippet it in the Web UI:**
1. Go to the Proxmox Web UI.
2. Click on **Datacenter** -> **Storage** in the left menu.
3. Double-click the storage named **local**.
4. In the "Content" dropdown, click it and highlight **Snippets** (so it turns blue along with ISO image and VZDump).
5. Click **OK**.

**Or run this command to add snippets in the list:**
```bash
pvesm set local --content iso,vztmpl,backup,import,snippets
```

**Step 3.2: Copy your public key to the Proxmox's root account:**
```bash
ssh-copy-id -i ~/.ssh/id_rsa_azure root@192.168.100.201
```
_(It will ask for your Proxmox Server's root password one last time to authorize the key)._
> **Why must we use root?** </br>
> The Snippet files must be uploaded directly to the Proxmox filesystem at /var/lib/vz/snippets/.
>    1. **The API Limitation:** Proxmox does not have an API endpoint to upload text files directly to the Snippet directory. This is why the BPG provider has to use a "backdoor" SSH connection to create the file.
>    2. **The Privilege Issue:** The bpg/proxmox provider is not smart enough to log in as your pen user, type a password, and then execute sudo. It expects to just drop the file directly into the folder.
>    3. **The Proxmox User Model:** Users like terraform-prov or pen are "Proxmox API Users" or "PAM Users". Even if they are Administrators in the _Web UI_, that does not give them physical write permissions to the underlying Debian filesystem directory /var/lib/vz/snippets/ without using sudo.
> 
> _Your_ _terraform-prov_ _token is still used for 99% of the actions—creating VMs, changing RAM, setting networks. The_ _root_ _SSH is used EXCLUSIVELY for transferring the Cloud-Init text file)_

**⚠️ To revoke a key (In case you change your laptop):**
1. Run `nano ~/.ssh/authorized_keys`
2. Identify the stolen key:
> They usually look like this:
> </br> 1 ssh-rsa AAAAB3NzaC1yc... estifen@Safe-Macbook
> </br> 2 ssh-rsa AAAAC8HdfJ2zz... estifen@Stolen-Laptop
> </br> 3 ssh-ed25519 AAAAC3Nza... root@backup-server

3. Delete the line and save.
4. Verify. Try to ssh: `ssh root@192.168.100.201`. </br>
   _(You should get Permission Denied)_

### Step 4: Plan and Apply!
This shows you what Terraform *will* do without actually doing it.
```bash  
terraform plan
```  
Apply:
```bash  
# To see detailed logs of what Terraform is doing under the hood, you can set the log level to INFO. This is optional but can be helpful for debugging.  
# export TF_LOG=INFO  
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

**Read your new, perfect logs!**
</br> Terraform will say Apply Complete very quickly (because it didn't wait for K3s to install). Wait about 60 seconds for the VM to finish the background work, then SSH in and read your logs:
```bash
ssh -i ~/.ssh/id_rsa_azure estifen@192.168.100.205
```
Inside the VM:
```bash
cat /var/log/cloud-init-output.log
```

### Step 5: Verify the Deployment
1. Log into the Proxmox web interface and navigate to your VM. You should see it running.
2. Check the "Summary" tab to find the assigned IP address.
3. Open a terminal and SSH into the VM:
```bash
ssh -i ~/.ssh/<SSH_PRIVATE_KEY> estifen@<VM_IP_ADDRESS>
# Example: ssh -i ~/.ssh/id_rsa_azure estifen@192.168.100.205
```
If you see "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" ran this command to clear the old fingerprint:
```bash
ssh-keygen -R <VM_IP_ADDRESS>
# Example: ssh-keygen -R 192.168.100.205
```
4. Once logged in, check that K3s is running:
```bash
sudo kubectl get nodes
```
* What to expect: You should see two rows. One named just-put-it-k3s-master (with the role control-plane,master) and one named just-put-it-k3s-worker-1 (with the role <none> or worker). Both must have the
  STATUS Ready.

---
## 3. Check kube-system and argocd namespaces
1. check kube-system:
```bash
sudo k3s kubectl get pods -n kube-system
```
How to read the output:
Look at the STATUS column.
* Settled: Every single row says Running or Completed.
* Not Settled: You see rows that say Pending, ContainerCreating, or CrashLoopBackOff.

2. check argocd:
```bash
sudo k3s kubectl get pods -n argocd
```
How to read the output:
ArgoCD installs about 7 different components (server, repo-server, redis, application-controller, etc.).
* Settled: Every single row says Running, AND the READY column says 1/1 (or 2/2 for some). This means the software is fully downloaded and online.
* Not Settled: You see ContainerCreating (it is still downloading from the internet) or 0/1 in the READY column (it is downloaded but still booting up).

3. The "Watch" command (Pro Tip):
If things are still downloading, and you don't want to keep typing the command over and over, you can add -w to "watch" the status update in real-time:
```bash
sudo k3s kubectl get pods -n argocd -w
````
### If something went wrong
- Check the logs of a specific pod:
```bash
sudo k3s kubectl logs argocd-applicationset-controller-b7669f646-gghvj -n argocd
```
- Sometimes, it just needs a forced restart:
```bash
sudo k3s kubectl delete pod argocd-applicationset-controller-b7669f646-gghvj -n argocd
```

---
## Access ArgoCD Dashboard
1. Get the ArgoCD admin password:
```bash
sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```
* Action: Copy the output (it will be a long string of random letters and numbers). Save this somewhere safe!
2. Expose the ArgoCD UI (Port Forwarding):
```bash
sudo k3s kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
```
* Note: This command will "hang" in the terminal. That is normal. It is keeping the tunnel open.
3. Log in to the ArgoCD dashboard:
   - Open your browser and go to: `https://<VM_IP_ADDRESS>:8080`
   - Browser Warning: Your browser will say "Your connection is not private" (because ArgoCD uses a self-signed security certificate by default). Click "Advanced" and then "Proceed to 192.168.100.205
       (unsafe)".
   - Username: admin
   - Password: Paste the secret password you copied in Step 1.