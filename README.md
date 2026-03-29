# Homelab

Infrastructure-as-code for a personal Kubernetes homelab built on Dell Wyse 5070 thin clients.

## Hardware

| Host | RAM | Storage | Role |
|------|-----|---------|------|
| hl-01 | 4GB | 15GB | Kubernetes control plane |
| hl-02 – hl-06 | 8GB | 64GB | Kubernetes workers |
| nas-01 | — | — | Synology NAS (persistent storage) |

**Network:** `192.168.1.x` — nodes are statically configured at `.200–.205`.

## Repo Structure

```
ansible.cfg               # Ansible configuration
inventory.yml             # Host and group definitions
user-data.yml             # Ubuntu autoinstall template (update hostname + IP per server)
router-setup-runbook.md   # Network planning and IP assignments
usb-prep-install-runbook.md  # OS install procedure
```

## Provisioning

1. **Network** — review IP assignments in `router-setup-runbook.md`
2. **OS install** — follow `usb-prep-install-runbook.md` to install Ubuntu 24.04 on each node via USB autoinstall
3. **Ansible** — once all nodes are up, verify connectivity:
   ```bash
   ansible all -m ping
   ```

## Prerequisites

- [1Password](https://1password.com) with SSH agent enabled (provides the `ansible_homelab` key)
- Ansible installed on the control node
- `/etc/hosts` entries for all nodes (see `router-setup-runbook.md`)
