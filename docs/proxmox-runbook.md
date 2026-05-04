# Proxmox Runbook

> **Status:** Active — Proxmox running, Tailscale subnet router active, Pi-hole handling DNS and DHCP
> **Last updated:** 2026-05-04
> **Hardware:** Apple Mac Mini (2011), Intel Core i5, 16GB RAM, single onboard NIC

---

## Overview

Proxmox VE is a bare-metal hypervisor running on the HP desktop. It hosts VMs and LXC
containers for services that don't belong in Kubernetes — primarily infrastructure services
that need to be available independently of the cluster (DNS, future pfSense, etc.).

| Host | Role | IP |
|---|---|---|
| `pve-01` | Proxmox hypervisor | `192.168.1.162` |
| `pihole` | Pi-hole DNS (LXC) | `192.168.1.161` |

---

## Phase 1 — Install Proxmox

### Download and prepare install media

1. Download the Proxmox VE ISO from [proxmox.com/downloads](https://www.proxmox.com/en/downloads)
2. Flash to a USB drive:
   ```bash
   # On Mac
   sudo dd if=proxmox-ve_*.iso of=/dev/rdiskN bs=1m status=progress

   # Or use Balena Etcher (GUI, cross-platform)
   ```

### Install

1. Boot the HP desktop from the USB drive
2. Select **Install Proxmox VE (Graphical)**
3. At the disk selection screen — select the target drive (the one being wiped)
4. Set the following:
   - **Country/timezone** — your local settings
   - **Hostname:** `pve-01.fiddlestick.org`
   - **IP address:** `192.168.1.160`
   - **Netmask:** `255.255.255.0`
   - **Gateway:** `192.168.1.1`
   - **DNS:** `192.168.1.1` (temporary — will point to Pi-hole once it's running)
   - **Root password** — set a strong one, store in password manager
5. Complete the install and reboot — remove USB when prompted

### First login

Access the Proxmox web UI at `https://192.168.1.160:8006` — accept the self-signed cert warning.

Login: `root` / your password

### Switch to the community repository (removes the enterprise nag)

Proxmox shows a subscription nag for two enterprise repos: `pve` and `ceph-squid`.
Switch both to the free community repos:

1. In the UI: **pve-01 → Repositories**
2. Disable both enterprise repos:
   - `https://enterprise.proxmox.com/debian/pve`
   - `https://enterprise.proxmox.com/debian/ceph-squid`
3. Click **Add** and select **No-Subscription** for each
4. Run updates:
   ```bash
   apt update && apt dist-upgrade -y
   ```

---

## Phase 2 — Install Tailscale on Proxmox Host

Install Tailscale directly on the Proxmox host (`pve-01`) so it can act as a subnet
router, advertising `192.168.1.0/24` to your tailnet. This gives you:

- Remote access to the Proxmox UI at `https://192.168.1.160:8006` via Tailscale
- Remote access to all LAN services via `*.fiddlestick.org` once subnet routing is active
- A stable out-of-band access path before DNS is changed

### Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### Start Tailscale with subnet routing

```bash
tailscale up --advertise-routes=192.168.1.0/24 --accept-dns=false
```

> `--accept-dns=false` — prevents Tailscale from overriding the host's DNS with MagicDNS,
> which could interfere with Pi-hole once it's running.

### Approve the subnet route

In the Tailscale admin console → **Machines** → click `pve-01` → **Edit route settings**
→ enable `192.168.1.0/24`.

### Verify

From any device on your tailnet, confirm you can reach:
```
https://192.168.1.160:8006   # Proxmox UI
```

---

## Phase 4 — Create the Pi-hole LXC

### Download a container template

In the Proxmox UI:
1. **local (pve-01) → CT Templates → Templates**
2. Download **Debian 12 (bookworm)** — Pi-hole's preferred base

### Create the LXC container

1. Click **Create CT** (top right)
2. Fill in:
   - **CT ID:** `100`
   - **Hostname:** `pihole`
   - **Password:** set a root password, store in password manager
   - **Template:** Debian 12
   - **Disk:** 8GB (plenty for Pi-hole)
   - **CPU:** 1 core
   - **Memory:** 512MB (Pi-hole is very lightweight)
   - **Network:** 
     - Bridge: `vmbr0`
     - IP: `192.168.1.161/24`
     - Gateway: `192.168.1.1`
   - **DNS:** `192.168.1.1` (temporary)
3. **Do not start on finish** — review settings first
4. Start the container

### Install Pi-hole

Connect to the container console (Proxmox UI → pihole → Console) or SSH:
```bash
ssh root@192.168.1.161
```

Install curl (not included in the Debian 12 LXC template) then run the Pi-hole installer:
```bash
apt-get update && apt-get install -y curl
curl -sSL https://install.pi-hole.net | bash
```

During the installer:
- **Interface:** `eth0`
- **Upstream DNS:** Cloudflare (`1.1.1.1`) or your preference
- **Block lists:** keep defaults
- **Admin web interface:** Yes
- **Logging:** Yes
- **Privacy mode:** 0 (show everything) for homelab use

> ℹ️ Pi-hole v6 does not display the admin password after install. Set it manually:
> ```bash
> pihole setpassword
> ```
> Store the password in your password manager.

After install, run a gravity update to download and compile the blocklists — blocking will
not work until this completes:
```bash
pihole -g
```

---

## Phase 5 — Configure DNS

### Strategy — Pi-hole as DHCP server

The Verizon G1100 does not expose LAN DNS settings in its UI, so the standard approach
of pointing DHCP DNS at Pi-hole is not available. Instead, Pi-hole takes over DHCP entirely.
Pi-hole hands out IP addresses AND pushes itself as the DNS server to every device automatically.

**Sequence (order matters to minimize disruption):**
1. Enable Pi-hole DHCP first
2. Disable router DHCP second

Devices with existing leases are unaffected until their lease renews. The brief window
between steps may cause a few seconds of disruption for any device that tries to renew
exactly then — this is rare and self-correcting.

> ⚠️ If Pi-hole goes down, devices can't get new DHCP leases. Existing leases continue
> working until they expire. To recover: re-enable DHCP on the router.

### Enable Pi-hole DHCP

1. In the Pi-hole admin UI: **Settings → DHCP**
2. Enable DHCP server
3. Set the range to match the router's current pool: `192.168.1.2` – `192.168.1.149`
4. Set the gateway to `192.168.1.1`
5. Save

### Disable router DHCP

On the Verizon G1100:
1. **My Network → Network Connections → Network (Home/Office) → Settings**
2. Find **IPv4 Address Distribution** and disable it
3. Save

### Point the network at Pi-hole

### Add local DNS records in Pi-hole

Pi-hole replaces the router's local DNS entries. Add one record per homelab service
via **Settings → DNS Records**. Pi-hole forwards anything without a local record to
upstream DNS (Cloudflare) — so external `fiddlestick.org` subdomains resolve normally.

> ⚠️ Do NOT use the dnsmasq wildcard approach (`address=/fiddlestick.org/192.168.1.201`)
> — this intercepts ALL fiddlestick.org queries including any externally hosted services.

For the current list of DNS records, see [cloudflare-dns-runbook.md](cloudflare-dns-runbook.md) — the local Pi-hole records mirror the Cloudflare records table.

### Remove router local DNS entries

Once Pi-hole wildcard DNS is confirmed working, remove the manual entries from the
Verizon router's local DNS settings.

---

## Phase 6 — Pi-hole HTTPS with Let's Encrypt

Pi-hole v6 supports HTTPS natively via a combined PEM file (key + fullchain). Certificates
are issued using `acme.sh` with Cloudflare DNS-01 challenge — no ports need to be opened.

This is now automated via the Ansible playbook `ansible/proxmox-pihole.yml`. See
[ansible/README.md](../ansible/README.md) for usage.

### How it works

- `acme.sh` is installed as root on the Pi-hole LXC
- Certificate is issued via Cloudflare DNS-01 (no port 80/443 required)
- A combined PEM file (key + fullchain) is written to `/etc/pihole/tls/combined.pem`
- Pi-hole FTL is configured to use the combined PEM for HTTPS on port 443
- acme.sh installs a cron job that renews ~60 days before expiry and rebuilds the combined
  file automatically on renewal

### Manual steps (reference only)

If you ever need to re-run this manually outside of Ansible:

```bash
# On the Pi-hole LXC as root
export CF_Token="<cloudflare-api-token>"
~/.acme.sh/acme.sh --issue --dns dns_cf -d pihole.fiddlestick.org
mkdir -p /etc/pihole/tls
~/.acme.sh/acme.sh --install-cert -d pihole.fiddlestick.org \
  --cert-file /etc/pihole/tls/cert.pem \
  --key-file /etc/pihole/tls/key.pem \
  --fullchain-file /etc/pihole/tls/fullchain.pem \
  --reloadcmd "cat /etc/pihole/tls/key.pem /etc/pihole/tls/fullchain.pem > /etc/pihole/tls/combined.pem && systemctl restart pihole-FTL"
cat /etc/pihole/tls/key.pem /etc/pihole/tls/fullchain.pem > /etc/pihole/tls/combined.pem
pihole-FTL --config webserver.tls.cert /etc/pihole/tls/combined.pem
systemctl restart pihole-FTL
```

---

## Phase 7 — Proxmox UI HTTPS with Let's Encrypt

Proxmox uses `pveproxy` to serve its web UI. It stores its certificate at
`/etc/pve/local/pveproxy-ssl.pem` and key at `/etc/pve/local/pveproxy-ssl.key`.

### Install acme.sh on Proxmox host

Run from the Proxmox shell (web UI → pve-01 → Shell):

```bash
curl https://get.acme.sh | sh -s email=doug@dwjames.org
source ~/.bashrc
```

### Issue the certificate

```bash
export CF_Token="<cloudflare-api-token>"
~/.acme.sh/acme.sh --issue --dns dns_cf -d pve-01.fiddlestick.org
```

### Install the certificate

```bash
~/.acme.sh/acme.sh --install-cert -d pve-01.fiddlestick.org \
  --cert-file /etc/pve/local/pveproxy-ssl.pem \
  --key-file /etc/pve/local/pveproxy-ssl.key \
  --reloadcmd "systemctl reload pveproxy"
```

acme.sh installs a cron job and renews automatically. The `--reloadcmd` reloads pveproxy
on each renewal — no manual intervention required.

Proxmox UI is now accessible at `https://pve-01.fiddlestick.org:8006` with a valid cert.

---

## Rename pve-02 → pve-01

The current Proxmox host was provisioned as `pve-02` (192.168.1.162) when the original
`pve-01` (192.168.1.160) was replaced. This section covers renaming it cleanly.

**Why the previous attempt failed:** Proxmox stores LXC configs at
`/etc/pve/nodes/<nodename>/lxc/`. When the node came up under the new name, it looked
for configs under `/etc/pve/nodes/pve-01/lxc/` — found nothing — and Pi-hole didn't
start.

**Key constraint:** `/etc/pve` is managed by pmxcfs, which does not allow `cp` — you
must use `mv` to move container configs.

### Before you start

Pi-hole handles DHCP, so there's no easy way to push a fallback DNS to devices ahead of
time. The rename takes a few minutes — just pick a quiet time (weekend morning, not a
workday). Manually set DNS to `1.1.1.1` on your phone and laptop before starting so you
have working DNS on your own devices if anything goes wrong mid-rename.

### Procedure

```bash
# 1. Check current state — see what node directories exist
ls /etc/pve/nodes/

# 2. Stop Pi-hole LXC cleanly (find the CT ID from pct list)
pct list
pct stop <containerid>

# 3. Update hostname
echo "pve-01" > /etc/hostname

# Edit /etc/hosts — change pve-02 to pve-01 on the 127.x.x.x line
nano /etc/hosts

# 4. Move LXC configs to the new node name BEFORE rebooting
mkdir -p /etc/pve/nodes/pve-01/lxc
mkdir -p /etc/pve/nodes/pve-01/qemu-server
mv /etc/pve/nodes/pve-02/lxc/* /etc/pve/nodes/pve-01/lxc/
rmdir /etc/pve/nodes/pve-02

# 5. Verify — pve-02 dir should be gone, pve-01 should have your container config
ls /etc/pve/nodes/
ls /etc/pve/nodes/pve-01/lxc/

# 6. Reboot
reboot
```

### After reboot

```bash
# Confirm hostname
hostnamectl

# Confirm Pi-hole LXC is visible
pct list

# Start Pi-hole
pct start <containerid>

# Confirm Pi-hole is resolving DNS
nslookup argocd.fiddlestick.org 192.168.1.161
```

Once Pi-hole is confirmed healthy, remove the fallback DNS from the router.

### After the rename — also update

- Ansible inventory: `ansible/inventory/hosts.yml` — change `pve-01` IP from `192.168.1.160` to `192.168.1.162`
- Ansible playbook: `ansible/proxmox-pihole.yml` — three hardcoded `node: pve-01` references are already correct once renamed
- TLS cert: the acme.sh cert was issued for `pve-01.fiddlestick.org` — reissue it after the rename since the hostname now matches the domain

---

## Checklist

### Proxmox
- [x] ISO downloaded and USB prepared ✅
- [x] Proxmox installed at `192.168.1.162` ✅
- [x] Community repo configured, updates applied ✅
- [x] Web UI accessible at `https://192.168.1.162:8006` ✅

### Tailscale subnet router
- [x] Tailscale installed on `pve-01` ✅
- [x] Subnet route `192.168.1.0/24` advertised and approved in Tailscale admin ✅
- [x] Proxmox UI reachable via Tailscale ✅

### Pi-hole LXC
- [x] Debian 12 template downloaded ✅
- [x] LXC created at `192.168.1.161` ✅
- [x] Pi-hole installed ✅
- [x] Admin UI accessible at `https://pihole.fiddlestick.org` ✅ (HTTPS via Let's Encrypt)

### DNS cutover
- [x] Wildcard DNS record added in Pi-hole (`fiddlestick.org` → `192.168.1.201`) ✅
- [x] Pi-hole DNS verified with nslookup ✅
- [x] Pi-hole DHCP enabled (range `192.168.1.2–192.168.1.149`, gateway `192.168.1.1`) ✅
- [x] Router DHCP disabled ✅
- [x] Devices picking up Pi-hole as DNS ✅
- [x] Router local DNS entries removed ✅
- [x] Proxmox host DNS updated to `192.168.1.161`, search domain `fiddlestick.org` ✅

### Future work
- [x] Pi-hole HTTPS via Let's Encrypt ✅
- [x] Proxmox UI TLS cert via Let's Encrypt (`pve-01.fiddlestick.org`) ✅
