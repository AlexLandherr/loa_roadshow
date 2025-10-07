#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob

##############################################################################
# Lawrence of Arabia (1962) – UHD “Roadshow” rebuild (HDR10 BL-only)
#
# Audio policy (per track):
#  1) If codec is supported for silence generation, create the gap in THAT codec
#     and append A1 + SIL + A2 losslessly.
#  2) If not (TrueHD / DTS-HD MA / unknown), rebuild the WHOLE track as FLAC
#     (A1->FLAC + SIL->FLAC + A2->FLAC) and concatenate with ffmpeg’s
#     filter_complex using aformat-normalization to guarantee matching params.
#  3) Track names = channel layout only (VLC/mpv add [Language] themselves).
#
# Hardenings:
#  • ffmpeg -nostdin everywhere
#  • FLAC fallback concatenation via concat filter + aformat normalization
#  • FLAC silence uses reference-driven SR/layout and explicit sample_fmt (s16/s32)
#  • Probe SR/CH from Disc-2 if Disc-1 part missing
##############################################################################

DISC1="pt1.mkv"     # Act I
DISC2="pt2.mkv"     # Act II

# Gap (intermission)
GAP_SEC=600
FPS_RAT="24000/1001"
W=3840; H=2160

# Preferred language(s) for default=yes (comma-separated 639-2 codes)
PREFERRED_LANGS="eng"
SET_DEFAULT_FOR_PREFERRED=1

TMP="$(pwd)/roadshow_tmp_hdr10"
OUT_DIR="roadshow_build"
OUT="$OUT_DIR/Lawrence of Arabia (1962) {edition-Restored Roadshow Version}.mkv"
KEEP_TMP=1

need(){ command -v "$1" &>/dev/null || { echo "❌ $1 missing"; exit 1; }; }
for b in mkvmerge mkvextract ffmpeg ffprobe jq awk sed dovi_tool; do need "$b"; done
[[ -e $DISC1 && -e $DISC2 ]] || { echo "❌ source MKVs missing"; exit 1; }

mkdir -p "$TMP" "$OUT_DIR"

# mkvmerge flags (feature-gated)
if mkvmerge --help | grep -q -- '--default-track-flag'; then DEFAULT_OPT="--default-track-flag"; else DEFAULT_OPT="--default-track"; fi
if mkvmerge --help | grep -q -- '--forced-track-flag';  then FORCED_OPT="--forced-track-flag";  else FORCED_OPT="--forced-track";  fi
HAS_CUE_DURATION=0; HAS_DEFAULT_DURATION=0; HAS_FIX_BT=0
mkvmerge --help | grep -q -- '--cue-duration' && HAS_CUE_DURATION=1
mkvmerge --help | grep -q -- '--default-duration' && HAS_DEFAULT_DURATION=1
mkvmerge --help | grep -q -- '--fix-bitstream-timing-information' && HAS_FIX_BT=1
echo "Using mkvmerge opts: DEFAULT_OPT='$DEFAULT_OPT' FORCED_OPT='$FORCED_OPT'"

# ----- FPS & gap frames -----
FPS_NUM=24000; FPS_DEN=1001
GAP_FRAMES=$(( (GAP_SEC*FPS_NUM + FPS_DEN - 1) / FPS_DEN ))
echo "Gap: ${GAP_SEC}s → ${GAP_FRAMES} frames @ ${FPS_RAT}"

# ----- Inspect inputs -----
J1="$TMP/pt1.json"; J2="$TMP/pt2.json"
mkvmerge -J "$DISC1" >"$J1"
mkvmerge -J "$DISC2" >"$J2"

VID1_ID=$(jq -r '.tracks[] | select(.type=="video") | .id' "$J1" | head -n1)
VID2_ID=$(jq -r '.tracks[] | select(.type=="video") | .id' "$J2" | head -n1)
[[ -n ${VID1_ID:-} && -n ${VID2_ID:-} ]] || { echo "❌ could not find video tracks"; exit 1; }

DISC1_DUR_MS=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$DISC1" | awk '{printf("%.0f",$1*1000)}')
SEAM_MS=$DISC1_DUR_MS
GAP_MS=$((GAP_SEC*1000))
echo "Seam (Disc-1 duration): $((SEAM_MS/1000)) s"

# ----- Demux BL (strip any DV EL/RPU) -----
echo "[1/6] Demuxing BL video…"
mkvextract "$DISC1" tracks ${VID1_ID}:"$TMP/d1_full.hevc" >/dev/null
mkvextract "$DISC2" tracks ${VID2_ID}:"$TMP/d2_full.hevc" >/dev/null
dovi_tool demux -i "$TMP/d1_full.hevc" -b "$TMP/d1_bl.hevc" >/dev/null
dovi_tool demux -i "$TMP/d2_full.hevc" -b "$TMP/d2_bl.hevc" >/dev/null

# ----- Copy HDR10 static metadata for the gap -----
HDR_MASTER=""; HDR_CLL=""
readarray -t SD < <(ffprobe -v error -select_streams v:0 \
  -show_entries stream=color_space,color_transfer,color_primaries:side_data_list \
  -of json "$DISC1" | jq -r '
    .streams[0].side_data_list // [] |
    map(select(.side_data_type=="Mastering display metadata")) |
    (.[0] // {}) as $m |
    [$m.red_x,$m.red_y,$m.green_x,$m.green_y,$m.blue_x,$m.blue_y,$m.white_point_x,$m.white_point_y,$m.max_luminance,$m.min_luminance] | @tsv
  ')
if [[ ${#SD[@]} -gt 0 && ${SD[0]} != "null	null	null	null	null	null	null	null	null	null" ]]; then
  IFS=$'\t' read -r Rx Ry Gx Gy Bx By Wx Wy Lmax Lmin <<<"${SD[0]}"
  if [[ -n ${Rx:-} && ${Rx} != "null" ]]; then
    s(){ awk -v x="$1" 'BEGIN{printf("%.0f", x*50000)}'; }
    n(){ awk -v x="$1" 'BEGIN{printf("%.0f", x*10000)}'; }
    HDR_MASTER="master-display=G($(s $Gx),$(s $Gy))B($(s $Bx),$(s $By))R($(s $Rx),$(s $Ry))WP($(s $Wx),$(s $Wy))L($(n $Lmax),$(n $Lmin))"
  fi
fi
CLL=$(ffprobe -v error -select_streams v:0 -show_entries side_data_list \
  -of json "$DISC1" | jq -r '.streams[0].side_data_list // [] | map(select(.side_data_type=="Content light level metadata")) | (.[0] // {}) | "\(.max_content|tostring),\(.max_average|tostring)"')
[[ -n ${CLL:-} && $CLL != "null,null" ]] && HDR_CLL="max-cll=${CLL}"
[[ -n $HDR_MASTER ]] && echo "HDR10 Mastering (copied): $HDR_MASTER"
[[ -n $HDR_CLL    ]] && echo "HDR10 CLL (copied):       $HDR_CLL"

# ----- Build HDR10 black gap (seam-friendly & level-matched) -----
echo "[2/6] Building ${GAP_SEC}s HDR10 black (Main10, fixed GOP, bframes=0)…"
X265P="profile=main10:level-idc=5.1:high-tier=1:repeat-headers=1:aud=1"
X265P="$X265P:open-gop=0:scenecut=0:bframes=0:ref=1:rc-lookahead=0:lookahead-slices=0"
X265P="$X265P:keyint=24:min-keyint=24"
X265P="$X265P:vbv-maxrate=120000:vbv-bufsize=120000:nal-hrd=vbr"
X265P="$X265P:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr10=1"
[[ -n $HDR_MASTER ]] && X265P="$X265P:$HDR_MASTER"
[[ -n $HDR_CLL    ]] && X265P="$X265P:$HDR_CLL"

ffmpeg -nostdin -hide_banner -loglevel error \
  -f lavfi -i "color=c=black:s=${W}x${H}:r=${FPS_RAT}" -frames:v $GAP_FRAMES -vf format=yuv420p10le \
  -c:v libx265 -preset ultrafast -crf 18 -x265-params "$X265P" -an -y "$TMP/gap_bl.hevc"

# ----- Concatenate BL video only -----
echo "[3/6] Concatenating video (BL only)…"
mkvmerge -q --no-audio --no-subtitles --no-chapters \
  -o "$TMP/video_cat_hdr10.mkv" \
  "$TMP/d1_bl.hevc" + "$TMP/gap_bl.hevc" + "$TMP/d2_bl.hevc"

##############################################################################
#                                AUDIO
##############################################################################
fix_lang(){ local L="${1:-und}"; [[ "$L" =~ ^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$ ]] && echo "$L" || echo "und"; }
chan_label(){ case "${1:-2}" in 1) echo "Mono";; 2) echo "Stereo";; 6) echo "Surround 5.1";; 7) echo "Surround 6.1";; 8) echo "Surround 7.1";; *) echo "${1}-channel";; esac; }
layout_for_ch(){ case "${1:-2}" in 1) echo "mono";; 2) echo "stereo";; 6) echo "5.1";; 8) echo "7.1";; *) echo "";; esac; }
codec_family(){
  local id="$1" name="$2"
  case "$id" in
    A_EAC3*) echo eac3;;
    A_AC3*)  echo ac3;;
    A_DTSHD*)echo dtshd;;
    A_DTS*)  echo dts;;
    A_TRUEHD*) echo truehd;;
    A_PCM*|A_MS/ACM*) echo pcm;;
    A_FLAC*) echo flac;;
    A_AAC*|A_AAC/*|A_AAC-2*) echo aac;;
    *) [[ "$name" == *"DTS-HD"* ]] && echo dtshd || { [[ "$name" == "DTS" ]] && echo dts || echo unknown; } ;;
  esac
}
probe_sr(){ ffprobe -v error -show_entries stream=sample_rate -of csv=p=0 "$1" | head -n1 || true; }
probe_ch(){ ffprobe -v error -show_entries stream=channels     -of csv=p=0 "$1" | head -n1 || true; }
probe_bps(){ ffprobe -v error -show_entries stream=bits_per_raw_sample -of csv=p=0 "$1" | head -n1 || true; }

# Decide target FLAC sample_fmt from bits-per-sample (default to s32 if unknown/24+)
choose_sf(){ local bps="${1:-}"; if [[ "$bps" =~ ^1?[0-9]$ ]]; then echo "s16"; else echo "s32"; fi; }

# Silence support in SAME codec
can_native_gap(){ case "$1" in ac3|eac3|dts|aac|pcm|flac) return 0;; *) return 1;; esac; }

# Make a silence chunk in a specific codec
# make_silence fam sr ch out [br] [sample_fmt_for_flac]
make_silence(){
  local fam="$1" sr="$2" ch="$3" out="$4" br="${5:-}" sf="${6:-}"
  local src="anullsrc=r=$sr"; local lay; lay="$(layout_for_ch "$ch")"; [[ -n "$lay" ]] && src="$src:cl=$lay"
  case "$fam" in
    ac3)   [[ -z $br ]] && br=$([[ $ch -ge 6 ]] && echo "640k" || echo "192k")
           ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -t $GAP_SEC -i "$src" -c:a ac3  -b:a "$br" -ar "$sr" -ac "$ch" "$out";;
    eac3)  [[ -z $br ]] && br=$([[ $ch -ge 6 ]] && echo "768k" || echo "224k")
           ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -t $GAP_SEC -i "$src" -c:a eac3 -b:a "$br" -ar "$sr" -ac "$ch" "$out";;
    dts)   local dbr=$([[ $ch -ge 6 ]] && echo "1536k" || echo "768k")
           ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -t $GAP_SEC -i "$src" -c:a dca  -b:a "$dbr" -ar "$sr" -ac "$ch" "$out";;
    aac)   [[ -z $br ]] && br=$([[ $ch -ge 6 ]] && echo "384k" || echo "128k")
           ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -t $GAP_SEC -i "$src" -c:a aac  -b:a "$br" -ar "$sr" -ac "$ch" "$out";;
    pcm)   ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -t $GAP_SEC -i "$src"           -c:a pcm_s16le -ar "$sr" -ac "$ch" "$out";;
    flac)  if [[ -n "$sf" ]]; then
             ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -t $GAP_SEC -i "$src" -c:a flac -compression_level 12 -sample_fmt "$sf" -ar "$sr" -ac "$ch" "$out"
           else
             ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -t $GAP_SEC -i "$src" -c:a flac -compression_level 12 -ar "$sr" -ac "$ch" "$out"
           fi
           ;;
    *)     return 2;;
  esac
}

# Re-encode a raw stream to a target codec (used for FLAC fallback)
# encode_to in out fam sr ch [br] [sample_fmt_for_flac]
encode_to(){
  local in="$1" out="$2" fam="$3" sr="$4" ch="$5" br="${6:-}" sf="${7:-}"
  case "$fam" in
    flac)
      if [[ -n "$sf" ]]; then
        # --- 24-bit mod: when using s32 pipeline, set bits_per_raw_sample=24 ---
        local bpr=()
        if [[ "$sf" == "s32" ]]; then bpr=( -bits_per_raw_sample 24 ); fi
        ffmpeg -nostdin -hide_banner -loglevel error -i "$in" \
          -c:a flac -compression_level 12 -sample_fmt "$sf" "${bpr[@]}" \
          -ar "$sr" -ac "$ch" "$out"
      else
        ffmpeg -nostdin -hide_banner -loglevel error -i "$in" \
          -c:a flac -compression_level 12 \
          -ar "$sr" -ac "$ch" "$out"
      fi
      ;;
    ac3)  [[ -z $br ]] && br=$([[ $ch -ge 6 ]] && echo "640k" || echo "192k"); ffmpeg -nostdin -hide_banner -loglevel error -i "$in" -c:a ac3  -b:a "$br" -ar "$sr" -ac "$ch" "$out" ;;
    aac)  [[ -z $br ]] && br=$([[ $ch -ge 6 ]] && echo "384k" || echo "128k"); ffmpeg -nostdin -hide_banner -loglevel error -i "$in" -c:a aac  -b:a "$br" -ar "$sr" -ac "$ch" "$out" ;;
    pcm)  ffmpeg -nostdin -hide_banner -loglevel error -i "$in" -c:a pcm_s16le -ar "$sr" -ac "$ch" "$out" ;;
    eac3) [[ -z $br ]] && br=$([[ $ch -ge 6 ]] && echo "768k" || echo "224k"); ffmpeg -nostdin -hide_banner -loglevel error -i "$in" -c:a eac3 -b:a "$br" -ar "$sr" -ac "$ch" "$out" ;;
    dts)  local dbr=$([[ $ch -ge 6 ]] && echo "1536k" || echo "768k"); ffmpeg -nostdin -hide_banner -loglevel error -i "$in" -c:a dca  -b:a "$dbr" -ar "$sr" -ac "$ch" "$out" ;;
    *)    return 2;;
  esac
}

lang_is_pref(){ local L="$1"; IFS=',' read -ra P <<<"$PREFERRED_LANGS"; for x in "${P[@]}"; do [[ "$x" == "$L" ]] && return 0; done; return 1; }

echo "[4/6] Handling audio…"
AUDIO_OPTS_PREF=(); AUDIO_OPTS_OTHERS=(); DEFAULT_SET=0

# Language hints from Disc 2 if Disc 1 says "und"
declare -A LANG_AUDIO_D2
while IFS=$'\t' read -r id lang; do
  [[ -n $id ]] && LANG_AUDIO_D2["$id"]="$lang"
done < <(jq -r '.tracks[] | select(.type=="audio") | "\(.id)\t\(.properties.language // "und")"' "$J2")

# Iterate Disc 1 audio tracks
while IFS=$'\t' read -r id codec_id codec_name lang_raw; do
  [[ -z ${id:-} ]] && continue
  lang=$(fix_lang "$lang_raw"); [[ "$lang" == "und" && -n ${LANG_AUDIO_D2[$id]:-} ]] && lang="${LANG_AUDIO_D2[$id]}"

  fam=$(codec_family "$codec_id" "$codec_name")
  A1="$TMP/a1_${id}.raw"; A2="$TMP/a2_${id}.raw"
  mkvextract "$DISC1" tracks "$id":"$A1" >/dev/null 2>&1 || true
  mkvextract "$DISC2" tracks "$id":"$A2" >/dev/null 2>&1 || true
  [[ ! -s $A1 && ! -s $A2 ]] && continue

  # Probe SR/CH; if Disc-1 missing but Disc-2 present, use Disc-2 values
  SR=$(probe_sr "$A1"); [[ -z ${SR:-} || "$SR" == "N/A" ]] && SR=$(probe_sr "$A2")
  CH=$(probe_ch "$A1"); [[ -z ${CH:-} || "$CH" == "N/A" ]] && CH=$(probe_ch "$A2")
  [[ -z ${SR:-} || "$SR" == "N/A" ]] && SR=48000
  [[ -z ${CH:-} || "$CH" == "N/A" ]] && CH=2

  # For FLAC (both native-gap and fallback) we need a stable sample_fmt (s16/s32)
  BPS1=$(probe_bps "$A1" || true); BPS2=$(probe_bps "$A2" || true)
  [[ -z "${BPS1:-}" || "$BPS1" == "N/A" ]] && BPS1=""
  [[ -z "${BPS2:-}" || "$BPS2" == "N/A" ]] && BPS2=""
  BPS="${BPS1:-${BPS2:-}}"
  SF_FLAC="$(choose_sf "$BPS")"  # s16 for <=16-bit, otherwise s32 (safe superset)

  CH_LABEL=$(chan_label "$CH")
  disp="${CH_LABEL} (gap-filled)"
  out="$TMP/audio_${id}.mka"

  if can_native_gap "$fam"; then
    # Make silence in the SAME codec
    case "$fam" in
      ac3)  EXT="ac3" ;; eac3) EXT="eac3" ;; dts) EXT="dts" ;;
      aac)  EXT="aac" ;; pcm)  EXT="wav"  ;; flac) EXT="flac" ;;
    esac
    SIL="$TMP/sil_${id}.${EXT}"
    if [[ "$fam" == "flac" ]]; then
      # Ensure silence FLAC matches sample_fmt of source (prevents mkvmerge append errors)
      make_silence flac "$SR" "$CH" "$SIL" "" "$SF_FLAC"
    else
      make_silence "$fam" "$SR" "$CH" "$SIL"
    fi

    # Append raw segments directly into one MKA
    if [[ -s $A1 && -s $A2 ]]; then
      mkvmerge -q -o "$out" "$A1" + "$SIL" + "$A2"
    elif [[ -s $A1 ]]; then
      mkvmerge -q -o "$out" "$A1" + "$SIL"
    else
      mkvmerge -q -o "$out" "$SIL" + "$A2"
    fi
  else
    # Fallback: rebuild whole track as FLAC (preserve channels)
    T1="$TMP/fb_a1_${id}.flac"; T2="$TMP/fb_a2_${id}.flac"; SIL="$TMP/fb_sil_${id}.flac"
    [[ -s $A1 ]] && encode_to "$A1" "$T1" flac "$SR" "$CH" "" "$SF_FLAC"
    [[ -s $A2 ]] && encode_to "$A2" "$T2" flac "$SR" "$CH" "" "$SF_FLAC"
    make_silence flac "$SR" "$CH" "$SIL" "" "$SF_FLAC"

    # Build robust concat via filter_complex + aformat (avoids FLAC param mismatches)
    declare -a IN_ARR=()
    [[ -s $T1 ]] && IN_ARR+=( "$T1" )
    IN_ARR+=( "$SIL" )
    [[ -s $T2 ]] && IN_ARR+=( "$T2" )

    N=${#IN_ARR[@]}
    [[ $N -ge 1 ]] || continue
    LAYOUT_STR="$(layout_for_ch "$CH")"
    [[ -z "$LAYOUT_STR" ]] && LAYOUT_STR="${CH}c"  # fallback, e.g., "3c"

    # Assemble ffmpeg inputs and filter graph
    declare -a FFM_IN=()
    for f in "${IN_ARR[@]}"; do FFM_IN+=( -i "$f" ); done

    filter_parts=()
    for ((i=0; i<N; i++)); do
      filter_parts+=("[${i}:a]aformat=sample_fmts=${SF_FLAC}:channel_layouts=${LAYOUT_STR}:sample_rates=${SR}[a${i}]")
    done
    concat_in=""
    for ((i=0; i<N; i++)); do concat_in="${concat_in}[a${i}]"; done
    FILTER="$(printf "%s; %s" "$(IFS='; '; echo "${filter_parts[*]}")" "${concat_in}concat=n=${N}:v=0:a=1[out]")"

    FULL="$TMP/fb_full_${id}.flac"
    ffmpeg -nostdin -hide_banner -loglevel error \
      "${FFM_IN[@]}" \
      -filter_complex "$FILTER" -map "[out]" \
      -c:a flac -compression_level 12 -sample_fmt "$SF_FLAC" -ar "$SR" -ac "$CH" "$FULL"

    mkvmerge -q -o "$out" "$FULL"
  fi

  # First preferred language becomes default=yes (once)
  ADD_OPTS=( --language 0:"$lang" --track-name 0:"$disp" "$DEFAULT_OPT" 0:no "$out" )
  if lang_is_pref "$lang" && (( SET_DEFAULT_FOR_PREFERRED==1 )) && (( DEFAULT_SET==0 )); then
    ADD_OPTS=( --language 0:"$lang" --track-name 0:"$disp" "$DEFAULT_OPT" 0:yes "$out" )
    DEFAULT_SET=1
    AUDIO_OPTS_PREF+=( "${ADD_OPTS[@]}" )
  else
    AUDIO_OPTS_OTHERS+=( "${ADD_OPTS[@]}" )
  fi

done < <(jq -r '.tracks[] | select(.type=="audio") | [(.id|tostring),(.codec_id // ""),(.codec // ""),(.properties.language // "und")] | @tsv' "$J1")

AUDIO_OPTS=( "${AUDIO_OPTS_PREF[@]}" "${AUDIO_OPTS_OTHERS[@]}" )

##############################################################################
#                               SUBTITLES
##############################################################################
echo "[5/6] Handling subtitles…"
declare -a SUB_OPTS=()
ENG_ID_DISC2=$(jq -r '(.tracks | map(select(.type=="subtitles" and ((.properties.language // "und")=="eng"))) | .[0]).id // empty' "$J2")
mapfile -t SUB_ID_LANG < <(jq -r '.tracks[] | select(.type=="subtitles") | "\(.id)\t\(.properties.language // "und")"' "$J1")
declare -A LANG_OF; declare -a ORDERED_SUB_IDS=()
for line in "${SUB_ID_LANG[@]}"; do id=${line%%$'\t'*}; lang=${line#*$'\t'}; LANG_OF["$id"]="$lang"; done
[[ -n ${ENG_ID_DISC2:-} ]] && ORDERED_SUB_IDS+=( "$ENG_ID_DISC2" )
for line in "${SUB_ID_LANG[@]}"; do id=${line%%$'\t'*}; [[ -n ${ENG_ID_DISC2:-} && $id == "$ENG_ID_DISC2" ]] && continue; ORDERED_SUB_IDS+=( "$id" ); done

last_pts_ms_or_disc1_end(){ local f="$1"; [[ -s "$f" ]] && ffprobe -v error -show_entries packet=pts_time -of csv=p=0 "$f" | tail -n1 | awk '{printf("%.0f",$1*1000)}' || echo "$DISC1_DUR_MS"; }
SUB_BASE_SHIFT_MS=$GAP_MS

first_eng_done=0
printf "%-7s %-6s %-10s %-10s %-10s\n" "SubID" "Lang" "last_s1" "shift(ms)" "notes"
for id in "${ORDERED_SUB_IDS[@]}"; do
  lang="${LANG_OF[$id]:-eng}"
  mkvextract "$DISC1" tracks "$id":"$TMP/s1_${id}.sub" >/dev/null 2>&1 || true
  mkvextract "$DISC2" tracks "$id":"$TMP/s2_${id}.sub" >/dev/null 2>&1 || true
  [[ ! -s $TMP/s1_${id}.sub && ! -s $TMP/s2_${id}.sub ]] && continue
  LAST1_MS=$(last_pts_ms_or_disc1_end "$TMP/s1_${id}.sub")
  EXTRA_COMP_MS=$(( SEAM_MS - LAST1_MS )); (( EXTRA_COMP_MS < 0 )) && EXTRA_COMP_MS=0
  SHIFT_MS=$(( SUB_BASE_SHIFT_MS + EXTRA_COMP_MS ))
  out="$TMP/sub_${id}.mks"
  if [[ -s $TMP/s1_${id}.sub && -s $TMP/s2_${id}.sub ]]; then
    mkvmerge -q -o "$out" "$TMP/s1_${id}.sub" + --sync 0:$SHIFT_MS "$TMP/s2_${id}.sub"
  elif [[ -s $TMP/s1_${id}.sub ]]; then
    mkvmerge -q -o "$out" "$TMP/s1_${id}.sub"
  else
    mkvmerge -q -o "$out" --sync 0:$SHIFT_MS "$TMP/s2_${id}.sub"
  fi
  def="no"; if (( first_eng_done==0 )) && [[ "$lang" == "eng" ]]; then def="yes"; first_eng_done=1; fi
  SUB_OPTS+=( --language 0:$lang "$DEFAULT_OPT" 0:$def "$FORCED_OPT" 0:no "$out" )
  note=""; [[ "$lang" == "eng" ]] && note="(ENG)"
  printf "%-7s %-6s %-10d %-10d %-10s\n" "$id" "$lang" "$LAST1_MS" "$SHIFT_MS" "$note"
done

##############################################################################
#                               FINAL MUX
##############################################################################
echo "[6/6] Final mux…"
GLOBAL_OPTS=( --clusters-in-meta-seek --timestamp-scale 1000000 --cluster-length 1000ms )
mkvmerge --help | grep -q -- '--enable-durations' && GLOBAL_OPTS+=( --enable-durations )
(( HAS_CUE_DURATION == 1 )) && GLOBAL_OPTS+=( --cue-duration )

VIDEO_FILE_OPTS=()
(( HAS_DEFAULT_DURATION == 1 )) && VIDEO_FILE_OPTS+=( --default-duration 0:${FPS_RAT}p )
(( HAS_FIX_BT == 1 )) && VIDEO_FILE_OPTS+=( --fix-bitstream-timing-information 0:1 )

mkvmerge -q -o "$OUT" \
  --title "Lawrence of Arabia (1962) - Restored Roadshow Version" \
  "${GLOBAL_OPTS[@]}" \
  "${VIDEO_FILE_OPTS[@]}" "$TMP/video_cat_hdr10.mkv" \
  "${AUDIO_OPTS[@]}" \
  "${SUB_OPTS[@]}"

[[ $KEEP_TMP -eq 0 ]] && rm -rf "$TMP" || echo "(temp left in $TMP)"

secs=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")
awk -v s="$secs" 'BEGIN{printf "SUCCESS → %s\nruntime: %02d:%02d:%02d\n", "'"$OUT"'", s/3600, (s%3600)/60, s%60}'
echo "==========================================="
printf "Disc-1 duration (seam) : %d ms\n" "$DISC1_DUR_MS"
printf "Intermission gap       : %d ms\n" "$GAP_MS"
echo "Done."
