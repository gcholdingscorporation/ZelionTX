#!/usr/bin/env bash
# Vendors the EdgeTX platform layer into platform/ from a pinned EdgeTX commit.
#
# This is the only way EdgeTX code enters this repository. The list of paths
# below is the record of what was taken (decision D-19). Re-run at a newer
# commit and review the diff to pick up upstream driver fixes.
#
# Usage: tools/vendor-edgetx.sh /path/to/edgetx-checkout
# The checkout must be at EDGETX_COMMIT with submodules lvgl, FreeRTOS, uf2
# and stb initialised.
set -euo pipefail

EDGETX_COMMIT="96ab2745d1bc0025c5508ac8a3b862f34cf97c6e"
SRC="${1:?path to EdgeTX checkout}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/platform"

have="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$have" != "$EDGETX_COMMIT" ]]; then
  echo "EdgeTX checkout is at $have, expected $EDGETX_COMMIT" >&2
  exit 1
fi
for sm in lvgl FreeRTOS uf2 stb; do
  [[ -e "$SRC/radio/src/thirdparty/$sm/.git" || -n "$(ls -A "$SRC/radio/src/thirdparty/$sm" 2>/dev/null)" ]] \
    || { echo "submodule $sm not initialised" >&2; exit 1; }
done

R="$SRC/radio/src"

# Paths relative to radio/src, copied whole. Trimming inside these directories
# happens in ZelionTX's own CMake by not listing files, never by deleting them
# here, so a re-vendor stays a clean diff.
PATHS=(
  # Hardware abstraction and OS wrapper
  hal
  os
  # STM32 drivers (H7 family only is selected by CMake)
  targets/common/arm/stm32
  targets/common/arm/CMakeLists.txt
  # Boards and radios
  boards/generic_stm32
  boards/rm-h750
  boards/hw_defs/tx15.json
  boards/hw_defs/tx16smk3.json
  boards/hw_defs/gx15.json
  targets/tx15
  targets/tx16smk3
  targets/gx15
  # Desktop simulator stubs
  targets/simu
  # Peripheral drivers used by the H750 boards
  drivers
  # Bootloader (UF2 install and rollback path)
  bootloader
  # Colour LCD plumbing kept for LVGL: flush, DMA2D, wrapper, boot menu, libui
  gui/colorlcd/lcd.cpp
  gui/colorlcd/lcd.h
  gui/colorlcd/LvglWrapper.cpp
  gui/colorlcd/LvglWrapper.h
  gui/colorlcd/lv_conf.h
  gui/colorlcd/boot_menu.cpp
  gui/colorlcd/libui
  gui/colorlcd/CMakeListsLVGL.txt
  # Fonts and bootloader bitmaps (trimmed later to the faces in use)
  fonts
  bitmaps
  # Core scheduling and CRSF pieces reused as-is
  tasks.cpp
  tasks.h
  mixer_scheduler.cpp
  mixer_scheduler.h
  pulses/crossfire.cpp
  pulses/crossfire.h
  telemetry/crossfire.cpp
  telemetry/crossfire.h
  crc.cpp
  crc.h
  FreeRTOSConfig.h
  # Third-party
  thirdparty/CMSIS
  thirdparty/STM32H7xx_HAL_Driver
  thirdparty/STM32_USB_Device_Library
  thirdparty/FatFs
  thirdparty/FreeRTOS
  thirdparty/lvgl
  thirdparty/uf2
  thirdparty/stb
  thirdparty/lz4
  thirdparty/libopenui
)

# Build-system pieces from outside radio/src
TOP_PATHS=(
  cmake/toolchain/arm-none-eabi.cmake
  cmake/toolchain/native.cmake
  cmake/Macros.cmake
  cmake/Bitmaps.cmake
  radio/util/hw_defs
  tools/hwdef_schema.json
)

rm -rf "$DEST"
mkdir -p "$DEST/radio/src" "$DEST/top"

copied=0
for p in "${PATHS[@]}"; do
  if [[ -e "$R/$p" ]]; then
    mkdir -p "$DEST/radio/src/$(dirname "$p")"
    cp -a "$R/$p" "$DEST/radio/src/$(dirname "$p")/"
    copied=$((copied+1))
  else
    echo "note: $p not present at this commit, skipped" >&2
  fi
done
for p in "${TOP_PATHS[@]}"; do
  if [[ -e "$SRC/$p" ]]; then
    mkdir -p "$DEST/top/$(dirname "$p")"
    cp -a "$SRC/$p" "$DEST/top/$(dirname "$p")/"
    copied=$((copied+1))
  else
    echo "note: $p not present at this commit, skipped" >&2
  fi
done

# Drop VCS metadata from submodules and any build residue
find "$DEST" -name .git -prune -exec rm -rf {} + 2>/dev/null || true
find "$DEST" -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true

cat > "$DEST/VENDORED.md" <<EOF
# Vendored from EdgeTX

Commit: $EDGETX_COMMIT
Script: tools/vendor-edgetx.sh
Paths: see the PATHS and TOP_PATHS arrays in the script ($copied entries copied).

Do not edit files here by hand without recording the change in CHANGES.md.
EOF
[[ -f "$DEST/CHANGES.md" ]] || printf '# Local changes to vendored EdgeTX files\n\n(none yet)\n' > "$DEST/CHANGES.md"

echo "vendored $copied paths into $DEST"
du -sh "$DEST"
