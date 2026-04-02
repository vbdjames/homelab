# Tailscale Runbook

> **Status:** In progress — OAuth credentials sealed, operator pending deployment
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

Annotate any `Service` with `tailscale.com/expose: "true"` and set a hostname:

```yaml
annotations:
  tailscale.com/expose: "true"
  tailscale.com/hostname: "grafana"  # appears as "grafana" in MagicDNS
```

The operator creates a Tailscale proxy pod and registers it on the tailnet. Within a
few seconds the service is accessible at `https://grafana` from any tailnet device.

---

## Services Exposed on Tailscale

| Service | MagicDNS hostname | Namespace |
|---|---|---|
| _(none yet — add as configured)_ | | |

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
- [ ] Tailscale operator deployed
- [ ] Devices visible in Tailscale admin console
- [ ] First service exposed and accessible from tailnet
