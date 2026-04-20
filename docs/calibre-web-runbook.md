# Calibre-Web Runbook

> **Status:** Active — running at `https://books.fiddlestick.org`
> **Stack:** Calibre-Web Automated (CWA) · NFS storage · Fastmail SMTP

---

## Overview

Calibre-Web Automated (CWA) is a self-hosted ebook library with automatic ingestion and
metadata management. Books dropped into the ingest folder are automatically imported into
the Calibre library.

| Component | Details |
|---|---|
| URL | `https://books.fiddlestick.org` |
| Image | `ghcr.io/crocodilestick/calibre-web-automated` |
| Namespace | `calibre-web` |
| Config PVC | `calibre-web-config` (1Gi) |
| Library PVC | `calibre-web-books` (50Gi) |
| Ingest PVC | `calibre-web-ingest` (10Gi) |
| NFS storage | Synology NAS `192.168.1.3` |

---

## Authentication — Authentik LDAP

Calibre-Web uses the Authentik LDAP outpost for authentication. Users log in with their
Authentik username and password. Accounts are auto-created on first login.

### LDAP Configuration (Admin → Configuration → Feature Configuration)

| Setting | Value |
|---|---|
| LDAP Server Host Name | `ak-outpost-ldap-outpost.authentik.svc.cluster.local` |
| LDAP Server Port | `389` |
| LDAP Encryption | None |
| LDAP Authentication | Simple |
| LDAP Distinguished Name (DN) | `ou=users,DC=ldap,DC=goauthentik,DC=io` |
| LDAP User Object Filter | `(cn=%s)` |
| LDAP Administrator Username | `cn=ldap-service,ou=serviceaccounts,DC=ldap,DC=goauthentik,DC=io` |
| LDAP Administrator Password | ldap-service Authentik password (1Password) |
| LDAP Server is OpenLDAP? | Yes |
| Auto-create users from LDAP | checked |
| LDAP Group Object Filter | `(cn=%s)` |
| LDAP Group Name | `family` |
| LDAP Group Members Field | `member` |

### User Roles

Calibre-Web stores permissions as a bitmask in its SQLite database (`/config/app.db`).
New LDAP users are created with role `0` (no permissions) and must be configured after
first login.

| User | Role value | Permissions |
|---|---|---|
| doug | `479` | Full admin |
| mj | set via UI | Download, edit shelves |

**To grant Doug admin after a fresh install or database reset:**
```bash
kubectl -n calibre-web exec deployment/calibre-web -- sqlite3 /config/app.db \
  "UPDATE user SET role=479 WHERE name='doug';"
```

### Adding a New Family User

1. Have the user log in with their Authentik credentials — account is auto-created
2. Go to **Admin → Users → \<username\>** and set appropriate permissions:
   - **Download books:** yes
   - **Edit public shelves:** yes
   - **Send to device:** yes if they have an e-reader
   - Everything else: no

---

## Email / Send to Device

Calibre-Web can send books directly to e-readers via email.

### SMTP Configuration (Admin → Email Server Settings)

| Setting | Value |
|---|---|
| SMTP Hostname | `smtp.fastmail.com` |
| SMTP Port | `465` |
| Encryption | `SSL/TLS` |
| SMTP Login | `doug@dwjames.org` (primary Fastmail account, not the alias) |
| SMTP Password | Fastmail app password (stored in 1Password: `homelab — Calibre-Web SMTP`) |
| From Email | `calibre@dwjames.org` |

> ℹ️ The SMTP login must be the primary Fastmail account even when sending from an alias.
> The From address can be any alias on the account.

### Adding a New Device (e.g. Kindle, Kobo)

1. Find the device's email address:
   - **Kindle:** amazon.com → Account → Manage Your Content and Devices → Preferences → Personal Document Settings
   - **Kobo:** kobo.com → account settings

2. Add `calibre@dwjames.org` to the device's approved sender list:
   - **Kindle:** Manage Your Content and Devices → Preferences → Personal Document Settings → Approved Personal Document Email List → Add

3. In Calibre-Web, edit the user → set **Kindle/Device Email** to the device address

### Adding a New User

1. **Admin → Users → Create new user**
2. Set username, password, and email
3. Set the user's **Kindle/Device Email** if they have an e-reader
4. Ensure they add `calibre@dwjames.org` to their device's approved sender list

---

## Book Ingest

Drop books into the ingest folder — CWA will automatically import and fetch metadata.

The ingest folder is at `/cwa-book-ingest` inside the container, backed by the
`calibre-web-ingest` NFS PVC. Books can be placed here via:
- The Calibre-Web UI upload
- Directly onto the NFS share at `192.168.1.3:/volume1/kubernetes/calibre-web/calibre-web-ingest`

### Memory and Large Books

The memory limit is set to 2Gi (`infrastructure/calibre-web/calibre-web.yaml`). Very large
reference books (dictionaries, encyclopedias) may require more — monitor logs if CWA starts
crash looping after ingesting a large file:

```bash
kubectl logs -n calibre-web -l app=calibre-web --tail=50
kubectl describe pod -n calibre-web -l app=calibre-web | grep -A3 "Last State"
```

OOMKill will show `Reason: OOMKilled` and `Exit Code: 137`.

---

## Troubleshooting

### Email not sending

Check logs for SMTP errors:

```bash
kubectl logs -n calibre-web -l app=calibre-web --tail=50 | grep -i "mail\|smtp\|error"
```

Common causes:
- **535 Incorrect username/password** — ensure SMTP Login is the primary Fastmail address, not the alias
- **Book not arriving on Kindle** — check the sender (`calibre@dwjames.org`) is in the device's approved list; delivery can take a few minutes

### CrashLoopBackOff

```bash
kubectl get pods -n calibre-web
kubectl describe pod -n calibre-web -l app=calibre-web | grep -A5 "Last State"
kubectl logs -n calibre-web -l app=calibre-web --previous --tail=50
```
