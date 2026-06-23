# OpenBao & External Secrets Operator (ESO) Setup Guide
#just_put_it #project #infrastructure

## Architecture Context & Assumptions
*   **The Goal:** Mimic an Enterprise Azure Key Vault setup entirely locally for $0.
*   **The Tools:** We use **OpenBao** (the open-source fork of HashiCorp Vault) as the central secret manager, and **External Secrets Operator (ESO)** to automatically sync those secrets into native Kubernetes `Secret` objects.
*   **The Risk (Sealed Vault):** OpenBao encrypts its own storage. If the Proxmox VM restarts, OpenBao will boot in a "Sealed" state. You must manually unseal it before applications can access secrets.
*   **Storage Assumption:** This guide assumes your K3s cluster has a default StorageClass available (K3s provides `local-path` by default) to allocate the 1GB persistent volume for OpenBao.

### Prerequisites (Read Before Starting)
1.  **Execution Environment:** All commands in this guide should be executed from your **Mac (Host Machine)**, *not* inside the Proxmox VMs via SSH. Your Mac acts as the "Operator Terminal."
2.  **Kubeconfig:** Your Mac must be connected to the K3s cluster. If `kubectl get nodes` shows your Master and Worker, you are ready.
3.  **Helm Installed:** Helm is the package manager for Kubernetes.
    *   **How to check:** Run `helm version` on your Mac terminal.
    *   **How to install:** If it says "command not found," run `brew install helm`.

---

## Step 1: Install OpenBao (The Central Vault)

We will install OpenBao using Helm. We are using "Standalone Mode" which writes data to a local file on the K3s node, bypassing the need for a complex, multi-node Raft consensus setup.

```bash
# 1. Add the official OpenBao repository
helm repo add openbao https://openbao.github.io/openbao-helm
helm repo update

# 2. Install OpenBao with local persistent storage enabled
helm install openbao openbao/openbao \
  --set "server.standalone.enabled=true" \
  --set "server.dataStorage.enabled=true" \
  --set "server.dataStorage.size=1Gi"
```

## Step 2: Initialize & Unseal OpenBao

When OpenBao first starts, it is completely blank and locked. You must initialize it to generate the master cryptographic keys.

```bash
# 1. Initialize the vault. 
# 🚨 CRITICAL: This will output 5 Unseal Keys and 1 Initial Root Token. 
# You MUST copy these and save them securely in your password manager immediately.
kubectl exec -it openbao-0 -- bao operator init

# 2. Unseal the vault. 
# You must run this command 3 separate times. Each time it prompts you, 
# paste a DIFFERENT Unseal Key from the 5 you saved above.
kubectl exec -it openbao-0 -- bao operator unseal
kubectl exec -it openbao-0 -- bao operator unseal
kubectl exec -it openbao-0 -- bao operator unseal

# 3. Log in to the vault using the Initial Root Token so you can issue commands
kubectl exec -it openbao-0 -- bao login <YOUR_INITIAL_ROOT_TOKEN>
```

## Step 3: Enable the Secret Engine and Store a Secret

OpenBao supports many types of secrets. We need the basic Key-Value version 2 (KV-v2) engine.

```bash
# 1. Enable the Key-Value (v2) engine at the path named "secret"
kubectl exec -it openbao-0 -- bao secrets enable -path=secret kv-v2

# 2. Store your actual Gemini API Key inside the vault at the path 'secret/just_put_it/prod'
kubectl exec -it openbao-0 -- bao kv put secret/just_put_it/prod gemini_api_key="YOUR_ACTUAL_API_KEY"
```

## Step 4: Install External Secrets Operator (ESO)

ESO is the bridge that reads from OpenBao and creates standard Kubernetes secrets so your Spring Boot app can read them natively.

```bash
# Add the ESO repository and install it
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
   -n external-secrets \
   --create-namespace \
   --set installCRDs=true
```

Check external-secrets if running first before applying step 5:
```shell
kubectl get pods -n external-secrets
```

## Step 5: Configure the Connection (The Enterprise Way)

To satisfy the **Everything as Code (ADR 005)** constraint, we will NOT use a static token. We will use the **Kubernetes Auth Method**. This allows ESO to authenticate to OpenBao using its own Kubernetes Service Account ID. Because there are no passwords, the resulting YAML files can be safely committed to Git.

### 5.1 Configure OpenBao to Trust Kubernetes
You must run these commands to teach OpenBao how to verify Kubernetes ID cards. We will create a dedicated ServiceAccount in the `default` namespace for your application to use.

```bash
# 1. Create a dedicated ServiceAccount in the default namespace for fetching secrets
	kubectl create serviceaccount notes-app-sa -n default

# 2. Log into the vault using the Root Token you saved in Step 2
kubectl exec -it openbao-0 -- bao login <YOUR_INITIAL_ROOT_TOKEN>

# 3. Enable the Kubernetes authentication method
kubectl exec -it openbao-0 -- bao auth enable kubernetes

# 4. Tell OpenBao how to talk to the K3s Master node
kubectl exec -it openbao-0 -- sh -c 'bao write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"'

# 5. Create a policy that allows reading the secret/ path
kubectl exec -it openbao-0 -- sh -c 'bao policy write eso-policy - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF'

# 6. Create a role that binds the new ServiceAccount to the policy
# OpenBao requires an "audience" parameter for Kubernetes Auth (usually the vault URL or cluster name)
kubectl exec -it openbao-0 -- bao write auth/kubernetes/role/eso-role \
    bound_service_account_names=notes-app-sa \
    bound_service_account_namespaces=default \
    policies=eso-policy \
    audience="vault" \
    ttl=1h
```

### 5.2 Create the GitOps-Safe YAML
Create a file named `eso-bao-config.yaml`. Notice there are **zero passwords** in this file. It is 100% safe to commit to GitHub.

```yaml
---
# 1. Define the SecretStore (The Connection)
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: openbao-store
  namespace: default
spec:
  provider:
    vault:
      server: "http://openbao.default.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
          # We reference the dedicated ServiceAccount we created in the SAME namespace
          serviceAccountRef:
            name: "notes-app-sa"
            audiences:
              - "vault"
---
# 2. Define the ExternalSecret (The Sync Rule)
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: sync-gemini-api-key
  namespace: default
spec:
  refreshInterval: "10m"
  secretStoreRef:
    name: openbao-store
    kind: SecretStore
  target:
    name: gemini-api-secret # Your Spring Boot app will mount a secret with THIS name
    creationPolicy: Owner
  data:
    - secretKey: api-key # The key name inside the Kubernetes secret
      remoteRef:
        key: just_put_it/prod # The path in OpenBao
        property: gemini_api_key # The specific key we stored in Step 3
```

Apply this configuration to the cluster:
```bash
kubectl apply -f eso-bao-config.yaml
```

## Step 6: Verification

Check if the pipeline worked. ESO should have connected to OpenBao, read the API key, and generated a native Kubernetes secret.

```bash
# 1. Check ESO status. Look for 'STATUS: SecretSynced'
kubectl get externalsecret sync-gemini-api-key

# 2. Check if the final Kubernetes secret exists. 
# If this exists, your application can now mount it.
kubectl get secret gemini-api-secret
```

---

## Troubleshooting: ESO Caching the Wrong Token

If you applied the `eso-bao-config.yaml` file with the placeholder `"YOUR_INITIAL_ROOT_TOKEN"` by mistake, simply editing the file and re-running `kubectl apply` might result in a persistent `SecretSyncedError` (403 Permission Denied).

### Why does this happen?
External Secrets Operator (ESO) caches credentials in memory for performance. Even if Kubernetes successfully updates the `bao-token` Secret, ESO's internal loop might not realize the password has changed and will keep trying to use the old one. Running `kubectl delete` and `apply` again works, but forces ESO to rebuild its state. A cleaner, non-destructive enterprise approach is to force a cache eviction using Kubernetes annotations.

### The Fix (Cache Eviction via Annotation)

You can force ESO to clear its memory cache and re-read the token by "touching" the resources with a dummy annotation. This updates their metadata timestamp, triggering an immediate, clean reconciliation loop.

```bash
# 1. Force the SecretStore to update and re-authenticate
kubectl annotate secretstore openbao-store force-sync=$(date +%s) --overwrite

# 2. Force the ExternalSecret to re-fetch the data
kubectl annotate externalsecret sync-gemini-api-key force-sync=$(date +%s) --overwrite
```

*Wait about 10 seconds, then run the verification commands in Step 6 again.*
