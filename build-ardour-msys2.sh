#!/usr/bin/env bash
# =============================================================================
#  build-ardour-msys2.sh
#  Builds Ardour from source on Windows using MSYS2 (UCRT64 environment).
#  (MSYS2 no longer ships glibmm, lilv, rubberband, aubio... for MINGW64, so
#   the old MINGW64 shell can't build Ardour any more - use UCRT64.)
#
#  Based on the community recipe "Building Ardour on Windows using MSYS2"
#  (discourse.ardour.org/t/building-ardour-on-windows-using-msys2).
#  This build method is NOT officially supported by the Ardour developers.
#  Please don't ask them for help with it.
#
#  ---------------------------------------------------------------------------
#  BEFORE RUNNING (one-time, manual):
#   1. Install MSYS2 from https://www.msys2.org to C:\msys64
#   2. Open "MSYS2 UCRT64" from the Start menu (not MINGW64, not MSYS)
#   3. Run:  pacman -Syu     (the window closes; reopen UCRT64)
#   4. Run:  pacman -Syu     again
#   5. ASIO: nothing to download - the script installs MSYS2's ASIO SDK package.
#      (To skip ASIO, WASAPI only: run with  PA_USE_ASIO=OFF bash build-ardour-msys2.sh)
#
#  TO RUN:
#   Copy this file into the MSYS2 home folder of the Windows user who will
#   build Ardour (C:\msys64\home\<username>\), then in the UCRT64 shell:
#       bash build-ardour-msys2.sh
#
#   Expect 1-2 hours total. Safe to re-run: finished steps are skipped.
#   All output is also saved to C:\share\log.txt (previous run: log.prev.txt).
#
#  RESULT:
#   Ardour installed in C:\Ardour, plus a launcher C:\Ardour\Start-Ardour.bat
#   you can double-click from File Explorer.
#
#  VIDEO: after installing, setup-ardour-video.sh (keep it next to this
#   script) finds your harvid, xjadeo and ffmpeg, copies them into
#   C:\Ardour\video and registers that folder the same way the official
#   Ardour installer does (one Windows admin prompt), so Ardour finds them.
#
#  SOURCE: the script downloads the 9.10 source itself with git. To use a
#   source tarball from ardour.org instead, run:
#       ARDOUR_TARBALL=/c/Users/<you>/Downloads/Ardour-9.10.0.tar.bz2 bash build-ardour-msys2.sh
#   (GitHub "Download ZIP" archives can't be built: they lack version info.)
# =============================================================================

set -euo pipefail

# --- Logging: everything below is shown on screen AND saved to the log ------
# Each run overwrites C:\share\log.txt (the previous run is kept as log.prev.txt).
LOG_DIR="/c/share"
LOG_FILE="$LOG_DIR/log.txt"
mkdir -p "$LOG_DIR"
[ -f "$LOG_FILE" ] && mv -f "$LOG_FILE" "$LOG_DIR/log.prev.txt"
exec > >(tee "$LOG_FILE") 2>&1
echo "Build started $(date) - logging to $(cygpath -w "$LOG_FILE")"
trap 'echo; echo "xx  FAILED at line $LINENO of the script. Full log: $(cygpath -w "$LOG_FILE")"' ERR

INSTALL_PREFIX="/c/Ardour"          # Windows: C:\Ardour
BUILD_DIR="$HOME/ardour-build"      # all sources and build files go here
JOBS="$(nproc)"

# Exact versions this script was tested with. Newer code may need new fixes,
# so change these only on purpose (and expect to troubleshoot).
ARDOUR_REF="${ARDOUR_REF:-9.10}"         # Ardour 9.10 release tag
ARDOUR_TARBALL="${ARDOUR_TARBALL:-}"     # optional: official source tarball instead of git
PORTAUDIO_REF="1ca0eeedb678c3cca80f3306c474d69a7a4b5278"   # PortAudio development version
FFTW_VERSION="3.3.10"
FFTW_MD5="8ccbf6a5ea78a16dbc3e1306e234cc5c"   # official checksum from fftw.org
PA_USE_ASIO="${PA_USE_ASIO:-ON}"         # OFF = build without ASIO (WASAPI only)

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

# Clone a repository if needed (retrying, as large downloads can drop),
# then switch it to the tested version
checkout_ref() {  # usage: checkout_ref <url> <folder> <commit-or-tag>
  if [ ! -d "$2" ]; then
    local try
    for try in 1 2 3; do
      git clone "$1" "$2" && break
      rm -rf "$2"
      [ "$try" = 3 ] && die "Could not download $2 after 3 tries. Check your internet connection and run the script again."
      warn "Download of $2 failed (try $try of 3) - retrying in 10 seconds"
      sleep 10
    done
  fi
  git -C "$2" checkout --quiet "$3" 2>/dev/null \
    || { git -C "$2" fetch --quiet --tags origin && git -C "$2" checkout --quiet "$3"; } \
    || die "Could not switch $2 to version $3."
  echo "$2 is at $(git -C "$2" describe --tags --always)"
}

# --- Sanity checks -----------------------------------------------------------
[ "${MSYSTEM:-}" = "UCRT64" ] || die "Run this from the 'MSYS2 UCRT64' shell (current: ${MSYSTEM:-unknown}). MSYS2 no longer has all of Ardour's libraries for MINGW64."
PREFIX="$MINGW_PREFIX"             # /ucrt64  (Windows: C:\msys64\ucrt64)
PKG="$MINGW_PACKAGE_PREFIX"        # mingw-w64-ucrt-x86_64
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# --- Step 2: dependencies ----------------------------------------------------
step "Installing build dependencies with pacman"
pacman -S --noconfirm --needed git unzip make \
  "$PKG"-{toolchain,boost,glib2,glibmm,libsndfile,curl,libarchive,liblo,taglib,vamp-plugin-sdk,rubberband,aubio,cairomm,pangomm,jack2,serd,sord,sratom,lilv,libwebsockets,cmake,ninja,libusb}

# --- Step 3: PortAudio (with ASIO unless PA_USE_ASIO=OFF) --------------------
# Rebuilt every run (about a minute): MSYS2's own non-ASIO portaudio package
# (pulled in by jack2) can overwrite our headers on a pacman update.
step "Building PortAudio (ASIO: $PA_USE_ASIO)"
checkout_ref https://github.com/PortAudio/portaudio.git portaudio "$PORTAUDIO_REF"
# PortAudio's CMake looks for the SDK in a folder named asiosdk* next to its
# source folder. Use a hand-downloaded asiosdk.zip if there is one, otherwise
# MSYS2's asiosdk package (no browser download needed any more).
rm -rf portaudio/asiosdk asiosdk asiosdk_extract
if [ "$PA_USE_ASIO" = "ON" ]; then
  if unzip -tq asiosdk.zip >/dev/null 2>&1; then
    echo "Using asiosdk.zip"
    mkdir asiosdk_extract && unzip -q asiosdk.zip -d asiosdk_extract
    ASIO_H="$(find asiosdk_extract -path '*/common/asio.h' | head -n1)"
    [ -n "$ASIO_H" ] || die "Could not find common/asio.h inside asiosdk.zip."
    mv "$(dirname "$(dirname "$ASIO_H")")" asiosdk
    rm -rf asiosdk_extract
  else
    pacman -S --noconfirm --needed "$PKG-asiosdk" \
      || die "Could not install the ASIO SDK package. Run with PA_USE_ASIO=OFF to build without ASIO."
    [ -f "$PREFIX/include/asiosdk/common/asio.h" ] || die "The ASIO SDK package is missing common/asio.h."
    echo "Using MSYS2's asiosdk package"
    cp -r "$PREFIX/include/asiosdk" asiosdk
  fi
fi
rm -rf portaudio/build && mkdir portaudio/build
rm -f "$PREFIX/include/pa_asio.h"   # so the ASIO check below only sees a fresh one
( cd portaudio/build \
  && cmake .. -G Ninja -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
       -DPA_USE_ASIO="$PA_USE_ASIO" -DPA_USE_JACK=OFF -DBUILD_SHARED_LIBS=OFF -DPA_BUILD_SHARED_LIBS=OFF \
  && ninja install )
if [ "$PA_USE_ASIO" = "ON" ]; then
  [ -f "$PREFIX/include/pa_asio.h" ] || die "PortAudio was built without ASIO (pa_asio.h not installed) - see the CMake output above."
fi

# --- Step 4: FFTW (single precision) -----------------------------------------
if [ -f "$PREFIX/lib/libfftw3f.dll.a" ] && [ -f "$BUILD_DIR/.fftw-done" ]; then
  step "FFTW already built - skipping"
else
  step "Building FFTW $FFTW_VERSION (single precision)"
  [ -f "fftw-$FFTW_VERSION.tar.gz" ] || curl -fLO "https://fftw.org/fftw-$FFTW_VERSION.tar.gz"
  echo "$FFTW_MD5  fftw-$FFTW_VERSION.tar.gz" | md5sum -c --quiet \
    || die "fftw-$FFTW_VERSION.tar.gz doesn't match the official checksum. Delete it and run again."
  rm -rf "fftw-$FFTW_VERSION" && tar xf "fftw-$FFTW_VERSION.tar.gz"
  ( cd "fftw-$FFTW_VERSION" \
    && ./configure --build=x86_64-pc-msys --host=x86_64-w64-mingw32 --prefix="$PREFIX" \
         --enable-shared --disable-static --enable-float --enable-threads \
         --with-combined-threads --with-our-malloc --enable-sse --enable-sse2 \
         --enable-avx --enable-avx2 --disable-dependency-tracking \
    && make -j"$JOBS" && make install )
  touch "$BUILD_DIR/.fftw-done"
fi

# --- Step 5: Ardour source ---------------------------------------------------
step "Getting the Ardour source"
if [ -n "$ARDOUR_TARBALL" ]; then
  TARBALL="$(cygpath -u "$ARDOUR_TARBALL")"
  [ -f "$TARBALL" ] || die "ARDOUR_TARBALL file not found: $ARDOUR_TARBALL"
  SRC_DIR="$BUILD_DIR/src-$(basename "$TARBALL" | sed -E 's/\.tar\.(bz2|gz|xz)$//')"
  if [ ! -f "$SRC_DIR/wscript" ]; then
    rm -rf "$SRC_DIR" && mkdir -p "$SRC_DIR"
    tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1
  fi
  [ -f "$SRC_DIR/libs/ardour/revision.cc" ] \
    || die "This tarball has no version info (libs/ardour/revision.cc), e.g. a GitHub ZIP. Run without ARDOUR_TARBALL to let the script get 9.10 with git."
  BUILD_ID="$(basename "$TARBALL")"
  cd "$SRC_DIR"
else
  # The forum recipe's sed patches are part of Ardour's own code now; undo
  # them if a very old run of this script applied them (before switching version)
  if [ -f ardour/.msys2-patched ]; then
    step "Reverting outdated patches from an earlier run"
    git -C ardour checkout -- libs/pbd/pbd.cc libs/ardour/wscript libs/backends/portaudio/wscript gtk2_ardour/main.cc
    rm -f ardour/.msys2-patched
  fi
  checkout_ref https://github.com/Ardour/ardour.git ardour "$ARDOUR_REF"
  BUILD_ID="$(git -C ardour rev-parse HEAD)"
  cd ardour
fi

# --- Step 6: start clean when the Ardour version changed ---------------------
# Reusing build files from another version (e.g. the old 9.8 build) can give
# subtle breakage, so do a full rebuild whenever the source changes.
BUILT_ID_FILE="$BUILD_DIR/.ardour-built-id"
if [ -d build ] && [ "$(cat "$BUILT_ID_FILE" 2>/dev/null)" != "$BUILD_ID" ]; then
  step "Ardour version changed - removing old build files (full rebuild)"
  rm -rf build
fi
# Record the version now (not after the build) so an interrupted or failed
# build resumes where it stopped on the next run instead of starting over.
echo "$BUILD_ID" > "$BUILT_ID_FILE"

# --- Step 7: configure -------------------------------------------------------
step "Configuring Ardour"
WAF_CONFIG_FLAGS=(--dist-target=mingw --prefix="$INSTALL_PREFIX" --configdir=share
                  --no-execstack --no-dr-mingw --optimize --cxx17 --ptformat)
if command -v cl.exe >/dev/null 2>&1; then
  warn "Visual Studio compiler detected - forcing gcc/g++"
  python3 waf configure --check-c-compiler=gcc --check-cxx-compiler=g++ "${WAF_CONFIG_FLAGS[@]}"
else
  ./waf configure "${WAF_CONFIG_FLAGS[@]}"
fi

# --- Step 8: build and install -----------------------------------------------
step "Building Ardour with $JOBS jobs (this takes a while)"
./waf -j"$JOBS"

# Move the old install aside: leftover ardour-9.8.*.exe files would otherwise
# sit next to the new ardour-9.10.*.exe and confuse the launcher.
if [ -d "$INSTALL_PREFIX" ]; then
  step "Moving the previous install to $(cygpath -w "$INSTALL_PREFIX").prev"
  rm -rf "$INSTALL_PREFIX.prev"
  mv "$INSTALL_PREFIX" "$INSTALL_PREFIX.prev" \
    || die "Could not move $(cygpath -w "$INSTALL_PREFIX"). Close Ardour, harvid, xjadeo and any Explorer window showing that folder, then run again."
fi

step "Installing to $INSTALL_PREFIX"
./waf install

# --- Step 9: launcher --------------------------------------------------------
step "Creating launcher"
ARDOUR_EXE="$(find "$INSTALL_PREFIX/lib" -type f -iname 'ardour-[0-9]*.exe' | sort -V | tail -n1)"
if [ -z "$ARDOUR_EXE" ]; then
  warn "Could not find the Ardour .exe under $INSTALL_PREFIX/lib - look for it manually."
else
  WIN_EXE="$(cygpath -w "$ARDOUR_EXE")"
  WIN_MINGW_BIN="$(cygpath -w "$PREFIX/bin")"
  LAUNCHER="$INSTALL_PREFIX/Start-Ardour.bat"
  WIN_XJADEO="$(cygpath -w "$INSTALL_PREFIX/video/xjadeo/xjadeo.exe")"
  printf '@echo off\r\nset "PATH=%s;%%PATH%%"\r\nif exist "%s" set "XJREMOTE=%s"\r\nstart "" "%s"\r\n' \
    "$WIN_MINGW_BIN" "$WIN_XJADEO" "$WIN_XJADEO" "$WIN_EXE" > "$LAUNCHER"
  step "Done. Start Ardour with: $(cygpath -w "$LAUNCHER")"
  echo "    or from this shell:  cmd //c \"$WIN_EXE\""
fi

# --- Step 10: copy DLLs next to the exe (if the helper script is present) ----
# Helper scripts: next to this script, or else in C:\share
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
helper() { if [ -f "$SCRIPT_DIR/$1" ]; then echo "$SCRIPT_DIR/$1"; else echo "/c/share/$1"; fi; }
BUNDLE_SCRIPT="$(helper bundle-ardour-dlls.sh)"
if [ -f "$BUNDLE_SCRIPT" ]; then
  step "Copying required DLLs next to the Ardour exe"
  bash "$BUNDLE_SCRIPT" || warn "DLL bundling failed - see C:\\share\\bundle-log.txt"
else
  warn "bundle-ardour-dlls.sh not found next to this script or in C:\\share - use Start-Ardour.bat to launch."
fi

# --- Step 11: video tools (harvid, xjadeo, ffmpeg) ----------------------------
VIDEO_SCRIPT="$(helper setup-ardour-video.sh)"
if [ -f "$VIDEO_SCRIPT" ]; then
  step "Setting up the video tools"
  bash "$VIDEO_SCRIPT" || warn "Video setup had a problem - see C:\\share\\video-log.txt"
else
  warn "setup-ardour-video.sh not found next to this script or in C:\\share - the video timeline won't be set up."
fi
