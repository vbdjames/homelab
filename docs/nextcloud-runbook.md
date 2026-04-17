# Nextcloud Runbook

> **Status:** Active — running at `https://nextcloud.fiddlestick.org`
> **Stack:** Nextcloud 33 · PostgreSQL · Redis · Collabora Online

---

## Overview

Nextcloud is a self-hosted file sharing and collaboration platform. Collabora Online
provides in-browser document editing (Word/Excel/PowerPoint compatible).

| Component | Details |
|---|---|
| URL | `https://nextcloud.fiddlestick.org` |
| Collabora URL | `https://collabora.fiddlestick.org` |
| Helm chart | `nextcloud/nextcloud` v9.0.5 |
| Collabora chart | `collabora-online/collabora-online` v1.1.60 |
| Nextcloud namespace | `nextcloud` |
| Collabora namespace | `collabora` |
| Database | PostgreSQL (bundled subchart) |
| Cache | Redis (bundled subchart, 1 master + 3 replicas) |
| Data PVC | `nextcloud-nextcloud-data` (50Gi, NFS) |
| Admin user | `admin` (credentials in 1Password) |

---

## First-Deploy Setup

After initial deployment the startup probe gives Nextcloud 5 minutes to complete
database schema initialization. Watch progress with:

```bash
while true; do kubectl logs -n nextcloud deployment/nextcloud -f 2>/dev/null; sleep 2; done
```

The pod will be `Running` but not `Ready` until initialization completes. This is normal.

### Known first-deploy gotchas

- **Liveness probe kills init** — the startup probe (`failureThreshold: 30`,
  `periodSeconds: 10`) must be in place or the liveness probe will kill the container
  before init completes. Already configured in `apps/nextcloud.yaml`.
- **Memory** — Nextcloud requires 2Gi during initialization. Limit is set to 2Gi in
  `apps/nextcloud.yaml`.
- **Reverse proxy / HTTPS config** — after first deploy, run these `occ` commands to
  tell Nextcloud it's behind an HTTPS-terminating proxy (otherwise Collabora will get
  HTTP redirect loops when calling WOPI endpoints):

  ```bash
  kubectl exec -n nextcloud deployment/nextcloud -- su -s /bin/sh www-data -c "
    php occ config:system:set overwriteprotocol --value='https'
    php occ config:system:set overwritehost --value='nextcloud.fiddlestick.org'
    php occ config:system:set trusted_proxies 0 --value='10.0.0.0/8'
    php occ config:system:set trusted_proxies 1 --value='172.16.0.0/12'
    php occ config:system:set trusted_proxies 2 --value='192.168.0.0/16'
  "
  ```

  These are stored in `config.php` on the PVC and survive pod restarts, but must be
  re-run if the PVC is ever recreated. The Helm chart `configs:` key cannot be used
  for this — it creates a volumeMount conflict with the chart's own config directory.

---

## Post-Deploy Configuration

### 1. Collabora (Nextcloud Office)

1. Log into Nextcloud as `admin`
2. Go to **Apps → Search** for "Nextcloud Office" and install it
3. Go to **Administration Settings → Office**
4. Select **Use your own server**
5. Enter: `https://collabora.fiddlestick.org`
6. Click **Save** — the green tick confirms Nextcloud can reach Collabora
7. In the **WOPI allow-list** field enter: `10.0.0.0/8,172.16.0.0/12,192.168.0.0/16`
8. Click **Save** — this restricts WOPI requests to RFC1918 addresses (appropriate for a homelab where Collabora and Nextcloud are on the same internal network)

> **Note:** `--o:security.capabilities=false` is set in `apps/collabora.yaml` so
> Collabora doesn't attempt filesystem mounts for process jails (requires `SYS_ADMIN`
> which is not available in a standard Kubernetes pod). Without this flag, documents
> fail to open with "No child available".

### 2. Authentik OIDC

Nextcloud uses the `user_oidc` app to authenticate via Authentik. Users are auto-provisioned
on first login.

**Authentik side:**
- Provider: `nextcloud` (OAuth2/OpenID, Confidential, Implicit consent)
- Application slug: `nextcloud`
- Redirect URI: `https://nextcloud.fiddlestick.org/apps/user_oidc/code`
- Client ID and secret stored in 1Password

**Nextcloud side — configure via occ (do not use the UI discovery check, it is unreliable):**

```bash
kubectl exec -n nextcloud deployment/nextcloud -- su -s /bin/sh www-data -c "
  php occ user_oidc:provider authentik \
    --clientid='<client-id>' \
    --clientsecret='<client-secret>' \
    --discoveryuri='https://authentik.fiddlestick.org/application/o/nextcloud/.well-known/openid-configuration' \
    --unique-uid=0
"
```

**Required system config** (Nextcloud blocks server-side requests to private IPs by default):

```bash
kubectl exec -n nextcloud deployment/nextcloud -- su -s /bin/sh www-data -c \
  "php occ config:system:set allow_local_remote_servers --value=true --type=bool"
```

**Verify provider is configured:**

```bash
kubectl exec -n nextcloud deployment/nextcloud -- su -s /bin/sh www-data -c \
  "php occ user_oidc:provider"
```

---

## Troubleshooting

### Pod stuck initializing / CrashLoopBackOff on first deploy

Check whether it's a probe timeout or OOM:

```bash
kubectl describe pod -n nextcloud -l app.kubernetes.io/name=nextcloud | grep -E "Exit Code|Reason|Killing"
```

- **Exit Code 137** — OOMKilled, increase memory limit in `apps/nextcloud.yaml`
- **Killing ... failed liveness probe** — startup probe not in effect, check probe config

### Redis replica can't connect to master

Usually a stale backoff after a node failure. Delete the replica pod and let it reschedule:

```bash
kubectl delete pod -n nextcloud nextcloud-redis-replicas-0
```

### General logs

```bash
kubectl logs -n nextcloud deployment/nextcloud --tail=50
kubectl logs -n nextcloud nextcloud-postgresql-0 --tail=20
```

### Pod not starting

```bash
kubectl get pods -n nextcloud
kubectl describe pod -n nextcloud -l app.kubernetes.io/name=nextcloud
```
