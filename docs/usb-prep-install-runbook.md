# USB Prep and Server Install Runbook — Homelab Provisioning

## Context

This runbook covers preparing the USB install media and the step-by-step procedure for provisioning each Ubuntu 24.04 server. Each server has a pre-configured `user-data` file in `user-data/` with its hostname and IP already set.

**Equipment needed:**
- USB stick 1 — boot stick (8 GB minimum, holds the Ubuntu ISO)
- USB stick 2 — config stick (any size, holds `user-data`)
- Laptop (Linux) as the workstation for preparing media
- Wyse 5070 servers to be provisioned

---

## One-Time Setup

### Step 1 — Download the Ubuntu 24.04 ISO

```bash
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso
```

Verify the checksum before writing:

```bash
wget https://releases.ubuntu.com/24.04/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

Expected output should include:
```
ubuntu-24.04-live-server-amd64.iso: OK
```

Do not proceed if the checksum fails — re-download the ISO.

---

### Step 2 — Write the ISO to USB 1 (Boot Stick)

Plug in USB 1 and identify its device name:

```bash
lsblk
```

Look for the USB stick by size. It will appear as `/dev/sdb`, `/dev/sdc`, or similar.

> **Warning:** `dd` will silently and permanently overwrite whatever device you target. Confirm the device name carefully before running the command.

Write the ISO:

```bash
sudo dd if=ubuntu-24.04-live-server-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your actual device name — use the **device**, not a partition (`/dev/sdb` not `/dev/sdb1`).

This stick is reusable for all six servers — it never needs to be modified.

---

### Step 3 — Prepare USB 2 (Config Stick)

Plug in USB 2 and identify its device name via `lsblk` as above.

Format it as FAT32 with the label `CIDATA` (the label is how the installer finds it):

```bash
sudo mkfs.vfat -F 32 -n CIDATA /dev/sdY
```

Replace `/dev/sdY` with your actual device name.

Create a mount point:

```bash
sudo mkdir -p /mnt/cidata
```

---

## Per-Server Install Procedure

Repeat the following steps for each server (`hl-01` through `hl-06`), in order.

### Step 1 — Load the Config Stick

Each server has a pre-configured `user-data` file with the correct hostname and IP already set. Just copy the right one:

| Server | File | IP |
|---|---|---|
| hl-01 | `user-data/user-data-hl-01.yml` | `192.168.1.150` |
| hl-02 | `user-data/user-data-hl-02.yml` | `192.168.1.151` |
| hl-03 | `user-data/user-data-hl-03.yml` | `192.168.1.152` |
| hl-04 | `user-data/user-data-hl-04.yml` | `192.168.1.153` |
| hl-05 | `user-data/user-data-hl-05.yml` | `192.168.1.154` |
| hl-06 | `user-data/user-data-hl-06.yml` | `192.168.1.155` |

```bash
sudo mount /dev/sdY /mnt/cidata

# Clear any previous install's files
sudo rm -f /mnt/cidata/user-data /mnt/cidata/meta-data

# Copy this server's user-data (meta-data must exist but can be empty)
sudo cp user-data/user-data-hl-01.yml /mnt/cidata/user-data   # replace hl-01 with this server's hostname
sudo touch /mnt/cidata/meta-data

sudo umount /mnt/cidata
```

---

### Step 2 — Boot the Server from USB 1

Insert both USB sticks into the server. Power on and enter the boot menu (Wyse 5070 boot menu is typically `F7`, `F11`, or `F12`).

Select USB 1 (the boot stick) as the boot device.

> **Tip:** If the server boots from the wrong device, enter BIOS/UEFI setup and adjust the boot order permanently so USB is first.

---

### Step 3 — Unattended Install

The installer will detect the config stick automatically and load `user-data`. Ubuntu 24.04's standard ISO does not have autoinstall baked in, so the installer will prompt for confirmation before proceeding — accept to continue. After that, no further input is required and the screen will show installation progress.

When complete the server will reboot automatically. **Remove both USB sticks before the server comes back up** so it boots from the internal disk.

Typical install time: 5–10 minutes depending on disk speed.

---

### Step 4 — Verify the Install

From the laptop (control node), once the server has rebooted:

```bash
# Confirm SSH access and hostname
ssh hl-01 hostname
```

Expected output: `hl-01`

If SSH fails:
- Wait 60 seconds and try again — the server may still be booting
- Verify the USB sticks were removed before reboot
- Try connecting directly by IP to rule out SSH config issues: `ssh ansible@192.168.1.150 hostname`

---

## Checklist

### One-time setup
- [x] Ubuntu 24.04 ISO downloaded and checksum verified
- [x] ISO written to USB 1 (boot stick)
- [x] USB 2 (config stick) formatted as FAT32 with label `CIDATA`
- [x] Wyse 5070 boot menu key confirmed

### Per server
- [x] `hl-01` — config stick loaded, installed, SSH verified
- [x] `hl-02` — config stick loaded, installed, SSH verified
- [x] `hl-03` — config stick loaded, installed, SSH verified
- [x] `hl-04` — config stick loaded, installed, SSH verified
- [x] `hl-05` — config stick loaded, installed, SSH verified
- [x] `hl-06` — config stick loaded, installed, SSH verified

---

## Next Steps

With all servers provisioned and reachable via SSH, proceed to:

1. **Ansible inventory** — define hosts and groups
2. **Ansible control node setup** — configure `ansible.cfg`, test connectivity with `ansible -m ping all`
3. **Base playbook** — personal admin user, firewall, NTP, hostname verification, package updates
