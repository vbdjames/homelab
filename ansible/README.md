# Playbooks

## Universal 

- **`base.yml`** - Run on every homelab host. Base OS configuration: package updates, timezone, `djames` admin user, SSH hardening, UFW.

## Kubernetes cluster

- **`k8s-provision.yml`** - *Run on all nodes before the cluster exists.* Runs base OS config then prepares each node for Kubernetes: disables swap, loads kernel modules, sets sysctl params, installs and configures containerd, disables UFW, installs kubeadm/kubelet/kubectl.
- **`k8s-init.yml`** - *Run once to create the cluster.* Initializes the control plane with `kubeadm init`, joins all worker nodes, installs Helm, installs Cilium CNI. Fetches kubeconfig to local machine.
- **`k8s-bootstrap.yml`** - *Run once after the cluster is healthy.* Installs ArgoCD. After this playbook, ArgoCD is running and accessible — apply the root App-of-Apps manifest manually to activate GitOps.
- **`k8s-add-node.yml`** - Adds a new worker to an existing cluster. Run `base.yml` against the new node first, then this playbook.

### Run order (fresh cluster)

```bash
# From the repo root

# 1. Prepare all nodes
ansible-playbook ansible/k8s-provision.yml

# 2. Create the cluster
ansible-playbook ansible/k8s-init.yml

# 3. Bootstrap GitOps
ansible-playbook ansible/k8s-bootstrap.yml
```

### Adding a new worker node

```bash
# The new host must already be in inventory before running these
ansible-playbook ansible/base.yml --limit hl-07
ansible-playbook ansible/k8s-add-node.yml -e target_host=hl-07
```