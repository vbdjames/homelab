# Backup Runbook

> **Status:** Partially complete — steps documented, not all performed
> **Last updated:** 2026-04-04

---

## Overview

Most cluster state is in Git (app manifests, sealed secrets, Ansible config) and is therefore
inherently backed up. Prometheus and Loki data live on NFS PVCs (Synology NAS) and are covered
by iDrive. Two things fall outside these paths and require explicit backup:

| What | Where | Risk if lost |
|------|-------|-------------|
| Sealed Secrets decryption key | etcd on `hl-01` | All sealed secrets in Git become permanently unreadable |
| Pi-hole DNS/DHCP config | Proxmox LXC (`pve-01`) | Local DNS records must be manually re-entered |

---

## Sealed Secrets Decryption Key

### Background

The Sealed Secrets controller generates a private key on first install and uses it to decrypt
every `SealedSecret` in the cluster. The matching public key is what `kubeseal` uses to encrypt
secrets before they're committed to Git.

The controller **auto-generates a new key on a rolling schedule** (default: every 30 days).
Old keys are retained so existing sealed secrets remain decryptable. This means:

- The key backup will go stale over time as new keys are generated
- Re-exporting is needed after any rotation (see [Key Rotation](#sealed-secrets-key-rotation) below)
- The export command below fetches **all** current keys at once

### Export

```bash
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml
```

> ⚠️ This file contains the raw private key. Do **not** commit it to Git.
> Store it encrypted, offline, or in a secrets manager.

### Storage

- **Location:** 1Password — Secure Note: `homelab — Sealed Secrets Decryption Key`
- **Last exported:** 2026-04-04

---

## Pi-hole Config Backup

Pi-hole runs in an LXC on `pve-01` and is not on the NAS. Its Teleporter export covers:
- Custom DNS records (all `*.fiddlestick.org → 192.168.1.201` entries and any others)
- DHCP static assignments
- Blocklist configuration and settings

### Export

In the Pi-hole UI: **Settings → Teleporter → Export**

This produces a single `.zip` file. Store it somewhere durable (password manager, cloud storage,
or alongside the Sealed Secrets backup).

### Storage

- **Location:** 1Password — Secure Note: `homelab — Pi-hole Config Backup` (zip attached)
- **Last exported:** 2026-04-04

---

## Sealed Secrets Key Rotation

### When to rotate

| Trigger | Action |
|---------|--------|
| Key backup file is compromised or exposed | Rotate immediately, re-seal all secrets |
| Scheduled hygiene | Optional — the auto-renewal schedule already limits exposure window |
| Retiring old keys to reduce historical exposure | Re-seal all secrets against current key, then delete old keys |

Note: auto-rotation generates new keys but **does not invalidate old ones**. If an old key is
compromised, it must be explicitly deleted after all secrets are re-sealed with the new key.

### How to rotate

1. **Force a new key to be generated** by deleting the existing key secret — the controller
   recreates it immediately on the next reconcile:
   ```bash
   # List all keys to identify the one(s) to remove
   kubectl get secret -n sealed-secrets \
     -l sealedsecrets.bitnami.com/sealed-secrets-key

   # Delete a specific key (replace <name> with the secret name)
   kubectl delete secret <name> -n sealed-secrets
   ```

2. **Re-seal all secrets** using the new active key. For each sealed secret in the repo:
   ```bash
   # Re-seal from the original plaintext value
   kubectl create secret generic <name> \
     --namespace <namespace> \
     --from-literal=<key>=<value> \
     --dry-run=client -o yaml | \
   kubeseal \
     --controller-name sealed-secrets-controller \
     --controller-namespace sealed-secrets \
     --format yaml \
     > infrastructure/<path>/<name>-sealed.yaml
   ```

3. **Commit and push** — ArgoCD will sync the re-sealed secrets.

4. **Verify** all workloads that depend on the secrets are still healthy:
   ```bash
   kubectl get pods -A | grep -v Running
   ```

5. **Re-export the key backup** and update the stored copy (see [Export](#export) above).

---

## Checklist

- [x] Sealed Secrets key exported and stored securely
- [x] Pi-hole Teleporter export completed and stored
- [x] Backup locations documented above
- [ ] Calendar reminder set to re-export Sealed Secrets key after each auto-rotation (~30 days)
