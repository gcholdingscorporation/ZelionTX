# 01. Vision and scope

## One sentence

ZelionTX is a transmitter firmware for RC helicopters that does three things well,
stick translation, ELRS link control and Rotorflight telemetry, and deliberately does
nothing else.

## The concept it serves

Rotorflight moved the flying logic into the flight controller: rates, expo, collective
curves, swash mixing, governor, rescue, arming safety and profile switching all live
there and are configured once with the Rotorflight Configurator. In that world a
general-purpose transmitter firmware such as EdgeTX carries a large model-programming
system (64 mixes, 64 logical switches, 64 special functions, flight modes, global
variables, curves, heli swash mixing, Lua scripting, 19 languages, a dozen RF protocols)
that a Rotorflight pilot never uses but still pays for in complexity, boot time, screen
refresh rate and the well-known Lua widget pain (bytecode caching, fixed fonts, sensor
discovery by name).

ZelionTX inverts the priority. The transmitter owns exactly what the FC cannot own:

1. reading the pilot's hands and switches accurately and quickly;
2. keeping the ELRS link at the rate the module asks for, with the model id and link
   settings the pilot chose;
3. showing and speaking what the aircraft reports, through the ZelionDash logic that
   already exists and has been flown.

Everything else is either the FC's job or is out of scope.

## What "read through everything" established

The full notes are in `../research/`. The conclusions that shape the design:

- **EdgeTX is separable.** Its hardware layer (STM32 drivers, board definitions,
  FreeRTOS wrapper, mixer scheduler driven by the module's requested period, CRSF
  driver, LVGL wrapper and colour LCD driver, SD/QSPI storage, audio, USB) is cleanly
  behind HAL headers and CMake options. The model-programming layer above it is what we
  do not want, and it can be left out rather than carved out.
- **The ELRS handset contract is small.** A handset must send RC frames at the interval
  the module announces, send a model-select command, honour the sync frame, and may
  optionally implement the parameter protocol for a native configuration screen. No
  handshake, no Lua required.
- **Rotorflight wants linear sticks and nothing more.** Default channel order is
  CH1 roll, CH2 pitch, CH3 throttle, CH4 yaw, CH5 collective, CH6 onward AUX. Throttle
  must be below about 1036 us to arm. The FC has no per-channel range calibration, so
  the transmitter's calibration and endpoints are the calibration.
- **Rotorflight's telemetry is fully specified by protocol id.** The 0x88 custom frame
  carries `[appId u16][value]` records with fixed encoders and units. A native decoder
  binds dashboard roles straight to appIds; the name-and-unit guessing layer of the Lua
  widget is no longer needed.
- **ZelionDash is already layered for porting.** Host adapter, roles, resolver, state,
  alerts, profiles, ESC fault decoding, flight log, time remaining and pack health are
  separate modules with 337 offline tests against a mock host. The port is a
  translation, not a redesign.
- **Licensing constrains reuse.** EdgeTX is GPL-2.0-only. ExpressLRS and Rotorflight
  (firmware, Lua, configurator) are GPL-3.0. GPL-2.0-only code and GPL-3.0 code cannot
  be combined in one program. ZelionTX will therefore be GPL-2.0 (because it derives
  from EdgeTX), and everything about ELRS and Rotorflight must be re-implemented from
  the protocol facts, never copied. ZelionDash has no licence file today; it is your own
  code, so you can license the port however GPL-2.0 requires.

## In scope for version 1

- Radios: RadioMaster TX16S Mk3 (800x480) and TX15 (480x320). Both are STM32H750 with
  an internal ELRS module as the only internal module, both are already in EdgeTX, and
  both are the radios ZelionDash was verified on. Adding further H7 radios (T15 Pro,
  GX15, TX16S Mk3 variants) is expected to be board-definition work only.
- Link: internal ELRS module over CRSF, full duplex UART. No external module bay, no
  other RF protocols.
- Aircraft: Rotorflight 2.x flight controllers (MSP API 12.6 to 12.10).
- Three baked-in screens (interpretation of "a baked in screen with 3 options", see
  decisions): the ZelionDash dashboard, a Link screen (native ELRS configuration and
  link statistics), and a Heli screen (Rotorflight status, arming blockers, profile
  selection, adjustment teller). Plus the minimum setup pages: model select, channel and
  switch assignment, calibration, radio settings.
- Audio and haptic alerts using the radio's number vocabulary, flight log to storage,
  USB mass storage for logs and voice files, USB serial passthrough for flashing the
  ELRS module.
- A desktop simulator and an offline test suite from day one.

## Out of scope for version 1

- Mixes, logical switches, special functions, flight modes, global variables, curves,
  trainer port, heli swash mixing, Lua scripting, themes, layouts, widgets, model
  wizard, multi-language UI, Bluetooth, GPS on the radio, gyro/IMU on the radio,
  external module bay, any non-ELRS protocol, mono-LCD radios (F4 class ELRS radios such
  as Boxer or Pocket are a possible version 2 target; the core is designed so the
  screen is the only thing that changes).
- Configuring Rotorflight from the radio beyond profile selection and adjustment
  functions. The Configurator stays the tool for that.

## Success criteria

- A pilot with a Rotorflight heli and an ELRS receiver can bind, calibrate, assign
  switches and fly within ten minutes of first boot, without reading a manual.
- RC frames leave the radio at the module's requested interval (up to 1 kHz) with
  jitter that the module's sync loop keeps within its 100 us margin.
- The dashboard refreshes at 30 fps or better while telemetry, audio and logging run,
  and never drops an RC frame to do so.
- Boot to a flyable state in under 3 seconds.
- Every non-hardware module has offline tests, and the whole UI runs in the simulator.
