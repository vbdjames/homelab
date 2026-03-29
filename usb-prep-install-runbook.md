# USB Prep and Server Install Runbook — Homelab Provisioning

## Context

This runbook covers preparing the USB install media and the step-by-step procedure for provisioning each Ubuntu 24.04 server. A single `user-data.yml` template is used for all servers — the hostname and IP address are updated in-place before each install.

**Equipment needed:**
- USB stick 1 — boot stick (8 GB minimum, holds the Ubuntu ISO)
- USB stick 2 — config stick (any size, holds `user-data`)
- Laptop (Linux) as the workstation for preparing media
- Wyze 5070 servers to be provisioned

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

### Step 4 — Verify the NIC Interface Name on Wyse 5070

`user-data.yml` uses `enp1s0` as the network interface name. This must be verified against actual hardware before the first real install — if it's wrong the server will boot without networking.

Boot one Wyse 5070 from USB 1 (boot stick only, no config stick). At the installer welcome screen, drop to a shell:

- Select **Help** → **Enter shell**, or press `Ctrl+Alt+F2`

Run:

```bash
ip link
```

Look for the interface name — it will be something like `enp1s0`, `eno1`, `eth0`, or similar. Note it down.

If the interface name differs from `enp1s0`, update `user-data.yml` before proceeding:

```bash
sed -i 's/enp1s0/ACTUAL_NAME/g' user-data.yml
```

---

## Per-Server Install Procedure

Repeat the following steps for each server (`hl-01` through `hl-06`), in order.

### Step 1 — Update user-data.yml and Load onto the Config Stick

Update the hostname and IP in `user-data.yml` for the server you are about to install:

| Server | Hostname | IP |
|---|---|---|
| hl-01 | `hl-01` | `192.168.1.200` |
| hl-02 | `hl-02` | `192.168.1.201` |
| hl-03 | `hl-03` | `192.168.1.202` |
| hl-04 | `hl-04` | `192.168.1.203` |
| hl-05 | `hl-05` | `192.168.1.204` |
| hl-06 | `hl-06` | `192.168.1.205` |

Edit the two fields in `user-data.yml`:
- `identity.hostname` — set to this server's hostname
- `network.ethernets.enp1s0.addresses` — set to this server's IP

Then copy to the config stick:

```bash
sudo mount /dev/sdY /mnt/cidata

# Clear any previous install's files
sudo rm -f /mnt/cidata/user-data /mnt/cidata/meta-data

# Copy the updated template (meta-data must exist but can be empty)
sudo cp user-data.yml /mnt/cidata/user-data
sudo touch /mnt/cidata/meta-data

sudo umount /mnt/cidata
```

---

### Step 2 — Boot the Server from USB 1

Insert both USB sticks into the server. Power on and enter the boot menu (check Wyze 5070 documentation for the boot menu key — typically `F7`, `F11`, or `F12`).

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
# Confirm network reachability
ping -c 3 hl-01

# Confirm SSH access
ssh -i ~/.ssh/ansible_homelab ansible@hl-01
```

If SSH connects successfully, the server is ready for Ansible.

If `ping` fails:
- Wait 60 seconds and try again — the server may still be booting
- Verify the USB sticks were removed before reboot
- Check that the NIC interface name in `user-data` is correct (see Step 4 of One-Time Setup)

---

## Checklist

### One-time setup
- [ ] Ubuntu 24.04 ISO downloaded and checksum verified
- [ ] ISO written to USB 1 (boot stick)
- [ ] USB 2 (config stick) formatted as FAT32 with label `CIDATA`
- [ ] NIC interface name verified on Wyze 5070 hardware
- [ ] `user-data.yml` updated with correct interface name if needed
- [ ] Wyze 5070 boot menu key confirmed

### Per server
- [ ] `hl-01` — config stick loaded, installed, SSH verified
- [ ] `hl-02` — config stick loaded, installed, SSH verified
- [ ] `hl-03` — config stick loaded, installed, SSH verified
- [ ] `hl-04` — config stick loaded, installed, SSH verified
- [ ] `hl-05` — config stick loaded, installed, SSH verified
- [ ] `hl-06` — config stick loaded, installed, SSH verified

---

## Next Steps

With all servers provisioned and reachable via SSH, proceed to:

1. **Ansible inventory** — define hosts and groups
2. **Ansible control node setup** — configure `ansible.cfg`, test connectivity with `ansible -m ping all`
3. **Base playbook** — personal admin user, firewall, NTP, hostname verification, package updates
