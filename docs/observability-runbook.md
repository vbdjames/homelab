# Observability Runbook

> **Status:** In progress — sealed secret committed, DNS pending
> **Last updated:** 2026-04-02
> **Stack:** kube-prometheus-stack (Prometheus + Grafana + Alertmanager) + Loki + Promtail
> **Dependencies:** Sealed Secrets controller running, NFS StorageClass available, ingress-nginx + cert-manager deployed

---

## Overview

- **Prometheus** — scrapes and stores metrics from all nodes, pods, and Kubernetes components
- **Grafana** — dashboards and log exploration; accessible at `grafana.fiddlestick.org`
- **Alertmanager** — alert routing (to be configured separately)
- **Loki** — log aggregation from all pods via Promtail
- **Promtail** — DaemonSet that ships pod logs to Loki

Retention: 30 days for both metrics (Prometheus) and logs (Loki).
Storage: Prometheus 20Gi, Loki 10Gi — both on NFS via the default StorageClass.

---

## Step 1 — Seal the Grafana admin password

The Sealed Secrets controller must be running before this step.

```bash
kubectl create secret generic grafana-admin \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<YOUR_PASSWORD> \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  --format yaml \
  > infrastructure/monitoring/grafana-admin-sealed.yaml
```

Commit `infrastructure/monitoring/grafana-admin-sealed.yaml` to Git — it is safe to do so.
Store the plaintext password in your password manager.

---

## Step 2 — Deploy via ArgoCD

Push to Git — ArgoCD deploys in wave order:
- **Wave 7** — kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- **Wave 8** — Loki + Promtail

---

## Step 3 — Add DNS records

Add to Cloudflare and the Verizon router (see `cloudflare-dns-runbook.md`):

| Hostname | Type | Value |
|---|---|---|
| `grafana.fiddlestick.org` | A | `192.168.1.201` |

---

## Verify

```bash
# All monitoring pods running
kubectl get pods -n monitoring

# Prometheus targets healthy
# Open https://grafana.fiddlestick.org → Explore → Prometheus

# Loki receiving logs
# Open https://grafana.fiddlestick.org → Explore → Loki

# PVCs bound
kubectl get pvc -n monitoring
```

---

## Checklist

- [x] Grafana admin password sealed and committed ✅
- [x] `grafana.fiddlestick.org` DNS records added (Cloudflare + router) ✅
- [ ] kube-prometheus-stack deployed and Grafana accessible
- [ ] Loki + Promtail deployed
- [ ] Prometheus targets all healthy
- [ ] Loki receiving logs from pods
- [ ] PVCs bound and data persisting to NFS
