# Deploying PostgreSQL with Helm

This guide explains how to deploy PostgreSQL to a local Kubernetes cluster using Helm, the Kubernetes package manager. This replaces the need for manual, hardcoded `postgres.yaml` manifests.

## Prerequisites
- A running Kubernetes cluster (e.g., KIND).
- Helm installed (`brew install helm` on macOS).

## Step 1: Add the Bitnami Repository
Helm needs to know where to download charts from. Bitnami provides highly trusted, production-ready charts for open-source software.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

## Step 2: Install PostgreSQL
We use the `helm install` command to deploy the database. We pass `--set` flags to configure the passwords, database name, and service name to match what our application expects.

```bash
helm install my-postgres bitnami/postgresql \
  --set fullnameOverride=postgres-service \
  --set auth.postgresPassword=postgres \
  --set auth.database=just_put_it \
  --set primary.persistence.enabled=false
```

### Explanation of Flags:
- `fullnameOverride=postgres-service`: Forces the created Kubernetes Service to be named exactly `postgres-service`. This ensures our Spring Boot app (`jdbc:postgresql://postgres-service:5432/just_put_it`) can find it without any code changes.
- `auth.postgresPassword=postgres`: Sets the default password.
- `auth.database=just_put_it`: Creates our application database on startup.
- `primary.persistence.enabled=false`: Disables persistent volumes. This is required for local KIND clusters to prevent pods from getting stuck waiting for cloud storage provisioning.

## Step 3: Verification
Verify the pod is running and the service was created with the correct name:

```bash
kubectl get pods
kubectl get svc | grep postgres-service
```

## Uninstallation
To completely remove the database and all its associated Kubernetes resources, simply uninstall the Helm release:

```bash
helm uninstall my-postgres
```
