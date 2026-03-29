# Router Setup Runbook — Homelab Provisioning

## Context

This runbook covers the network configuration decisions and any router-side steps required before provisioning homelab servers.

Server IPs are configured statically on each server via autoinstall `user-data` rather than via DHCP reservations. This avoids any dependency on router DHCP behavior and makes each server fully self-contained with respect to its network identity.

**Environment:**
- Router: Verizon FiOS G1100
- Subnet: `192.168.1.x`
- Gateway: `192.168.1.1`
- DNS: `192.168.1.1` (primary), `1.1.1.1` (fallback)
- Control node: Laptop (or devpod on laptop)

---

## IP Address Plan

The router's dynamic DHCP pool is left unchanged to avoid disrupting existing devices. Server addresses are carved out of the upper range, above the highest known dynamic lease.

| Range | Purpose |
|---|---|
| `192.168.1.1` | Router gateway |
| `192.168.1.2 – .199` | Dynamic DHCP — existing devices, left as-is |
| `192.168.1.200 – .249` | Homelab servers — statically configured on each server |
| `192.168.1.250 – .254` | Available |

The `.200–.249` block provides 50 slots, comfortably accommodating the current 6 servers with room to grow to ~15 or beyond.

> **Note:** No router-side DHCP configuration is required. Static IPs are set directly on each server during autoinstall and do not interact with the router's DHCP pool.
>
> **Why the DHCP pool end is not restricted:** The G1100 does not provide a usable DHCP reservation UI, and existing dynamic leases extend as high as `.232` — capping the pool end at `.199` would cut off those devices on their next renewal. Since server IPs are statically configured on the servers themselves, there is no risk of the router dynamically assigning a conflicting address into the `.200–.249` block. The pool restriction is therefore unnecessary and has been intentionally skipped.

---

## Server Hostname and IP Assignments

| Hostname | IP | Hardware | Role |
|---|---|---|---|
| `hl-01` | `192.168.1.200` | Wyse 5070 (4GB/15GB) | K8s control plane |
| `hl-02` | `192.168.1.201` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-03` | `192.168.1.202` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-04` | `192.168.1.203` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-05` | `192.168.1.204` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-06` | `192.168.1.205` | Wyse 5070 (8GB/64GB) | K8s worker |
| `nas-01` | `192.168.1.3` | Synology NAS | NAS |

---

## Netplan Static IP Configuration (per server)

Each server's static IP is configured via Netplan in the autoinstall `user-data`. The values that differ per server are the IP address and hostname — everything else is shared.

```yaml
network:
  version: 2
  ethernets:
    eth0:                          # interface name may differ — verify on first boot
      dhcp4: false
      addresses:
        - 192.168.1.200/24         # change per server
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.1
          - 1.1.1.1
```

> **Interface name:** Ubuntu 24.04 uses predictable interface names (`enp1s0`, `eno1`, etc.) rather than `eth0`. The actual name depends on the hardware. If autoinstall fails to configure networking, boot the server and run `ip link` to find the correct interface name, then update the Netplan config in `/etc/netplan/`.

---

## /etc/hosts on Control Node

Add the following entries to `/etc/hosts` on the Ansible control node. This provides hostname resolution without depending on router DNS, and ensures Ansible works reliably regardless of router behavior.

```
# Homelab servers
192.168.1.200   hl-01
192.168.1.201   hl-02
192.168.1.202   hl-03
192.168.1.203   hl-04
192.168.1.204   hl-05
192.168.1.205   hl-06
192.168.1.3     nas-01

# Kubernetes
192.168.1.199   k8s-api   # kube-vip control plane VIP
```

On Linux/macOS: `/etc/hosts`  
On WSL: `/etc/hosts` inside the WSL instance, and optionally `C:\Windows\System32\drivers\etc\hosts` on the Windows host if you also want resolution from PowerShell/CMD.

---

## Verification

After each server is provisioned and booted, verify from the control node:

```bash
# Confirm IP is reachable
ping hl-01

# Confirm SSH access (once autoinstall is complete)
ssh ansible@hl-01
```

---

## Checklist

- [ ] IP plan reviewed — `.200–.249` block confirmed clear of existing leases
- [ ] Hostname/IP assignments recorded in this document
- [ ] `/etc/hosts` entries added to control node
- [ ] Netplan interface name verified for Wyze 5070 hardware
- [ ] Connectivity verified for each server post-provisioning (`ping`, then `ssh`)

---

## Next Steps

With the network plan locked, proceed to:

1. **autoinstall `user-data`** — bakes hostname, static IP, SSH key, and base user into each server at install time
2. **Ansible inventory** — uses hostnames from this document
3. **Control node SSH setup** — keypair whose public key is seeded via autoinstall
