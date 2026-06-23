---
title: Proxmox K3s Context Isolation Protocol
category: Protocol Documentation
tags: [kubernetes, vm, just_put_it, protocol]
created_date: 2026-06-22
---

# Proxmox K3s Context Isolation Protocol

**Goal:** Securely connect to a local Proxmox K3s cluster (`just_put_it`) without risking accidental deployment to the company's Azure Kubernetes contexts.

## Strategy: The Sandbox Method
This protocol relies on physically isolating the `kubeconfig` file and loading it into the terminal using the `export KUBECONFIG` environment variable. This ensures that the access is restricted **only** to the active terminal tab. Closing the tab immediately revokes access and defaults back to the safe company environment.

---

## Step-by-Step Instructions

### Phase 1: Retrieve the Kubeconfig from the Proxmox VM
Log into your master Proxmox VM to copy and take ownership of the Kubernetes configuration file.

1. SSH into your Proxmox VM:
   ```bash
   ssh -i ~/.ssh/id_rsa_azure estifen@192.168.100.205
   ```
2. Once inside the VM, copy the file to your home directory:
   ```bash
   sudo cp /etc/rancher/k3s/k3s.yaml ~/k3s.yaml
   ```
3. Take ownership of the file so your user account can download it:
   ```bash
   sudo chown estifen:estifen ~/k3s.yaml
   ```
4. Disconnect from the Proxmox VM and return to your Mac:
   ```bash
   exit
   ```

### Phase 2: Download and Sanitize the File on your Mac
You must securely copy the file from the VM to your Mac's `.kube` folder using a **unique name** to protect your company's `~/.kube/config` file.

1. Download the file and name it `just_put_it_k3s.yaml`:
   ```bash
   scp -i ~/.ssh/id_rsa_azure estifen@192.168.100.205:~/k3s.yaml ~/.kube/just_put_it_k3s.yaml
   ```
2. Open the newly downloaded file in a text editor (like nano) to correct the IP address:
   ```bash
   nano ~/.kube/just_put_it_k3s.yaml
   ```
3. Locate the server configuration line: `server: https://127.0.0.1:6443`
4. Change `127.0.0.1` to your VM's IP: `server: https://192.168.100.205:6443`
5. Save the file and exit (`Ctrl+O`, `Enter`, then `Ctrl+X` in nano).

### Phase 3: Connect Safely
To use this cluster without breaking your company setup, run this environment variable command in your Mac terminal:

```bash
export KUBECONFIG=~/.kube/just_put_it_k3s.yaml
```

**Verification Check:**
* If you run `kubectl get nodes` in this specific tab, you will see your Proxmox nodes.
* If you open a *completely new* terminal tab and type `kubectl get nodes`, it will safely default back to your company's Azure cluster. 

**MANDATORY RULE:** Whenever you want to work on the `just_put_it` project, you must open a terminal and run the `export` command above before executing any `kubectl` or `helm` commands.
