# Authentication Plan

> **Goal:** Authentik as the single identity provider for all homelab apps. lldap removed.
> Users: Doug (admin), MJ (family) — Barb, Michael, Meagan, Alesha future family tier.

---

## End State

| App | Auth method | Users | Status |
|-----|-------------|-------|--------|
| Immich | Authentik OIDC | family | ✅ Done |
| Nextcloud | Authentik OIDC | family | ✅ Done |
| Jellyfin | Authentik LDAP outpost | family | ✅ Done |
| Paperless | Authentik OIDC | family | ✅ Done |
| Calibre-Web | Authentik LDAP outpost | family | ✅ Done |
| Grafana | Authentik OIDC | admins | ✅ Done |
| ArgoCD | Authentik OIDC | admins | ✅ Done |
| Homepage | None (Tailscale-only) | admins | No action needed |
| ARM | None (Tailscale-only) | admins | No action needed |
| Radarr | None (Tailscale-only) | admins | No action needed |
| Sonarr | None (Tailscale-only) | admins | No action needed |
| Bazarr | None (Tailscale-only) | admins | No action needed |
| Alertmanager | None (Tailscale-only) | admins | No action needed |
| Prometheus | None (Tailscale-only) | admins | No action needed |
| Audiobookshelf | Authentik OIDC | family | Future (not yet deployed) |
| Karakeep | TBD — investigate OIDC support | family | Future (not yet deployed) |
| Forgejo | Authentik OIDC | admins | Future (not yet deployed) |
| Home Assistant | Authentik OIDC | family | Future (Proxmox VM, not cluster) |

**Auth methods explained:**
- **Authentik OIDC** — full SSO; users log in via Authentik, app auto-provisions accounts on first login
- **Authentik LDAP outpost** — users log in with Authentik credentials via LDAP; requires manual user import into the app
- **None (Tailscale-only)** — no additional auth needed; Tailscale membership is the access control

---

## Groups

| Group | Members | Purpose |
|-------|---------|---------|
| `admins` | Doug | Full access to all apps including infrastructure |
| `family` | MJ (+ future) | Access to family-facing apps only |

---

## Phase 1 — Foundation ✅

- [x] Create `admins` group in Authentik
- [x] Create `family` group in Authentik
- [x] Create Doug user in Authentik — assigned to `admins`, `family`, and `authentik Admins`
- [x] Create MJ user in Authentik — assigned to `family`
- [x] Disconnect lldap LDAP source from Authentik (disabled, not deleted)
- [x] Verify Immich still works with Authentik OIDC

> Doug's Authentik account is now the day-to-day admin account. `akadmin` kept as break-glass.
> **Note:** Admin access to Authentik itself requires membership in the built-in `authentik Admins`
> group — separate from our custom `admins` group which is used for app-level role mapping.

---

## Phase 2 — Migrate Nextcloud ✅

- [x] Create Authentik OIDC provider + application for Nextcloud
- [x] Install `user_oidc` app in Nextcloud via `occ`
- [x] Configure Nextcloud OIDC via `occ user_oidc:provider` (UI discovery check unreliable)
- [x] Set `allow_local_remote_servers = true` in Nextcloud config (required — Nextcloud blocks
      server-side requests to private IPs by default; Authentik's internal hostname triggers this)
- [x] Doug made Nextcloud admin via OIDC-provisioned account
- [x] lldap LDAP backend disabled in Nextcloud
- [x] Verified login via Authentik OIDC

---

## Phase 3 — Family Apps SSO (Near-term)

Bring remaining family apps onto Authentik so MJ (and future users) get per-user accounts.

### Paperless ✅
Native OIDC support via django-allauth. Auto-provisions users on first login.
`PAPERLESS_DISABLE_REGULAR_LOGIN=true` skips the login method selector and goes
straight to Authentik.

- [x] Create Authentik OIDC provider + application for Paperless
- [x] Add OIDC env vars to Paperless deployment
- [x] Test login and auto-provisioning
- [ ] Decide on document sharing model (shared library vs per-user)

### Jellyfin ✅
No native OIDC. Using Authentik LDAP outpost instead — users log in with their Authentik
credentials directly. Works on all clients including TV apps (Apple TV, Android TV, etc.)
where browser-based OAuth redirects are not possible.

- [x] Create Authentik LDAP provider + application (family group binding)
- [x] Deploy Authentik LDAP outpost (managed by Kubernetes integration)
- [x] Install LDAP-Auth plugin in Jellyfin
- [x] Configure LDAP-Auth plugin pointing at outpost
- [x] Test Doug and MJ login
- [x] Configure per-user library access (Rip Queue restricted to Doug)

### Calibre-Web
No OIDC support, but native LDAP authentication is supported. Point it at Authentik's LDAP
outpost — users log in with their Authentik credentials directly, no double login.

Note: LDAP does not auto-provision users. Doug and MJ must be imported via the
"Import LDAP Users" button in Calibre-Web admin after LDAP is configured.

- [x] Deploy Authentik LDAP outpost (shared with Jellyfin — already live)
- [x] Create LDAP provider + application in Authentik
- [x] Configure Calibre-Web LDAP: point at Authentik outpost, set bind DN and user filter
- [x] Doug and MJ auto-created on first login (Import LDAP Users button not needed)
- [x] Test login with Authentik credentials
- [x] Grant Doug admin via sqlite (LDAP users created with role=0); demote local admin

---

## Phase 4 — Admin Apps OIDC (Near-term)

Replace local admin accounts with Authentik OIDC. Not a security requirement (Tailscale
already gates access), but eliminates shared `admin` accounts and gives proper audit trails.

### Grafana ✅
Native OIDC/OAuth2 support. Can map Authentik groups to Grafana roles (admins → GrafanaAdmin).

- [x] Create Authentik OIDC provider + application for Grafana
- [x] Configure Grafana OIDC via Helm values
- [x] Map `admins` group → Grafana Admin role
- [x] Test login
- [ ] Optionally disable local admin account

### ArgoCD ✅
Native OIDC support. Can map Authentik groups to ArgoCD RBAC roles.

- [x] Create Authentik OIDC provider + application for ArgoCD
- [x] Configure ArgoCD OIDC via argocd-cm ConfigMap
- [x] Map `admins` group → ArgoCD admin role (policy.default: role:admin)
- [x] Test login
- [ ] Optionally disable local admin account

---

## Phase 5 — Decommission lldap (After Phase 2)

Once Nextcloud is on OIDC and no app references lldap, remove it entirely.

- [x] Confirm no app is connecting to `ldap://lldap.lldap.svc.cluster.local:3890`
- [x] Remove `apps/lldap.yaml` ArgoCD Application
- [x] Remove `infrastructure/lldap/` directory
- [x] Remove lldap sealed secrets
- [ ] Remove lldap DNS entry if applicable
- [ ] Archive or remove `lldap-runbook.md`

---

## Notes

**Break-glass access:** Keep `akadmin` in Authentik as a local account (not synced from anywhere).
Store its password in a password manager. Use it only if Authentik OIDC is broken and you need
to access apps directly.

**App-side access control:** Group membership (admins/family) controls which apps users can
reach via Authentik. Fine-grained within-app permissions (e.g. which Jellyfin libraries MJ
sees, which Nextcloud folders are shared) are managed inside each app, not in Authentik.

**Future users:** Adding Barb, Michael, Meagan, or Alesha = create user in Authentik, add to
`family` group. They get access to all family apps automatically on first login.

**Forward Auth:** Not implemented — all admin-only apps are Tailscale-gated, which is
sufficient. Revisit if any services are ever exposed publicly.

**TODO — Authentik app portal icons:** Once all apps are configured, add icons to each
Authentik Application via Edit → Icon. Use the walkxcode CDN:
`https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/<app-name>.png`
