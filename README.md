# *Lawrence of Arabia* (1962) Roadshow Rebuild
This project uses [MakeMKV](https://www.makemkv.com/download/) and the [Lawrence of Arabia 4K Blu-ray SteelBook / 60th Anniversary Limited Edition](https://www.blu-ray.com/movies/Lawrence-of-Arabia-4K-Blu-ray/312408/)
to turn *Lawrence of Arabia* (1962) into the **Restored Roadshow** presentation by concatenating Disc 1 (Act I), a generated black Intermission (video-only), and Disc 2 (Act II).
The script preserves HDR10 metadata, fills the intermission gap cleanly, and reliably handles audio/subtitle seams.

**NOTE:** The script itself was created in part with **ChatGPT 5 Thinking** as the finer points of video, audio, and subtitle processing were beyond what I could learn in a reasonable amount of time.

> ✅ Verified working end-to-end on Debian 12 with VLC, mpv, and Plex (HDR10 passthrough).

## Features

- **BL-only HDR10 video:** Demuxes Dolby Vision streams and keeps base layer (BL).

- **Intermission gap:** Generates fixed-GOP, bframes=0, HDR10-compliant black video (duration configurable).

- **Audio policy**

  1. If a codec supports silence generation, creates the intermission gap in the same codec and appends losslessly.

  2. Otherwise (TrueHD / DTS-HD MA / unknown), rebuilds **A1 + gap + A2 as FLAC** and muxes as one track.

  3. Track names set to **channel layout + “(gap-filled)”**; players typically show language automatically.

- **Subtitles:** Concatenates Disc-1 + shifted Disc-2, compensating for seam differences using measured PTS.

- **Plex-friendly title:** Output filename supports Plex’s `{edition-…}` tag.

## Requirements
When developing this, I used MakeMKV on Windows 10 to get `pt1.mkv` and `pt2.mkv`. I kept **ALL**
subtitle and audio tracks from both discs.

Install the following tools (package names shown for Debian/Ubuntu):

- **MKVToolNix:** `mkvmerge`, `mkvextract`
  ```
  sudo apt install mkvtoolnix
  ```
- **FFmpeg suite:** `ffmpeg`, `ffprobe`
  ```
  sudo apt install ffmpeg
  ```
- **Utilities:** `jq`, `awk`, `sed`
  ```
  sudo apt install jq gawk sed
  ```
- **dovi_tool** (to strip DV EL/RPU):
    - From source or prebuilt release: https://github.com/quietvoid/dovi_tool
> Make sure all binaries are in your `PATH`.

## Inputs & Outputs
- **Inputs**
    - `pt1.mkv` — Disc 1 (Act I)
    - `pt2.mkv` — Disc 2 (Act II)
    Place them in the same directory as the script, or adjust variables in the script.
- **Output**
    - `./roadshow_build/Lawrence of Arabia (1962) {edition-Restored Roadshow Version}.mkv`
      (Change the `OUT` variable if you prefer a different Plex title.)

## Quick Start
```
# 1) Make the script executable
chmod +x build-loa_roadshow.sh

# 2) Put pt1.mkv and pt2.mkv next to the script (or edit DISC1/DISC2 variables)

# 3) Run
./build-loa_roadshow.sh
```

The script creates a temp workspace at `./roadshow_tmp_hdr10` (kept by default for inspection) and writes
the final MKV to `./roadshow_build/`.

## Configuration (edit at top of the script)
| Variable                    | Purpose                                                    | Default                |
| --------------------------- | ---------------------------------------------------------- | ---------------------- |
| `DISC1`, `DISC2`            | Input MKVs for Act I/II                                    | `pt1.mkv`, `pt2.mkv`   |
| `GAP_SEC`                   | Intermission length in seconds                             | `600`                  |
| `PREFERRED_LANGS`           | Comma-separated 639-2/BCP-47 codes to mark **default=yes** | `eng`                  |
| `SET_DEFAULT_FOR_PREFERRED` | Whether to mark first preferred track as default           | `1`                    |
| `TMP`                       | Temp folder                                                | `./roadshow_tmp_hdr10` |
| `OUT_DIR`                   | Output folder                                              | `./roadshow_build`     |
| `OUT`                       | Output file path/name (Plex-friendly supported)            | see script             |
| `KEEP_TMP`                  | Keep temp files (`1`) or delete (`0`)                      | `1`                    |

## How it Works (high level)
1. **Probe** both discs (durations, track lists, languages).

2. **Video**
     - Demux HEVC from both discs.
     - Strip DV EL/RPU with `dovi_tool` → BL only.
     - Extract HDR10 mastering/CLL metadata from Disc 1.
     - Encode a black gap with x265 Main10, fixed GOP (keyint 24, no B-frames), HDR10 metadata copied.
     - Concatenate BL streams: Disc1 + Gap + Disc2.

3. **Audio** (per track id)
     - Try to create silence in the same codec (AC-3, E-AC-3, DTS core, AAC, PCM, FLAC).
     - If not supported (e.g., **TrueHD**, **DTS-HD MA**), transcode Act I, gap, Act II to **FLAC**, concatenate once via `ffmpeg -f concat`, then mux.
     - Track language and display name set; first preferred language gets `default=yes`.

4. **Subtitles**
     - Extract Disc-1/2, compute a precise shift for Disc-2 (Intermission + seam compensation), and append.
    - First English subtitle is set `default=yes` (not forced).

5. **Final mux** with `mkvmerge`, including appropriate feature-gated flags (e.g., `--default-duration`, `--cue-duration`).

## Notes & Tips
- **Naming for Plex**
    The default output uses Plex’s edition tag:
    `Lawrence of Arabia (1962) {edition-Restored Roadshow Version}.mkv`

- **Disk space**
    You’ll need free space for temporary HEVC streams, audio intermediates, and the final MKV. UHD
    sources are large; plan accordingly.

- **Performance**
    Gap encoding is fast (ultrafast preset) and small; the heavy lifting is I/O and muxing.

- **Safety**
    The script runs with `set -euo pipefail` and uses `ffmpeg -nostdin` to avoid accidental stalls.

## Troubleshooting
- **“command not found” errors**: Confirm required tools are installed and in `PATH`.
- **DV not stripped / color issues**: Ensure `dovi_tool` is installed and accessible.
- **Audio default not set**: Check `PREFERRED_LANGS` values (use `eng`, `deu`, `fra`, etc.).
- **Mismatched audio channel layouts**: The script probes SR/CH and standardizes during FLAC fallback; if you have unusual layouts, verify with `ffprobe`.
- **Subtitle drift after intermission**: The script compensates using measured last PTS of Disc-1 per stream; if you customized `GAP_SEC`, re-run from scratch.

## Repository Layout (suggested)
```
.
├── build-loa_roadshow.sh     # Main script
├── README.md                 # This file
└── docs/                     # (optional) notes, logs, screenshots
```

## License
GNU General Public License v2.0

## Acknowledgments
- MKVToolNix by Moritz Bunkus
- FFmpeg project
- `dovi_tool` by quietvoid

## Disclaimer
This script is intended for lawful personal use with content you own. Respect copyright and your local laws.
