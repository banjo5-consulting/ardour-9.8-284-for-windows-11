#!/usr/bin/env bash
# =============================================================================
#  bundle-ardour-dlls.sh
#  Copies the MSYS2 DLLs that Ardour needs into the folder holding the Ardour
#  .exe, so it starts directly from File Explorer (no .bat launcher needed).
#
#  Run in the "MSYS2 MINGW64" shell after a successful build:
#      bash bundle-ardour-dlls.sh
#  Re-run it after every rebuild. Output is also saved to C:\share\bundle-log.txt
# =============================================================================
set -euo pipefail

INSTALL_PREFIX="/c/Ardour"
LOG_FILE="/c/share/bundle-log.txt"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee "$LOG_FILE") 2>&1

[ "${MSYSTEM:-}" = "MINGW64" ] || { echo "Run this from the 'MSYS2 MINGW64' shell."; exit 1; }

ARDOUR_EXE="$(find "$INSTALL_PREFIX/lib" -type f -iname 'ardour-[0-9]*.exe' | sort | tail -n1)"
[ -n "$ARDOUR_EXE" ] || { echo "No Ardour .exe found under $INSTALL_PREFIX/lib"; exit 1; }
EXE_DIR="$(dirname "$ARDOUR_EXE")"
echo "Ardour: $(cygpath -w "$ARDOUR_EXE")"

# Every exe and dll Ardour installed (main program, backends, plugins, tools)
mapfile -t BINARIES < <(find "$INSTALL_PREFIX" -type f \( -iname '*.exe' -o -iname '*.dll' \))
echo "Scanning ${#BINARIES[@]} Ardour binaries for MSYS2 dependencies..."

# ldd lists dependencies recursively; keep the ones that come from /mingw64/bin
mapfile -t DEPS < <(
  for b in "${BINARIES[@]}"; do ldd "$b" 2>/dev/null || true; done \
    | awk '$3 ~ /^\/mingw64\/bin\// {print $3}' | sort -u
)

# Always overwrite, so copies stay in sync after an MSYS2 update (pacman -Syu)
for dll in "${DEPS[@]}"; do
  cp -f "$dll" "$EXE_DIR/"
done
echo "Copied ${#DEPS[@]} DLLs into $(cygpath -w "$EXE_DIR")"

# Report anything ldd could not resolve. Ardour's own DLLs (ardour.dll, pbd.dll,
# ytk.dll...) show as "not found" when ldd checks plugins in subfolders such as
# backends\ or surfaces\, but Windows finds them at runtime because they sit
# next to the exe, which loads them first. So only report names that exist
# nowhere in the Ardour install.
MISSING=""
while read -r name; do
  [ -z "$name" ] && continue
  if [ -z "$(find "$INSTALL_PREFIX" -type f -iname "$name" -print -quit)" ]; then
    MISSING+="  $name"$'\n'
  fi
done < <(for b in "${BINARIES[@]}"; do ldd "$b" 2>/dev/null || true; done \
           | awk '/not found/ {print $1}' | sort -u)
if [ -n "$MISSING" ]; then
  echo "WARNING - these DLLs were not found anywhere:"
  printf '%s' "$MISSING"
else
  echo "All dependencies resolved. You can now double-click:"
  echo "  $(cygpath -w "$ARDOUR_EXE")"
fi
