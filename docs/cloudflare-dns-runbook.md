# Cloudflare DNS Setup Runbook

> **Status:** Cloudflare configured — API token ready, cluster integration pending
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

> ℹ️ The ingress-nginx external IP is determined after deployment — run `kubectl get svc -n ingress-nginx` to find it.

| Hostname | Type | Value | Notes |
|---|---|---|---|
| `argocd.fiddlestick.org` | A | `<ingress IP>` | ArgoCD UI |
| `podinfo.fiddlestick.org` | A | `<ingress IP>` | Smoke-test workload |

Add entries to this table as new services are deployed. All records point at the same ingress IP.

> ⚠️ These are real public DNS records resolving to a private LAN IP (`192.168.1.2xx`). They will only work on your LAN (or via Tailscale). That is intentional — the domain is used for cert issuance only, not for public exposure.

---

## Checklist

- [x] Cloudflare account created ✅
- [x] `fiddlestick.org` added to Cloudflare ✅
- [x] Nameservers updated at Hover ✅
- [x] Propagation verified (`dig NS fiddlestick.org`) ✅
- [x] API token created and stored in password manager ✅
- [ ] API token stored as Sealed Secret in cluster (see cert-manager runbook)
- [ ] Ingress IP determined and DNS records added
