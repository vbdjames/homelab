# Wallabag Runbook

> **Status:** Active — running at `https://wallabag.fiddlestick.org`
> **Stack:** Wallabag · PostgreSQL · NFS storage

---

## Overview

Wallabag is a self-hosted read-it-later service. Save articles from the web and read them
later in a clean format, with browser extensions and mobile apps available.

| Component | Details |
|---|---|
| URL | `https://wallabag.fiddlestick.org` |
| Image | `wallabag/wallabag:latest` |
| Namespace | `wallabag` |
| Database | PostgreSQL (in-cluster, `wallabag` namespace) |
| Images PVC | `wallabag-images` (5Gi, NFS) |

---

## First-Deploy Setup

After the pods come up for the first time, the database schema must be initialized manually.
`POPULATE_DATABASE=true` in the environment does **not** run the migrations automatically.

```bash
kubectl exec -n wallabag deployment/wallabag -- sh -c \
  "cd /var/www/wallabag && SYMFONY_ENV=prod bin/console wallabag:install --no-interaction"
```

This creates all tables and seeds the default config. The site will return a 500 error on
the `/login` page until this is done.

After running the install command, fix cache ownership — the install runs as root but the
app runs as `nobody`:

```bash
kubectl exec -n wallabag deployment/wallabag -- sh -c \
  "chown -R nobody:nobody /var/www/wallabag/var/cache/prod/"
```

### Post-Install Steps

1. Log in with the default credentials: `wallabag` / `wallabag`
2. Go to **Admin → Users** and rename the default user to `admin`, set a strong password
3. Update the email address on the account

---

## Authentication

Wallabag uses local accounts only (FOSUserBundle). There is no native LDAP support and no
standard way to integrate with lldap without a custom Docker image. Manage users via
**Admin → Users** in the UI.

---

## Troubleshooting

### 500 error on /login — `wallabag_internal_setting` does not exist

The database schema has not been initialized. Run the install command above.

### General errors

```bash
kubectl logs -n wallabag deployment/wallabag --tail=50
kubectl exec -n wallabag deployment/wallabag -- sh -c "cat /var/www/wallabag/var/logs/prod.log" | tail -50
```

### Pod not starting

```bash
kubectl get pods -n wallabag
kubectl describe pod -n wallabag -l app=wallabag
kubectl logs -n wallabag deployment/postgres --tail=50
```
