# 04. Roadmap

Nine phases. Each has an exit test you can run, and each leaves the radio in a state
that is more useful than before. Phases 1 and 2 are the risky ones; do them first and
do not start UI work until phase 2's exit test passes on a real module.

| # | Phase | Exit test |
|---|---|---|
| 0 | Bootstrap | Repo has LICENSE, NOTICE, toolchain pin, CI that builds native tests and both firmware targets from an empty `src/`. |
| 1 | Platform bring-up | A ZelionTX build boots on TX16S Mk3 and TX15, shows a blank LVGL screen with a frame counter, reads sticks to the serial console, plays a tone, mounts storage, enumerates USB mass storage. Same binary logic runs in the SDL simulator. |
| 2 | Link core | RC frames stream to the internal ELRS module at the module's requested interval; model-select accepted; sync tracked; link statistics decoded; a Rotorflight FC on the bench shows all 16 channels moving in the Configurator receiver tab at the right values. Logic-analyser capture shows frame jitter under 50 us at 500 Hz. |
| 3 | Model and safety | Calibration, channel map, switch levels, throttle policy, hold switch, boot safety check. A heli arms and flies with rates and governor configured on the FC. This is the first flyable release. |
| 4 | Telemetry | Native and 0x88 decoding, telemetry store, sensor map page showing every configured sensor with unit and age; MSP identity and RTC set on connect. |
| 5 | Dashboard | ZelionDash ported with all 337 test behaviours passing natively; audio and haptic alerts; flight log written; screenshots at both resolutions checked in. |
| 6 | Link screen | Native ELRS configuration replacing `elrs.lua`: packet rate, telemetry ratio, switch mode, power, model match, WiFi, bind, other devices; status line with bad/good and flags. |
| 7 | Heli screen | FC status, arming blockers by name, PID and rate profile selection, adjustment teller, flight stats, "write recommended sensor list". |
| 8 | Release hardening | USB module passthrough and ELRS flashing verified, storage atomicity, brown-out behaviour, memory report, user guide, release packaging, a beta with the three helis ZelionDash was verified on. |

## Phase details

### Phase 0. Bootstrap (days)

- Create `LICENSE` (GPL-2.0-only) and `NOTICE` naming EdgeTX and the commit used.
- `git subtree add` EdgeTX at `96ab274` into `platform/`, then delete everything not in
  the reuse list in one commit so the provenance is visible in history.
- Pin Arm GNU 14.2.rel1; add `CMakePresets.json` with `tx16smk3`, `tx15`, `native`.
- CI: build native tests, build both firmware targets, upload `.bin` and map files.
- Decide the two open decisions in `05-decisions-and-risks.md` that block phase 1
  (arming byte policy can wait; the LVGL version cannot).

### Phase 1. Platform bring-up (2 to 3 weeks)

- Build with `GUI=OFF LUA=OFF` equivalents removed rather than switched: the new
  `src/` contains only `core/`, a stub `ui/` and a serial console.
- Verify each driver on both boards: ADC values, switches, keys, rotary, touch (TX16S
  Mk3), LCD flush, backlight, audio tone, haptic, storage mount and file write, USB MSC,
  module power and boot pin toggling, internal UART loopback.
- Simulator: SDL window, keyboard-driven inputs, virtual storage directory, a fake
  module UART pair.
- Deliverable: `docs/modules/platform.md` with a bring-up checklist per board and the
  list of EdgeTX files retained.

### Phase 2. Link core (2 to 3 weeks)

- `link/crsf`, `link/elrs` (state machine, sync, link stats), `core/rc_scheduler`.
- Test double: a scripted ELRS module for native tests (answers ping, sends sync with a
  chosen interval and offset, sends link stats, drops frames on demand).
- Hardware validation with a logic analyser on the module UART and with an FC in the
  Configurator's receiver tab. Record a capture of real module output into
  `tests/captures/` for the simulator's stream player.
- Also implement: module power sequencing, baud selection, USB CDC passthrough (it
  needs the same UART plumbing and unblocks ELRS flashing early).

### Phase 3. Model and safety (2 weeks)

- `input/` calibration and `model/` translation with tests first.
- Minimal setup pages in LVGL: Calibration, Channels, Models. Plain lists, no polish.
- Boot safety check and throttle hold.
- Fly. Log every surprise into `docs/flight-notes.md`.

### Phase 4. Telemetry (1 to 2 weeks)

- `telemetry/` store and decoders, `link/msp`, `rf/` identity and RTC.
- Sensor map page (this becomes the diagnostics page of the Dash screen).
- Capture a real 0x88 stream from each of the three helis for the test suite.

### Phase 5. Dashboard (3 to 4 weeks)

- Port order: `roles` -> `state` -> `alerts` -> `profiles` -> `escfault` ->
  `flightlog` -> `flighttime` -> `packhealth`, each with its test file ported first.
- `audio/` number vocabulary and tone queue.
- Dash screen layout for 800x480 and 480x320, screenshots checked in.

### Phase 6. Link screen (2 weeks)

- Parameter protocol client with the scripted module double from phase 2 extended to
  serve a parameter tree.
- Generic renderer for folders, selections, numbers, info and commands, so ELRS
  firmware updates that add parameters need no ZelionTX change.

### Phase 7. Heli screen (1 to 2 weeks)

- Status, arming blockers, profile switching, adjustment teller, flight stats.
- "Write recommended CRSF sensor list" with a confirmation dialog and EEPROM write.

### Phase 8. Release hardening (2 weeks)

- ELRS flashing through the radio with the ELRS Configurator's "via ETX passthrough".
- Storage fault injection (power off during write), brown-out, watchdog recovery.
- Memory and timing report in CI; user guide; beta.

## Estimated effort

Roughly 16 to 20 weeks of one experienced embedded developer's time for phases 0 to 8,
front-loaded on phases 1 and 2. The dashboard port is the most predictable phase because
its behaviour is already specified by tests. [unverified: estimates are judgement, not
measurement.]

## Version 2 candidates (not planned, listed so version 1 does not preclude them)

- Mono-LCD F4 radios with internal ELRS (Boxer, Pocket, Zorro, TX12 Mk2, MT12): the
  core is screen-agnostic; a `ui/mono` would be the work.
- Trims as real trims with voice feedback.
- Adjustment functions driven from the radio's rotary with the FC's adjustment ranges.
- Voice pack builder for languages other than English.
- Lua sandbox for user dashboards, if ever demanded; the platform can host it because
  EdgeTX's Lua bindings remain available to fork, but it is deliberately absent from
  version 1.
