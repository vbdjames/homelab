# cert-manager + Ingress Runbook

> **Status:** Complete — cert-manager and ingress-nginx deployed, wildcard TLS via Let's Encrypt active
> **Last updated:** 2026-04-03
> **Dependencies:** Sealed Secrets controller running, Cloudflare API token in hand (see cloudflare-dns-runbook.md)

---

## Overview

cert-manager automates TLS certificate lifecycle — issuance and renewal — using Let's Encrypt with the Cloudflare DNS-01 challenge. ingress-nginx provides a single entry point for all HTTP/HTTPS traffic, routing by hostname to the correct service.

The Cloudflare API token is stored as a `SealedSecret` — encrypted at rest in Git, decrypted only by the Sealed Secrets controller running in the cluster.

---

## Step 1 — Seal the Cloudflare API token

The Sealed Secrets controller must be running before this step (`kubectl get pods -n sealed-secrets`).

```bash
# Create the secret manifest and pipe directly to kubeseal — the plaintext never touches disk
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=<YOUR_CLOUDFLARE_API_TOKEN> \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  --format yaml \
  > infrastructure/cert-manager/cloudflare-api-token-sealed.yaml
```

Commit `infrastructure/cert-manager/cloudflare-api-token-sealed.yaml` to Git — it is safe to do so.
The plaintext token is never written to disk or committed.

---

## Step 2 — Deploy cert-manager and ingress-nginx via ArgoCD

These are deployed as ArgoCD Applications (see `apps/`). ArgoCD handles the rest once pushed to Git.

Wave ordering:
- **Wave 3** — cert-manager (depends on Sealed Secrets at wave 0)
- **Wave 4** — cert-manager config (ClusterIssuer + sealed secret; depends on cert-manager CRDs)
- **Wave 5** — ingress-nginx (depends on cert-manager being ready to issue certs)

---

## Step 3 — Add DNS records in Cloudflare

Once ingress-nginx is deployed, get the external IP MetalLB assigned:

```bash
kubectl get svc -n ingress-nginx
```

Add an A record in Cloudflare for each service (see `cloudflare-dns-runbook.md`):

| Hostname | Type | Value |
|---|---|---|
| `argocd.fiddlestick.org` | A | `<ingress IP>` |
| `podinfo.fiddlestick.org` | A | `<ingress IP>` |

---

## Step 4 — Update app manifests to use ingress

Each app needs an `Ingress` resource added to its manifests pointing at the correct hostname.
cert-manager will issue a certificate automatically when it sees the ingress annotation:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod
```

---

## Verify

```bash
# cert-manager pods running
kubectl get pods -n cert-manager

# ClusterIssuer ready
kubectl get clusterissuer

# Certificate issued and Ready
kubectl get certificates -A

# ingress-nginx pods running
kubectl get pods -n ingress-nginx

# ingress-nginx external IP assigned
kubectl get svc -n ingress-nginx
```

---

## Checklist

- [x] Sealed Secrets controller running ✅
- [x] Cloudflare API token sealed and committed ✅
- [x] cert-manager deployed and ClusterIssuer ready ✅
- [x] ingress-nginx deployed and external IP assigned (`192.168.1.201`) ✅
- [x] Cloudflare DNS records added for each service ✅
- [x] Certificates issued and Ready ✅
