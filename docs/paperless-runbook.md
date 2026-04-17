# Paperless Runbook

> **Status:** Active — running at `https://paperless.fiddlestick.org`
> **Stack:** Paperless-ngx 2.13 · PostgreSQL · Redis

---

## Overview

Paperless-ngx is a self-hosted document management system. Authentication is via
Authentik OIDC — users are auto-provisioned on first login and redirected straight
to Authentik without seeing a login method selector.

| Component | Details |
|---|---|
| URL | `https://paperless.fiddlestick.org` |
| Namespace | `paperless` |
| Image | `ghcr.io/paperless-ngx/paperless-ngx:2.13` |
| Database | PostgreSQL (separate deployment in `paperless` namespace) |
| Cache | Redis (separate deployment in `paperless` namespace) |

---

## Key Files

- `infrastructure/paperless/paperless.yaml` — PVCs, Deployment, Service, Ingress
- `infrastructure/paperless/paperless-oidc-sealed.yaml` — SealedSecret containing
  the Authentik OIDC provider config (client ID, secret, discovery URL)
- `infrastructure/paperless/secrets-sealed.yaml` — DB password, secret key, admin
  credentials

---

## Authentik OIDC

Paperless uses django-allauth's `openid_connect` provider. On first login, Authentik
redirects back and Paperless auto-creates the user account.

**Authentik side:**
- Provider: `paperless` (OAuth2/OpenID, Confidential, Implicit consent)
- Application slug: `paperless`
- Redirect URI: `https://paperless.fiddlestick.org/accounts/authentik/login/callback/`
- Client ID and secret stored in the `paperless-oidc` SealedSecret

**Paperless env vars (in `paperless.yaml`):**
```yaml
- name: PAPERLESS_APPS
  value: allauth.socialaccount.providers.openid_connect
- name: PAPERLESS_ACCOUNT_EMAIL_VERIFICATION
  value: none
- name: PAPERLESS_DISABLE_REGULAR_LOGIN
  value: "true"
- name: PAPERLESS_SOCIALACCOUNT_PROVIDERS
  valueFrom:
    secretKeyRef:
      name: paperless-oidc
      key: providers
```

The `paperless-oidc` secret `providers` key contains a JSON blob:
```json
{"openid_connect":{"APPS":[{"provider_id":"authentik","name":"Authentik","client_id":"<id>","secret":"<secret>","settings":{"server_url":"https://authentik.fiddlestick.org/application/o/paperless/.well-known/openid-configuration"}}]}}
```

**Why `PAPERLESS_ACCOUNT_EMAIL_VERIFICATION=none`:** allauth defaults to requiring
email verification, which triggers a `NoReverseMatch` 500 error on new OIDC logins
because no email backend is configured.

**Why `PAPERLESS_DISABLE_REGULAR_LOGIN=true`:** Skips the "choose your login method"
page and redirects directly to Authentik. Without this, users see an intermediate
page with a "Login with Authentik" button.

---

## New User Permissions

Auto-provisioned OIDC users are created with no permissions — they can log in but
see a blank dashboard and can't do anything. After a new user's first login, configure
their account via the Django admin UI at `https://paperless.fiddlestick.org/admin/`.

### Admin users (Doug)

1. Go to **Authentication → Users → doug**
2. Check **Superuser status** (grants full access, bypasses all permission checks)
3. Leave **Staff status** unchecked unless you need Django admin access
4. Save

### Family users (MJ and future)

1. Have the user log in via Authentik first (creates the account)
2. Go to `https://paperless.fiddlestick.org/admin/` → **Authentication → Users → \<username\>**
3. Leave **Staff status** and **Superuser status** both **unchecked**
4. Scroll to **User permissions** and grant:
   - `documents | document | Can add document`
   - `documents | document | Can change document`
   - `documents | document | Can delete document`
   - `documents | document | Can view document`
   - `documents | tag | Can add/change/view tag`
   - `documents | correspondent | Can add/change/view correspondent`
   - `documents | document type | Can add/change/view document type`
5. Save

### Shared documents (Household group)

To share documents between Doug and MJ:

1. Go to **Authentication → Groups → Add group**
2. Name it `Household`, grant the same document permissions as above
3. Add Doug and MJ to the group
4. When uploading a document, set its permissions to include the `Household` group
   for documents meant to be shared; leave personal documents unshared

---

## Troubleshooting

### 500 error on first OIDC login

Almost always the email verification issue. Confirm `PAPERLESS_ACCOUNT_EMAIL_VERIFICATION=none`
is set:

```bash
kubectl -n paperless exec deployment/paperless -- env | grep EMAIL_VERIFICATION
```

### Check logs

```bash
kubectl -n paperless logs deployment/paperless --tail=50
kubectl -n paperless get pods
```

### Pod slow to start

Paperless adjusts NFS file permissions on startup — this can take 30–60 seconds.
A 502 during this window is normal. Wait and retry.

### Re-seal the OIDC secret

If you need to rotate the client secret:

```bash
kubectl create secret generic paperless-oidc \
  --namespace paperless \
  --from-literal=providers='{"openid_connect":{"APPS":[{"provider_id":"authentik","name":"Authentik","client_id":"<id>","secret":"<new-secret>","settings":{"server_url":"https://authentik.fiddlestick.org/application/o/paperless/.well-known/openid-configuration"}}]}}' \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets-controller \
           --controller-namespace=sealed-secrets \
           --format yaml > infrastructure/paperless/paperless-oidc-sealed.yaml
```
