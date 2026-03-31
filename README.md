# Homelab

Infrastructure-as-code for a personal Kubernetes homelab built on Dell Wyse 5070 thin clients.

## Hardware

| Host | RAM | Storage | Role |
|------|-----|---------|------|
| hl-01 | 4GB | 15GB | Kubernetes control plane |
| hl-02 – hl-06 | 8GB | 64GB | Kubernetes workers |
| nas | — | — | Synology NAS (persistent storage) |

**Network:** `192.168.1.x` — nodes are statically configured at `.150–.155`.

## Repo Structure

```
ansible.cfg                    # Ansible configuration
ansible/
  inventory/
    hosts.yml                  # Host and group definitions
    group_vars/
      all.yml                  # Variables shared across all hosts
  requirements.yml             # Ansible collection dependencies
  playbooks/
    base.yml                   # Base OS config for all homelab nodes
user-data/
  user-data-hl-{01-06}.yml    # Per-server Ubuntu autoinstall configs (hostname + IP pre-set)
docs/
  router-setup-runbook.md      # Network planning and IP assignments
  usb-prep-install-runbook.md  # OS install procedure
  nas-runbook.md               # NAS Kubernetes storage integration
```

## Provisioning

1. **Network** — review IP assignments in `router-setup-runbook.md`
2. **OS install** — follow `usb-prep-install-runbook.md` to install Ubuntu 24.04 on each node via USB autoinstall
3. **Ansible** — install collections, verify connectivity, then run the base playbook:
   ```bash
   ansible-galaxy collection install -r ansible/requirements.yml
   ansible all -m ping
   ansible-playbook ansible/playbooks/base.yml
   ```

## Prerequisites

- [1Password](https://1password.com) with SSH agent enabled (provides the `ansible_homelab` key)
- Ansible installed on the control node
- `~/.ssh/config` entries for all nodes (see `router-setup-runbook.md`)
