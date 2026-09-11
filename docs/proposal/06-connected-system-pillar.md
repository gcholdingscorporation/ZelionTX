# 06. The connected-system pillar (VBar-style integration)

Added after the first proposal draft. This chapter changes the intent from "a
transmitter that stays out of the FC's way" to "a transmitter that is the FC's control
surface", in the way Mikado's VBar Control is the control surface of a VBar NEO. The
research behind it is in `../research/vbar-control.md`; note its caveat that the
Mikado sources were read through search summaries only.

## The principle

**The flight controller is the model. The radio is a window onto it.**

In the VBar system the flybarless unit holds the whole aircraft setup, the radio holds
no model memories, binding selects the aircraft, a wizard on the radio writes the
initial setup into the unit, parameters are edited on the radio and stored in the unit,
and logs flow back to the radio. Rotorflight already stores everything on the FC and
exposes it over MSP, so the same shape is available to us; what nobody has built is a
radio firmware that treats that as the design centre rather than as a Lua add-on.

## What changes in the proposal

| Before (chapters 01 to 05) | Now |
|---|---|
| Radio owns a list of models with channel maps; ELRS model id per model | Radio keeps a thin **aircraft record** keyed by the FC's `MSP_UID`, created automatically on first connection, holding only what the FC cannot hold: stick calibration is radio-wide, switch-to-channel assignment, ELRS model id, dashboard overrides, cached copies of FC data for offline viewing |
| Model selection is a menu on the radio | **Aircraft recognition on link-up**: the radio reads `MSP_UID` and `MSP_NAME`, selects the matching aircraft record, and shows its name; a new UID starts the setup wizard. Wrong-model flying is impossible by construction |
| Configuration stays in the Configurator; Heli screen shows status and profiles only | **Setup wizard** and **native parameter editors** on the radio, writing to the FC over MSP: rates, PIDs, governor, rescue, profiles, mixer and servo trims, battery profiles, ESC parameters, telemetry sensor list, mode and adjustment ranges. The Configurator remains for first-time hardware setup (ports, motor protocol, sensor alignment) and for anything the link is too slow for |
| Flight log is radio-side only | **Aircraft-side identity in every log line**: UID, name, FC version, profile numbers; plus a radio-synthesised **event log** per flight (arm, disarm, governor state changes, rescue, arming blockers, link drops, alerts) and the FC's own lifetime flight stats |
| No backup | **Backup and restore** of the FC's configuration to the radio's storage, keyed by UID and FC version, with a diff view before restore |
| ELRS configured per radio model | ELRS link settings (rate, ratio, power, switch mode, model match id) are part of the aircraft record and applied to the module when the aircraft is recognised |

## Features, by how close they are to VBar

### Same as VBar

- Aircraft identity from the unit, not a slot on the radio.
- Setup wizard on first connection: name the aircraft, confirm channel map
  (`MSP_RX_MAP`), assign switches to ARM, RESCUE, governor and profiles and write the
  matching mode ranges (`MSP_SET_MODE_RANGE`) and adjustment ranges, write the
  recommended telemetry sensor list, set the ELRS model match id, check stick travel
  against `MSP_RC_CONFIG` with a live `MSP_RC` view, save with `MSP_EEPROM_WRITE`.
- Parameter editing on the radio, stored in the unit: every editor is a thin view over
  an MSP message, with the API-version-dependent layouts from
  `rotorflight-configurator.md`.
- Live telemetry, talking telemetry, per-flight logs on the radio.
- ESC setup from the radio for the vendors Rotorflight supports.
- Backup of the unit's setup to the radio.

### Same idea, different mechanics

- **Switch assignment lives in two places by nature.** The radio knows which physical
  switch drives which channel; the FC knows which channel range activates which mode.
  The wizard keeps them coherent by writing both at once, and the Heli screen shows
  them side by side so a mismatch is visible.
- **Event log is synthesised on the radio** from telemetry transitions and MSP status,
  because Rotorflight has no event log to send. It is still saved next to the flight
  log and still named by aircraft.
- **Receiver updates** are triggered from the radio (ELRS "Enable Rx WiFi") but
  performed by the receiver's own WiFi. The module is flashed through the radio's USB
  passthrough.

### Not achievable over an ELRS link, stated plainly

- Streaming vibration analysis or an oscilloscope. Telemetry bandwidth at typical
  settings is tens of bits per second; blackbox stays on the FC's flash.
- Updating the FC's firmware through the radio. That is DFU over USB.
- An app store or cloud. Out of scope by design.

## Design consequences for the modules

- `model/` becomes `aircraft/`: a record per FC UID with the fields above; the
  channel-translation logic is unchanged.
- `rf/` grows three parts: `rf/identity` (UID, name, version, API gating, auto-select),
  `rf/params` (a table-driven MSP parameter layer: one descriptor per message and API
  version, generic editors built from descriptors so a new Rotorflight field is a
  table row, not a screen), `rf/wizard` and `rf/backup` (sequenced MSP transactions
  with confirmation and rollback on error).
- `dash/flightlog` gains an `events` stream and the aircraft identity columns.
- `ui/` Heli screen becomes a set of pages: Overview, Setup wizard, Profiles, Rates,
  PIDs, Governor, Rescue, Mixer and Servos, Battery, ESC, Telemetry list, Backup,
  Events. Each page is generated from `rf/params` descriptors, so the screen count
  does not multiply the code.
- `link/msp` needs a request queue with priorities and a bulk mode for wizard, backup
  and page loads, and a clear "link too slow" indicator, since at 250 Hz and 1:64 a
  page of parameters can take seconds to load. The ELRS telemetry ratio should be
  raised automatically while a configuration page is open and restored afterwards,
  the same trick the Rotorflight Lua suite recommends by requiring a high baud and
  ratio.

## Consequences for scope, roadmap and decisions

- Scope (chapter 01): "Configuring Rotorflight from the radio beyond profile selection"
  moves from out of scope to in scope; the Configurator remains for hardware-level
  setup.
- Requirements (chapter 02): new section G in that chapter.
- Roadmap (chapter 04): phase 7 splits into 7a identity and wizard, 7b parameter
  editors and backup, 7c events and ESC; hardening becomes phase 8 as before. Estimate
  grows by about 6 to 8 weeks. [unverified: judgement]
- Decisions (chapter 05): Q-5 is answered by this pillar (tuning on the radio is in),
  and a new question Q-8 asks how far the wizard should go in writing FC settings.

## The risk this pillar adds

Writing to the FC from the radio means a mistaken write can make a helicopter
unflyable or unsafe. VBar accepts this because the radio and unit are one vendor's
tested pair. ZelionTX mitigates it with: every write goes through one `rf/params`
path with range checking from the descriptor table; writes are refused while armed;
the wizard shows a summary and asks once before `MSP_EEPROM_WRITE`; a backup is taken
automatically before the first write of a session; and the Heli screen shows the FC's
reboot-required and configuration-state flags.
