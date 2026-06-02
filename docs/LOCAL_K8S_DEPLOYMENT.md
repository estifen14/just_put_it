# Local Kubernetes Deployment Guide (KIND)

This guide explains how to deploy the `just_put_it` application (specifically the `notes_service` and its PostgreSQL database) to a local Kubernetes cluster using KIND (Kubernetes in Docker).

## Prerequisites
- Docker (and Docker Desktop running)
- KIND installed (`brew install kind` on macOS)
- `kubectl` installed (`brew install kubectl` on macOS)
- A running KIND cluster named `just-put-it-cluster` (`kind create cluster --name just-put-it-cluster`)

---

## Deployment Steps

### Step 0: Build the Container Image
Before Kubernetes can run the app, it needs an image. 

Navigate to the service directory:
```bash
cd services/notes_service
```

Build the image using the provided Dockerfile. **Important:** If you are on an Apple Silicon Mac (M1/M2/M3), you must build for the `arm64` platform so it matches the KIND cluster architecture.

```bash
docker build --platform linux/arm64 -t notes-service:v1 .
```

### Step 1: Load the Image into KIND
KIND is isolated from your local Docker environment. You must "upload" your built image into the KIND cluster so K8s can see it without trying to pull from the internet.

```bash
kind load docker-image notes-service:v1 --name just-put-it-cluster
```

### Step 2: Deploy the Database (Pre-requisite)
Spring Boot will crash immediately if it cannot connect to its database. Before deploying the app, we must deploy PostgreSQL.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update && helm install my-postgres bitnami/postgresql --set fullnameOverride=postgres-service --set auth.postgresPassword=postgres --set auth.database=just_put_it --set primary.persistence.enabled=false
```
*Note: This creates a Deployment and a Service named `postgres-service`.*

### Step 3: Deploy the Application
Now, apply the deployment and service manifests for the `notes_service`. 

```bash
kubectl apply -f services/notes_service/k8s-local/notes-configmap.yaml
kubectl apply -f services/notes_service/k8s-local/notes-deployment.yaml
kubectl apply -f services/notes_service/k8s-local/notes-service.yaml
```

**Verification:**
Wait until both pods are in the `Running` state:
```bash
kubectl get pods
```

---

## Access & Test the API

Kubernetes services are isolated. To access the `notes-service` from your laptop, create a port-forward tunnel.

**Terminal 1 (Keep Open):**
```bash
# Map your laptop's port 8888 to the Service's port 80
kubectl port-forward service/notes-service 8888:80
```

**Terminal 2 (Test):**
```bash
curl -i -X POST http://localhost:8888/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "k8s_test@example.com", "password": "securepassword123"}'
```

You should receive a `201 Created` response with a JWT token.

---

## Troubleshooting & Operations

### System Owner Validation Drill (Scale & Rollback)
Run these commands one by one to demonstrate System Ownership and resilience:

**1. Scale Up:** Verify you can horizontally scale without downtime.
```bash
kubectl scale deployment notes-service --replicas=3
kubectl get pods -w
```

**2. Push Bad Update:** Intentionally break the application by requesting an image tag that doesn't exist.
```bash
kubectl set image deployment/notes-service notes-service-container=notes-service:v-broken
kubectl get pods
```
*(You should see `ImagePullBackOff` or `ErrImagePull`)*

**3. Rollback:** Restore the system to its last known good state.
```bash
kubectl rollout undo deployment/notes-service
kubectl get pods
```

### How to Restart the Application
In Kubernetes, you do not SSH into a container to restart a process. Instead, you tell Kubernetes to restart the Pod. The Deployment will automatically spin up a fresh instance.

**Method 1: The "Rollout Restart" (Industry Standard)**
This tells the Deployment to gracefully shut down old pods and spin up new ones without downtime.
```bash
kubectl rollout restart deployment notes-service
```

**Method 2: The "Brute Force" Pod Delete (Faster for local Dev)**
This simply deletes the pod. The Deployment panics and instantly creates a new one to replace it.
```bash
kubectl delete pod -l app=notes-service
```
