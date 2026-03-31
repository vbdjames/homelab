# NAS Runbook — nas

## Context

`nas` is a Synology DiskStation providing persistent storage for the homelab. It is configured manually via the DSM web UI and is **not managed by Ansible**.

This runbook captures only the Kubernetes-relevant configuration — shares, exports, access controls, and integration decisions made over time. It does not attempt to document the full DSM configuration.

**Environment:**
- Host: `nas` (`192.168.1.3`)
- OS: Synology DSM
- Management UI: `http://192.168.1.3:5000` (or `https://192.168.1.3:5001`)

---

## Kubernetes Storage Integration

> **Status:** Not yet decided. Options under consideration include NFS shares, iSCSI, and the Synology CSI driver. This section will be filled in as decisions are made.

---

## Shares

> Document NAS shares used by the Kubernetes cluster here as they are created.

| Share Name | Protocol | Path | Purpose |
|---|---|---|---|
| _(none yet)_ | | | |

---

## Access Control

> Document any service accounts, API keys, or network-level access rules configured for cluster access.

_(none yet)_

---

## Checklist

_(To be built up as integration is configured)_
