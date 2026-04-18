#!/usr/bin/env bash
# filebot.sh — rename media files in place using FileBot, ready for
# Sonarr/Radarr manual import from the imports folder.
#
# Usage:
#   ./scripts/filebot.sh <movies|tv> [test|rename]
#
# Drop files to process on the NAS at:
#   /volume1/jellyfin/imports/movies   (for movies)
#   /volume1/jellyfin/imports/tv       (for TV shows)
#
# FileBot renames files in place — use Sonarr/Radarr Manual Import
# pointing at the imports folder to move them into the library.
#
# Always run with 'test' first to preview renames before committing.
#
# Examples:
#   ./scripts/filebot.sh movies test     # preview movie renames
#   ./scripts/filebot.sh movies rename   # rename movies in place
#   ./scripts/filebot.sh tv test         # preview TV show renames
#   ./scripts/filebot.sh tv rename       # rename TV shows in place

set -euo pipefail

MEDIA_TYPE="${1:-}"
ACTION="${2:-test}"

# Validate arguments
if [[ -z "$MEDIA_TYPE" ]]; then
  echo "Usage: $0 <movies|tv> [test|move]" >&2
  exit 1
fi

if [[ "$MEDIA_TYPE" != "movies" && "$MEDIA_TYPE" != "tv" ]]; then
  echo "Error: media type must be 'movies' or 'tv'" >&2
  exit 1
fi

if [[ "$ACTION" != "test" && "$ACTION" != "rename" ]]; then
  echo "Error: action must be 'test' or 'rename'" >&2
  exit 1
fi

# Config per media type
if [[ "$MEDIA_TYPE" == "movies" ]]; then
  DB="TheMovieDB"
  SOURCE="/media/imports/movies"
  FORMAT="{n} ({y})"
else
  DB="TheTVDB"
  SOURCE="/media/imports/tv"
  FORMAT="{n} - {s00e00} - {t}"
fi

if [[ "$ACTION" == "test" ]]; then
  echo "==> DRY RUN — no files will be renamed"
else
  echo "==> LIVE RUN — files in $SOURCE will be renamed in place"
  read -r -p "Are you sure? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "==> Cleaning up any previous filebot-rename job..."
kubectl delete job -n arr filebot-rename --ignore-not-found

echo "==> Submitting FileBot job (type=$MEDIA_TYPE, action=$ACTION)..."
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: filebot-rename
  namespace: arr
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: filebot
          image: rednoah/filebot
          command:
            - filebot
            - -rename
            - "${SOURCE}"
            - -r
            - --db
            - "${DB}"
            - --format
            - "${FORMAT}"
            - --action
            - "$([[ "$ACTION" == "test" ]] && echo TEST || echo MOVE)"
            - -non-strict
            - --no-xattr
          volumeMounts:
            - name: media
              mountPath: /media
            - name: license
              mountPath: /data/license.txt
              subPath: license.psm
      volumes:
        - name: media
          persistentVolumeClaim:
            claimName: arr-media
        - name: license
          secret:
            secretName: filebot-license
EOF

echo "==> Waiting for pod to start..."
until kubectl logs -n arr job/filebot-rename --follow 2>/dev/null; do
  sleep 3
done

echo ""
echo "==> Job complete."
if [[ "$ACTION" == "test" ]]; then
  echo "    Review the output above, then run:"
  echo "    $0 $MEDIA_TYPE rename"
fi
