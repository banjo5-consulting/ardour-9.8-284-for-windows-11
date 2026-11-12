#!/usr/bin/env bash
# =============================================================================
#  setup-ardour-video.sh
#  Makes the video timeline work in a self-built Ardour on Windows.
#
#  Ardour looks for its video tools in a fixed way (libs/ardour/video_tools_paths.cc):
#  first the folder in the registry value
#      HKLM\Software\Ardour\v<major>\video  ->  Install_Dir
#  expecting  <Install_Dir>\harvid\harvid.exe, harvid\ffmpeg.exe, harvid\ffprobe.exe
#  and        <Install_Dir>\xjadeo\xjadeo.exe
#  (the official installer sets this up). A copy of harvid/ffmpeg somewhere on
#  PATH is NOT found on Windows, and ffmpeg is never found in its own folder,
#  so import transcoding and video export quietly break.
#
#  This script finds the harvid, xjadeo and ffmpeg already on this computer,
#  copies them into C:\Ardour\video in that layout, checks they run, and
#  registers the folder (one Windows admin prompt).
#
#  Runs automatically at the end of build-ardour-msys2.sh, or on its own in
#  the "MSYS2 UCRT64" shell:   bash setup-ardour-video.sh
#  If a tool isn't found, point to its folder, e.g.:
#     HARVID_DIR="C:\Tools\harvid" XJADEO_DIR="C:\Tools\xjadeo" FFMPEG_DIR="C:\ffmpeg\bin" bash setup-ardour-video.sh
#  Output is also saved to C:\share\video-log.txt
# =============================================================================
set -euo pipefail

INSTALL_PREFIX="/c/Ardour"
VIDEO_DIR="$INSTALL_PREFIX/video"
LOG_FILE="/c/share/video-log.txt"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee "$LOG_FILE") 2>&1

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32mok  %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

[ "${MSYSTEM:-}" = "UCRT64" ] || die "Run this from the 'MSYS2 UCRT64' shell."

ARDOUR_EXE="$(find "$INSTALL_PREFIX/lib" -type f -iname 'ardour-[0-9]*.exe' 2>/dev/null | sort -V | tail -n1)"
[ -n "$ARDOUR_EXE" ] || die "No Ardour .exe under $(cygpath -w "$INSTALL_PREFIX")\\lib - build Ardour first."
MAJOR="$(basename "$ARDOUR_EXE" | sed -E 's/^ardour-([0-9]+)\..*/\1/I')"
REG_KEY="HKLM\\Software\\Ardour\\v$MAJOR\\video"
echo "Ardour: $(cygpath -w "$ARDOUR_EXE")  (registry key: $REG_KEY)"

# Windows tools get their /switches mangled by MSYS2 path conversion unless told not to
winrun() { MSYS2_ARG_CONV_EXCL='*' "$@"; }

# Install_Dir from a registry key (64- and 32-bit views), as a unix path
reg_install_dir() {
  local view out
  for view in 64 32; do
    out="$(winrun reg query "HKLM\\$1" /v Install_Dir /reg:$view 2>/dev/null | tr -d '\r' \
           | sed -n 's/^.*Install_Dir[[:space:]]*REG_[A-Z_]*SZ[[:space:]]*//p' | head -n1)"
    [ -n "$out" ] && { cygpath -u "$out"; return 0; }
  done
  return 0
}

# Look a program up on the real Windows PATH (MSYS2 hides it), following
# winget-style links to the real file
win_path_lookup() {
  local p
  p="$(winrun powershell.exe -NoProfile -NonInteractive -Command "
    \$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User');
    \$c = Get-Command '$1' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1;
    if (\$c) { \$i = Get-Item -LiteralPath \$c.Source; if (\$i.LinkType -and \$i.Target) { @(\$i.Target)[0] } else { \$i.FullName } }
  " 2>/dev/null | tr -d '\r' | head -n1)"
  [ -n "$p" ] && cygpath -u "$p"
  return 0
}

# Find <exe>: override folder, then registry key, then Windows PATH, then common folders
find_tool() {  # usage: find_tool <exe> <registry-key-or-empty> <override-dir-or-empty>
  local exe="$1" key="$2" override="$3" d p root
  if [ -n "$override" ]; then
    p="$(cygpath -u "$override")/$exe"
    [ -f "$p" ] && { echo "$p"; return 0; }
    warn "$exe not found in $override" >&2
  fi
  if [ -n "$key" ]; then
    d="$(reg_install_dir "$key")"
    [ -n "$d" ] && [ -f "$d/$exe" ] && { echo "$d/$exe"; return 0; }
  fi
  p="$(win_path_lookup "$exe")"
  [ -n "$p" ] && [ -f "$p" ] && { echo "$p"; return 0; }
  for root in "/c/Program Files" "/c/Program Files (x86)" "$(cygpath -u "${USERPROFILE:-C:\\Users}")" "/c"; do
    [ -d "$root" ] || continue
    p="$(find "$root" -maxdepth 4 \
           \( -ipath '/c/Windows' -o -ipath '/c/msys64' -o -ipath '/c/Ardour*' -o -iname 'AppData' -o -iname '$Recycle.Bin' \) -prune \
           -o -type f -iname "$exe" -print 2>/dev/null | head -n1)"
    [ -n "$p" ] && { echo "$p"; return 0; }
  done
  return 0
}

# Copy a tool's folder (or just its exe + DLLs if the folder is big/shared)
copy_tool() {  # usage: copy_tool <exe-path> <dest-subfolder>
  local src_dir dest size_mb
  src_dir="$(dirname "$1")"; dest="$VIDEO_DIR/$2"
  mkdir -p "$dest"
  size_mb="$(du -sm "$src_dir" 2>/dev/null | cut -f1)"
  if [ "${size_mb:-9999}" -lt 400 ]; then
    cp -rf "$src_dir/." "$dest/"
  else
    cp -f "$1" "$dest/"
    cp -f "$src_dir"/*.dll "$dest/" 2>/dev/null || true
  fi
}

# Run a tool the way Ardour will (from its own folder, without MSYS2 on PATH)
run_clean() {
  # /usr/bin/timeout by full path: with this PATH, plain "timeout" would be
  # Windows' own TIMEOUT.EXE, which does something else entirely
  ( cd "$(dirname "$1")" && PATH="/c/Windows/System32:/c/Windows" /usr/bin/timeout 20 "$@" 2>&1 ) || true
}

# Start fresh each run so stale copies never linger
rm -rf "$VIDEO_DIR"
mkdir -p "$VIDEO_DIR"

# --- harvid (video decoder / frame server for the timeline) -------------------
step "Looking for harvid"
HARVID_SRC="$(find_tool harvid.exe 'Software\RSS\harvid' "${HARVID_DIR:-}")"
[ -n "$HARVID_SRC" ] || die "harvid.exe not found. Run again with HARVID_DIR=\"<folder containing harvid.exe>\"."
echo "found: $(cygpath -w "$HARVID_SRC")"
copy_tool "$HARVID_SRC" harvid
HARVID="$VIDEO_DIR/harvid/harvid.exe"
HV_OUT="$(run_clean "$HARVID" --version)"
HV="$(printf '%s' "$HV_OUT" | sed -n 's/.*harvid v\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' | head -n1)"
if [ -z "$HV" ]; then
  warn "harvid didn't report a version - it may be missing DLLs. Output was:"; printf '%s\n' "$HV_OUT"
  die "harvid.exe doesn't run from $(cygpath -w "$VIDEO_DIR")\\harvid."
fi
# Ardour needs >= 0.8.2 for Windows drive-letter paths
if [ "$(printf '%s\n0.8.2\n' "$HV" | sort -V | head -n1)" != "0.8.2" ]; then
  die "harvid $HV is too old (need 0.8.2 or newer). Get a current one from https://x42.github.io/harvid/"
fi
ok "harvid $HV"

# --- ffmpeg / ffprobe (import transcoding, video export, file info) -----------
# Prefer the ffmpeg that ships inside the harvid folder (matched build, what the
# official Ardour package uses); otherwise use the ffmpeg installed on this PC.
step "Setting up ffmpeg / ffprobe"
HDIR="$VIDEO_DIR/harvid"
if [ -n "${FFMPEG_DIR:-}" ] || [ ! -f "$HDIR/ffmpeg.exe" ] || [ ! -f "$HDIR/ffprobe.exe" ]; then
  FF_SRC="$(find_tool ffmpeg.exe '' "${FFMPEG_DIR:-}")"
  [ -n "$FF_SRC" ] || die "ffmpeg.exe not found. Run again with FFMPEG_DIR=\"<folder containing ffmpeg.exe>\"."
  FP_SRC="$(dirname "$FF_SRC")/ffprobe.exe"
  [ -f "$FP_SRC" ] || FP_SRC="$(find_tool ffprobe.exe '' '')"
  [ -n "$FP_SRC" ] && [ -f "$FP_SRC" ] || die "ffprobe.exe not found next to $(cygpath -w "$FF_SRC")."
  echo "using: $(cygpath -w "$FF_SRC")"
  cp -f "$FF_SRC" "$FP_SRC" "$HDIR/"
  # "shared" ffmpeg builds need their DLLs; never overwrite harvid's own
  for dll in "$(dirname "$FF_SRC")"/*.dll; do
    [ -f "$dll" ] || continue
    if [ -f "$HDIR/$(basename "$dll")" ]; then
      cmp -s "$dll" "$HDIR/$(basename "$dll")" || warn "kept harvid's own $(basename "$dll") (ffmpeg has a different one)"
    else
      cp "$dll" "$HDIR/"
    fi
  done
else
  echo "using the ffmpeg bundled with harvid"
fi
FF_OUT="$(run_clean "$HDIR/ffmpeg.exe" -hide_banner -version)"
grep -q '^ffmpeg version' <<<"$FF_OUT" || { printf '%s\n' "$FF_OUT"; die "ffmpeg.exe doesn't run from the harvid folder (missing DLLs?)."; }
FP_OUT="$(run_clean "$HDIR/ffprobe.exe" -hide_banner -version)"
grep -q '^ffprobe version' <<<"$FP_OUT" || die "ffprobe.exe doesn't run from the harvid folder."
ok "$(head -n1 <<<"$FF_OUT" | cut -c1-60)"
# Ardour's "transcode on import" makes an intra-frame MJPEG copy for frame-accurate seeking
ENC_OUT="$(run_clean "$HDIR/ffmpeg.exe" -hide_banner -encoders)"
if grep -qE '^ *V[^ ]* +mjpeg ' <<<"$ENC_OUT"; then
  ok "ffmpeg has the mjpeg encoder used for import transcoding"
else
  warn "this ffmpeg has no mjpeg encoder - 'transcode on import' will fail. Use a full build (e.g. gyan.dev 'full')."
fi

# --- xjadeo (video monitor window) ---------------------------------------------
step "Looking for xjadeo"
XJ_SRC="$(find_tool xjadeo.exe 'Software\RSS\xjadeo' "${XJADEO_DIR:-}")"
[ -n "$XJ_SRC" ] || die "xjadeo.exe not found. Run again with XJADEO_DIR=\"<folder containing xjadeo.exe>\"."
echo "found: $(cygpath -w "$XJ_SRC")"
copy_tool "$XJ_SRC" xjadeo
XJADEO="$VIDEO_DIR/xjadeo/xjadeo.exe"
XJ_OUT="$(run_clean "$XJADEO" --version)"
XV="$(printf '%s' "$XJ_OUT" | sed -n 's/.* version \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' | head -n1)"
if [ -z "$XV" ]; then
  warn "xjadeo didn't report a version (Ardour needs this to accept it). Output was:"; printf '%s\n' "$XJ_OUT"
elif [ "$(printf '%s\n0.7.7\n' "$XV" | sort -V | head -n1)" != "0.7.7" ]; then
  die "xjadeo $XV is too old (need 0.7.7 or newer). Get a current one from https://x42.github.io/xjadeo/"
else
  ok "xjadeo $XV"
fi

# --- Register the folder, like the official installer ------------------------
step "Registering $(cygpath -w "$VIDEO_DIR") for Ardour $MAJOR"
WIN_VIDEO_DIR="$(cygpath -w "$VIDEO_DIR")"
REG_FILE="$VIDEO_DIR/register-video-tools.reg"
printf 'Windows Registry Editor Version 5.00\r\n\r\n[HKEY_LOCAL_MACHINE\\SOFTWARE\\Ardour\\v%s\\video]\r\n"Install_Dir"="%s"\r\n' \
  "$MAJOR" "${WIN_VIDEO_DIR//\\/\\\\}" > "$REG_FILE"

reg_ok() { [ "$(reg_install_dir "Software\\Ardour\\v$MAJOR\\video")" = "$VIDEO_DIR" ]; }
if ! reg_ok; then
  winrun reg add "$REG_KEY" /v Install_Dir /t REG_SZ /d "$WIN_VIDEO_DIR" /f /reg:64 >/dev/null 2>&1 || true
fi
if ! reg_ok; then
  echo "Asking Windows for administrator permission (accept the prompt)..."
  winrun powershell.exe -NoProfile -NonInteractive -Command \
    "Start-Process reg.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList 'import','\"$(cygpath -w "$REG_FILE")\"','/reg:64'" \
    >/dev/null 2>&1 || true
fi
if reg_ok; then
  ok "Ardour will find the video tools in $WIN_VIDEO_DIR"
else
  warn "Couldn't write the registry entry. Double-click this file and accept the prompts:"
  warn "  $(cygpath -w "$REG_FILE")"
fi

echo
echo "Video tools ready:"
echo "  harvid : $(cygpath -w "$HARVID")"
echo "  ffmpeg : $(cygpath -w "$HDIR/ffmpeg.exe")"
echo "  xjadeo : $(cygpath -w "$XJADEO")"
