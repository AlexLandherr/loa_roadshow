# *Lawrence of Arabia* (1962) Roadshow Rebuild
This project uses [MakeMKV](https://www.makemkv.com/download/) and the [Lawrence of Arabia 4K Blu-ray SteelBook / 60th Anniversary Limited Edition](https://www.blu-ray.com/movies/Lawrence-of-Arabia-4K-Blu-ray/312408/)
to turn *Lawrence of Arabia* (1962) into the **Restored Roadshow** presentation by concatenating Disc 1 (Act I), a generated black Intermission (video-only), and Disc 2 (Act II).
The script preserves HDR10 metadata, fills the intermission gap cleanly, and reliably handles audio/subtitle seams.

**NOTE:** The script itself was created in part with **ChatGPT 5 Thinking** as the finer points of video, audio, and subtitle processing were beyond what I could learn in a reasonable amount of time.

> ✅ Verified working end-to-end on Debian 12 with VLC, mpv, and Plex (HDR10 passthrough).

## Background: what is a “roadshow” presentation?
In the mid-20th century, some prestige films opened as **roadshow presentations**: limited engagements with reserved seating, printed souvenir programs, and overture/entr’acte music, often with an **intermission** placed at a dramatic midpoint. These elements were designed to give the screening a theatrical, event-like character and to accommodate projection/reel changes in very long films (Wikipedia 2025a; Wikipedia 2025b).

*Lawrence of Arabia* premiered in 1962 in just such a format. The original release ran for roughly 222 minutes **plus an overture, an intermission, and exit music**; subsequent restorations have likewise preserved the overture/intermission structure (Wikipedia 2025b). In home-media contexts, those elements may be omitted or separated unless deliberately reconstructed; this project re-creates the roadshow flow—**Overture → Act I → Intermission (black screen, no audio/subs) → Entr’acte → Act II**—inside a single, HDR10-compliant MKV to match the historical presentation (Wikipedia 2025a; Wikipedia 2025b).

Roadshow engagements of epic features included overture, intermission, and entr’acte material, with the intermission intended as a short, scheduled pause. Contemporary exhibitor guidance reproduced by the Widescreen Museum specifies that “the length of an intermission should be between ten and fifteen minutes at most,” reflecting industry practice for reserved-seat roadshows of the period (Widescreen Museum, n.d.). Modern archival/repertory screenings of Lawrence of Arabia continue this convention; for example, TIFF lists its 70mm presentations of the film as including a 15-minute intermission (TIFF, 2024). This project’s default 600-second gap follows that norm.

- Disc 1 of the linked-to Blu-ray contains the Overture (to black) → Act I → **INTERMISSION** card followed by end of Disc 1. It's duration (@ 24000/1001 fps) is ~2 hours 19 minutes 23 seconds.
- Disc 2 of the linked-to Blu-ray contains the Entr'acte (to black) → Act II → End credits. It's duration (@ 24000/1001 fps) is ~1 hour 27 minutes 38 seconds.

As such this projects default uses an Intermission of 10 minutes such that the final video duration is 3 hours 57 minutes 1 second.

### References
- Wikipedia (2025a) *Intermission (film)*. https://en.wikipedia.org/wiki/Intermission_(film)
 (Accessed: 2025-10-05).
- Wikipedia (2025b) *Lawrence of Arabia (film) — Release and restoration notes*. https://en.wikipedia.org/wiki/Lawrence_of_Arabia_(film)
 (Accessed: 2025-10-05).
- Widescreen Museum (n.d.) *Intermissions, Lounges and Foyers*. https://www.widescreenmuseum.com/sound/stereo20.htm
 (Accessed: 2025-10-05).
- TIFF (2024) *Lawrence of Arabia (70mm)*. https://tiff.net/events/lawrence-of-arabia
 (Accessed: 2025-10-05).

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
  sudo apt install jq awk sed
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
