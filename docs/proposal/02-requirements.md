# 02. Requirements

Identifiers: F = functional, S = safety, P = performance, C = constraint, Q = quality.
"Source" says where the requirement comes from in the research notes. "MUST" is
version 1; "SHOULD" is version 1 if cheap, otherwise version 2.

## A. Inputs and stick translation

| Id | Requirement | Source |
|---|---|---|
| F-A1 | MUST read all gimbal axes, pots, sliders and switches of the target radio through the EdgeTX hardware definition for that board. | edgetx.md 2 |
| F-A2 | MUST provide a calibration flow (centre, min, max per analog) and store it per radio. | edgetx.md 4; rotorflight-firmware.md 2 (FC has no rxrange) |
| F-A3 | MUST map sources to 16 output channels with, per channel: source, reverse, endpoints, subtrim. No expo, no curves, no mixing. | rotorflight-firmware.md 3 and 9 |
| F-A4 | MUST default the channel order to Rotorflight's `AETRC`: CH1 roll, CH2 pitch, CH3 throttle, CH4 yaw, CH5 collective, CH6+ AUX. Order MUST be editable. | rotorflight-firmware.md 2 |
| F-A5 | MUST support switch-driven channels with named positions and microsecond values in 5 us steps, so ARM, RESCUE, PREARM, governor bypass/suspend/fallback, USER1-4 and adjustment functions can be assigned to physical switches. | rotorflight-firmware.md 2, 7 |
| F-A6 | MUST support a throttle channel that can be either the throttle stick (governor NORMAL type) or a switch with 2 to 4 fixed levels (governor SWITCH and FUNCTION types, e.g. OFF 988 / IDLE 1250 / AUTO 1500 / RUN 1750 us). | rotorflight-firmware.md 8 |
| F-A7 | MUST provide a throttle hold (throttle cut) switch that forces the throttle channel to its off value regardless of the source. | ZelionDash "Hold Switch"; Governor.md |
| F-A8 | SHOULD provide trims on roll, pitch, yaw and collective as a subtrim offset only, with an on-screen indicator. | edgetx.md 4 |
| F-A9 | MUST expose every input's current value on a diagnostics page (channel monitor). | practice |

## B. ELRS link

| Id | Requirement | Source |
|---|---|---|
| F-B1 | MUST drive the internal module UART full duplex 8N1 at a rate from `{400000, 921600, 1870000, 3750000, 5250000}`, default 1870000, selectable in radio settings. | expresslrs.md 3; edgetx.md 5 |
| F-B2 | MUST send CRSF 0x16 RC frames (16 x 11-bit, 172/992/1811 for -100/0/+100 %) continuously at the interval announced by the module's 0x3A sync frame, and MUST apply the sync offset to phase the frame. | expresslrs.md 3, checklist 2-3 |
| F-B3 | MUST send the model-select command (0x32 / 0x10 / 0x05 / id) at module start and on model change; each ZelionTX model MUST carry an ELRS model id 0..63. | expresslrs.md 6 |
| F-B4 | MUST decode 0x14 link statistics and expose RSSI1/2, LQ, SNR, RF mode, TX power, and downlink values as telemetry. | expresslrs.md 4 |
| F-B5 | MUST implement the ELRS parameter protocol client (0x28/0x29/0x2C/0x2B/0x2D/0x2E) natively and render it as the Link screen, including folders, text selections, numeric fields, info fields, COMMAND step machine with confirm and the modal error flags. | expresslrs.md 5 |
| F-B6 | MUST poll ELRS status (0x2D id 0) every second and show connected, model mismatch, armed, bad/good counts. | expresslrs.md 5 |
| F-B7 | MUST send the bind command from the Link screen. SHOULD allow reading the module UID via encapsulated MSP. | expresslrs.md 5, 8 |
| F-B8 | SHOULD send the ELRS arming status byte (25-byte RC frame) when "arm via switch" is configured, otherwise arm rides on CH5 as in ELRS default. Version 1 MAY choose one and document it. | expresslrs.md 2, 7 |
| F-B9 | MUST control module power and the boot pin, and provide USB serial passthrough so the ELRS module can be flashed with the standard ELRS tooling. | edgetx.md 5, 11 |

## C. Rotorflight telemetry and MSP

| Id | Requirement | Source |
|---|---|---|
| F-C1 | MUST decode native CRSF frames 0x02, 0x07, 0x08, 0x09, 0x0C, 0x0D, 0x1E, 0x21, 0x0B, 0x29. | rotorflight-firmware.md 5 |
| F-C2 | MUST decode the Rotorflight 0x88 custom telemetry frame with the full appId table (0x1000..0x1220, 0xDB00..0xDB07) and its encoders (U8..S32, CellVolt, Cells, Control, Attitude, Accel, LatLong, AdjFunc). Frame id gaps MUST be counted. | rotorflight-firmware.md 5 |
| F-C3 | MUST keep a telemetry store keyed by protocol id with value, validity, age, session min and max, and a per-sensor timeout. Missing and zero MUST be distinguishable. | zeliondash.md; edgetx.md 6 |
| F-C4 | MUST implement chunked MSP over CRSF (0x7A/0x7B/0x7C, status byte with sequence, start and version bits, 8-byte uplink chunks, 58-byte downlink chunks) with retry and timeout. | rotorflight-firmware.md 6; expresslrs.md 8 |
| F-C5 | MUST on link connect: read MSP_API_VERSION, MSP_FC_VARIANT, MSP_FC_VERSION, MSP_NAME, MSP_STATUS, MSP_TELEMETRY_CONFIG, and set the FC clock with MSP_SET_RTC. MUST refuse Rotorflight-specific features outside API 12.6..12.10 and say so on screen. | rotorflight-firmware.md 7; rotorflight-configurator.md 1 |
| F-C6 | MUST read MSP_BOXNAMES and MSP_BOXIDS so mode names are never hard-coded. | rotorflight-configurator.md 5 |
| F-C7 | MUST allow selecting PID profile 1..6 and rate profile 1..6 from the Heli screen using MSP_SELECT_SETTING, and MUST show the active profiles from telemetry. | rotorflight-firmware.md 3 |
| F-C8 | MUST show arming-disable flags by name (27 flags, names taken from the firmware table) when the FC reports "DISABLED". | rotorflight-firmware.md 4 |
| F-C9 | SHOULD show the adjustment-function teller (function id and value from appId 0x1220) with the function name table. | rotorflight-firmware.md 7 |
| F-C10 | SHOULD read MSP_FLIGHT_STATS (API >= 12.9) for lifetime flight count and time. | zeliondash.md rf2 |
| F-C11 | SHOULD offer "write the recommended CRSF sensor list to the FC" from the Heli screen using MSP_SET_TELEMETRY_CONFIG plus MSP_EEPROM_WRITE, with confirmation, since a factory FC sends nothing. | rotorflight-firmware.md 5 |

## D. Dashboard and alerts (port of ZelionDash)

| Id | Requirement | Source |
|---|---|---|
| F-D1 | MUST reproduce the ZelionDash dashboard: hero tiles for battery and headspeed, cell voltage over fuel gauge, governor, current, ESC temperature, BEC, link, flight timer, alert strip; two density classes (800x480, 480x320). | zeliondash.md |
| F-D2 | MUST port the state model (validity, session extremes, arm session, resting voltage, decay detection), alerts (hysteresis, repeat, settle, once-per-pack, main power lost), profiles (auto from pack voltage), ESC fault decoding for the three documented vendors, flight log CSV (same columns, append-only), time remaining, pack health. | zeliondash.md |
| F-D3 | MUST bind dashboard roles directly to protocol ids (appId or link-stats field) with an optional per-model override; the name/unit guessing of the Lua widget is replaced, not ported. | zeliondash.md; rotorflight-firmware.md 5 |
| F-D4 | MUST provide the sensor map diagnostics page (role, bound source, how, live value with unit). | zeliondash.md |
| F-D5 | MUST speak numbers through the radio's voice vocabulary and support tone plus haptic alerts, with a hold switch that silences and an arm-switch polarity option. | zeliondash.md |
| F-D6 | MUST carry the 337 existing tests' behaviours across as native tests (same cases, same expected values) so the port is provably faithful. | zeliondash.md |

## E. Screens and setup

| Id | Requirement | Source |
|---|---|---|
| F-E1 | MUST have exactly three main screens reachable by one key or swipe: Dash, Link, Heli. | user brief |
| F-E2 | MUST have setup pages: Models (select, new, rename, delete, ELRS model id), Channels (source, reverse, endpoints, subtrim, switch levels), Calibration, Radio (baud, backlight, volume, alerts defaults, USB mode, about). | derived |
| F-E3 | MUST show a persistent status strip: model name, link state, TX battery, time, ELRS mode and power. | practice |
| F-E4 | SHOULD support touch on the TX16S Mk3 and the rotary/keys on both radios through LVGL input devices. | edgetx.md 8 |

## F. Storage, USB, audio

| Id | Requirement | Source |
|---|---|---|
| F-F1 | MUST persist radio settings and up to 32 models on the radio's storage in a small human-readable text format, with a version field and forward-compatible parsing. | edgetx.md 9 |
| F-F2 | MUST write the flight log to `/LOGS/zeliondash.csv` (same path and columns as today). | zeliondash.md |
| F-F3 | MUST provide USB mass storage (logs, voices, models) and USB serial (module passthrough). USB joystick is optional. | edgetx.md 11 |
| F-F4 | MUST play WAV voice files from `/SOUNDS/<lang>/SYSTEM` for numbers and units, and synthesise tones without files. | edgetx.md 10 |

## G. Connected system (chapter 06)

| Id | Requirement | Source |
|---|---|---|
| F-G1 | MUST identify the aircraft on link-up from `MSP_UID` and `MSP_NAME`, select the matching aircraft record, and show its name in the status strip. An unknown UID MUST offer the setup wizard. | vbar-control.md; rotorflight-configurator.md 2 |
| F-G2 | MUST keep one aircraft record per UID holding only what the FC cannot: switch-to-channel assignment, ELRS model match id and link settings, dashboard overrides, alert thresholds, cached FC data for offline viewing. | vbar-control.md |
| F-G3 | MUST provide a setup wizard that, with confirmation, names the aircraft (`MSP_SET_NAME`), confirms the channel map (`MSP_RX_MAP`), writes mode ranges and adjustment ranges matching the radio's switch assignment, writes the recommended telemetry list, sets the ELRS model id on the module, checks stick travel against `MSP_RC_CONFIG` with a live `MSP_RC` view, and saves with `MSP_EEPROM_WRITE`. | rotorflight-configurator.md 3; expresslrs.md 6 |
| F-G4 | MUST provide table-driven parameter editors for rate profiles, PID profiles and tuning, governor config and profile, rescue profile, mixer config and trims, servo configuration, battery config and profiles, ESC sensor config, telemetry config, with layouts selected by FC API version. Out-of-range values MUST be refused at the editor. | rotorflight-configurator.md 3 |
| F-G5 | MUST refuse any FC write while the FC reports armed, and MUST show the FC's reboot-required and configuration-state flags. | rotorflight-firmware.md 6 |
| F-G6 | MUST back up the FC configuration (every readable config message for the API version) to storage keyed by UID and FC version before the first write of a session, and on demand; MUST offer restore with a field-level diff and confirmation. | vbar-control.md |
| F-G7 | MUST write a per-flight event log (arm, disarm, governor state changes, rescue, arming blockers, link drops, alerts, profile changes) alongside the flight log, and MUST tag both with aircraft UID, name, FC version and profile numbers. | vbar-control.md; rotorflight-firmware.md 5 |
| F-G8 | SHOULD provide ESC parameter pages for the vendors Rotorflight supports through `MSP_ESC_PARAMETERS`. | rotorflight-firmware.md 6 |
| F-G9 | SHOULD raise the ELRS telemetry ratio while a Heli configuration page is open and restore it on leaving, and MUST show link throughput so a slow page load is explained. | expresslrs.md 4 |
| F-G10 | SHOULD trigger ELRS receiver WiFi update mode from the Link screen. FC firmware update over the link is out of scope and the UI MUST say so where a user would look for it. | expresslrs.md 5; vbar-control.md |

## S. Safety

| Id | Requirement | Source |
|---|---|---|
| S-1 | MUST warn on boot if the ARM switch, throttle hold or a throttle switch is not in its safe position, and MUST hold the throttle channel at its off value until acknowledged. | rotorflight-firmware.md 4 (ARM must be off at boot; throttle off to arm) |
| S-2 | MUST never send a throttle above the off value while the hold switch is active. | F-A7 |
| S-3 | MUST show link loss within 1 s (LQ 0 or no link stats for 1 s) visibly and audibly. | expresslrs.md 4 |
| S-4 | MUST keep sending RC frames while any UI, storage or USB operation runs; the RC path has the highest priority and no shared locks with the UI. | edgetx.md 3 |
| S-5 | MUST refuse to change ELRS packet rate or switch mode while connected (mirror the module's rule) and show why. | expresslrs.md 5 |
| S-6 | MUST store calibration and models atomically (write temp, rename) so a power loss cannot corrupt the active model. | practice |

## P. Performance

| Id | Requirement |
|---|---|
| P-1 | RC frame period follows the module sync from 1000 us to 50 ms; frame timing jitter under 50 us (measured on the UART line in the simulator and on hardware with a logic analyser). |
| P-2 | Time from stick movement to RC frame on the wire under 1.5 frame periods. |
| P-3 | Dashboard steady-state 30 fps at 800x480 with telemetry at 20 Hz, audio playing and logging enabled; UI task budget under 50 % of one core. |
| P-4 | Boot to RC frames flowing in under 2 s, to dashboard in under 3 s. |
| P-5 | Flash and RAM headroom of at least 50 % on the H750 targets after version 1 (they have 8 MB NOR and 8 or 32 MB SDRAM, so this is about discipline, not capacity). |

## C. Constraints

| Id | Constraint |
|---|---|
| C-1 | Licence GPL-2.0-only (derives from EdgeTX). No code from ExpressLRS, Rotorflight or their Lua scripts may be copied; protocol facts are re-implemented from the research notes. |
| C-2 | Toolchain: Arm GNU 14.2.rel1 (EdgeTX's pinned toolchain) and CMake, so the reused platform layer builds unchanged. |
| C-3 | Targets: STM32H750 boards with LVGL 8.2 as in EdgeTX (upgrading LVGL is a separate decision). |
| C-4 | Rotorflight MSP API 12.6..12.10 and ELRS 3.x module firmware; older ELRS is not supported. |

## Q. Quality

| Id | Requirement |
|---|---|
| Q-1 | Every module below the UI (codec, link, telemetry decoder, MSP, telemetry store, dashboard logic, alerts, log, storage format) builds natively and has unit tests; CI runs them on every push. |
| Q-2 | The full UI runs in a desktop simulator fed by a recorded or synthetic CRSF stream, so screens are developed without a radio. |
| Q-3 | Protocol golden vectors (RC frame, sync, param entries, 0x88 frames, MSP chunks) live in the tests and are cross-checked against captures from a real module and FC before release. |
| Q-4 | One document per module states what it owns, its public interface and its tests. |
