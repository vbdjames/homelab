# Tailscale Runbook

> **Status:** Active — redundant subnet routers on pve-01 and NAS; split DNS for fiddlestick.org via Pi-hole
> **Last updated:** 2026-04-26

---

## Overview

Tailscale provides remote access to all homelab services. Two subnet routers advertise
`192.168.1.0/24` to the tailnet — Tailscale automatically fails over between them:

| Device | Role | IP |
|--------|------|----|
| `pve-01` | Primary subnet router | `192.168.1.162` |
| `nas` | Secondary subnet router | `192.168.1.3` |

Split DNS routes `*.fiddlestick.org` queries to Pi-hole (`192.168.1.161`) when on the
tailnet — the same URLs work whether you're home or remote.

**Why not the Tailscale Kubernetes operator:**
The operator was evaluated but removed in favour of the subnet router approach.
The operator requires per-service configuration and OAuth credentials; the subnet
router gives access to all services automatically with ACL-based access control.

---

## Subnet Router Setup — Proxmox Host

Tailscale is installed directly on the Proxmox host, not in the cluster. This keeps
it independent of the cluster — if the cluster is down, Tailscale still works.

### Prerequisites — IP forwarding

Proxmox does not enable IP forwarding by default. Without it, Tailscale cannot relay
subnet traffic and will show a warning in the admin console.

```bash
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p
```

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

In the Tailscale admin console → **Machines** → click the host → **Edit route settings**
→ enable `192.168.1.0/24`.

---

## Subnet Router Setup — Synology NAS

Tailscale is available as a native package in the Synology Package Center.

### Install

Synology DSM → Package Center → search **Tailscale** → Install

### Configure subnet routing

In the Tailscale package UI, set **Advertised routes** to `192.168.1.0/24`.

### Approve the subnet route

Tailscale admin console → **Machines** → click `nas` → **Edit route settings**
→ enable `192.168.1.0/24`.

Tailscale automatically load-balances and fails over between multiple subnet routers
advertising the same route. No further configuration required.

---

## Split DNS Setup

Split DNS routes `fiddlestick.org` queries to Pi-hole when on the tailnet, so
`*.fiddlestick.org` names resolve to `192.168.1.201` (ingress-nginx) from anywhere.

### Configure in Tailscale admin console

**DNS** → **Nameservers** → **Add nameserver**:
- IP: `192.168.1.161`
- Enable **Restrict to domain**: `fiddlestick.org`

> Do not set Pi-hole as a global nameserver — that would route all DNS through Pi-hole
> including ad blocking, which may be undesirable on remote devices.

---

## Services Accessible by IP (no DNS required)

These are reachable directly by IP once the subnet route is active:

| Service | URL |
|---------|-----|
| Proxmox UI | `https://192.168.1.162:8006` |
| Pi-hole | `https://192.168.1.161` |
| NAS (DSM) | `http://192.168.1.3:5000` |

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
# Confirm subnet router is active
tailscale status

# From any tailnet device off the LAN, confirm LAN access
ping 192.168.1.201

# Confirm DNS resolution
nslookup argocd.fiddlestick.org   # should return 192.168.1.201
```

---

## Checklist

### pve-01 subnet router
- [x] IP forwarding enabled (`net.ipv4.ip_forward`, `net.ipv6.conf.all.forwarding`) ✅
- [x] Tailscale installed ✅
- [x] Subnet route `192.168.1.0/24` advertised and approved ✅

### NAS subnet router
- [x] Tailscale installed via Package Center ✅
- [x] Subnet route `192.168.1.0/24` advertised and approved ✅

### Split DNS
- [ ] Pi-hole (`192.168.1.161`) configured as split DNS nameserver for `fiddlestick.org`

### Access control
- [ ] ACLs configured before inviting other users
