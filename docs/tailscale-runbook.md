# Tailscale Runbook

> **Status:** Active — subnet router running on pve-01, full LAN accessible via tailnet
> **Last updated:** 2026-04-04

---

## Overview

Tailscale provides remote access to all homelab services via a subnet router running on
`pve-01`. The subnet router advertises `192.168.1.0/24` to the tailnet — any device on
the tailnet can reach any LAN IP as if they were home.

Services are accessed via their `*.fiddlestick.org` names, which resolve to
`192.168.1.201` (ingress-nginx) via Pi-hole on LAN and via public Cloudflare DNS on
the tailnet. The same URL works everywhere.

**Why not the Tailscale Kubernetes operator:**
The operator was evaluated but removed in favour of the subnet router approach.
The operator requires per-service configuration and OAuth credentials; the subnet
router gives access to all services automatically with ACL-based access control.

---

## Subnet Router Setup (pve-01)

Tailscale is installed directly on the Proxmox host (`pve-01`), not in the cluster.
This keeps it independent of the cluster — if the cluster is down, Tailscale still works.

### Install

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### Start with subnet routing

```bash
tailscale up --advertise-routes=192.168.1.0/24 --accept-dns=false
```

> `--accept-dns=false` — prevents Tailscale from overriding Pi-hole DNS on the host.

### Approve the subnet route

In the Tailscale admin console → **Machines** → click `pve-01` → **Edit route settings**
→ enable `192.168.1.0/24`.

---

## Access Control (ACLs)

> ⚠️ ACLs not yet configured. Until they are, all tailnet devices have full LAN access.
> Configure ACLs before inviting family members or other users to the tailnet.

ACLs are configured in the Tailscale admin console → **Access Controls**.

Example to restrict a `tag:family` group to ingress only:

```json
{
  "tagOwners": {
    "tag:admin":  ["autogroup:owner"],
    "tag:family": ["autogroup:owner"]
  },
  "acls": [
    {"action": "accept", "src": ["tag:admin"],  "dst": ["*:*"]},
    {"action": "accept", "src": ["tag:family"], "dst": ["192.168.1.201:443"]}
  ]
}
```

---

## Adding a Tailnet User

1. Invite them from the Tailscale admin console → **Users → Invite**
2. Once they join, tag their device appropriately (`tag:family` etc.)
3. ACLs apply automatically based on tag

---

## Verify

```bash
# Confirm subnet router is active on pve-01
tailscale status

# From any tailnet device, confirm LAN access
ping 192.168.1.201
```

---

## Checklist

- [x] Tailscale installed on `pve-01` ✅
- [x] Subnet route `192.168.1.0/24` advertised and approved ✅
- [x] LAN accessible from tailnet ✅
- [ ] ACLs configured before inviting other users
