# Handoff: state of ZelionTX as of 2026-09-18

Read this first in any new session or Project thread. It replaces the need for the
original conversation transcript.

## What exists

- Proposal: `docs/proposal/01` to `06` (vision, requirements, architecture and
  modules, roadmap, decisions and risks, connected-system pillar).
- Research notes with file and line references into the reference snapshots:
  `docs/research/` (EdgeTX, ExpressLRS, Rotorflight firmware and Lua, Rotorflight
  Configurator, ZelionDash, VBar Control).
- Platform layer vendored from EdgeTX `96ab274` into `platform/` by
  `tools/vendor-edgetx.sh` (decision D-19). Everything above the HAL is new code
  in `src/`.
- Build: `tools/setup-toolchain.sh` (xPack Arm GCC 14.2.1), `cmake --preset tx15`,
  `cmake --build --preset tx15`. CI in `.github/workflows/build.yml`.
- Build 1 for the TX15: boots the board, LVGL frame counter, live analog values,
  hold power two seconds to switch off. 225 KB text. UF2 writes only external
  flash; the EdgeTX bootloader is untouched. Details and the flashing procedure in
  `docs/modules/platform.md`. **Not yet flashed by anyone.**

## Decisions that bind the work

All in `docs/proposal/05-decisions-and-risks.md`, D-1 to D-19. The ones a new
thread most often needs:

- GPL-2.0-only; no code from ExpressLRS or Rotorflight (GPL-3.0), protocols are
  re-implemented from `docs/research/`.
- Targets: TX15 first, then TX16S Mk3 and GX15. ELRS 4.1 minimum.
- Channel map for Rotorflight on ELRS is `AECR1T23` (CH1 roll, CH2 pitch, CH3
  collective, CH4 yaw, CH5 AUX1 = ARM, CH6 throttle, CH7+ AUX). Arm via the ELRS
  arming byte.
- The FC is the model; the radio is a window onto it (chapter 06). Aircraft
  records keyed by FC UID; wizard on first connection; Simple and Expert Heli
  pages; every FC write refused unless throttle hold is active and the FC is
  disarmed, backed up first, read back after.
- Starter rates written by the wizard: 300 deg/s, named as a Zelion default.
- Working model: the owner flashes builds and reports; the software is written and
  tested natively. No logic analyser; the ELRS module's counters are the timing
  instrument.

## Open items

- Owner to flash build 1 and report: boot, counter, input values, power-off,
  photo.
- Next code: phase 2, the link core (`src/link/crsf`, `src/link/elrs`, RC scheduler
  driven by the module's sync frame). Needs no radio to write and unit-test.
- Debts to retire: every symbol in `src/compat/app_globals.cpp`.
- Unverified: TX15 bootloader key combination; VBar Control notes were read through
  search summaries only.

## Suggested Project instructions (paste into the Project)

You are working on ZelionTX, a GPL-2.0 transmitter firmware for RC helicopters
that talks only to Rotorflight flight controllers over an internal ExpressLRS
module. Read docs/HANDOFF.md first, then docs/proposal/ in order. Facts about
EdgeTX, ExpressLRS and Rotorflight come only from docs/research/; never copy code
from ExpressLRS or Rotorflight. Label statements as FACT, INFERENCE or GUESS and
mark anything unverified. The owner is not a programmer: they flash builds and
report what the radio does; you write and test the code. Every FC write path must
honour the safety interlocks in docs/proposal/06. Commit small, push to the
working branch, and keep docs/modules/ current.
