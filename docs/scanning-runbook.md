#h  Scanning Runbook — Epson FF-680W → Paperless

> **Scanner:** Epson FF-680W (network scanner, eSCL/AirScan)
> **Destination:** Paperless-ngx at `https://paperless.fiddlestick.org`
> **Script:** `scripts/scan-to-paperless.sh`

---

## How It Works

The script uses SANE with the `sane-airscan` backend, which speaks the scanner's
native **eSCL** protocol over the network. No USB, no proprietary Epson driver.
The scan is uploaded directly to Paperless via its REST API — no NFS mount needed.
Works on the local LAN or remotely via Tailscale.

---

## One-Time Setup (Linux Laptop)

### 1. Install packages

```bash
sudo apt install sane sane-utils sane-airscan img2pdf
```

`sane-airscan` auto-discovers the FF-680W via mDNS — no manual config file needed
as long as the laptop and scanner are on the same network (or reachable via Tailscale).

Verify the scanner is visible:

```bash
scanimage -L
# Expected output includes something like:
# device `airscan:escl:Epson FF-680W:http://192.168.1.xxx/eSCL/' is a ...
```

If the scanner doesn't appear, see [Troubleshooting](#troubleshooting).

### 2. Get a Paperless API token

1. Log in to `https://paperless.fiddlestick.org`
2. Go to **Settings → API** (or `/api/auth/token/`)
3. Click **Generate token** and copy it

### 3. Add the token to your shell environment

Add to `~/.bashrc` or `~/.zshrc` (or a `.env` file you source before scanning):

```bash
export PAPERLESS_TOKEN="your-token-here"
```

Reload your shell:

```bash
source ~/.bashrc
```

### 4. Make the script available

From the homelab repo root:

```bash
ln -s "$(pwd)/scripts/scan-to-paperless.sh" ~/.local/bin/scan-to-paperless
chmod +x ~/.local/bin/scan-to-paperless
```

Or add the `scripts/` directory to your `PATH`.

---

## Usage

### Quick scan (flatbed, colour, 300 dpi)

```bash
scan-to-paperless.sh
```

### Specify a title (shows up in Paperless immediately)

```bash
scan-to-paperless.sh --title "Electricity Bill April 2026"
```

### ADF — multi-page document

Feed the pages into the ADF, then:

```bash
scan-to-paperless.sh --source "ADF Front"
```

For duplex:

```bash
scan-to-paperless.sh --source "ADF Duplex"
```

### Greyscale at lower resolution (faster, smaller file)

```bash
scan-to-paperless.sh --mode Gray --res 200
```

### All options

```
Options:
  -s, --source   Flatbed | ADF Front | ADF Duplex  (default: Flatbed)
  -r, --res      Scan resolution in DPI             (default: 300)
  -m, --mode     Color | Gray | Lineart             (default: Color)
  -d, --device   SANE device string (auto-detected if omitted)
  -t, --title    Document title in Paperless
  -h, --help     Show this help
```

---

## Resolution Guide

| Use case | Resolution | Mode |
|---|---|---|
| Text / receipts | 200–300 dpi | Gray or Lineart |
| Colour documents | 300 dpi | Color |
| Photos for archiving | 600 dpi | Color |
| Film (FF-680W speciality) | 1200–4800 dpi | Color |

Paperless OCR works well at 300 dpi. Going higher mainly helps for photos/film.

---

## Troubleshooting

### Scanner not found (`scanimage -L` returns nothing)

1. Confirm the scanner is powered on and connected to the network
2. Confirm mDNS is working on the laptop:
   ```bash
   avahi-browse -rt _uscan._tcp
   avahi-browse -rt _scanner._tcp
   ```
   You should see `Epson FF-680W` in the output.
3. If mDNS is blocked (e.g. on a different VLAN), add the scanner IP manually
   to `/etc/sane.d/airscan.conf`:
   ```ini
   [devices]
   "Epson FF-680W" = http://192.168.1.XXX/eSCL/, eSCL
   ```
   Find the scanner IP in your router's DHCP table or the Epson app.

### Remote scanning over Tailscale

The scanner itself is not on the Tailscale network — mDNS doesn't traverse VPN.
When connecting remotely, add the scanner IP explicitly in `airscan.conf` (see above).
The IP is reachable via the `192.168.1.0/24` subnet route.

### `img2pdf` not found

```bash
sudo apt install img2pdf
```

### Upload returns 401

Token is wrong or expired. Regenerate it in Paperless → Settings → API.

### Upload returns 413

The scan file exceeds the nginx body limit. The ingress is configured for 64 MB
(`nginx.ingress.kubernetes.io/proxy-body-size: 64m`). Reduce resolution or split
the document.

### ADF scans stop early / miss pages

Some ADF sources use slightly different strings. List what the backend reports:

```bash
scanimage --help --device-name="$(scanimage -L | grep -i epson | sed "s/.*\`\(.*\)'.*/\1/")"
```

Look for the `--source` option and use the exact string (e.g. `ADF` vs `ADF Front`).

---

## Paperless Post-Scan

Documents uploaded via the API go through the normal Paperless processing pipeline:

1. **OCR** — text is extracted (30–60 seconds depending on pages)
2. **Auto-tagging** — if you've configured correspondents/tags/types with matching rules
3. **Inbox** — document appears in the Inbox view (untagged documents) for review and manual tagging

Paperless does not auto-assign tags unless you've set up matching rules under
**Settings → Matching**. A minimal useful rule: match on `--source Flatbed` in
the title or content to auto-tag scanned documents.
