# ARM Runbook

> **Status:** Active — running at `https://arm.fiddlestick.org`
> **Stack:** Automatic Ripping Machine 2.23.2 · MakeMKV · hl-07 (HP 8200 Elite)

---

## Overview

ARM (Automatic Ripping Machine) auto-detects disc insertion, identifies the disc type,
and rips DVD/Blu-ray content to MKV using MakeMKV. Output lands on the NAS where it
can be picked up by Radarr/Sonarr for import into the media library.

| Detail | Value |
|---|---|
| URL | `https://arm.fiddlestick.org` |
| Namespace | `arm` |
| Node | `hl-07` (labelled `homelab/optical-drive=true`) |
| NAS output share | `192.168.1.3:/volume1/arm` |
| Config PVC | `arm-config` (5Gi NFS) — persists ARM config and database |
| Media PVC | `arm-media` (2Ti static NFS → `/volume1/arm`) |

---

## Architecture

### Why hl-07 only

ARM requires physical access to an optical drive. The deployment uses a `nodeAffinity`
rule (`homelab/optical-drive=true`) to pin the pod to hl-07, which is an HP 8200 Elite
with a built-in DVD drive.

### Device access

The ARM container runs `privileged: true` so its own udev daemon can manage `/dev/sr0`
natively. The device is NOT passed via a Kubernetes hostPath volume — doing so creates
a bind mount that `findmnt` reports as a devtmpfs filesystem, which causes ARM's
`check_mount()` to use `/dev/sr0` as the disc mountpoint instead of mounting it
properly. With udev running inside the container, it creates `/dev/sr0` via `mknod`
(matching Docker's `--device` behaviour), and ARM can mount the disc at `/mnt/dev/sr0`
using the container's fstab entry.

### Disc detection flow

1. Disc inserted → kernel uevent fires
2. Container's udev receives event, creates/updates `/dev/sr0` and writes device
   properties to `/run/udev/data/b11:0`
3. udev fires `51-docker-arm.rules` → runs `docker_arm_wrapper.sh sr0`
4. ARM's `parse_udev()` reads `ID_CDROM_MEDIA_DVD` (or `BD`/`CD`) from udev database
5. ARM's `check_mount()` calls `findmnt --json /dev/sr0` → no result (disc not yet
   mounted) → mounts disc at `/mnt/dev/sr0` using fstab
6. `get_disc_type()` finds `VIDEO_TS` → `disctype = "dvd"`
7. MakeMKV rips all titles above `MINLENGTH` seconds

### Important: do NOT mount /run/udev from host

The deployment deliberately does NOT mount `/run/udev` from the host. Doing so
prevents the container's own udevd from starting (socket conflict: "Address already in
use"). The container's udev is what triggers ARM and what populates the device database
that `parse_udev()` reads.

---

## Post-Deploy Configuration

### 1. OMDB API key (title metadata)

Without an API key, rips land in `completed/unidentified/None (None)/`. To enable
automatic title lookup:

1. Get a free key at `https://www.omdbapi.com/apikey.aspx`
2. Log into ARM at `https://arm.fiddlestick.org`
3. Go to **Settings**
4. Set `OMDB_API_KEY` to your key
5. Set `METADATA_PROVIDER` to `OMDB` (or `TMDB` if you prefer — requires a separate
   TMDB key)
6. Click **Save**

Settings are stored in `/etc/arm/config/arm.yaml` on the `arm-config` NFS PVC and
survive pod restarts.

### 2. Rip settings

Recommended starting config (set in **Settings** in the web UI):

| Setting | Value | Notes |
|---|---|---|
| `SKIP_TRANSCODE` | `true` | MKV output only; HandBrake transcode is very slow on hl-07 |
| `RIPMETHOD` | `mkv` | MakeMKV rip |
| `MINLENGTH` | `600` | Skip titles shorter than 10 minutes (skips trailers/extras by default) |
| `MAINFEATURE` | `false` | Rip all titles above MINLENGTH |
| `MANUAL_WAIT` | `true` | 60-second window to override disc type before rip starts |

---

## Normal Workflow

1. Insert disc — ARM auto-detects and creates a job (check the web UI)
2. Wait 60 seconds (manual override window) — you can change disc type or title here
3. MakeMKV rips to `/home/arm/media/completed/<title>/`
4. Files appear on NAS at `/volume1/arm/completed/<title>/`
5. In Radarr/Sonarr: **Manual Import** → point at the NAS path → match and import

---

## Troubleshooting

### Disc not auto-detected

Check udev is running in the container:
```bash
kubectl -n arm exec deployment/arm -- ps aux | grep udev
```

If udevd is not running, the most likely cause is that `/run/udev` is being mounted
from the host (see architecture note above). Check the deployment for a `udev` volume.

### Disc identified as "data" instead of "dvd"

This means `check_mount()` found a false mountpoint. Usually caused by the `/dev/sr0`
hostPath volume being present in the deployment. Check:
```bash
kubectl -n arm exec deployment/arm -- findmnt --json /dev/sr0
```
If it returns a `devtmpfs` entry, the hostPath volume for `sr0` is present and needs to
be removed.

### Title not identified (files land in `unidentified/`)

OMDB API key not set, or the disc's CRC isn't in the ARM online database. Options:
- Set the API key (see Post-Deploy Configuration above)
- In the web UI, manually edit the job title before or during the 60-second wait window
- Rename the output files manually after the rip

### MakeMKV key expired

ARM auto-updates the MakeMKV beta key on each rip. If rips fail with a key error,
check `https://forum.makemkv.com/forum/viewtopic.php?t=1053` for the current beta key
and set it in **Settings → MAKEMKV_PERMA_KEY**.

### Eject fails after rip

```
eject: udev: mounted on /dev/sr0
```

This error is cosmetic — it means the disc was already unmounted by ARM but `eject`
couldn't confirm via udev. The disc will still eject. Can be ignored.

---

## Re-deploying / Recovering

The ARM database and config live on `arm-config` (NFS PVC). Deleting and recreating the
pod does not lose any state. If the pod is crashlooping:

```bash
# Check logs
kubectl -n arm logs deployment/arm

# Check init container (handles chown of /home/arm)
kubectl -n arm logs deployment/arm -c fix-permissions
```

The `fix-permissions` init container runs `chown -R 1000:1000 /home/arm` on the config
PVC at startup. If the NFS share permissions change, this will fix ownership.

---

## Key Files

| File | Purpose |
|---|---|
| `infrastructure/arm/arm.yaml` | PVCs, Deployment, Service, Ingress |
| `apps/arm.yaml` | ArgoCD Application |
| `infrastructure/nfs/arm-pv.yaml` | Static PV for the NAS media share |
