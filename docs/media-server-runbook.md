# Media Server Runbook

> **Status:** Active — Jellyfin, Sonarr, Radarr, and Bazarr running
> **Stack:** Jellyfin · Sonarr · Radarr · Bazarr · Synology NAS (NFS)

---

## Overview

A self-hosted media stack for TV shows, movies, and home movies.

| Component | Role | URL |
|---|---|---|
| Jellyfin | Media server — streams to clients | `https://jellyfin.fiddlestick.org` |
| Sonarr | TV show monitoring and organization | `https://sonarr.fiddlestick.org` |
| Radarr | Movie monitoring and organization | `https://radarr.fiddlestick.org` |
| Bazarr | Subtitle fetching and management | `https://bazarr.fiddlestick.org` |
| ARM | Automatic Ripping Machine — future DVD/Blu-ray rips | — |

All components run in the `arr` namespace (except Jellyfin, which runs in `jellyfin`).

---

## Architecture

### Storage

All four pods mount the same NAS share (`/volume1/jellyfin` on `192.168.1.3`) via separate
static PVs, but bound to the same underlying filesystem. This means file operations between
pods (e.g. Sonarr organizing a file that Jellyfin then reads) are filesystem-local — no
network copies.

| Pod | PVC | Mount path | NAS path |
|---|---|---|---|
| Jellyfin | `jellyfin-media` | `/media` | `/volume1/jellyfin` |
| Sonarr | `arr-media` | `/media` | `/volume1/jellyfin` |
| Radarr | `arr-media` | `/media` | `/volume1/jellyfin` |
| Bazarr | `arr-media` | `/media` | `/volume1/jellyfin` |

### NAS Directory Structure

```
/volume1/jellyfin/          (NAS root — appears as /media inside pods)
  tv/                       Organized TV library (Sonarr root folder, Jellyfin source)
  movies/                   Organized movie library (Radarr root folder, Jellyfin source)
  home-movies/              Home movies — managed directly, no arr involvement
  imports/                  Drop files here for Sonarr/Radarr manual import
```

### Workflow

```
New media (ARM rip, existing file, etc.)
        │
        ▼
     imports/
        │
        ▼
  Sonarr / Radarr manual import
  (match → rename → Move into tv/ or movies/)
        │
        ▼
  Bazarr detects new file via Sonarr/Radarr API
  → fetches subtitles automatically
        │
        ▼
  Jellyfin scans library → available to stream
```

### Hardlinks

**Not used.** Files are **moved** (not hardlinked or copied) from `imports/` to the organized
library during import. Hardlinks are only beneficial when a torrent client needs to keep
seeding from the original path while arr manages the organized copy — this workflow uses
ARM rips and manual imports, not torrents.

If a torrent client is added in future, this decision should be revisited. The infrastructure
already supports hardlinks since all pods share the same NFS filesystem.

---

## In-App Configuration

### Sonarr (Settings → Media Management)

- **Root Folders:** `/media/tv`
- **Import Mode:** Move

### Radarr (Settings → Media Management)

- **Root Folders:** `/media/movies`
- **Import Mode:** Move

### Jellyfin (Dashboard → Libraries)

| Library name | Content type | Path |
|---|---|---|
| TV Shows | TV Shows | `/media/tv` |
| Movies | Movies | `/media/movies` |
| Home Movies | Mixed Content (or Movies) | `/media/home-movies` |

> ℹ️ Use **Mixed Content** or **Home Videos** for home movies to prevent Jellyfin from
> attempting to match them against external metadata databases (TMDB, etc.).

### Bazarr (Settings → Sonarr / Radarr)

Bazarr connects to Sonarr and Radarr via their internal cluster DNS names and API keys.
It does not require separate path configuration — it reads file locations from the arr APIs.

---

## Workflows

### Manual Import — TV Shows

1. Copy or move files into `/volume1/jellyfin/imports/` on the NAS (flat, no subdirectories needed)
2. In Sonarr: **Series → Add New** — search for the series and add it to the library
3. Go to **Wanted → Manual Import**
4. Browse to `/media/imports/`
5. Match each file to the correct series/season/episode
6. Click **Import** — Sonarr moves the file to `/media/tv/` with the correct name
7. Bazarr picks up the new episodes automatically and fetches subtitles

### Manual Import — Movies

1. Copy or move files into `/volume1/jellyfin/imports/` on the NAS
2. In Radarr: **Movies → Add New** — search for the movie and add it to the library (it will show as Missing — that's expected)
3. Click **Manual Import** (now active), browse to `/media/imports/`
4. Match the file to the correct movie
5. Click **Import** — Radarr moves the file to `/media/movies/` with the correct name
6. Bazarr picks up the new movie automatically and fetches subtitles

> ℹ️ Manual Import is grayed out until at least one movie is added to the Radarr library.
> Always add the movie via Add New before attempting to import a file for it.

### Identifying Ambiguous Media

When a filename gives little information (e.g. `MURDERORIENT`), use runtime to identify
which version of a film or episode you have. Different releases of the same title almost
always have different runtimes.

**Check runtime via Jellyfin's bundled ffprobe** (Jellyfin mounts the same NAS share as
the arr pods, so `imports/` is visible from there):

```bash
kubectl exec -n jellyfin deploy/jellyfin -- \
  /usr/lib/jellyfin-ffmpeg/ffprobe -v quiet \
  -show_entries format=duration,tags \
  -of default \
  /media/imports/<folder>/<file>
```

The `duration` field is in seconds — divide by 60 for minutes. Cross-reference against
IMDB to identify the version.

Example — `MURDERORIENT/MURDERORIENT.mkv` returned `duration=7677` → 127 min → 1974 Lumet version.

Other signals that can help narrow things down:

| Signal | How to use |
|---|---|
| **Runtime** | Most reliable — versions rarely match exactly |
| **Resolution** | 480p/576p → pre-2000s rip; 1080p → modern |
| **Aspect ratio** | Classic films often 4:3; modern widescreen 2.39:1 |
| **Audio tracks** | Mono/stereo only → older; Dolby Atmos/TrueHD → recent disc |
| **Embedded tags** | Some rip tools write title/year into file metadata — shown in ffprobe output above |

### Checking Subtitles After Import

Bazarr should fetch subtitles automatically within a few minutes of a file being imported.
To verify and fix issues:

**1. Check whether subtitles were fetched**

In Bazarr, go to **Wanted** — anything listed there is missing subtitles and hasn't been
fetched yet. If your newly imported item appears here, trigger a manual search:
- Click the search icon next to the item, or
- Select multiple items and use **Search Selected**

**2. Manually search for a specific item**

Navigate to the episode or movie in Bazarr → click the subtitle search icon → pick a result
from the list. Prefer subtitles with a high score/match percentage.

**3. Check sync**

Play the content in Jellyfin. If subtitles are noticeably early or late:

1. In Bazarr, find the episode or movie
2. Click the **Synchronize** button next to the subtitle (clock icon)
3. Bazarr will analyze the audio and shift the subtitle timing to match

> ℹ️ Sync works best when the subtitle is a close match for the right episode/version but
> just has a timing offset. If the subtitle is for a completely different cut or release,
> sync may not be able to correct it — search for a different subtitle file instead.

**4. Replace a bad subtitle**

If sync can't fix it, search for a different file:
1. In Bazarr, find the item → click the subtitle search icon
2. Browse results and pick a different one — try to match the release name shown in
   Sonarr/Radarr (e.g. `WEB-DL`, `BluRay`, specific encoder group)

### DVD Extras

Radarr only imports the main feature file — extras must be handled manually after import.

Jellyfin recognizes extras placed in specifically named subfolders next to the movie file.
After Radarr has organized the main feature, move extras into the movie's directory on the NAS:

```
/media/movies/Murder on the Orient Express (1974)/
  Murder on the Orient Express (1974).mkv   ← placed here by Radarr
  extras/
  behind the scenes/
  deleted scenes/
  featurettes/
  interviews/
  trailers/
```

Jellyfin surfaces these on the movie's detail page. Folder names are case-insensitive.

Individual extra files are displayed using their filename as the title, so rename them
descriptively before moving (e.g. `Albert Finney Interview.mkv` rather than `VTS_01_1.VOB`).

After moving extras, trigger a Jellyfin library scan: Dashboard → Libraries → Scan All Libraries.

### Adding Home Movies

1. Copy files into `/volume1/jellyfin/home-movies/` on the NAS directly
2. Jellyfin will pick them up on its next library scan (or trigger a manual scan via
   Dashboard → Libraries → Scan All Libraries)

No Sonarr, Radarr, or Bazarr involvement.

---

## Troubleshooting

### Files not appearing in Jellyfin after import

Jellyfin may not have scanned yet. Trigger a manual scan:

```bash
# Or use the UI: Dashboard → Libraries → Scan All Libraries
kubectl logs -n jellyfin -l app=jellyfin --tail=50 | grep -i "scan\|library"
```

### Sonarr/Radarr can't see files in imports/

Confirm the file exists on the NAS and the pod can see it:

```bash
kubectl exec -n arr deploy/sonarr -- ls /media/imports/
kubectl exec -n arr deploy/radarr -- ls /media/imports/
```

### Bazarr not fetching subtitles

Check that Bazarr can reach Sonarr and Radarr:

```bash
kubectl logs -n arr -l app=bazarr --tail=50 | grep -i "error\|sonarr\|radarr"
```

Check Bazarr UI: Settings → Sonarr and Settings → Radarr — both should show a green
connection status.

### Pod logs

```bash
kubectl logs -n arr -l app=sonarr --tail=50
kubectl logs -n arr -l app=radarr --tail=50
kubectl logs -n arr -l app=bazarr --tail=50
kubectl logs -n jellyfin -l app=jellyfin --tail=50
```
