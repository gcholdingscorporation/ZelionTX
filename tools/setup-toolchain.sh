#!/usr/bin/env bash
# Installs the Arm GCC toolchain ZelionTX builds with.
#
# EdgeTX pins Arm GNU Toolchain 14.2.rel1. Arm's own download host is not
# reachable from every network, so this script fetches the xPack build of the
# same GCC (14.2.1 20241119) from GitHub releases, which produces identical
# code for our purposes. Pass --arm to try Arm's host first.
#
# Usage: tools/setup-toolchain.sh [--arm] [DEST_DIR]
# Afterwards: export PATH="$DEST_DIR/bin:$PATH"
set -euo pipefail

TRY_ARM=0
if [[ "${1:-}" == "--arm" ]]; then TRY_ARM=1; shift; fi
DEST="${1:-$HOME/.zeliontx/toolchain}"
XPACK_VER="14.2.1-1.1"
XPACK_URL="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v${XPACK_VER}/xpack-arm-none-eabi-gcc-${XPACK_VER}-linux-x64.tar.gz"
ARM_URL="https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi.tar.xz"

if [[ -x "$DEST/bin/arm-none-eabi-gcc" ]]; then
  echo "toolchain already present: $("$DEST/bin/arm-none-eabi-gcc" --version | head -1)"
  exit 0
fi

mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ $TRY_ARM == 1 ]] && curl -fsSL -o "$tmp/arm.tar.xz" "$ARM_URL"; then
  tar -xJf "$tmp/arm.tar.xz" -C "$tmp"
  src="$(find "$tmp" -maxdepth 1 -type d -name 'arm-gnu-toolchain-*' | head -1)"
else
  echo "fetching xPack GCC ${XPACK_VER}"
  curl -fsSL -o "$tmp/xpack.tar.gz" "$XPACK_URL"
  tar -xzf "$tmp/xpack.tar.gz" -C "$tmp"
  src="$(find "$tmp" -maxdepth 1 -type d -name 'xpack-arm-none-eabi-gcc-*' | head -1)"
fi

cp -a "$src"/. "$DEST"/
echo "installed: $("$DEST/bin/arm-none-eabi-gcc" --version | head -1)"
echo "add to PATH: export PATH=\"$DEST/bin:\$PATH\""
