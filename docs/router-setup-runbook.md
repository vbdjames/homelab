# Router Setup Runbook — Homelab Provisioning

## Context

This runbook covers the network configuration decisions and any router-side steps required before provisioning homelab servers.

Server IPs are configured statically on each server via autoinstall `user-data` rather than via DHCP reservations. This avoids any dependency on router DHCP behavior and makes each server fully self-contained with respect to its network identity.

**Environment:**
- Router: Verizon FiOS G1100
- Subnet: `192.168.1.x`
- Gateway: `192.168.1.1`
- DNS: `192.168.1.1` (primary), `1.1.1.1` (fallback)
- Control node: Laptop (devpod on laptop)

---

## IP Address Plan

| Range | Purpose |
|---|---|
| `192.168.1.1` | Router gateway |
| `192.168.1.2 – .149` | Dynamic DHCP pool |
| `192.168.1.150 - .169` | Static - homelab nodes |
| `192.168.1.160` | Proxmox hypervisor (`pve-01`) |
| `192.168.1.161` | Pi-hole DNS LXC (`pihole`) |
| `192.168.1.170` | HP 1820 managed switch (management IP) |
| `192.168.1.171 – .199` | Reserved — future static devices |
| `192.168.1.200 – .254` | MetalLB load balancer pool (not in router DHCP) |

> **Why the DHCP pool is capped at `.149`:** MetalLB requires exclusive use of `.200–.254` to assign external IPs to Kubernetes services. These addresses must not be assigned by the router's DHCP pool. The G1100's DHCP pool end has been set to `.149` to enforce this boundary. Existing dynamic leases that previously extended above `.149` were either moved to DHCP reservations or left to expire.

---

## Server Hostname and IP Assignments

| Hostname | IP | Hardware | Role |
|---|---|---|---|
| `hl-01` | `192.168.1.150` | Wyse 5070 (4GB/15GB) | K8s control plane |
| `hl-02` | `192.168.1.151` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-03` | `192.168.1.152` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-04` | `192.168.1.153` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-05` | `192.168.1.154` | Wyse 5070 (8GB/64GB) | K8s worker |
| `hl-06` | `192.168.1.155` | Wyse 5070 (8GB/64GB) | K8s worker |
| `nas`   | `192.168.1.3`   | Synology NAS | NAS (DHCP reservation) |

---

## Netplan Static IP Configuration (per server)

Each server's static IP is configured via Netplan in the autoinstall `user-data`. The values that differ per server are the IP address and hostname — everything else is shared.

```yaml
network:
  version: 2
  ethernets:
    enp1s0:                        # confirmed interface name on Wyse 5070
      dhcp4: false
      addresses:
        - 192.168.1.150/24         # change per server
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.1
          - 1.1.1.1
```

> **Interface name:** Confirmed as `enp1s0` on Wyse 5070 hardware running Ubuntu 24.04. If you reinstall and networking fails, boot the server and run `ip link` to verify.

---

## ~/.ssh/config on Control Node

Add the following entries to `~/.ssh/config` on the Ansible control node. This handles hostname resolution for SSH-based tools (ansible, `ssh`, `scp`) without touching system files.

```
Host hl-*
    User ansible
    IdentityFile ~/.ssh/ansible_homelab
    StrictHostKeyChecking accept-new

Host hl-01
    HostName 192.168.1.150
Host hl-02
    HostName 192.168.1.151
Host hl-03
    HostName 192.168.1.152
Host hl-04
    HostName 192.168.1.153
Host hl-05
    HostName 192.168.1.154
Host hl-06
    HostName 192.168.1.155

Host nas
    HostName 192.168.1.3
```

`StrictHostKeyChecking accept-new` automatically adds new host keys on first connection without prompting, but still rejects changed keys — appropriate for freshly provisioned nodes.

---

## Verification

After each server is provisioned and booted, verify from the control node:

```bash
# Confirm SSH access and hostname (once autoinstall is complete)
ssh hl-01 hostname

# Confirm Ansible can reach all nodes
ansible all -m ping
```

---

## Checklist

- [x] DHCP pool capped at `.149` ✅
- [x] MetalLB range `.200–.254` confirmed clear ✅
- [x] Hostname/IP assignments recorded in this document ✅
- [x] SSH config entries added to control node (`~/.ssh/config`) ✅
- [x] Netplan interface name confirmed as `enp1s0` for Wyse 5070 hardware ✅
- [x] Connectivity verified for each server post-provisioning (`ssh hl-0N hostname`) ✅

---

## Next Steps

With the network plan locked, proceed to:

1. **autoinstall `user-data`** — bakes hostname, static IP, SSH key, and base user into each server at install time (`user-data/user-data-hl-{01-06}.yml`)
2. **Ansible inventory** — `ansible/inventory/hosts.yml` uses hostnames and IPs from this document

