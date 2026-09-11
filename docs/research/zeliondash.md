# ZelionDash (existing EdgeTX Lua widget) notes

Source: `gcholdingscorporation/zelionpowerflightdashboard` at `fc6b953` (release 1.5.1).
No LICENSE file in the repository.

## What it is

An EdgeTX Lua full-screen widget for Rotorflight electric helicopters, verified on a
TX16S Mk3 (800x480) and a TX15 (480x320) across three helicopters (200-size on 3S, M7R
on 12S, M4 Max on 6S). Requires EdgeTX 2.11+. About 5.9k lines of Lua in `src/`, 5.4k
lines of tests (337 tests) in `tests/`, a mock EdgeTX host and screen renderer in `tools/`.

## Module layout (already layered; this is the structure a native port keeps)

| File | Lines | Role |
|---|---|---|
| `host.lua` | 596 | Host adapter: the only place EdgeTX APIs are touched (getTime, getValue, getFieldInfo, model.getSensor, playNumber/Tone/Haptic/File, lcd.sizeText, timers, file IO) |
| `roles.lua` | 238 | Role definitions: a role such as `headspeed` lists candidate sensor names, unit hint, sanity window, whether integer, which extreme to track |
| `sensors.lua` | 293 | Resolver: binds each role to a real sensor by override, then name, then unique unit; re-probes unbound roles every second |
| `state.lua` | 714 | State model: current value, validity, session extremes, arm/session logic, resting voltage capture, decay detection ("shown but not trusted") |
| `alerts.lua` | 345 | Alert engine: hysteresis, repeat timers, 4 s settle, once-per-pack checks, spoken values |
| `profiles.lua` | 222 | Aircraft profile (auto from pack voltage): plausibility windows, flying-RPM threshold, ESC temp threshold; self-correcting |
| `escfault.lua` | 183 | Decodes ESC status word for HobbyWing V5, Scorpion, OpenYGE; others shown undecoded |
| `flightlog.lua` | 380 | One CSV line per flight to `/LOGS/zeliondash.csv`, append-only columns, 200 flights kept |
| `flighttime.lua` | 199 | Time-remaining estimate from mAh used and percent, drives an EdgeTX timer, monotonic |
| `packhealth.lua` | 173 | Internal resistance per cell from V-vs-I regression over 3 s windows, median per flight |
| `rf2.lua` | 287 | Optional integration with the Rotorflight RF Tool `rf2` global for link state and FC flight stats (MSP_FLIGHT_STATS, API >= 12.09) |
| `config.lua` | 229 | `sensors.cfg` parsing, per-model sections |
| `dashboard.lua`, `layout.lua`, `theme.lua`, `widget.lua` | ~1.9k | Rendering, density classes (roomy 800x480, tight 480x320/480x272), widget lifecycle, sensor map diagnostics screen |

## Roles and the Rotorflight sensor names they expect

headspeed (Hspd, RPM), tailSpeed (Tspd), packVoltage (Vbat), cellVoltage (Vcel),
cellCount (Cel#), batteryPercent (Bat%), current (Curr), capacity (Capa), power,
becVoltage (Vbec), escTemperature (Tesc), mcuTemperature (Tmcu), governor (Gov),
armFlags (ARM), throttle (Thr), batteryProfile (BAT#), escSignature (Esc#), escStatus
(EscF), linkQuality (RQly, TQly), rssi1 (1RSS), rssi2 (2RSS), txVoltage, flightMode (FM).
Important roles: headspeed, packVoltage, current, batteryPercent, escTemperature, governor.

Every one of these names is a Rotorflight custom-telemetry sensor (appIds 0x1011..0x1220)
or an ELRS link-statistics field, so a native decoder can bind roles directly to appIds
and the name/unit guessing layer becomes unnecessary.

## Behaviours worth preserving verbatim in a native port

- Missing sensor and a sensor reading zero must never look the same (validity flag).
- Telemetry serviced at 10 Hz; nothing on a heli dashboard changes usefully faster.
- Alerts: cell 3.40 V / clear 3.50 V, ESC temp 110 C / clear 102 C, governor fault
  (THR-OFF, LOST-HS, AUTOROT), link lost or LQ 30 / clear 45; spoken through the radio's
  number vocabulary; silent for the first 4 s; hold switch silences.
- Main-power-lost detection: a monotonically falling voltage is displayed but not trusted
  for minima or the low-cell alarm; if it never stops, "MAIN POWER LOST" with BEC voltage
  read out every 6 s, flight only.
- Pack-charged check once per pack 8 s after settle.
- ESC fault decoding only for vendors with documented layouts; `0xFF` signature means
  "restart to apply settings", not a fault.
- Flight log columns only ever appended; flights under 20 s not logged; resting voltages
  sampled while disarmed and frozen at arm.
- Time remaining needs no pack size; reaches zero at a 20 % reserve; only ever falls.
- Arm and hold switch polarity are user options (Arm Invert, Hold Invert).
- Aircraft profile auto-detects from pack voltage, latches, and un-latches if it keeps
  rejecting readings the role accepts.

## EdgeTX pain points the widget documents (all disappear in a native build)

- `.luac` bytecode cache with timestamp comparison silently runs stale code.
- Widget options have no list type, so profile is a number.
- Only a handful of fixed font sizes, so layouts rearrange rather than scale.
- Widget zone clipping when not in a full-screen slot.
- Throttle role guessed onto the wrong percent sensor (TQly) because sensor discovery is
  by name and unit rather than by protocol id.
- Sensor discovery order on the radio matters; scripts advise deleting all sensors and
  rediscovering.
