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
ansible.cfg                        # Ansible configuration
ansible/
  inventory/
    hosts.yml                      # Host and group definitions
    group_vars/
      all.yml                      # Variables shared across all hosts
  requirements.yml                 # Ansible collection dependencies
  README.md                        # Playbook descriptions and run order
  base.yml                         # Base OS config for all homelab nodes
  k8s-provision.yml                # Kubernetes node preparation
  k8s-init.yml                     # Cluster initialization
  k8s-bootstrap.yml                # ArgoCD bootstrap (run once)
  k8s-add-node.yml                 # Add a worker node to existing cluster
  roles/
    k8s_node/                      # Swap, kernel modules, containerd, netplan
    k8s_kubeadm/                   # kubelet, kubeadm, kubectl install
    k8s_control_plane/             # kubeadm init, Helm, Cilium
    k8s_workers/                   # kubeadm join
    k8s_argocd/                    # ArgoCD bootstrap
user-data/
  user-data-hl-01.yml              # Ubuntu autoinstall config per node
  ...
docs/
  router-setup-runbook.md          # Network planning and IP assignments
  usb-prep-install-runbook.md      # OS install procedure
  nas-runbook.md                   # NAS (nas-01) Kubernetes storage integration
```

## Provisioning

1. **Network** — review IP assignments in `docs/router-setup-runbook.md`
2. **OS install** — follow `docs/usb-prep-install-runbook.md` to install Ubuntu 24.04 on each node via USB autoinstall
3. **Ansible** — install collections and verify connectivity:
   ```bash
   ansible-galaxy collection install -r ansible/requirements.yml
   ansible all -m ping
   ```
4. **Provision and build the cluster:**
   ```bash
   ansible-playbook ansible/k8s-provision.yml
   ansible-playbook ansible/k8s-init.yml
   ansible-playbook ansible/k8s-bootstrap.yml
   ```

See `ansible/README.md` for full details and the add-node workflow.

## Prerequisites

- [1Password](https://1password.com) with SSH agent enabled (provides the `ansible_homelab` key)
- Ansible installed on your local machine
- SSH config entries for all nodes (see `docs/router-setup-runbook.md`)
