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

> **Status:** Complete — NFS configured on Synology, CSI driver deployed, StorageClass active as cluster default

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

## Known Limitation — Non-root UID Access

Synology's NFS server maps client UIDs against its own user database. UIDs that don't
correspond to a Synology user (e.g. uid 1000 from a container running as a non-root app
user) are effectively denied access, even if file permissions appear to allow it.

**Symptom:** `Permission denied` on NFS-mounted directories from a container running as a
non-root UID, despite the directory showing `0777` permissions when inspected as root.

**Workarounds (pick one):**
- **Run the container as root** — use `USERMAP_UID=0` / `USERMAP_GID=0` if the app
  supports uid remapping (e.g. Paperless-ngx), or set `securityContext.runAsUser: 0`.
  Works via `no_root_squash` on the export. Simple but runs the app as root.
- **Create a matching Synology user** — add a user in DSM with the same UID as the
  container user and grant it access to the `kubernetes` share. Proper fix but requires
  NAS UI changes for each new UID.

Paperless-ngx uses `USERMAP_UID=0` as its workaround.

---

## Checklist

- [x] NFS service enabled (NFSv4.1) ✅
- [x] `kubernetes` shared folder created on Volume 1 ✅
- [x] NFS export configured for `192.168.1.0/24` with no root squash ✅
- [x] Export verified with `showmount -e 192.168.1.3` ✅
- [x] NFS CSI driver deployed in cluster ✅
- [x] StorageClass verified — test PVC provisioned successfully ✅
