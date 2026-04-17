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

Auto-provisioned OIDC users are created with no permissions (can log in but see a
blank dashboard). After a new user's first login, grant them access via the Django
admin UI:

1. Log in as an admin at `https://paperless.fiddlestick.org/admin/`
2. Go to **Authentication → Users** → click the new user
3. Set **Staff status** and **Superuser status** as appropriate
4. Save

> **Note:** This is a known rough edge. A future improvement would be to auto-grant
> permissions based on the Authentik group claim.

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
