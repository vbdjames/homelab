# NAS Runbook — nas

## Context

`nas` is a Synology DiskStation providing persistent storage for the homelab. It is configured manually via the DSM web UI and is **not managed by Ansible**.

This runbook covers the Kubernetes-relevant NAS configuration — NFS setup, shares, and access controls.

**Environment:**
- Host: `nas` (`192.168.1.3`)
- OS: Synology DSM
- Management UI: `http://192.168.1.3:5000` (or `https://192.168.1.3:5001`)

---

## Kubernetes Storage Integration

> **Status:** NFS — CSI driver to be deployed via ArgoCD, NAS-side config documented below.

**Approach:** NFS via the [NFS CSI driver](https://github.com/kubernetes-csi/csi-driver-nfs). A dedicated share (`/volume1/kubernetes`) on the NAS is exported to the cluster nodes. The CSI driver provisions subdirectories automatically for each PersistentVolumeClaim.

**Why NFS over the Synology CSI driver:** The generic NFS CSI driver is simpler, has no Synology-specific dependencies, and works across any NFS server. The Synology CSI driver adds features (snapshots, iSCSI) that aren't needed yet — iSCSI can be added later for databases requiring block storage.

---

## Phase 1 — Configure NFS on the Synology

All steps are performed in the DSM web UI.

### Enable the NFS service

1. **Control Panel → File Services → NFS**
2. Enable NFS service
3. Set **Maximum NFS Protocol** to `NFSv4.1` (required by the CSI driver)
4. Click Apply

### Create the Kubernetes share

1. **Control Panel → Shared Folder → Create**
2. Set:
   - **Name:** `kubernetes`
   - **Description:** Kubernetes persistent volumes
   - **Location:** Volume 1 (or whichever volume has space)
   - Leave encryption and other options at defaults
3. On the permissions screen — skip user permissions (NFS uses IP-based access control, not user accounts)

### Configure NFS export permissions

1. Select the `kubernetes` share → **Edit → NFS Permissions → Create**
2. Set:
   - **Hostname or IP:** `192.168.1.0/24` — allows all cluster nodes (and the NAS subnet)
   - **Privilege:** `Read/Write`
   - **Squash:** `No mapping` (do not squash root — the CSI driver needs root access to create subdirectories)
   - **Security:** `sys`
   - **Enable asynchronous:** checked
   - **Allow connections from non-privileged ports:** checked
3. Click Save and Apply

### Verify the NFS export

From any cluster node (or the devcontainer if `nfs-common` is installed):
```bash
showmount -e 192.168.1.3
# Should show: /volume1/kubernetes  192.168.1.0/24
```

---

## Shares

| Share Name | Protocol | Path | Purpose |
|---|---|---|---|
| `kubernetes` | NFS | `/volume1/kubernetes` | Kubernetes persistent volumes |

---

## Access Control

| Resource | Access | Notes |
|---|---|---|
| `/volume1/kubernetes` | `192.168.1.0/24` read/write | All cluster nodes; no root squash |

---

## Checklist

- [ ] NFS service enabled (NFSv4.1)
- [ ] `kubernetes` shared folder created on Volume 1
- [ ] NFS export configured for `192.168.1.0/24` with no root squash
- [ ] Export verified with `showmount -e 192.168.1.3`
- [ ] NFS CSI driver deployed in cluster (see homelab-runbook.md)
- [ ] StorageClass verified — test PVC provisions successfully
