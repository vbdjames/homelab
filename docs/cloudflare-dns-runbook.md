# Cloudflare DNS Setup Runbook

> **Status:** Complete — ingress IP `192.168.1.201`, DNS records active
> **Last updated:** 2026-04-01
> **Purpose:** Delegate DNS for `fiddlestick.org` to Cloudflare so cert-manager can automate Let's Encrypt wildcard certificates via the DNS-01 challenge.

---

## Background

`fiddlestick.org` is registered at Hover. Hover has no DNS API, so cert-manager cannot automate certificate renewal. The solution is to keep the domain registered at Hover but delegate DNS to Cloudflare, which has full API support and a free tier.

After this setup:
- All DNS for `fiddlestick.org` is managed at Cloudflare
- Homelab services are reachable at `<service>.fiddlestick.org` with valid Let's Encrypt certs
- Cert-manager handles certificate issuance and renewal automatically

---

## Step 1 — Create a Cloudflare account

1. Go to cloudflare.com and create a free account
2. Add `fiddlestick.org` as a new site
3. Cloudflare will scan and import existing DNS records — review and remove anything not needed
4. Note the two Cloudflare nameservers assigned to your zone (e.g. `ns1.cloudflare.com`, `ns2.cloudflare.com`)

---

## Step 2 — Update nameservers at Hover

1. Log in to Hover and go to `fiddlestick.org` → DNS
2. Replace the existing nameservers with the two Cloudflare nameservers from Step 1
3. Save — propagation typically takes 15–30 minutes

Verify propagation:
```bash
dig NS fiddlestick.org +short
# Should return Cloudflare nameservers
```

---

## Step 3 — Create a Cloudflare API token

This token is used by cert-manager to create and delete TXT records during the DNS-01 challenge.

1. In Cloudflare: **My Profile → API Tokens → Create Token**
2. Use the **Edit zone DNS** template
3. Scope it to **Zone → fiddlestick.org only** (do not grant access to all zones)
4. Set an expiration if desired, or leave unlimited
5. Create the token and **copy it immediately** — it is only shown once

Store the token temporarily in a safe place (password manager). It will be stored permanently as a Sealed Secret in the cluster — see the cert-manager runbook.

---

## Step 4 — Add DNS records for homelab services

All homelab services share a single ingress-nginx IP (assigned by MetalLB). Add one A record per service pointing at that IP.

> ℹ️ ingress-nginx external IP: `192.168.1.201` (assigned by MetalLB). All records point here.

| Hostname | Type | Value | Notes |
|---|---|---|---|
| `argocd.fiddlestick.org` | A | `192.168.1.201` | ArgoCD UI |
| `grafana.fiddlestick.org` | A | `192.168.1.201` | Grafana dashboards |
| `alertmanager.fiddlestick.org` | A | `192.168.1.201` | Alertmanager UI |
| `home.fiddlestick.org` | A | `192.168.1.201` | Homepage dashboard |
| `paperless.fiddlestick.org` | A | `192.168.1.201` | Paperless-ngx |
| `books.fiddlestick.org` | A | `192.168.1.201` | Calibre-Web |
| `pihole.fiddlestick.org` | A | `192.168.1.161` | Pi-hole admin UI (direct, not via ingress) |
| `jellyfin.fiddlestick.org` | A | `192.168.1.201` | Jellyfin media server |
| `sonarr.fiddlestick.org` | A | `192.168.1.201` | Sonarr TV show manager |
| `radarr.fiddlestick.org` | A | `192.168.1.201` | Radarr movie manager |
| `bazarr.fiddlestick.org` | A | `192.168.1.201` | Bazarr subtitle manager |
| `podinfo.fiddlestick.org` | A | `192.168.1.201` | Smoke-test workload |

Add entries to this table as new services are deployed.

> ⚠️ These are real public DNS records resolving to private LAN IPs. They will only work on your LAN (or via Tailscale). That is intentional — the domain is used for cert issuance only, not for public exposure.

### Local DNS records (Pi-hole)

Pi-hole handles local DNS via a wildcard record — no per-service entries needed:

| Hostname | IP | Notes |
|---|---|---|
| `*.fiddlestick.org` | `192.168.1.201` | Wildcard — covers all ingress services |
| `pihole.fiddlestick.org` | `192.168.1.161` | Direct to Pi-hole LXC |
| `pve-01.fiddlestick.org` | `192.168.1.160` | Direct to Proxmox host |

---

## Checklist

- [x] Cloudflare account created ✅
- [x] `fiddlestick.org` added to Cloudflare ✅
- [x] Nameservers updated at Hover ✅
- [x] Propagation verified (`dig NS fiddlestick.org`) ✅
- [x] API token created and stored in password manager ✅
- [x] API token stored as Sealed Secret in cluster ✅
- [x] Ingress IP determined (`192.168.1.201`) and DNS records added ✅
