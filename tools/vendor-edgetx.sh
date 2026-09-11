#!/usr/bin/env bash
# Vendors the EdgeTX platform layer into platform/ from a pinned EdgeTX commit.
#
# This is the only way EdgeTX code enters this repository (decision D-19).
# The tree radio/src is copied whole and then the EXCLUDES below are removed,
# so the record of what was taken is "everything in radio/src at the commit,
# minus this list". Trimming *within* what remains happens in ZelionTX's own
# CMake by not compiling files, never by editing the vendored tree, so a
# re-vendor at a newer commit is a clean diff.
#
# Usage: tools/vendor-edgetx.sh /path/to/edgetx-checkout
# The checkout must be at EDGETX_COMMIT with submodules lvgl, FreeRTOS, uf2
# and stb initialised.
set -euo pipefail

EDGETX_COMMIT="96ab2745d1bc0025c5508ac8a3b862f34cf97c6e"
SRC="${1:?path to EdgeTX checkout}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/platform"

have="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$have" != "$EDGETX_COMMIT" ]]; then
  echo "EdgeTX checkout is at $have, expected $EDGETX_COMMIT" >&2
  exit 1
fi
for sm in lvgl FreeRTOS uf2 stb; do
  [[ -n "$(ls -A "$SRC/radio/src/thirdparty/$sm" 2>/dev/null)" ]] \
    || { echo "submodule $sm not initialised" >&2; exit 1; }
done

# Paths relative to radio/src that are removed after the copy.
EXCLUDES=(
  # Other MCU families and their HAL/CMSIS
  thirdparty/STM32F2xx_HAL_Driver
  thirdparty/STM32F4xx_HAL_Driver
  thirdparty/STM32H7RS_HAL_Driver
  thirdparty/CMSIS/Device/ST/STM32F2xx
  thirdparty/CMSIS/Device/ST/STM32F4xx
  thirdparty/CMSIS/Device/ST/STM32H7RS
  targets/common/arm/stm32/f2
  targets/common/arm/stm32/f4
  # Radios we do not target
  targets/taranis
  targets/horus
  targets/pl18
  targets/t15pro
  targets/st16
  targets/pa01
  targets/c14
  targets/v12
  targets/t22
  targets/stm32h7s78-dk
  boards/jumper-h750
  boards/helloradio-h750
  # Lua, YAML storage tables, mono-LCD GUIs, debug tooling
  thirdparty/Lua
  thirdparty/Segger
  thirdparty/AccessDenied
  lua
  storage/yaml
  gui/128x64
  gui/212x64
  # LVGL: keep src/ and the top-level headers only
  thirdparty/lvgl/docs
  thirdparty/lvgl/examples
  thirdparty/lvgl/demos
  thirdparty/lvgl/tests
  thirdparty/lvgl/scripts
  thirdparty/lvgl/env_support
  thirdparty/lvgl/.github
  # FreeRTOS: keep the kernel, the Cortex-M4F GCC port and MemMang
  thirdparty/FreeRTOS/.github
  thirdparty/FreeRTOS/examples
  thirdparty/FreeRTOS/portable/ARMClang
  thirdparty/FreeRTOS/portable/ARMv8M
  thirdparty/FreeRTOS/portable/BCC
  thirdparty/FreeRTOS/portable/CCS
  thirdparty/FreeRTOS/portable/CodeWarrior
  thirdparty/FreeRTOS/portable/Common
  thirdparty/FreeRTOS/portable/IAR
  thirdparty/FreeRTOS/portable/Keil
  thirdparty/FreeRTOS/portable/MPLAB
  thirdparty/FreeRTOS/portable/MSVC-MingW
  thirdparty/FreeRTOS/portable/MikroC
  thirdparty/FreeRTOS/portable/oWatcom
  thirdparty/FreeRTOS/portable/Paradigm
  thirdparty/FreeRTOS/portable/RVDS
  thirdparty/FreeRTOS/portable/Renesas
  thirdparty/FreeRTOS/portable/Rowley
  thirdparty/FreeRTOS/portable/SDCC
  thirdparty/FreeRTOS/portable/Softune
  thirdparty/FreeRTOS/portable/Tasking
  thirdparty/FreeRTOS/portable/ThirdParty
  thirdparty/FreeRTOS/portable/WizC
  # stb: only the two image headers are used
  thirdparty/stb/deprecated
  thirdparty/stb/tests
  thirdparty/stb/tools
  thirdparty/stb/data
  thirdparty/stb/docs
  # Fonts: only the standard-size English face is kept (see below)
  fonts/Arimo
  fonts/Kanit
  fonts/Nanum
  fonts/Noto
  fonts/Roboto
  fonts/Ubuntu
  fonts/sqt5
  fonts/std
  fonts/lvgl/sml
  fonts/lvgl/lrg
)

# Individual files kept from an otherwise excluded area are listed here as
# "excluded-dir-glob-to-remove" after the copy; fonts/lvgl/std keeps only the
# English STD face and the boot font.
FONT_KEEP_REGEX='lv_font_(en_STD|bl)\.c$'

# Build-system pieces from outside radio/src
TOP_PATHS=(
  cmake/toolchain/arm-none-eabi.cmake
  cmake/toolchain/native.cmake
  cmake/Macros.cmake
  cmake/Bitmaps.cmake
  cmake/FetchGtest.cmake
  radio/util/hw_defs
  radio/util/elf2uf2.py
  radio/util/encode-bitmap.py
  radio/util/codecs.py
  tools/hwdef_schema.json
)

rm -rf "$DEST"
mkdir -p "$DEST/radio/src"

# Copy radio/src whole, without VCS metadata or build residue
cp -a "$SRC/radio/src/." "$DEST/radio/src/"
find "$DEST/radio/src" -name .git -prune -exec rm -rf {} + 2>/dev/null || true
find "$DEST/radio/src" -maxdepth 1 -name 'build*' -prune -exec rm -rf {} + 2>/dev/null || true

for p in "${EXCLUDES[@]}"; do
  rm -rf "$DEST/radio/src/$p"
done
find "$DEST/radio/src/fonts/lvgl/std" -type f -name 'lv_font_*.c' \
  | grep -Ev "$FONT_KEEP_REGEX" | xargs -r rm -f

# stb: keep only the headers EdgeTX includes
find "$DEST/radio/src/thirdparty/stb" -maxdepth 1 -type f \
  | grep -Ev '/(stb_image\.h|stb_image_write\.h|LICENSE|README\.md)$' | xargs -r rm -f

# Build-system pieces keep their EdgeTX-relative paths so that Macros.cmake
# finds radio/util next to radio/src.
for p in "${TOP_PATHS[@]}"; do
  if [[ -e "$SRC/$p" ]]; then
    mkdir -p "$DEST/$(dirname "$p")"
    cp -a "$SRC/$p" "$DEST/$(dirname "$p")/"
  else
    echo "note: $p not present at this commit, skipped" >&2
  fi
done
find "$DEST" -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true

# Keep only the hw_defs JSONs for radios we target
find "$DEST/radio/src/boards/hw_defs" -name '*.json' \
  | grep -Ev '/(tx15|tx16smk3|gx15)\.json$' | xargs -r rm -f

cat > "$DEST/VENDORED.md" <<EOF
# Vendored from EdgeTX

Commit: $EDGETX_COMMIT
Script: tools/vendor-edgetx.sh

Contents: EdgeTX radio/src at that commit minus the EXCLUDES list in the
script, plus the build-system pieces in TOP_PATHS at their EdgeTX-relative paths. Every file keeps
its EdgeTX licence header (GPL-2.0).

Do not edit files here by hand without recording the change in CHANGES.md.
EOF
[[ -f "$DEST/CHANGES.md" ]] || printf '# Local changes to vendored EdgeTX files\n\n(none yet)\n' > "$DEST/CHANGES.md"

echo "vendored into $DEST"
du -sh "$DEST"
