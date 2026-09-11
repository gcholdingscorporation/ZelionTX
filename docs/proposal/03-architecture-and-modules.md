# 03. Architecture and modules

## Strategy: fork the floor, rebuild the house

Three ways to build this were weighed against the research:

1. **Clean-room firmware** (Zephyr or bare FreeRTOS, own drivers). Cleanest result,
   but the STM32H750 bring-up in EdgeTX (QSPI XIP into SDRAM, LCD with DMA2D, touch,
   audio codec over I2S, SDIO, USB, backlight, power, per-board pin maps) is months of
   risk that EdgeTX has already retired. Rejected.
2. **EdgeTX build with everything switched off.** Fast start, but the model-programming
   layer is not a compile option; the mixer, storage schema, telemetry sensor table and
   GUI are entangled, and Lua remains the only path to ELRS and Rotorflight menus.
   Rejected as the end state, though phase 1 uses it as the bring-up baseline.
3. **Fork the platform layer, write a new core.** Keep EdgeTX's `targets/`, `boards/`,
   `hal/`, `os/`, mixer scheduler, CRSF driver, LVGL wrapper, storage drivers, audio and
   USB. Replace everything above the HAL with small purpose-built modules. **Chosen.**

The rule that keeps option 3 honest: **nothing above the HAL is copied from EdgeTX
unless it is listed in the "reuse" column below.** Copying is a decision, not a default.

## Layer diagram

```
+---------------------------------------------------------------------+
|  ui/            Dash screen   Link screen   Heli screen   Setup      |  LVGL 8.2
+---------------------------------------------------------------------+
|  dash/          roles  state  alerts  profiles  escfault  flightlog   |  pure logic
|                 flighttime  packhealth  (ported from ZelionDash)      |  (ported tests)
+---------------------------------------------------------------------+
|  rf/            fc identity, status, profiles, boxnames, telemetry    |  MSP client
|                 config, flight stats, adjustment names                |
+-------------------------------+-------------------------------------+
|  telemetry/  store + decoders |  link/elrs  params client, status,   |
|  (native + 0x88 + linkstats)  |  model select, bind, sync tracking    |
+-------------------------------+-------------------------------------+
|  link/msp   chunked MSP over CRSF (seq, start, version, retries)      |
+---------------------------------------------------------------------+
|  link/crsf  frame codec, CRC-8 0xD5, parser, router by type/address  |
+---------------------------------------------------------------------+
|  model/     channel map, switch levels, throttle policy, model store  |
|  input/     ADC read, calibration, switch positions, normalisation    |
+---------------------------------------------------------------------+
|  core/      tasks, scheduler (module-period driven), events, clock    |
+---------------------------------------------------------------------+
|  platform/  EdgeTX HAL + STM32 drivers + board defs + FreeRTOS + LVGL |  reused
|             + FatFs + USB + audio drivers + simulator stubs           |
+---------------------------------------------------------------------+
```

Data flows in two loops that never block each other:

- **RC loop** (hard real time, highest priority): module sync -> scheduler timer ->
  `input` sample -> `model` translate -> `link/crsf` pack -> UART DMA. One pass per
  module frame, 1 to 50 ms.
- **Telemetry and UI loop** (soft real time): UART idle interrupt -> `link/crsf` parse
  in a deferred worker -> route to `link/elrs`, `link/msp`, `telemetry` -> `dash` and
  `rf` update their state at 10 Hz -> `ui` renders at 30 ms LVGL ticks.

## Module catalogue

Each module lists: owns, interface, reuse from EdgeTX, tests.

### platform/  (reused)

- Owns: board init, pin maps, ADC, switch and key drivers, UART with DMA and idle
  callback, module port power and boot pin, LCD and DMA2D flush, backlight, touch,
  rotary, audio DAC/I2S, haptic, SDIO/QSPI disk IO, FatFs, USB device classes,
  watchdog, FreeRTOS config and the `os/` wrapper, linker scripts, bootloader.
- Reuse: `targets/common/arm/stm32/`, `targets/tx16smk3/`, `targets/tx15/`,
  `boards/generic_stm32/`, `boards/rm-h750/`, `boards/hw_defs/` + generator, `hal/`,
  `os/`, `thirdparty/` (STM32 HAL, CMSIS, FatFs, USB, lz4), LVGL submodule and
  `gui/colorlcd/lcd.cpp`, `LvglWrapper.cpp`, `dma2d.cpp`, fonts actually used,
  `targets/simu/` stubs.
- Tests: EdgeTX's `module_ports` and `crossfire` gtests carried over; hardware smoke
  test checklist per board.

### core/

- Owns: task set (rc task at highest priority, telemetry worker, audio task, ui task),
  the module-period scheduler (from EdgeTX `mixer_scheduler.*`, renamed `rc_scheduler`),
  a lock-free single-producer event queue from workers to UI, monotonic clock, boot
  sequence, brown-out and watchdog policy.
- Interface: `rc_scheduler_set_period(us)`, `events_post(Event)`, `clock_ms()`.
- Reuse: `tasks.cpp` skeleton, `mixer_scheduler.cpp`, `mixer_scheduler_driver.cpp`.
- Tests: scheduler period clamp and sync application (native).

### input/

- Owns: raw ADC sampling with EdgeTX's jitter filter, calibration data (centre, min,
  max, dead zone per analog), switch position decoding (2/3-position, ADC flex
  switches), normalisation to -1024..+1024, input snapshot struct.
- Interface: `input_sample(InputFrame&)`, `input_calibration_*`.
- Reuse: `hal/adc_driver.cpp`, `analogs.cpp`, `switches.cpp:389-460` (position
  decoding only), calibration struct.
- Tests: calibration maths, dead zone, switch decoding with synthetic ADC values.

### model/

- Owns: the ZelionTX model schema and the translation from an `InputFrame` to 16
  channel values in CRSF units.
  - `Channel { source, reverse, endpointLow, endpointHigh, subtrim, kind }` where kind
    is `Analog` or `Switch`.
  - `SwitchChannel { switchId, levels[] }` with microsecond levels in 5 us steps
    (ARM 988/2012, three-level gov switch 988/1500/2012, function throttle
    988/1250/1500/1750, and so on).
  - Throttle policy: `source = stick | switch`, hold switch id and polarity, off value.
  - ELRS model id, model name, dashboard overrides (role -> appId or off), aircraft
    profile override, alert thresholds, arm-switch polarity.
- Interface: `model_translate(const InputFrame&, ChannelFrame&)`, model load/save/list.
- Reuse: none above the HAL. Endpoint and subtrim maths are a few lines; EdgeTX's
  `applyLimits` is not worth carrying.
- Tests: golden translations (stick at -100/0/+100 with endpoints and reverse; switch
  levels; hold forcing; boot-safety gating).

### link/crsf/

- Owns: frame layout, CRC-8 0xD5, streaming parser with resync, extended-header
  detection (type >= 0x28), 11-bit channel packing and unpacking, address constants,
  frame builders for 0x16 (22 and 23-byte payloads), 0x32 commands, 0x28 ping, 0x2C
  read, 0x2D write, 0x7A/0x7C MSP chunks.
- Interface: `crsf_pack_channels(...)`, `crsf_parser_feed(byte|buffer) -> frames`,
  `crsf_build_*`.
- Reuse: `pulses/crossfire.cpp` packing and CRC, `telemetry/crossfire.cpp`
  defragmenting parser, EdgeTX's crossfire test vectors.
- Tests: every builder against golden bytes from the research notes; parser fuzz
  (random garbage never crashes, valid frames always recovered).

### link/elrs/

- Owns: the handset state machine: module power on, first frames, model select,
  ping until device info, channel streaming; sync tracking (0x3A interval and offset ->
  `rc_scheduler`); link statistics decode; parameter protocol client (device list,
  field enumeration with chunk reassembly, typed field model, write, COMMAND step
  machine with timeouts, reload of parent and siblings after a write, modal error
  flags); status polling; bind; encapsulated MSP for UID.
- Interface: `elrs_start(modelId)`, `elrs_on_frame(frame)`, `elrs_params_*` (enumerate,
  get field, set value, run command), `elrs_status()`, `elrs_linkstats()`.
- Reuse: `ModuleSyncStatus` and `getAdjustedRefreshRate` logic from EdgeTX; nothing
  from `elrs.lua` (GPL-2.0 header, but a native client is cleaner anyway).
- Tests: scripted module simulator (a test double that answers pings, serves a
  parameter tree with chunking, runs a COMMAND through steps 2/3/4, raises error flags)
  and assertions on the client's requests and resulting field model.

### link/msp/

- Owns: MSP v1/v2 body encoding, chunking into 8-byte uplink CRSF frames with the
  status byte (sequence, start, version, error), reassembly of 58-byte downlink chunks,
  request queue with one in-flight request, retry every 800 ms, per-request timeout,
  error responses.
- Interface: `msp_request(cmd, payload, callback)`, `msp_on_frame(frame)`.
- Reuse: none (EdgeTX has no native MSP).
- Tests: chunking golden vectors, sequence-gap abort, jumbo v1 size, v2 code > 255,
  retry and timeout timing with a fake clock.

### telemetry/

- Owns: the telemetry store keyed by `SourceId` (`{protocol, id}`: link-stats field,
  native CRSF frame field, Rotorflight appId) with value, unit, precision, validity,
  last-seen time, timeout, session min and max, change counter; decoders for the native
  frames and the 0x88 custom frame with the full appId table and encoders; frame-id gap
  counting; the "discovery pass" observation on connect.
- Interface: `telemetry_get(SourceId) -> Reading`, `telemetry_subscribe(SourceId)`,
  `telemetry_list()`.
- Reuse: `TelemetryItem` min/max/timeout idea from EdgeTX; the code is small enough to
  write fresh against the store's needs.
- Tests: one golden 0x88 frame per encoder; timeout and validity transitions;
  min/max reset on session start.

### rf/  (Rotorflight service)

- Owns: FC identity and API gating, `MSP_STATUS` polling at 2 Hz while on screen,
  boxnames/boxids fetch and cache per FC, profile selection, arming-disable names,
  adjustment function names, `MSP_TELEMETRY_CONFIG` read and the "write recommended
  list" action, `MSP_SET_RTC` on connect, `MSP_FLIGHT_STATS` when supported, FC model
  name to radio model name suggestion.
- Interface: `rf_state()` (connected, api, variant, profiles, arming flags),
  `rf_select_profile(kind, index)`, `rf_write_telemetry_list(list)`.
- Tests: fake FC answering the MSP set; payload decoders against the layouts in
  `rotorflight-configurator.md`.

### dash/  (port of ZelionDash)

- Owns: roles (now `role -> SourceId` with a default table and per-model overrides),
  state model, alerts, profiles, ESC fault decoding, flight log writer, time remaining,
  pack health. Pure logic over `telemetry/` readings and a small host interface (clock,
  speak number, tone, haptic, timer, file IO) so the tests can run natively exactly as
  the Lua tests do against `mock_edgetx.lua`.
- Interface: `dash_service(now)` at 10 Hz, `dash_view()` (a plain struct the UI draws).
- Reuse: the Lua modules are the specification; port module by module with the test
  file for each module ported first.
- Tests: all 337 cases translated; the CSV writer checked byte-for-byte against the
  documented row.

### ui/

- Owns: three screens plus setup pages on LVGL 8.2, navigation (keys, rotary, touch),
  status strip, density classes for 800x480 and 480x320, fonts (two faces, four sizes),
  a single theme, alert strip, screenshot to storage.
- Interface: `ui_init()`, `ui_tick()` from the ui task every 30 ms, screens consume
  view structs from `dash`, `link/elrs`, `rf`, `model`.
- Reuse: `LvglWrapper.cpp`, `lcd.cpp`, `dma2d.cpp`, the `libui/` primitives that are
  actually needed (window, page, button, choice, number edit, keyboard), fonts.
  Discard layouts, widgets, themes, topbar, the 200 setup screens.
- Tests: simulator screenshots per screen per resolution, checked into `docs/screens/`
  as the visual record (as the Lua project already does).

### audio/

- Owns: tone synthesis, WAV playback from `/SOUNDS/<lang>/SYSTEM`, number and unit
  vocabulary (`playNumber` semantics), haptic patterns, volume, a priority queue.
- Reuse: `audio.cpp` queue and DAC/I2S drivers, trimmed of vario and background music.

### storage/

- Owns: file layout `/ZELION/radio.cfg`, `/ZELION/models/NN.cfg`, `/LOGS/`,
  `/SOUNDS/`, `/SCREENSHOTS/`; a flat `key = value` text format with sections, a
  version field, unknown keys preserved; atomic writes; model list.
- Reuse: `sdcard.*`, FatFs glue. Not the YAML engine and its libclang-generated tables;
  the schema here is a few dozen keys.
- Tests: round trip, forward compatibility, truncated file recovery.

### usb/

- Owns: mode selection popup, mass storage, CDC passthrough to the module UART with
  baud forwarding and the boot pin for flashing, optional HID joystick.
- Reuse: EdgeTX USB driver and classes, `usb_joystick.cpp` if kept.

### sim/ and tests/

- Owns: SDL desktop simulator built from the same sources with EdgeTX's `targets/simu`
  stubs; a CRSF stream player (recorded module output plus scripted FC telemetry);
  gtest suite; CI workflow (native build + tests + firmware build for both boards on
  every push; artifacts uploaded).

## Repository layout (proposed)

```
ZelionTX/
  CMakeLists.txt            superbuild: native (sim, tests) + arm (firmware)
  cmake/                    toolchain files (from EdgeTX), options
  platform/                 reused EdgeTX platform layer (git subtree, with NOTICE)
    targets/  boards/  hal/  os/  thirdparty/  lvgl/
  src/
    core/  input/  model/  link/{crsf,elrs,msp}/  telemetry/  rf/  dash/  ui/
    audio/  storage/  usb/
  sim/                      desktop simulator entry, stream player
  tests/                    gtest, golden vectors, recorded captures
  tools/                    hwdef generation, voice pack builder, release scripts
  docs/                     proposal, research, module docs, screens
  LICENSE                   GPL-2.0-only
  NOTICE                    provenance of platform/ (EdgeTX, GPL-2.0)
```

`platform/` is brought in with `git subtree` at a pinned EdgeTX commit so upstream
driver fixes can be merged later; every file taken keeps its EdgeTX header.

## Resource discipline (the "no hogging" rule, made concrete)

- The RC task owns the UART TX DMA and nothing else. No storage, no LVGL, no MSP on
  that task. Budget per frame at 1 kHz: under 100 us.
- The telemetry worker parses and routes; decoders update the store under a short
  critical section; nothing allocates after boot.
- `dash_service` and `rf` poll at 10 Hz and 2 Hz respectively, never per frame.
- LVGL runs on the ui task at 30 ms with partial invalidation; the dashboard updates
  only the labels whose value changed since the last tick.
- No Lua interpreter, no YAML parser, no translations table, no protocol switch.
- Static allocation only, as EdgeTX's FreeRTOS config already enforces.
- A build-time report of flash and RAM per module (`-Wl,--print-memory-usage`, map
  file summary in CI) is part of the definition of done for each phase.
