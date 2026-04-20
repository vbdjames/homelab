# Authentik Runbook

Authentik is the homelab identity provider (IdP). It provides OAuth2/OIDC single sign-on and LDAP authentication across services.

## Architecture

- **Helm chart:** `authentik` v2026.2.2 from `https://charts.goauthentik.io`
- **PostgreSQL:** bundled Bitnami subchart, NFS-backed PVC
- **User directory:** lldap (separate deployment in `lldap` namespace) — Authentik syncs from it via LDAP
- **Ingress:** `https://authentik.fiddlestick.org`
- **Email:** Fastmail SMTP for password resets and notifications

## Key files

- `apps/authentik.yaml` — ArgoCD Application (multi-source: git + Helm chart)
- `infrastructure/authentik/secrets-sealed.yaml` — SealedSecret with secret-key, db-password, smtp credentials

## Secrets

The `authentik-secrets` SealedSecret (namespace `authentik`) contains:
- `secret-key` — random 50-char string; **never change after first deploy** (invalidates all sessions and tokens)
- `db-password` — PostgreSQL password for the `authentik` user
- `smtp-username` — Fastmail address used for outbound email
- `smtp-password` — Fastmail app password created for Authentik

## Post-Deploy Setup

### 1. Initial admin setup

Navigate to `https://authentik.fiddlestick.org/if/flow/initial-setup/` and set the admin email and password.

### 2. Connect lldap as LDAP source (historical — lldap no longer used)

> lldap has been replaced by native Authentik user management. This section is kept for
> reference only. The lldap LDAP source is disabled in Authentik.



This syncs your existing lldap users into Authentik.

1. Go to **Directory → Federation & Social login → Add** → choose **LDAP Source**
2. Fill in:
   - **Name:** `lldap`
   - **Slug:** `lldap`
   - **Server URI:** `ldap://lldap.lldap.svc.cluster.local:3890`
   - **Bind DN:** `uid=admin,ou=people,dc=fiddlestick,dc=org`
   - **Bind password:** lldap admin password (from `lldap-secrets` → `ldap-admin-password`)
   - **Base DN:** `dc=fiddlestick,dc=org`
3. Under sync settings:
   - **User DN:** `ou=people,dc=fiddlestick,dc=org`
   - **Group DN:** `ou=groups,dc=fiddlestick,dc=org`
4. Save, then trigger a sync (see [Triggering a sync](#triggering-a-sync) below)

After a successful sync, lldap users appear under **Directory → Users** but in the `Root/goauthentik.io` virtual path — not in `Root/users`. The `users` path is local Authentik accounts only (e.g. `akadmin`). Both paths show up in the same user list; use the folder tree on the left to navigate between them.

### 3. Create an OAuth2/OIDC provider for Immich

See the [Immich section](#immich-oidc-provider) below.

### Triggering a sync

The UI sync button can be unreliable. If users don't appear after clicking it, trigger from the worker pod:

```bash
kubectl -n authentik exec deploy/authentik-worker -- /bin/bash -c "
cd /; DJANGO_SETTINGS_MODULE=authentik.root.settings python3 -c \"
import django; django.setup()
from authentik.sources.ldap.models import LDAPSource
from authentik.sources.ldap.tasks import ldap_sync
s = LDAPSource.objects.first()
ldap_sync.send(str(s.pk))
print('Sync triggered for:', s.name)
\"" 2>&1 | grep -v "^{" | grep -v "^$"
```

Then check worker logs: `kubectl -n authentik logs deploy/authentik-worker --tail=20`

---

## lldap Reference

lldap is the lightweight LDAP user directory that backs Authentik.

- **Web UI:** `https://lldap.fiddlestick.org`
- **Admin user:** `vbdjames@gmail.com` (also accessible as `uid=admin,ou=people,dc=fiddlestick,dc=org`)
- **In-cluster LDAP:** `ldap://lldap.lldap.svc.cluster.local:3890`
- **Base DN:** `dc=fiddlestick,dc=org`
- **Users OU:** `ou=people,dc=fiddlestick,dc=org`
- **Groups OU:** `ou=groups,dc=fiddlestick,dc=org`

### Key files

- `apps/lldap.yaml` — ArgoCD Application
- `infrastructure/lldap/lldap.yaml` — Deployment, Service, Ingress
- `infrastructure/lldap/secrets-sealed.yaml` — SealedSecret with `ldap-admin-password` and `jwt-secret`

### User management

Users are managed directly in Authentik at **Directory → Users**. lldap is no longer used.

**Groups:**
- `authentik Admins` (built-in) — grants superuser access to Authentik itself
- `admins` — used for app-level role mapping (Grafana, ArgoCD, etc.)
- `family` — used for access control on family-facing apps

**Current users:**
- `akadmin` — break-glass account; keep password in 1Password, do not use day-to-day
- `doug` — primary admin; member of `authentik Admins`, `admins`, and `family`
- `mj` — family member; member of `family`
- `ldap-service` — LDAP bind account for Jellyfin and Calibre-Web; path `serviceaccounts`;
  member of `authentik Admins` (required for LDAP user search — see note below)
- `homepage` — Calibre-Web OPDS widget account for Homepage dashboard; path `serviceaccounts`;
  member of `family` (bind-only — does not need `authentik Admins`)

**Adding a new user:** Directory → Users → Create. Set path to `users`, assign to appropriate
groups, set a password via the Set Password button.

---

## LDAP Outpost

An LDAP outpost is deployed for apps that can't use OIDC (Jellyfin, Calibre-Web).
Authentik manages the outpost pod directly via its Kubernetes integration.

**In-cluster LDAP endpoint:** `ak-outpost-ldap-outpost.authentik.svc.cluster.local:389`  
**Base DN:** `DC=ldap,DC=goauthentik,DC=io`  
**Users OU:** `ou=users,DC=ldap,DC=goauthentik,DC=io`  
**Groups OU:** `ou=groups,DC=ldap,DC=goauthentik,DC=io`  
**User DN format:** `cn=<username>,ou=users,DC=ldap,DC=goauthentik,DC=io`  
**Service accounts DN format:** `cn=<username>,ou=serviceaccounts,DC=ldap,DC=goauthentik,DC=io`

The outpost is configured with:
- **Provider:** `ldap` (Cached binding, Direct querying, default-authentication-flow)
- **Application:** `LDAP` — policy-bound to `family` group only
- **Integration:** Local Kubernetes Cluster (Authentik manages the pod)

### LDAP bind accounts

Apps that use LDAP need a bind account to search the directory. The `ldap-service` account
serves this role for all LDAP-connected apps.

**Important:** The bind account must be a member of `authentik Admins` to search for other
users. A regular Authentik user can only see themselves in LDAP — `authentik Admins`
membership grants the superuser flag required for directory-wide search. The bind account's
path (`serviceaccounts`) and group membership (`family`) do not affect search capability.

**Note:** Accounts that only need to bind as themselves (e.g. for OPDS widget auth) only
need `family` group membership — `authentik Admins` is not required.

**Note:** When Calibre-Web is configured for LDAP, it authenticates *all* users via LDAP —
including accounts created locally in the admin UI. Local password hashes are not used as
a fallback. Any account used for OPDS/API access must therefore exist in Authentik.

**Bind account DN:** `cn=ldap-service,ou=serviceaccounts,DC=ldap,DC=goauthentik,DC=io`  
**Password:** stored in 1Password as `homelab — ldap-service`

To restart the outpost (e.g. after config changes):
```bash
kubectl rollout restart deployment/ak-outpost-ldap-outpost -n authentik
kubectl rollout status deployment/ak-outpost-ldap-outpost -n authentik
```

To check outpost health:
```bash
kubectl -n authentik get pods | grep ldap
kubectl -n authentik logs ak-outpost-ldap-outpost-<pod-id> --tail=30
```

---

## Immich OIDC Provider

Create an OAuth2/OIDC provider for Immich:

1. Go to **Applications → Providers → Create** → choose **OAuth2/OpenID Provider**
2. Fill in:
   - **Name:** `immich`
   - **Client type:** Confidential
   - **Client ID:** (auto-generated or set to `immich`)
   - **Client Secret:** (auto-generated — copy this for Immich config)
   - **Redirect URIs:** `https://immich.fiddlestick.org/auth/login`
   - **Signing Key:** select the default RS256 key
3. Save, then create an **Application**:
   - Go to **Applications → Applications → Create**
   - **Name:** `Immich`
   - **Slug:** `immich`
   - **Provider:** select the provider you just created
4. Note the **Client ID** and **Client Secret** for Immich's `values.yaml`

---

## Troubleshooting

### Ingress not created / sync error about invalid host

The Authentik chart uses a flat `hosts` list (strings only), not the per-host object format used by some other charts. Correct format:

```yaml
server:
  ingress:
    hosts:
      - authentik.fiddlestick.org   # plain string, NOT "host: ..." object
    tls:
      - secretName: authentik-tls
        hosts:
          - authentik.fiddlestick.org
```

### Check pod status

```bash
kubectl -n authentik get pods
kubectl -n authentik logs deploy/authentik-server
kubectl -n authentik logs deploy/authentik-worker
```

### Check certificate

```bash
kubectl -n authentik get certificate
kubectl -n authentik describe certificate authentik-tls
```
