---
title: Local GitOps with ArgoCD (Beginner's Guide)
category: Technical Guide
tags: [kubernetes, kind, argocd, gitops, ci-cd, just_put_it]
---

# Local GitOps with ArgoCD: Beginner's Guide

## The Core Concept: What is GitOps?
Normally, you would type `kubectl apply -f my-app.yaml` to put your application into Kubernetes. 
In **GitOps**, you *never* deploy apps manually. Instead:
1. You push your Kubernetes YAML files to a **GitHub repository**.
2. **ArgoCD** (a robot living inside your cluster) constantly watches that repository.
3. If ArgoCD sees a new change in GitHub, it pulls the YAML and deploys it automatically.

GitHub becomes the "Single Source of Truth." If your cluster dies (or when you move to the Mini PC), ArgoCD simply reads GitHub and rebuilds everything instantly.

---

## Phase 1: Prepare Your Cluster

*Prerequisite: Ensure Docker Desktop is open and running on your Mac.*

### 1. Create a Fresh Cluster
Let's create a brand new cluster specifically for GitOps testing.
```bash
kind create cluster --name gitops-cluster
```
*The Logic:* This creates a fresh, empty Kubernetes node running as a Docker container on your Mac.

### 2. Verify Your Context
Make sure your terminal is talking to the new cluster:
```bash
kubectl cluster-info --context kind-gitops-cluster
```

---

## Phase 2: Install ArgoCD (The Brain)

ArgoCD is just an application that runs *inside* Kubernetes. We need to install it first.

### 1. Create a Namespace
Namespaces are like folders in Kubernetes. We want to keep ArgoCD isolated.
```bash
kubectl create namespace argocd
```

### 2. Install ArgoCD
We will download and apply the official ArgoCD installation manifests straight from their website.

**Command:**
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
```

**Troubleshooting: The "Too Long" Error**
If you ever run a standard `kubectl apply` and see this error:
> `The CustomResourceDefinition "applicationsets.argoproj.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes`

**The Fix:** You must append `--server-side --force-conflicts` to your apply command (as done above). 
**The Reason:** ArgoCD's configuration files are massive. By default, `kubectl` tries to save a backup copy of the *entire* file inside the cluster's memory (as an annotation) before applying it. Kubernetes has a strict size limit for these annotations. Using `--server-side` tells the cluster to bypass this limitation and process the file natively on the server.

### 3. Wait for it to start
ArgoCD downloads a lot of containers. Wait until they are all running (this takes 1-2 minutes):
```bash
kubectl get pods -n argocd -w
```
*(Press `Ctrl+C` to exit the watch screen once they all say `Running`)*

---

## Phase 3: Access the ArgoCD Dashboard

Because ArgoCD is running *inside* your cluster (which is inside Docker), your Mac's browser cannot see it natively. We need to open a tunnel.

### 1. Port Forwarding
Run this in a **separate terminal window** and leave it running:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 2. Get the Default Password
ArgoCD auto-generates a secure password on installation. Run this command to reveal it:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```
*(Copy the output, you will need it)*

### 3. Log In
1. Open your browser and go to: `https://localhost:8080`
2. Your browser will warn you the connection is not private. Click **Advanced -> Proceed to localhost**.
3. **Username:** `admin`
4. **Password:** (Paste the password you copied above).

*You are now inside the ArgoCD command center!*

---

## Phase 4: Prepare the "Git" in GitOps

ArgoCD needs a GitHub repository to read from. It **cannot** read files directly from your Mac's hard drive. 

### 1. Make your GHCR Image Public (Crucial Beginner Step)
By default, GitHub makes your pushed Docker images Private. If it's private, Kubernetes won't have permission to download it without complex secrets.
*   Go to **GitHub.com** -> Click your profile picture -> **Your Profile**.
*   Click the **Packages** tab.
*   Click your `notes_service` package.
*   On the right sidebar, click **Package Settings**.
*   Scroll down to the "Danger Zone" and click **Change visibility** -> Make it **Public**.

### 2. Create the Kubernetes YAMLs
Inside your `just_put_it` code repository on your Mac, create a new folder named `k8s`. 

Inside `k8s/`, create a file named `application.yaml`:

```yaml
# k8s/application.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notes-service
  template:
    metadata:
      labels:
        app: notes-service
    spec:
      containers:
      - name: notes-service
        # UPDATE THIS: Replace YOUR_GITHUB_USERNAME with your actual username
        # UPDATE THIS: Make sure the tag (latest or v1) matches what CircleCI pushed
        image: ghcr.io/YOUR_GITHUB_USERNAME/just_put_it/notes_service:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: notes-service-svc
spec:
  selector:
    app: notes-service
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: NodePort
```

### 3. Push to GitHub
Commit this new folder to your GitHub repository:
```bash
git add k8s/application.yaml
git commit -m "Add K8s manifests for ArgoCD"
git push origin main
```

---

## Phase 5: Connect ArgoCD to GitHub

Now we tell ArgoCD where to look.

1. Go back to your ArgoCD UI (`https://localhost:8080`).
2. Click the **+ NEW APP** button at the top left.
3. Fill out the form exactly like this:

**General:**
*   **Application Name:** `notes-service-app`
*   **Project Name:** `default`
*   **Sync Policy:** `Automatic` *(Check "Prune Resources" and "Self Heal")*

**Source:**
*   **Repository URL:** `https://github.com/YOUR_GITHUB_USERNAME/just_put_it.git` (Use the HTTPS link of your repo)
*   **Revision:** `HEAD` (or `main`)
*   **Path:** `k8s` *(This is the folder we just created)*

**Destination:**
*   **Cluster URL:** `https://kubernetes.default.svc` *(Leave as default, this means "deploy into myself")*
*   **Namespace:** `default`

4. Click **CREATE** at the top.

---

## Phase 6: The Magic Happens

1. ArgoCD will immediately connect to your GitHub repo, read the `application.yaml` inside the `k8s` folder, and deploy it to your `gitops-cluster`.
2. You will see a beautiful graph of your Deployment, Service, and Pod appearing on the screen.
3. If it is green and says "Healthy", it worked! K8s reached out to GHCR, downloaded your image, and started it.

### How to test your API:
To hit the API locally, port-forward the new service you just deployed:
```bash
kubectl port-forward svc/notes-service-svc 8888:80
```
Then run your `curl` command against `http://localhost:8888`.

### The True Power of GitOps
Try this:
1. Change `replicas: 1` to `replicas: 3` in your `k8s/application.yaml` on your Mac.
2. `git commit` and `git push`.
3. Watch the ArgoCD dashboard. Within 3 minutes, it will automatically detect the change on GitHub and spin up 2 more Pods without you touching the cluster!

---

## Appendix: Adopting Pre-Existing Resources

If you are installing ArgoCD into a cluster that *already* has applications running (because you manually typed `kubectl apply` earlier), ArgoCD will not automatically see them. 

ArgoCD is completely blind to anything deployed manually. It operates strictly on **GitOps**: it looks at GitHub to see what *should* be running, not at the cluster to see what *is* running.

To make ArgoCD take over management of your existing apps, you must "Adopt" them. Because the resources already exist in your cluster, when ArgoCD syncs with GitHub, it won't crash—it will realize "Oh, these are already here," take ownership of them, and start displaying them in the UI.

### Step 1: Push Your Existing YAMLs to GitHub
ArgoCD needs your files in GitHub. It is highly recommended to keep Kubernetes manifests next to the microservice they belong to (the "App-of-Apps" pattern).

1. Ensure your existing YAML files (e.g., `postgres.yaml`, `notes-deployment.yaml`) are inside a specific folder in your repo, such as `services/notes_service/k8s-local`.
2. Commit and push them:
```bash
git add services/notes_service/k8s-local/
git commit -m "Add existing k8s manifests for ArgoCD adoption"
git push origin main
```

### Step 2: Create the ArgoCD Application
Tell ArgoCD to watch that specific folder path in GitHub.

1. Go to your ArgoCD UI (`https://localhost:8080`).
2. Click **+ NEW APP**.
3. Fill out the form:

**General:**
*   **Application Name:** `just-put-it-stack`
*   **Project Name:** `default`
*   **Sync Policy:** `Automatic` (Check both **Prune Resources** and **Self Heal**)

**Source:**
*   **Repository URL:** `https://github.com/YOUR_GITHUB_USERNAME/just_put_it.git`
*   **Revision:** `HEAD` (or `main`)
*   **Path:** `services/notes_service/k8s-local` *(This tells ArgoCD to navigate down from the repo root to find the YAMLs)*

**Destination:**
*   **Cluster URL:** `https://kubernetes.default.svc`
*   **Namespace:** `default` *(Assuming your apps were deployed to the default namespace)*

### Step 3: Click CREATE
ArgoCD will connect to GitHub, read the YAMLs in that specific path, map them to your existing running Pods in the `default` namespace, and they will instantly appear in your dashboard!