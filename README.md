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
ansible.cfg                  # Ansible configuration
inventory.yml                # Host and group definitions
requirements.yml             # Ansible collection dependencies
group_vars/
  all.yml                    # Variables shared across all hosts
playbooks/
  base.yml                   # Base configuration for all homelab nodes
user-data.yml                # Ubuntu autoinstall template (update hostname + IP per server)
router-setup-runbook.md      # Network planning and IP assignments
usb-prep-install-runbook.md  # OS install procedure
nas-runbook.md               # NAS (nas-01) Kubernetes storage integration
```

## Provisioning

1. **Network** — review IP assignments in `router-setup-runbook.md`
2. **OS install** — follow `usb-prep-install-runbook.md` to install Ubuntu 24.04 on each node via USB autoinstall
3. **Ansible** — install collections, verify connectivity, then run the base playbook:
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ansible all -m ping
   ansible-playbook playbooks/base.yml
   ```

## Prerequisites

- [1Password](https://1password.com) with SSH agent enabled (provides the `ansible_homelab` key)
- Ansible installed on the control node
- `/etc/hosts` entries for all nodes (see `router-setup-runbook.md`)
