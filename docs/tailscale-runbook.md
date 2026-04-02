# Tailscale Runbook

> **Status:** In progress — auth key sealed, operator pending deployment
> **Last updated:** 2026-04-02
> **Dependencies:** Sealed Secrets controller running

---

## Overview

The Tailscale Kubernetes operator exposes cluster services directly on the tailnet.
Each exposed service gets a Tailscale IP and a MagicDNS hostname, accessible from
any device on the tailnet with valid HTTPS certs issued by Tailscale.

This provides remote access to all homelab services without opening ports on the
Verizon router or relying on the `*.fiddlestick.org` ingress path.

---

## Auth Key Rotation (every 90 days)

> ⚠️ Personal Tailscale accounts cap auth keys at 90 days. The operator loses tailnet
> access if the key expires — set a calendar reminder before the expiry date.

To rotate:
1. Generate a new auth key at `login.tailscale.com` → **Settings → Auth keys**
   - Reusable: yes, Ephemeral: yes, Expiry: 90 days
2. Re-seal and overwrite the existing secret:
   ```bash
   kubectl create secret generic tailscale-operator-auth \
     --namespace tailscale \
     --from-literal=TS_AUTHKEY=<NEW_KEY> \
     --dry-run=client -o yaml | \
   kubeseal \
     --controller-name sealed-secrets-controller \
     --controller-namespace sealed-secrets \
     --format yaml \
     > infrastructure/tailscale/auth-sealed.yaml
   ```
3. Commit and push — ArgoCD deploys the updated secret automatically
4. Restart the operator to pick up the new key:
   ```bash
   kubectl rollout restart deployment/operator -n tailscale
   ```

---

## Exposing a Service on Tailscale

Annotate any `Service` with `tailscale.com/expose: "true"` and optionally set a hostname:

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

## kubectl Access via Tailscale

The Kubernetes API server can be exposed on the tailnet, enabling `kubectl` from anywhere:

```yaml
# infrastructure/tailscale/apiserver-proxy.yaml
apiVersion: v1
kind: Service
metadata:
  name: apiserver-proxy
  namespace: tailscale
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "k8s-homelab"
spec:
  type: ExternalName
  externalName: kubernetes.default.svc.cluster.local
  ports:
    - port: 443
      targetPort: 443
```

Then update your local kubeconfig to point at the Tailscale hostname instead of the
node IP — works from anywhere on the tailnet.

---

## Verify

```bash
# Operator pod running
kubectl get pods -n tailscale

# Devices registered on tailnet
# Check login.tailscale.com → Machines — should see new entries tagged k8s
```

---

## Checklist

- [x] Auth key generated (expires 2026-07-01 — rotate before this date) ✅
- [x] Auth key sealed and committed ✅
- [ ] Tailscale operator deployed
- [ ] Devices visible in Tailscale admin console
- [ ] First service exposed and accessible from tailnet
- [ ] Auth key rotation reminder set in calendar
