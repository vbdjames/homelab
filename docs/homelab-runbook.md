# Homelab Kubernetes Cluster — Build Runbook

> **Status:** Active — cluster provisioning complete, ArgoCD bootstrapped, GitOps active
> **Last updated:** 2026-04-01
> **Stack:** Ubuntu 24.04 · kubeadm · Cilium · MetalLB · ArgoCD · Synology NAS (NFS)

---

## Table of Contents

1. [Architecture Decisions](#1-architecture-decisions)
2. [IP & Network Plan](#2-ip--network-plan)
3. [Prerequisites](#3-prerequisites)
4. [Phase 1 — Node Provisioning (Ansible)](#4-phase-1--node-provisioning-ansible)
5. [Phase 2 — Cluster Init (Ansible)](#5-phase-2--cluster-init-ansible)
6. [Phase 3 — Bootstrap ArgoCD](#6-phase-3--bootstrap-argocd)
7. [Repo Structure](#7-repo-structure)
8. [Runbook — Day 2 Operations](#8-runbook--day-2-operations)
9. [Confirmed Values](#9-confirmed-values)

---

## 1. Architecture Decisions

A record of every significant decision and its rationale. Update this section if anything changes.

| Decision | Choice | Rationale |
|---|---|---|
| Container runtime | containerd | Default for kubeadm; Docker not required |
| CNI | Cilium | eBPF-based, strong observability via Hubble, industry direction |
| Cluster bootstrap | kubeadm | Standard, well-documented, works well with Ansible |
| Control plane topology | Single control node | Appropriate for homelab; HA can be added later with kube-vip |
| Control plane endpoint | Static IP (`192.168.1.150`) | Simple, no DNS dependency at init time; DNS alias to be added when Pi-hole is deployed |
| Pod network CIDR | `172.16.0.0/16` | Avoids conflict with LAN (`192.168.x.x`) and work VPN (`10.x.x.x`) |
| Service CIDR | `172.17.0.0/16` | Same reasoning; clean separation from pod CIDR |
| Load balancer | MetalLB (L2 mode) | Best documentation, widely used in homelab and on-prem; L2 mode requires no BGP-capable router |
| Ingress | ingress-nginx | Standard, well-supported, pairs cleanly with cert-manager |
| TLS | cert-manager | Automates certificate lifecycle; self-signed CA internally to start |
| GitOps | ArgoCD | Better UI for learning; App-of-Apps pattern for managing infrastructure |
| Storage (primary) | NFS via Synology | RWX support, simple setup, covers most use cases |
| Storage (future) | iSCSI via Synology | To be added when block storage is needed (e.g. databases with heavy I/O) |
| Secrets | Sealed Secrets | Encrypted at rest in Git; simple operator model |
| Observability | kube-prometheus-stack + Loki | Full metrics + logs stack; standard in production environments |
| kubectl access | Local machine + control node | kubeconfig on local machine for daily use; control node as fallback |

---

## 2. IP & Network Plan

> ℹ️ Network finalized 2026-03-30. All node IPs confirmed.

### Subnet Layout

| Range | Purpose |
|---|---|
| `192.168.1.1` | Gateway (Verizon router) |
| `192.168.1.2 – 192.168.1.149` | DHCP pool (router-managed) |
| `192.168.1.150 – 192.168.1.169` | Static — nodes and NAS |
| `192.168.1.170` | Static — HP 1820-24G managed switch (management IP) |
| `192.168.1.171 – 192.168.1.199` | Reserved for future static devices |
| `192.168.1.200 – 192.168.1.254` | MetalLB IP pool (not in router DHCP) |

> ℹ️ Network cleanup fully completed 2026-03-30. All ranges clear.

### Node IPs

| Host | Role | IP |
|---|---|---|
| `hl-01` | Control plane | `192.168.1.150` |
| `hl-02` | Worker | `192.168.1.151` |
| `hl-03` | Worker | `192.168.1.152` |
| `hl-04` | Worker | `192.168.1.153` |
| `hl-05` | Worker | `192.168.1.154` |
| `hl-06` | Worker | `192.168.1.155` |
| `nas` | NAS | `192.168.1.3` |

### Cluster CIDRs

| Purpose | CIDR |
|---|---|
| Pod network | `172.16.0.0/16` |
| Service network | `172.17.0.0/16` |
| MetalLB pool | `192.168.1.200 – 192.168.1.254` |

### Network Cleanup Status

- [x] Shrink DHCP pool end to `192.168.1.149` ✅
- [x] Add DHCP reservations for fixed devices ✅
  - Synology NAS pinned at `192.168.1.3`
  - QCA4002 device at `192.168.1.100`
  - Cisco extender/mesh node at `192.168.1.101`
  - Vizio TV at `192.168.1.102`
- [x] Verify `.150–.169` clear ✅
- [x] MetalLB pool set to `.200–.244` (capped due to two unresolved static devices) ✅
- [x] Identify and move `192.168.1.248` (Mac Mini / Kubuntu) — resolved 2026-03-30, now at `.56` ✅
- [x] Identify and move `192.168.1.245` (HP 1820-24G switch) — resolved 2026-03-30, moved to `.170` ✅
- [x] MetalLB pool expanded to full `192.168.1.200–192.168.1.254` ✅
- [x] Update node IPs in `ansible/inventory/hosts.yml` ✅

---

## 3. Prerequisites

### On your local machine

> ℹ️ Running in a devcontainer — `kubectl` and `argocd` CLI are installed via `.devcontainer/Dockerfile` and available automatically.

- [x] Ansible installed (`pip install ansible`)
- [x] `kubectl` installed and on PATH (devcontainer)
- [x] `argocd` CLI installed and on PATH (devcontainer)
- [x] `kubeseal` CLI installed and on PATH (devcontainer)
- [x] SSH key deployed to all nodes (`ssh-copy-id user@NODE_IP`)
- [x] Git repo cloned locally

### On each node (should be done by existing Ansible plays)

- [x] Ubuntu 24.04 installed
- [x] SSH accessible
- [x] Sudo without password for Ansible user
- [x] Static IP set via netplan (see Phase 1)

---

## 4. Phase 1 — Node Provisioning (Ansible)

**Goal:** Take bare Ubuntu 24.04 nodes to a state ready for `kubeadm`.
**Playbook:** `ansible/k8s-provision.yml`
**Runs against:** all nodes (control + workers)

### Ansible Repo Structure

```
ansible/
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       └── all.yml
├── roles/
│   ├── k8s_node/         # swap, kernel modules, sysctl, containerd, UFW, netplan
│   ├── k8s_kubeadm/      # install kubeadm, kubelet, kubectl
│   ├── k8s_control_plane/ # kubeadm init, kubeconfig, Helm, Cilium
│   ├── k8s_workers/      # kubeadm join
│   └── k8s_argocd/       # one-time ArgoCD bootstrap
├── README.md              # playbook descriptions and run order
├── base.yml               # base OS config (all homelab nodes)
├── k8s-provision.yml      # runs base + k8s_node + k8s_kubeadm on all nodes
├── k8s-init.yml           # control plane init + workers join + Cilium
├── k8s-bootstrap.yml      # ArgoCD bootstrap (run once after cluster is healthy)
└── k8s-add-node.yml       # for adding future worker nodes
```

See `ansible/inventory/hosts.yml` and `ansible/inventory/group_vars/all.yml`.

### Role: `k8s_node`

Tasks (in order):

1. **Disable swap** — `swapoff -a` + comment out swap entry in `/etc/fstab`

2. **Load kernel modules** — `overlay`, `br_netfilter`; persisted in `/etc/modules-load.d/k8s.conf`

3. **Set sysctl params** — write to `/etc/sysctl.d/k8s.conf`:
   ```
   net.bridge.bridge-nf-call-iptables  = 1
   net.bridge.bridge-nf-call-ip6tables = 1
   net.ipv4.ip_forward                 = 1
   ```

4. **Install containerd**
   - Add Docker apt repo (containerd is distributed here)
   - Install `containerd.io={{ containerd_version }}`
   - Generate default config; enable `SystemdCgroup = true`
   - Enable and start `containerd` service

5. **Disable UFW** — Cilium handles network policy on k8s nodes

6. **Set static IP via netplan** — removes the cloud-init-generated config and writes `/etc/netplan/01-k8s-static.yaml` using `ansible_host` as the node IP and `enp1s0` as the interface (confirmed on Wyse 5070s)

### Role: `k8s_kubeadm`

1. Add Kubernetes apt repo (`pkgs.k8s.io` — the old `packages.cloud.google.com` repo is deprecated)
2. Install `kubelet`, `kubeadm`, `kubectl` at `{{ kubernetes_version }}`
3. Hold package versions with `apt-mark hold`
4. Enable and start `kubelet` service (it will crash-loop until `kubeadm init` — this is normal)

### Run Phase 1

```bash
ansible-playbook ansible/k8s-provision.yml
```

**Verify:**

```bash
ansible k8s_control_plane:k8s_workers -m command -a "systemctl is-active containerd"
ansible k8s_control_plane:k8s_workers -m command -a "swapon --show"       # no output = swap off
ansible k8s_control_plane:k8s_workers -m command -a "sysctl net.ipv4.ip_forward"  # should return 1
```

---

## 5. Phase 2 — Cluster Init (Ansible)

**Goal:** Initialize the control plane, join workers, install CNI.
**Playbook:** `ansible/k8s-init.yml`

### Role: `k8s_control_plane`

1. **Run `kubeadm init`** on the control node:
   ```bash
   kubeadm init \
     --control-plane-endpoint=192.168.1.150 \
     --pod-network-cidr=172.16.0.0/16 \
     --service-cidr=172.17.0.0/16 \
     --upload-certs
   ```

2. **Set up kubeconfig** on the control node for the `ansible` user, and fetch it to `~/.kube/config` on the local machine.

3. **Install Helm** on the control node, then install Cilium via Helm.

4. **Capture join command** — registered as an Ansible fact and consumed by the workers role.

### Role: `k8s_workers`

Run the captured join command on all worker nodes. Already-joined nodes are detected via `/etc/kubernetes/kubelet.conf` and skipped.

### Cilium CNI — installed by `k8s_control_plane` role via Helm

Cilium is installed as part of the control plane role (after `kubeadm init`) using Helm:

```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version {{ cilium_version }} \
  --namespace kube-system \
  --set ipam.mode=kubernetes
```

Helm itself is installed on the control node by the same role before this step.

### Run Phase 2

```bash
ansible-playbook ansible/k8s-init.yml
```

### Verify Cluster Health

```bash
# All 6 nodes should be Ready
kubectl get nodes

# All system pods running
kubectl get pods -n kube-system

# Cilium healthy
cilium status
```

> ✅ **This is the handoff point.** Once all nodes show `Ready`, Ansible's job is largely done. Everything from here is managed via GitOps (ArgoCD).

---

## 6. Phase 3 — Bootstrap ArgoCD

**Goal:** Get ArgoCD running so it can manage all future cluster state from Git.
**Playbook:** `ansible/k8s-bootstrap.yml`
**Run once only** — after this, ArgoCD manages itself and everything in `apps/`.

### Bootstrap Steps

Steps 1–5 are handled by `ansible/k8s-bootstrap.yml`. Steps 6–7 are one-time manual commands.

1. **Create namespace** — `kubectl create namespace argocd`

2. **Install ArgoCD** — applies the upstream stable manifest

3. **Wait for ArgoCD server** — polls until `argocd-server` deployment is Available

4. **Expose ArgoCD UI** via NodePort (temporary — MetalLB will replace this once deployed):
   Access at `https://192.168.1.150:<nodeport>`

5. **Print initial admin password** — displayed at the end of the playbook run

6. **Create a dedicated deploy key for ArgoCD** — ArgoCD needs unattended Git access.
   Do not use your personal SSH key; use a read-only deploy key scoped to this repo.

   ```bash
   # Generate a key with no passphrase
   ssh-keygen -t ed25519 -C "argocd@homelab" -f ~/.ssh/argocd_homelab -N ""
   ```

   Then add the public key to GitHub:
   > `github.com/vbdjames/homelab` → Settings → Deploy keys → Add deploy key
   > Paste contents of `~/.ssh/argocd_homelab.pub` — leave "Allow write access" unchecked.

   Register the private key with ArgoCD (stored internally as a cluster secret):
   ```bash
   argocd repo add git@github.com:vbdjames/homelab.git \
     --ssh-private-key-path ~/.ssh/argocd_homelab
   ```

7. **Activate GitOps — apply the root App-of-Apps (one time only):**
   ```bash
   kubectl apply -f bootstrap/apps.yaml
   ```
   This tells ArgoCD to watch the `apps/` directory in this repo. From this point, every file
   added to `apps/` is a deployment — push to Git and ArgoCD handles the rest.

### Run Phase 3

```bash
ansible-playbook ansible/k8s-bootstrap.yml

# Get the NodePort assigned to argocd-server
kubectl get svc argocd-server -n argocd

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Log in to ArgoCD (--insecure skips TLS verification for the self-signed cert)
argocd login 192.168.1.150:<nodeport> --username admin --insecure

# Register the deploy key (see step 6 above):
argocd repo add git@github.com:vbdjames/homelab.git \
  --ssh-private-key-path ~/.ssh/argocd_homelab

# Activate GitOps:
kubectl apply -f bootstrap/apps.yaml
```

### Verify ArgoCD

```bash
# All ArgoCD pods should be Running
kubectl get pods -n argocd

# Root app and all child apps should show Synced + Healthy
kubectl get applications -n argocd

# Get the NodePort and access URL
kubectl get svc argocd-server -n argocd
```

Access the UI at `https://192.168.1.150:<nodeport>` — username `admin`, password from playbook output.

---

## 7. Repo Structure

```
homelab/
├── ansible.cfg
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       └── all.yml
│   ├── requirements.yml
│   ├── roles/
│   │   ├── k8s_node/
│   │   ├── k8s_kubeadm/
│   │   ├── k8s_control_plane/
│   │   ├── k8s_workers/
│   │   └── k8s_argocd/
│   ├── README.md
│   ├── base.yml
│   ├── k8s-provision.yml
│   ├── k8s-init.yml
│   ├── k8s-bootstrap.yml
│   └── k8s-add-node.yml
├── bootstrap/
│   └── apps.yaml              # root App-of-Apps — apply once to activate GitOps
├── apps/
│   ├── podinfo.yaml             # smoke-test workload
│   ├── metallb.yaml             # MetalLB controller (Helm, wave 1)
│   ├── metallb-config.yaml      # IP pool + L2 config (wave 2)
│   ├── sealed-secrets.yaml      # Sealed Secrets controller (wave 0)
│   ├── cert-manager.yaml        # cert-manager controller (wave 3)
│   ├── cert-manager-config.yaml # ClusterIssuer + Cloudflare token (wave 4)
│   ├── ingress-nginx.yaml       # ingress controller (wave 5)
│   ├── argocd-config.yaml       # ArgoCD ingress + insecure mode (wave 6)
│   ├── nfs-csi.yaml             # NFS CSI driver (wave 1)
│   ├── nfs-csi-config.yaml      # NFS StorageClass (wave 2)
│   ├── tailscale-operator.yaml  # Tailscale operator (wave 1)
│   └── tailscale-config.yaml    # auth secret + exposed services (wave 2)
├── infrastructure/
│   ├── metallb/
│   │   ├── ipaddresspool.yaml       # assigns 192.168.1.200-254 to MetalLB
│   │   └── l2advertisement.yaml     # enables L2/ARP mode for that pool
│   ├── cert-manager/
│   │   ├── clusterissuer.yaml       # Let's Encrypt + Cloudflare DNS-01 solver
│   │   └── cloudflare-api-token-sealed.yaml
│   ├── argocd/
│   │   ├── params.yaml              # sets argocd-server to insecure mode
│   │   └── ingress.yaml             # routes argocd.fiddlestick.org via ingress-nginx
│   ├── nfs/
│   │   └── storageclass.yaml        # default StorageClass backed by Synology NFS
│   └── tailscale/
│       └── operator-oauth-sealed.yaml  # sealed Tailscale OAuth credentials
├── docs/
│   ├── homelab-runbook.md
│   ├── cloudflare-dns-runbook.md    # Cloudflare setup, API token, DNS records
│   ├── cert-manager-runbook.md      # Sealed secret workflow, cert-manager, ingress-nginx
│   ├── nas-runbook.md               # NFS setup on Synology
│   ├── observability-runbook.md     # kube-prometheus-stack, Loki, Grafana
│   └── tailscale-runbook.md         # Tailscale operator, auth key rotation, exposing services
│   ├── router-setup-runbook.md
│   └── usb-prep-install-runbook.md
└── user-data/
    └── user-data-hl-{01-06}.yml
```

---

## 8. Runbook — Day 2 Operations

### Rotate or Update a Sealed Secret

Updating a `SealedSecret` does **not** automatically restart the pods that use it.
After committing and pushing a new sealed secret, manually restart the affected deployment:

```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

ArgoCD will sync the new secret, but pods only pick up secret changes on restart.

---

### Deploy a New Application (GitOps workflow)

1. Create an ArgoCD `Application` manifest in `apps/`:
   ```bash
   # Example: apps/my-app.yaml
   # See apps/podinfo.yaml for a reference — Helm chart or raw manifests both work
   ```
2. Commit and push to `main`
3. ArgoCD detects the new file within ~3 minutes and deploys it automatically

To force an immediate sync without waiting:
```bash
# Via CLI
argocd app sync my-app

# Or trigger from the ArgoCD UI
```

### Add a Worker Node

1. Provision the new machine (Ubuntu 24.04, static IP)
2. Run base config against the new node:
   ```bash
   ansible-playbook ansible/base.yml --limit hl-07
   ```
3. Run the add-node playbook (generates a fresh join token automatically):
   ```bash
   ansible-playbook ansible/k8s-add-node.yml -e target_host=hl-07
   ```
4. Verify: `kubectl get nodes`

### Upgrade Kubernetes Version

> ⚠️ An `upgrade.yml` playbook has not yet been written. The steps below are the intended approach.

1. Update `kubernetes_version` in `ansible/inventory/group_vars/all.yml`, commit to Git
2. Drain, upgrade, and uncordon the control plane manually or via a future `k8s-upgrade.yml` playbook
3. Upgrade workers one at a time, draining each before upgrading

### Drain a Node for Maintenance

```bash
# Drain (evicts pods gracefully)
kubectl drain hl-02 --ignore-daemonsets --delete-emptydir-data

# Do maintenance work...

# Return node to service
kubectl uncordon hl-02
```

### Reset a Node (full wipe and rejoin)

```bash
# On the node
kubeadm reset
iptables -F && iptables -t nat -F && iptables -t mangle -F

# Then re-run the add-node playbook
ansible-playbook ansible/k8s-add-node.yml -e target_host=hl-02
```

### Access ArgoCD UI

ArgoCD is exposed via NodePort on `hl-01`. Get the port with:
```bash
kubectl get svc argocd-server -n argocd
```
Access at `https://192.168.1.150:<nodeport>` — username `admin`.

Retrieve the password (valid until manually changed):
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

If NodePort is unavailable, port-forward as a fallback:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# then access https://localhost:8080
```

---

## 9. Confirmed Values

| Item | Value |
|---|---|
| `hl-01` (control plane) | `192.168.1.150` ✅ |
| `hl-02` (worker) | `192.168.1.151` ✅ |
| `hl-03` (worker) | `192.168.1.152` ✅ |
| `hl-04` (worker) | `192.168.1.153` ✅ |
| `hl-05` (worker) | `192.168.1.154` ✅ |
| `hl-06` (worker) | `192.168.1.155` ✅ |
| `nas-01` (Synology NAS) | `192.168.1.3` ✅ |

---

*This runbook is a living document. Update it as the environment evolves — especially when IPs are confirmed, DNS is added, or new components are deployed.*
