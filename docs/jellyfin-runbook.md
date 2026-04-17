# Jellyfin Runbook

> **Status:** Active — running at `https://jellyfin.fiddlestick.org`
> See `docs/media-server-runbook.md` for Sonarr/Radarr/Bazarr/ARM details.

---

## Overview

Jellyfin is the homelab media server. Authentication is via Authentik LDAP outpost —
users log in with their Authentik username and password directly in any Jellyfin client,
including TV apps that can't do browser-based OAuth.

| Component | Details |
|---|---|
| URL | `https://jellyfin.fiddlestick.org` |
| Namespace | `jellyfin` |
| Auth | Authentik LDAP outpost |

---

## Key Files

- `infrastructure/jellyfin/jellyfin.yaml` — Deployment, Service, Ingress, PVCs
- Jellyfin config is stored on a PVC (not in git) — plugin config, library config, etc.

---

## Authentication — Authentik LDAP

Jellyfin uses the **LDAP-Auth** plugin (official Jellyfin plugin) to authenticate users
against the Authentik LDAP outpost.

### Authentik side

- **LDAP Provider:** `ldap` (Cached binding, Direct querying, default-authentication-flow)
- **Application:** `LDAP` — policy-bound to `family` group
- **Outpost:** `ldap-outpost` — managed by Authentik's Kubernetes integration
- **In-cluster endpoint:** `ak-outpost-ldap-outpost.authentik.svc.cluster.local:389`
- **Base DN:** `DC=ldap,DC=goauthentik,DC=io`

### Jellyfin LDAP-Auth plugin settings

Located at **Dashboard → Plugins → LDAP-Auth**:

| Setting | Value |
|---|---|
| LDAP Server | `ak-outpost-ldap-outpost.authentik.svc.cluster.local` |
| LDAP Port | `389` |
| Secure LDAP | unchecked |
| Base DN | `DC=ldap,DC=goauthentik,DC=io` |
| LDAP Search Filter | `(objectClass=user)` |
| LDAP Search Attributes | `cn` |
| LDAP UID Attribute | `cn` |
| LDAP Username Attribute | `cn` |
| Bind User | `cn=doug,ou=users,DC=ldap,DC=goauthentik,DC=io` |
| Bind Password | Doug's Authentik password |
| Enable user creation | checked |
| Admin Filter | `(memberOf=cn=admins,ou=groups,DC=ldap,DC=goauthentik,DC=io)` |

### Adding a new family user

1. Create the user in Authentik (Directory → Users → Create), add to `family` group
2. The user can log in to Jellyfin immediately — their account is auto-created on first login
3. After first login, go to **Dashboard → Users → \<username\>** and configure library access

### User library access

- **Doug:** access to all libraries including Rip Queue; Server Administrator
- **MJ:** access to family libraries; Rip Queue excluded

---

## Installed Plugins

| Plugin | Version | Purpose |
|---|---|---|
| LDAP-Auth | 22.0.0.0 | Authentik LDAP authentication |

| LDAP-Auth | 22.0.0.0 | Authentik LDAP authentication |

---

## Troubleshooting

### Login fails with "Invalid username or password"

Check the LDAP outpost logs first:
```bash
kubectl -n authentik logs -l app=ak-outpost-ldap-outpost --tail=30
```

Look for `Bind request` events. If the bind succeeds in the outpost but Jellyfin still
rejects the login, the Jellyfin user account may have been created by the SSO plugin
and is routing auth through SSO instead of LDAP. Fix: delete the Jellyfin user account
and let LDAP recreate it on next login.

### New user logs in but sees no libraries

The auto-created account has no library access by default. Go to **Dashboard → Users →
\<username\>** and grant library access manually.

### LDAP outpost pod not running

```bash
kubectl -n authentik get pods | grep ldap
```

Authentik manages this pod — if it's missing, check Authentik's outpost configuration
at **Applications → Outposts → ldap-outpost** and trigger a reconciliation.

### Check Jellyfin logs

```bash
kubectl -n jellyfin logs deployment/jellyfin --tail=50 | grep -i -E "ldap|auth|error"
```
