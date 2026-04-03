# Tailscale Runbook

> **Status:** Active — operator running, Grafana exposed at grafana.taila8768.ts.net
> **Last updated:** 2026-04-02
> **Dependencies:** Sealed Secrets controller running

---

## Overview

The Tailscale Kubernetes operator exposes cluster services directly on the tailnet.
Each exposed service gets a Tailscale IP and a MagicDNS hostname, accessible from
any device on the tailnet with valid HTTPS certs issued by Tailscale.

This provides remote access to all homelab services without opening ports on the
Verizon router or relying on the `*.fiddlestick.org` ingress path.

The operator authenticates via an OAuth client (Trust Credentials) created at
`login.tailscale.com/admin` — no expiry, no rotation needed.

---

## Initial Setup

### Create OAuth credentials

1. Go to `login.tailscale.com/admin` → **Settings → Trust Credentials**
2. Create a new OAuth client named `homelab-k8s-operator`
3. Scopes required: **Devices — write**, **Auth keys — write**
4. Copy the **Client ID** and **Client Secret**

### Seal the credentials

```bash
kubectl create secret generic operator-oauth \
  --namespace tailscale \
  --from-literal=client_id=<CLIENT_ID> \
  --from-literal=client_secret=<CLIENT_SECRET> \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  --format yaml \
  > infrastructure/tailscale/operator-oauth-sealed.yaml
```

Commit `infrastructure/tailscale/operator-oauth-sealed.yaml` — safe to commit.

---

## Exposing a Service on Tailscale

Use a Kubernetes `Ingress` resource with `ingressClassName: tailscale` — **not** service
annotations. Service annotations only support HTTP; the Ingress approach gets a valid
Tailscale TLS cert automatically.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring  # must be in the same namespace as the target service
spec:
  ingressClassName: tailscale
  tls:
    - hosts:
        - grafana  # becomes grafana.taila8768.ts.net
  defaultBackend:
    service:
      name: kube-prometheus-stack-grafana
      port:
        number: 80
```

Place the manifest in `infrastructure/<namespace>/` so the relevant ArgoCD app picks it up.

> ⚠️ If a proxy pod gets into a CrashLoopBackOff after manual intervention, do a full
> clean slate: delete the StatefulSet, both secrets, and the Ingress, then reapply the
> Ingress. The operator will recreate everything cleanly.

---

## Services Exposed on Tailscale

| Service | MagicDNS hostname | Namespace |
|---|---|---|
| Grafana | `grafana.taila8768.ts.net` | monitoring |
| ArgoCD | `argocd.taila8768.ts.net` | argocd |

---

## Verify

```bash
# Operator pod running
kubectl get pods -n tailscale

# Proxy pods for exposed services
kubectl get pods -n tailscale

# Devices registered on tailnet
# Check login.tailscale.com/admin → Machines — should see entries tagged k8s
```

---

## Checklist

- [x] OAuth credentials created (Trust Credentials) ✅
- [x] OAuth credentials sealed and committed ✅
- [x] Tailscale operator deployed ✅
- [x] Devices visible in Tailscale admin console ✅
- [x] First service exposed — Grafana at grafana.taila8768.ts.net ✅
