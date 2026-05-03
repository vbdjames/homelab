#!/usr/bin/env bash
# scan-to-paperless.sh
#
# Scan from Epson FF-680W and upload to Paperless-ngx.
#
# Usage:
#   scan-to-paperless.sh [options]
#
# Options:
#   -s, --source   Flatbed | ADF Front | ADF Duplex  (default: Flatbed)
#   -r, --res      Scan resolution in DPI             (default: 300)
#   -m, --mode     Color | Gray | Lineart             (default: Color)
#   -d, --device   SANE device string (auto-detected if omitted)
#   -t, --title    Document title in Paperless
#   -h, --help     Show this help
#
# Required env vars:
#   PAPERLESS_TOKEN   API token from Paperless Settings → API
#
# Optional env vars:
#   PAPERLESS_URL     Defaults to https://paperless.fiddlestick.org
#   SCANNER_DEVICE    Override SANE device (skips auto-detection)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
PAPERLESS_URL="${PAPERLESS_URL:-https://paperless.fiddlestick.org}"
SOURCE="Flatbed"
RESOLUTION="300"
MODE="Color"
DEVICE="${SCANNER_DEVICE:-}"
TITLE=""

# ── Args ──────────────────────────────────────────────────────────────────────
usage() {
  sed -n '/^# Usage/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source)  SOURCE="$2";     shift 2 ;;
    -r|--res)     RESOLUTION="$2"; shift 2 ;;
    -m|--mode)    MODE="$2";       shift 2 ;;
    -d|--device)  DEVICE="$2";     shift 2 ;;
    -t|--title)   TITLE="$2";      shift 2 ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Prereq checks ─────────────────────────────────────────────────────────────
if [[ -z "${PAPERLESS_TOKEN:-}" ]]; then
  echo "Error: PAPERLESS_TOKEN is not set." >&2
  echo "  Get it from: ${PAPERLESS_URL}/settings/ → API" >&2
  exit 1
fi

for cmd in scanimage img2pdf curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' not found. See scanning runbook for setup." >&2
    exit 1
  fi
done

# ── Temp dir (cleaned up on exit) ────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_PDF="$WORK_DIR/scan_${TIMESTAMP}.pdf"

# ── Device detection ──────────────────────────────────────────────────────────
if [[ -z "$DEVICE" ]]; then
  echo "Detecting scanner..."
  DEVICE=$(scanimage -L 2>/dev/null \
    | grep -iE "epson|ff-680|airscan" \
    | head -1 \
    | sed "s/.*\`\(.*\)'.*/\1/" \
    || true)
  if [[ -z "$DEVICE" ]]; then
    echo "Error: No Epson scanner found." >&2
    echo "  Run 'scanimage -L' to list available devices." >&2
    echo "  Ensure the scanner is on and on the same network (or reachable via Tailscale)." >&2
    exit 1
  fi
  echo "Found: $DEVICE"
fi

# ── Scan ──────────────────────────────────────────────────────────────────────
echo "Scanning: source=$SOURCE  resolution=${RESOLUTION}dpi  mode=$MODE"

if [[ "$SOURCE" == Flatbed ]]; then
  # Single page — scan directly to PDF if the backend supports it,
  # otherwise to TIFF then convert.
  if scanimage --help --device-name="$DEVICE" 2>/dev/null | grep -q 'format.*pdf'; then
    scanimage \
      --device-name="$DEVICE" \
      --format=pdf \
      --resolution="$RESOLUTION" \
      --mode="$MODE" \
      --source="Flatbed" \
      >"$OUTPUT_PDF"
  else
    PAGE="$WORK_DIR/page.tiff"
    scanimage \
      --device-name="$DEVICE" \
      --format=tiff \
      --resolution="$RESOLUTION" \
      --mode="$MODE" \
      --source="Flatbed" \
      >"$PAGE"
    img2pdf "$PAGE" -o "$OUTPUT_PDF"
  fi
else
  # ADF — batch scan all pages to individual TIFFs, then combine into one PDF.
  echo "ADF mode: feed pages now; scanning will stop when the ADF is empty."
  scanimage \
    --device-name="$DEVICE" \
    --format=tiff \
    --resolution="$RESOLUTION" \
    --mode="$MODE" \
    --source="$SOURCE" \
    --batch="$WORK_DIR/page-%04d.tiff" \
    --batch-start=1 \
    2>&1 | grep -v "^Scanned" || true  # suppress per-page noise but keep errors

  PAGES=("$WORK_DIR"/page-*.tiff)
  if [[ ${#PAGES[@]} -eq 0 || ! -f "${PAGES[0]}" ]]; then
    echo "Error: No pages scanned." >&2
    exit 1
  fi
  echo "Scanned ${#PAGES[@]} page(s). Combining into PDF..."
  img2pdf "${PAGES[@]}" -o "$OUTPUT_PDF"
fi

PAGE_COUNT=$(img2pdf --help &>/dev/null && python3 -c "
import sys
try:
  import pypdf; r=pypdf.PdfReader('$OUTPUT_PDF'); print(len(r.pages))
except Exception: print('?')
" 2>/dev/null || echo "?")
echo "PDF ready: $(du -h "$OUTPUT_PDF" | cut -f1) (${PAGE_COUNT} page(s))"

# ── Upload ────────────────────────────────────────────────────────────────────
echo "Uploading to Paperless..."

CURL_ARGS=(
  -sf
  -X POST
  -H "Authorization: Token $PAPERLESS_TOKEN"
  -F "document=@${OUTPUT_PDF};type=application/pdf"
)

if [[ -n "$TITLE" ]]; then
  CURL_ARGS+=(-F "title=${TITLE}")
fi

RESPONSE=$(curl "${CURL_ARGS[@]}" "${PAPERLESS_URL}/api/documents/post_document/")

# The API returns a task UUID on success
TASK_ID=$(echo "$RESPONSE" | grep -o '"[0-9a-f-]\{36\}"' | tr -d '"' || true)
if [[ -n "$TASK_ID" ]]; then
  echo "Success! Task ID: $TASK_ID"
  echo "  Document will appear in Paperless within ~30 seconds."
  echo "  Track: ${PAPERLESS_URL}/api/tasks/?task_id=${TASK_ID}"
else
  echo "Upload response: $RESPONSE" >&2
  echo "Warning: Unexpected response — check Paperless for the document." >&2
fi
