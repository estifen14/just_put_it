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
kubectl apply -f k8s-local/postgres.yaml
```
*Note: This creates a Deployment and a Service named `postgres-service`.*

### Step 3: Deploy the Application
Now, apply the deployment and service manifests for the `notes_service`. Ensure your `notes-deployment.yaml` points its `SPRING_DATASOURCE_URL` to `jdbc:postgresql://postgres-service:5432/just_put_it`.

```bash
kubectl apply -f k8s-local/notes-deployment.yaml
kubectl apply -f k8s-local/notes-service.yaml
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

