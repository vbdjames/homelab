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

### 2. LDAP Integration

1. Go to **Apps → Search** for "LDAP user and group backend" and install it
2. Go to **Administration Settings → LDAP / AD Integration**

**Server tab:**
| Setting | Value |
|---|---|
| Host | `ldap://lldap.lldap.svc.cluster.local` |
| Port | `3890` |
| Bind DN | `uid=svc-nextcloud,ou=people,dc=fiddlestick,dc=org` |
| Bind password | Stored in `nextcloud-secrets` (set when creating the SealedSecret) |
| Base DN | `dc=fiddlestick,dc=org` |

> **Important:** There is a small enable/disable toggle at the top of the LDAP settings page. The configuration is saved but inactive until this toggle is switched on. Easy to miss.

**Users tab:**
- Object classes: `person`
- Search attributes: `uid`, `mail`

> **Important:** The `svc-nextcloud` service account must be a member of the
> `lldap_strict_readonly` group in lldap. Without this, the account can only read
> its own entry and Nextcloud will find only 1 user (itself).

**Login attributes tab:**
- LDAP attribute: `uid`

**Groups tab:**
- Object classes: `groupOfUniqueNames`
- Base DN: `ou=groups,dc=fiddlestick,dc=org`

> **Tip:** Create a dedicated `nextcloud` group in lldap and restrict Nextcloud access
> to members of that group using the user filter:
> `(&(objectclass=person)(memberOf=cn=nextcloud,ou=groups,dc=fiddlestick,dc=org))`

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
