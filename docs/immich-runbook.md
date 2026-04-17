# Immich Runbook

Immich is the homelab photo library. It provides photo/video storage, sharing, and ML-powered search and face recognition. Authentication is via Authentik OIDC — navigating to the URL redirects straight to Authentik with no login page shown.

## Architecture

- **Helm chart:** `immich` v0.11.1 from `https://immich-app.github.io/immich-charts/`
- **PostgreSQL:** self-managed StatefulSet using `pgvector/pgvector:pg16` (pgvector required for ML embeddings)
- **Valkey:** bundled in-cluster Redis replacement for job queues
- **Machine learning:** separate pod for facial recognition and CLIP embeddings
- **Storage:** NAS share `/volume1/immich` for photo library; NFS dynamic PVC for ML model cache
- **Auth:** Authentik OAuth2/OIDC — see `docs/authentik-runbook.md`
- **Ingress:** `https://immich.fiddlestick.org`

## Key files

- `apps/immich.yaml` — ArgoCD Application (multi-source: git + Helm chart)
- `infrastructure/immich/postgres.yaml` — pgvector StatefulSet, Service, PVC
- `infrastructure/immich/pvs.yaml` — static NFS PV + PVC for photo library
- `infrastructure/immich/secrets-sealed.yaml` — two SealedSecrets:
  - `immich-db-secrets` — postgres password
  - `immich-config` — full Immich config YAML including OAuth client secret

## Secrets

- `immich-db-secrets` → `db-password` — postgres password for the `immich` user
- `immich-config` → `immich-config.yaml` — mounted at `/config/immich-config.yaml`; contains OAuth issuer URL, client ID, and client secret

The config secret must use `configurationKind: Secret` in the Helm values (not the default `ConfigMap`) since it contains credentials.

## Post-Deploy Setup

### First-run admin account

On a fresh install, Immich shows a **Getting Started** wizard before showing the login page. You must complete this to create the first local admin account. After that, the normal login page appears with the **Login with Authentik** button.

The local admin account is a break-glass fallback — keep the credentials in 1Password.

### Subsequent users

Family members are redirected straight to Authentik on arrival (`autoLaunch: true` in the
config). With `autoRegister: true`, their Immich account is created automatically on first
login using their Authentik credentials.

## Authentik OAuth2 Provider

The Authentik provider was configured with:
- **Provider name:** `Immich`
- **Client type:** Confidential
- **Redirect URI:** `https://immich.fiddlestick.org/auth/login`
- **Issuer URL (for Immich config):** `https://authentik.fiddlestick.org/application/o/immich/`

To find the client ID and secret: **Applications → Providers → Immich** in the Authentik UI.

## Troubleshooting

### No auto-redirect to Authentik (login page shown instead)

Check config is mounted:
```bash
kubectl -n immich exec deploy/immich-server -- cat /config/immich-config.yaml
kubectl -n immich exec deploy/immich-server -- env | grep IMMICH_CONFIG
```

If `IMMICH_CONFIG_FILE` is not set, `configurationKind: Secret` may be missing from Helm values.

### Postgres OOMKilled on first start

pgvector initialization is memory-intensive. Memory limit in `infrastructure/immich/postgres.yaml` is set to `1Gi` — do not lower it.

### Check pod status

```bash
kubectl -n immich get pods
kubectl -n immich logs deploy/immich-server --tail=50
kubectl -n immich logs statefulset/immich-postgres --tail=30
```
