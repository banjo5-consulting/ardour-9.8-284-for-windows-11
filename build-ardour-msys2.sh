#!/usr/bin/env bash
# =============================================================================
#  build-ardour-msys2.sh
#  Builds Ardour from source on Windows using MSYS2 (MINGW64 environment).
#
#  Based on the community recipe "Building Ardour on Windows using MSYS2"
#  (discourse.ardour.org/t/building-ardour-on-windows-using-msys2).
#  This build method is NOT officially supported by the Ardour developers.
#  Please don't ask them for help with it.
#
#  ---------------------------------------------------------------------------
#  BEFORE RUNNING (one-time, manual):
#   1. Install MSYS2 from https://www.msys2.org to C:\msys64
#   2. Open "MSYS2 MINGW64" from the Start menu (not UCRT64, not MSYS)
#   3. Run:  pacman -Syu     (the window closes; reopen MINGW64)
#   4. Run:  pacman -Syu     again
#   5. Download the ASIO SDK in a browser from Steinberg's developer site
#      (Developers > ASIO SDK) and save it as
#      C:\msys64\home\<username>\ardour-build\asiosdk.zip
#      Or skip ASIO (WASAPI only): run with  PA_USE_ASIO=OFF bash build-ardour-msys2.sh
#
#  TO RUN:
#   Copy this file into the MSYS2 home folder of the Windows user who will
#   build Ardour (C:\msys64\home\<username>\), then in the MINGW64 shell:
#       bash build-ardour-msys2.sh
#
#   Expect 1-2 hours total. Safe to re-run: finished steps are skipped.
#   All output is also saved to C:\share\log.txt (previous run: log.prev.txt).
#
#  RESULT:
#   Ardour installed in C:\Ardour, plus a launcher C:\Ardour\Start-Ardour.bat
#   you can double-click from File Explorer.
#
#  NOT INCLUDED: the video timeline tools (Harvid + Xjadeo) needed to score
#   against picture. Download their Windows builds from https://x42.github.io
#   and set their folder in Ardour: Edit > Preferences > Video.
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
ARDOUR_REF="704731d2a5468f6f4ca77f9130eb893dc38ec7e9"      # Ardour 9.8-284 (development build after the 9.8 release)
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
[ "${MSYSTEM:-}" = "MINGW64" ] || die "Run this from the 'MSYS2 MINGW64' shell (current: ${MSYSTEM:-unknown})."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# --- Step 2: dependencies ----------------------------------------------------
step "Installing build dependencies with pacman"
pacman -S --noconfirm --needed git unzip make \
  mingw-w64-x86_64-{toolchain,boost,glib2,glibmm,libsndfile,curl,libarchive,liblo,taglib,vamp-plugin-sdk,rubberband,aubio,cairomm,pangomm,jack2,serd,sord,sratom,lilv,libwebsockets,cmake,ninja,libusb}

# --- Step 3: PortAudio (with ASIO unless PA_USE_ASIO=OFF) --------------------
if [ -f /mingw64/lib/libportaudio.a ] && [ -f "$BUILD_DIR/.portaudio-done" ]; then
  step "PortAudio already built - skipping"
else
  step "Building PortAudio (ASIO: $PA_USE_ASIO)"
  checkout_ref https://github.com/PortAudio/portaudio.git portaudio "$PORTAUDIO_REF"
  if [ "$PA_USE_ASIO" = "ON" ] && [ ! -d portaudio/asiosdk ]; then
    # Steinberg's download needs a browser, so use the zip saved by hand
    unzip -tq asiosdk.zip >/dev/null 2>&1 || die "asiosdk.zip is missing or not a valid zip. Download the ASIO SDK in a browser from steinberg.net (Developers > ASIO SDK) and save it as $(cygpath -w "$BUILD_DIR")\\asiosdk.zip - or run with PA_USE_ASIO=OFF to build without ASIO."
    rm -rf asiosdk_extract && mkdir asiosdk_extract
    unzip -q asiosdk.zip -d asiosdk_extract
    ASIO_DIR="$(find asiosdk_extract -mindepth 1 -maxdepth 1 -type d | head -n1)"
    [ -n "$ASIO_DIR" ] || die "Could not find the ASIO SDK folder inside asiosdk.zip."
    mv "$ASIO_DIR" portaudio/asiosdk
    rm -rf asiosdk_extract
  fi
  rm -rf portaudio/build && mkdir portaudio/build
  ( cd portaudio/build \
    && cmake .. -G Ninja -DCMAKE_INSTALL_PREFIX=/mingw64 -DPA_USE_ASIO="$PA_USE_ASIO" \
         -DPA_USE_JACK=OFF -DBUILD_SHARED_LIBS=OFF -DPA_BUILD_SHARED_LIBS=OFF \
    && ninja install )
  touch "$BUILD_DIR/.portaudio-done"
fi

# --- Step 4: FFTW (single precision) -----------------------------------------
if [ -f /mingw64/lib/libfftw3f.dll.a ] && [ -f "$BUILD_DIR/.fftw-done" ]; then
  step "FFTW already built - skipping"
else
  step "Building FFTW $FFTW_VERSION (single precision)"
  [ -f "fftw-$FFTW_VERSION.tar.gz" ] || curl -fLO "https://fftw.org/fftw-$FFTW_VERSION.tar.gz"
  echo "$FFTW_MD5  fftw-$FFTW_VERSION.tar.gz" | md5sum -c --quiet \
    || die "fftw-$FFTW_VERSION.tar.gz doesn't match the official checksum. Delete it and run again."
  rm -rf "fftw-$FFTW_VERSION" && tar xf "fftw-$FFTW_VERSION.tar.gz"
  ( cd "fftw-$FFTW_VERSION" \
    && ./configure --build=x86_64-pc-msys --host=x86_64-w64-mingw32 --prefix=/mingw64 \
         --enable-shared --disable-static --enable-float --enable-threads \
         --with-combined-threads --with-our-malloc --enable-sse --enable-sse2 \
         --enable-avx --enable-avx2 --disable-dependency-tracking \
    && make -j"$JOBS" && make install )
  touch "$BUILD_DIR/.fftw-done"
fi

# --- Step 5: Ardour source ---------------------------------------------------
step "Getting the Ardour source"
checkout_ref https://github.com/Ardour/ardour.git ardour "$ARDOUR_REF"
cd ardour

# --- Step 6: no patches needed -----------------------------------------------
# The forum recipe's sed patches are now part of Ardour's own code (MSYS2
# linking in libs/backends/portaudio/wscript, LILV/SERD/SORD/SRATOM in
# libs/ardour/wscript, and the old GLib thread_init code is gone).
# Applying them again breaks the build, so undo them if an earlier run did.
if [ -f .msys2-patched ]; then
  step "Reverting outdated patches from an earlier run"
  git checkout -- libs/pbd/pbd.cc libs/ardour/wscript libs/backends/portaudio/wscript gtk2_ardour/main.cc
  rm -f .msys2-patched
fi

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

step "Installing to $INSTALL_PREFIX"
./waf install

# --- Step 9: launcher --------------------------------------------------------
step "Creating launcher"
ARDOUR_EXE="$(find "$INSTALL_PREFIX/lib" -type f -iname 'ardour-[0-9]*.exe' | sort | tail -n1)"
if [ -z "$ARDOUR_EXE" ]; then
  warn "Could not find the Ardour .exe under $INSTALL_PREFIX/lib - look for it manually."
else
  WIN_EXE="$(cygpath -w "$ARDOUR_EXE")"
  WIN_MINGW_BIN="$(cygpath -w /mingw64/bin)"
  LAUNCHER="$INSTALL_PREFIX/Start-Ardour.bat"
  printf '@echo off\r\nset "PATH=%s;%%PATH%%"\r\nstart "" "%s"\r\n' "$WIN_MINGW_BIN" "$WIN_EXE" > "$LAUNCHER"
  step "Done. Start Ardour with: $(cygpath -w "$LAUNCHER")"
  echo "    or from this shell:  cmd //c \"$WIN_EXE\""
fi

# --- Step 10: copy DLLs next to the exe (if the helper script is present) ----
BUNDLE_SCRIPT="$(dirname "$(readlink -f "$0")")/bundle-ardour-dlls.sh"
if [ -f "$BUNDLE_SCRIPT" ]; then
  step "Copying required DLLs next to the Ardour exe"
  bash "$BUNDLE_SCRIPT" || warn "DLL bundling failed - see C:\\share\\bundle-log.txt"
else
  warn "bundle-ardour-dlls.sh not found next to this script - use Start-Ardour.bat to launch."
fi

echo
warn "Remember: add Harvid + Xjadeo (https://x42.github.io) for the video timeline,"
warn "then set their folder in Ardour under Edit > Preferences > Video."
