# Rotorflight FC and Lua scripts: what the transmitter must send and can receive

Sources: `rotorflight-firmware` at `33be766` (FC version 4.7.0, MSP API 12.10,
"Built on Betaflight 4.3", GPL-3.0) and `rotorflight-lua-scripts` at `220ce91`
(Lua suite version 2.3.0, GPL-3.0). FW = firmware repo, LUA = scripts repo.

## 1. Layout

`FW/src/main/`: `blackbox build cli cms common config drivers fc flight io msc msp osd
pg rx scheduler sensors startup target telemetry vcp`. Heli-specific: `flight/`
(`governor.c`, `rescue.c`, `mixer.c`, `servos.c`, `setpoint.c`, `leveling.c`,
`rpm_filter.c`), `fc/` (`rc.c`, `rc_rates.c`, `rc_adjustments.c`, `rc_modes.c`, `core.c`),
`telemetry/` (`crsf.c`, `sensors.c`, `msp_shared.c`), `msp/`, `rx/`.

## 2. RC input over CRSF

Parsing (`FW/src/main/rx/crsf.c`): 420000 baud on the FC side, sync 0xC8, max frame 64.
0x16 RC frames are accepted only when the device address byte is 0xC8. Also handled:
0x17 subset channels, 0x7A/0x7C MSP, 0x7D displayport, 0x14 link statistics (RSSI/LQ
source), 0x32 command (baud negotiation), 0x28 device ping (replies with device info).

Channel conversion (`crsf.c:591-610`): `us = 0.62477120195241 * raw + 881`
(172 -> 988, 992 -> 1500, 1811 -> 2012). 16 channels.

Range handling (`rx/rx.c`, `fc/rc.c`):
- Valid pulse 885..2115 us; final input constrained to 750..2250. **No per-channel
  rxrange calibration exists in Rotorflight.**
- Channel letters `AERCT12345678`; default map `AETRC123`. Internal order ROLL, PITCH,
  YAW, COLLECTIVE, THROTTLE, AUX1..AUX12. Resulting default CRSF assignment:
  **CH1 Roll (A), CH2 Pitch (E), CH3 Throttle (T), CH4 Yaw (R), CH5 Collective (C),
  CH6 AUX1, CH7 AUX2, ...**. Mode ranges index AUX channels as index + 5.
- **ELRS preset map (observed in the owner's Configurator, Receiver tab, 2026-09-11):**
  CH1 Roll, CH2 Pitch, CH3 Collective, CH4 Yaw, CH5 AUX1, CH6 Throttle, CH7 AUX2,
  CH8 AUX3, CH9-16 AUX4-AUX11, i.e. `AECR1T23`. This keeps collective and throttle
  off ELRS's one-bit channel 5 and puts ARM (AUX1) on it.
- `rcControlsConfig` defaults: `rc_center 1500`, `rc_deflection 510`, `rc_min_throttle 0`
  and `rc_max_throttle 0` (auto), `rc_deadband 5`, `rc_yaw_deadband 5`, `rc_smoothness 50`.
- Stick processing (`fc/rc.c:191-217`): `data = input - 1500; deadband; deflection =
  constrain(data / (510 - deadband), -1, 1)`. Collective has no deadband. Throttle:
  with defaults `minThrottle = 1041`, `maxThrottle = 1959`, `offThrottle = 1036`;
  `isThrottleOff()` is `input < 1036`. AUX: `command = input - 1500`.
- Smoothing is a single `rc_smoothness` parameter in the setpoint filter.
- Failsafe: control channels AUTO, AUX HOLD; `failsafe_procedure DROP_IT`,
  `failsafe_delay 15` (1.5 s).
- Mode ranges: `1500 + 5*step`, steps -125..125 (875..2125 us), active when
  `start <= value < end`. Up to 20 mode activation conditions with OR/AND logic and
  linking.

Box list (`FW/src/main/msp/msp_box.c:52-107`), name and permanent id:
ARM 0, ANGLE 1, HORIZON 2, TRAINER 47, ALTHOLD 3, RESCUE 53, GPS RESCUE 46, FAILSAFE 27,
PREARM 36, PARALYZE 45, BEEPER 13, BEEPER MUTE 52, LEDLOW 15, CALIB 17, OSD DISABLE 19,
TELEMETRY 20, GPS BEEP SATELLITE COUNT 37, BLACKBOX 26, BLACKBOX ERASE 31, CAMERA CONTROL
1/2/3 32/33/34, VTX PIT MODE 39, VTX CONTROL DISABLE 48, STICK COMMANDS DISABLE 51,
GOVERNOR FALLBACK 55, GOVERNOR SUSPEND 56, GOVERNOR BYPASS 57, USER1..4 40..43.

There is no "governor on/off", "rate profile" or "PID profile" box; profiles are switched
through adjustment functions or MSP. Flight-mode bits: FAILSAFE 0, ANGLE 1, HORIZON 2,
TRAINER 3, ALTHOLD 4, RESCUE 5, GPS_RESCUE 6.

## 3. Rates and expo live in the FC

Rate types: NONE 0, BETAFLIGHT 1, RACEFLIGHT 2, KISS 3, ACTUAL 4, QUICK 5,
ROTORFLIGHT 6. `controlRateConfig_t` has per-axis (roll, pitch, yaw, collective) rate,
expo, super rate, response time, acceleration limit, cyclic ring, setpoint boost, yaw
dynamic deadband. 6 PID profiles and 6 rate profiles on targets with more than 256 KB
flash.

Selection: adjustment functions `RATE_PROFILE 1`, `PID_PROFILE 2` driven by an AUX
channel; MSP `MSP_SELECT_SETTING 210` with one byte (bit7 set = rate profile); stick
commands only if `enable_stick_commands` (default off). `MSP_COPY_PROFILE 183`.

Consequence: **the transmitter must send linear, un-curved sticks**; TX-side expo or
rates would be applied twice.

## 4. Arming

Arming-disable flags (`runtime_config.h`, bit = index): 0 NOGYRO, 1 FAILSAFE, 2 RXLOSS,
3 BADRX, 4 BOXFAILSAFE, 5 GOVERNOR (string "RUNAWAY"), 6 RPM_SIGNAL (string "CRASH"),
7 THROTTLE, 8 ANGLE, 9 BOOTGRACE, 10 NOPREARM, 11 LOAD, 12 CALIB, 13 CLI, 14 CMS, 15 BST,
16 MSP, 17 PARALYZE, 18 GPS, 19 RESCUE_SW, 20 RPMFILTER, 21 REBOOT_REQD, 22 DSHOT_BBANG,
23 NO_ACC_CAL, 24 MOTOR_PROTO, 25 OVERRIDE, 26 ARMSWITCH.

Conditions (`fc/core.c:234-430`):
- Throttle must be off (`< 1036` us with defaults). Governor docs: "the throttle channel
  must be within the stop range".
- Boot grace `power_on_arming_grace_time 3` s; must be upright; CPU load; calibrating;
  PREARM if configured; **an active RESCUE switch blocks arming**; PARALYZE; overrides.
- Arm switch safety: if the link recovers while ARM is active, `BAD_RX_RECOVERY` until
  the switch is turned off. If arming is blocked while ARM is on, `ARM_SWITCH` is latched
  until the switch goes off, so the switch must be cycled after fixing a blocker and in
  practice must be off at boot.
- Stick arming only if no ARM range exists and `enable_stick_arming` (default off).
  Switch path: ARM box on -> `tryArm()`; off -> disarm after more than 3 consecutive
  frames with valid signal and no failsafe.
- Feedback: swashplate wiggle on ready/error/fatal. Flight-mode telemetry string reads
  "DISABLED" when arming is blocked.

## 5. Telemetry over CRSF (`FW/src/main/telemetry/crsf.c`)

Frame types: GPS 0x02, VARIO 0x07, BATTERY 0x08, ALTITUDE 0x09, HEARTBEAT 0x0B, RPM 0x0C,
TEMP 0x0D, LINK_STATISTICS 0x14, ATTITUDE 0x1E, FLIGHT_MODE 0x21, DEVICE_PING 0x28,
DEVICE_INFO 0x29, MSP_REQ 0x7A, MSP_RESP 0x7B, MSP_WRITE 0x7C, DISPLAYPORT 0x7D,
**CUSTOM_TELEM 0x88**.

Native frames (big-endian): 0x02 GPS (lat, lon deg*1e7, speed km/h*10, heading
deg*100, altitude m+1000, sats); 0x07 vario cm/s; 0x09 altitude dm+10000 plus vario;
0x08 battery (0.1 V, 0.1 A, u24 mAh, %); 0x0B heartbeat; 0x0C RPM (source 0, s24
headspeed, s24 tailspeed); 0x0D temp (source 0, s16 MCU 0.1 C, s16 ESC 0.1 C); 0x1E
attitude rad*10000; 0x21 flight mode string; 0x29 device info "Rotorflight 4.7.0".

Modes and scheduling: `crsf_telemetry_mode` 0 NATIVE (default) or 1 CUSTOM;
`crsf_telemetry_link_rate` default 250, `crsf_telemetry_link_ratio` default 8;
`telemetry_sensors[40]` slots. **Sensor slots default to all zero and nothing populates
them**; with a factory config only heartbeat, device info and MSP are sent until the list
is configured through `MSP_SET_TELEMETRY_CONFIG 74`. Rate limiter: token bucket with
`link_rate / ratio` slots per second, a frame of N bytes costs `(N+9)/5` slots; no
telemetry during boot grace. Send order per tick: MSP response, displayport, device
info, native sensor, custom frame, populate, heartbeat. Each sensor is scheduled at its
fast interval when the value changed, otherwise its slow interval.

In NATIVE mode only FLIGHT_MODE, BATTERY, ATTITUDE, ALTITUDE, GPS, RPM, TEMP exist.

### Custom telemetry frame 0x88

Header `[0x88][dest 0xEA][origin 0xC8][frameId u8]`, then repeated
`[appId u16 BE][payload per encoder]` while more than 32 bytes remain. `frameId`
increments per frame so the TX can count skips. On startup in CUSTOM mode the FC sends
the NONE sensor (0x1000) about 10 times, then every configured sensor once in configured
order (a discovery pass), then normal scheduling.

Encoders: U8/S8/U16/S16/U24/S24/U32/S32 clamped; CellVolt = u8 (avg cell in 0.01 V
clamped 200..455, minus 200); Cells = u8 count + count x u8; Control = 6 bytes packing
four signed 12-bit values; Attitude = 3 x s16 decidegrees; Accel = 3 x s16 0.01 g;
LatLong = 2 x s32 deg*1e7; AdjFunc = u16 function id + s32 value.

| appId | id | name | enc | unit | fast/slow ms |
|---|---|---|---|---|---|
| 0x1000 | 0 | NONE | none | | 1000 |
| 0x1001 | 1 | BEAT | U16 | ms % 60000 | 1000 |
| 0x1011 | 3 | Vbat | U16 | 0.01 V | 200/3000 |
| 0x1012 | 4 | Curr | U16 | 0.01 A | 200/3000 |
| 0x1013 | 5 | Capa | U16 | mAh | 200/3000 |
| 0x1014 | 6 | Bat% | U8 | % | 200/3000 |
| 0x1020 | 7 | Cel# | U8 | cells | 200/3000 |
| 0x1021 | 8 | Vcel | CellVolt | (v+200) x 0.01 V | 200/3000 |
| 0x102F | 9 | Cels | Cells | inactive in firmware | |
| 0x1030 | 10 | Ctrl | Control | packed 12-bit | 100/3000 |
| 0x1031-34 | 11-14 | CPtc/CRol/CYaw/CCol | S16 | 0.1 deg | 200/3000 |
| 0x1035 | 15 | Thr | S8 | % | 200/3000 |
| 0x1041 | 17 | EscV | U16 | 0.01 V | 200/3000 |
| 0x1042 | 18 | EscI | U16 | 0.01 A | 200/3000 |
| 0x1043 | 19 | EscC | U16 | mAh | 200/3000 |
| 0x1044 | 20 | EscR | U24 | eRPM | 200/3000 |
| 0x1045 | 21 | EscP | U16 | 0.1 % | 200/3000 |
| 0x1046 | 22 | Esc% | U16 | 0.1 % | 200/3000 |
| 0x1047 | 23 | EscT | U8 | C | 200/3000 |
| 0x1048 | 24 | BecT | U8 | C | 200/3000 |
| 0x1049 | 25 | BecV | U16 | 0.01 V | 200/3000 |
| 0x104A | 26 | BecI | U16 | 0.01 A | 200/3000 |
| 0x104E | 27 | EscF | U32 | vendor status bits | 200/3000 |
| 0x104F | 28 | Esc# | U8 | vendor id | 200/3000 |
| 0x1051.. | 30.. | Es2V/Es2I/Es2C/Es2R/Es2T/Es2# | as ESC1 | | |
| 0x1080-83 | 42-45 | Vesc/Vbec/Vbus/Vmcu | U16 | 0.01 V | 200/3000 |
| 0x1090-93 | 46-49 | Iesc/Ibec/Ibus/Imcu | U16 | 0.01 A | 200/3000 |
| 0x10A0 | 50 | Tesc | U8 | C | 500/3000 |
| 0x10A1 | 51 | Tbec | U8 | C | 500/3000 |
| 0x10A3 | 52 | Tmcu | U8 | C | 500/3000 |
| 0x10B1 | 57 | Hdg | S16 | 0.1 deg | 200/3000 |
| 0x10B2 | 58 | Alt | S24 | cm | 200/3000 |
| 0x10B3 | 59 | Var | S16 | cm/s | 200/3000 |
| 0x10C0 | 60 | Hspd | U16 | rpm | 200/3000 |
| 0x10C1 | 61 | Tspd | U16 | rpm | 200/3000 |
| 0x1100 | 64 | Attd | Attitude | 3 x 0.1 deg | 100/3000 |
| 0x1101-03 | 65-67 | Ptch/Roll/Yaw | S16 | deg | 200/3000 |
| 0x1110 | 68 | Accl | Accel | 3 x 0.01 g | 100/3000 |
| 0x1111-13 | 69-71 | AccX/Y/Z | S16 | 0.1 g | 200/3000 |
| 0x1121 | 73 | Sats | U8 | count | 500/3000 |
| 0x1123 | 75 | HDOP | U8 | raw | 500/3000 |
| 0x1125 | 77 | GPS | LatLong | deg*1e7 | 200/3000 |
| 0x1126 | 78 | GAlt | S16 | cm | 200/3000 |
| 0x1127 | 79 | GHdg | S16 | 0.1 deg | 200/3000 |
| 0x1128 | 80 | GSpd | U16 | cm/s | 200/3000 |
| 0x1129 | 81 | GDis | U16 | distance to home | 200/3000 |
| 0x112A | 82 | GDir | S16 | direction to home | 200/3000 |
| 0x1141-43 | 85-87 | CPU%/SYS%/RT% | U8 | % | 500/3000 |
| 0x1200 | 88 | MDL# | U8 | model id | 200/3000 |
| 0x1201 | 89 | Mode | U16 | flight mode bits | 200/3000 |
| 0x1202 | 90 | ARM | U8 | bit0 ARMED, bit1 WAS_EVER_ARMED, bit2 WAS_ARMED_WITH_PREARM | 200/3000 |
| 0x1203 | 91 | ARMD | U32 | arming-disable bitmask | 200/3000 |
| 0x1204 | 92 | Resc | U8 | 0 OFF,1 PULLUP,2 FLIP,3 CLIMB,4 HOVER,5 EXIT | 200/3000 |
| 0x1205 | 93 | Gov | U8 | 0 THROTTLE_OFF,1 IDLE,2 SPOOLUP,3 RECOVERY,4 ACTIVE,5 THROTTLE_HOLD,6 FALLBACK,7 AUTOROTATION,8 BAILOUT,9 BYPASS | 200/3000 |
| 0x1211 | 95 | PID# | U8 | 1-based | 200/3000 |
| 0x1212 | 96 | RTE# | U8 | 1-based | 200/3000 |
| 0x1213 | 98 | LED# | U8 | inactive | |
| 0x1214 | 97 | BAT# | U8 | 1-based | 200/3000 |
| 0x1220 | 99 | ADJ | AdjFunc | u16 id + s32 value | 200/3000 |
| 0xDB00-07 | 100-107 | DBG0-7 | S32 | debug | 100/3000 |

Lua decoder table: `LUA/src/SCRIPTS/RF2/rf2tlm_sensors.lua`; frame parser
`LUA/src/SCRIPTS/RF2/rf2tlm.lua` (reads frameId at byte 3, loops `sid u16 -> decoder`,
stops on unknown sid, counts frames and skips).

Flight-mode string (`crsf.c:466-497`): "DISABLED" (disarmed and arming blocked),
"GPS-WAIT", "FAILSAFE", "GPS-RESCUE", "RESCUE", "HORIZON", "ANGLE", "NORMAL", followed by
`*` if armed else a space. A governor-state string variant exists but its call is
commented out.

## 6. MSP over CRSF

Inbound 0x7A/0x7C frames buffered from payload byte 2; the reply goes to the request's
origin address. Response frame `[0x7B][origin][0xC8][status][MSP body]`, chunk payload
up to 58 bytes; TX-to-FC chunk up to 8 bytes. Status byte: bits 0-3 sequence, bit 4 start
of frame, bits 5-6 MSP version (1 or 2), bit 7 error. First chunk v2:
`[status][flags][cmd lo][cmd hi][size lo][size hi]...`; v1: `[status][size][cmd]...`.
Continuation `[status][data]`. MSP checksum is not sent over CRSF. Request buffer 192,
response buffer 320. After `MSP_EEPROM_WRITE` the FC skips 5 telemetry requests.

Lua transport (`LUA/src/SCRIPTS/RF2/MSP/crsf.lua`): pushes
`crossfireTelemetryPush(0x7C, {0xC8, 0xEA, status, ...})` in 8-byte chunks, version bit
2 if cmd > 255, retries every 0.8 s, infinite retries unless the error flag is set.

Identity: `MSP_API_VERSION 1` -> `[0, 12, 10]`; `MSP_FC_VARIANT 2` -> "RTFL";
`MSP_FC_VERSION 3` -> `[4,7,0]`. `MSP_STATUS 101`: u16 pid dt, u16 gyro dt, u16 sensors,
u32 box flags, u8, u16 RT load, u16 CPU load, u8, u8 arming-flag count (27), u32 arming
disable flags, u8 reboot required, u8 config state, u8 PID profile, u8 PID count, u8
rate profile, u8 rate count, u8 motors, u8 servos. `MSP_BATTERY_STATE 130`: u8 state,
u8 cells, u16 capacity, u16 used, u16 V (10 mV), u16 I (10 mA), u8 %, u8 profile.
`MSP_TELEMETRY_CONFIG 73 / SET 74` carry mode, link rate, link ratio and the 40 sensor ids.

Heli-specific MSP v1 codes: PILOT_CONFIG 12/13, FLIGHT_STATS 14/15, BATTERY_CONFIG 32/33,
MODE_RANGES 34/35, MIXER_CONFIG 42/43, ADJUSTMENT_RANGES 52/53, RC_CONFIG 66/67,
TELEMETRY_CONFIG 73/74, PID_PROFILE 94/95, RC_TUNING 111/204, PID_TUNING 112/202,
RC_COMMAND 113, RX_CHANNELS 114, SETPOINT 115, ESC_SENSOR_CONFIG 123/216,
MOTOR_TELEMETRY 139, GOVERNOR_CONFIG 142/143, RPM_FILTER 144/145, RESCUE_PROFILE 146/147,
GOVERNOR_PROFILE 148/149, RPM_FILTER_V2 154/155, GET_ADJUSTMENT_RANGE 156,
GET_ADJUSTMENT_FUNCTION_IDS 167, MIXER_INPUTS 170/171, MIXER_RULES 172/173,
BATTERY_PROFILE 175/176, COPY_PROFILE 183, MIXER_OVERRIDE 190/191, SERVO_OVERRIDE
192/193/196, MOTOR_OVERRIDE 194/195, SELECT_SETTING 210, ESC_PARAMETERS 217/218,
ACC_TRIM 240/239, ACC_CALIBRATION 205, EEPROM_WRITE 250. MSP v2: SMARTFUEL 0x4000/1,
FBUS 0x5F07..0x5F0A.

## 7. Lua scripts repo

Structure: `TOOLS/rf2.lua`, `FUNCTIONS/rf2bg.lua`, `RF2/` (core `rf2.lua`, `pages.lua`,
`radios.lua`, `protocols.lua`, `background.lua`, `adj_teller.lua`, `rf2tlm.lua`,
`rf2tlm_sensors.lua`, UI backends for LCD and LVGL, per-resolution templates 128x64 to
800x480, `MSP/` transport and one file per command, `MSP/RATES/*`, `PAGES/`),
`WIDGETS/RfTool`, `WIDGETS/RfStats`.

Pages: Status, Rates, Rate Dynamics, PID Gains, PID Controller, Profile Various, Rescue,
Governor profile, Battery, Smart Fuel, Servos, Mixer, Gyro Filters, Governor, Accelerometer
Trim, ESC Sensor, Model, Experimental, ESC vendor pages (AM32, BLHeli_S, Bluejay,
FLYROTOR, HW Platinum V5, Scorpion Tribunus, XDFly/OMP/ZTW, YGE), Settings. Profile and
rate selection uses `MSP_STATUS` then `MSP_SELECT_SETTING`.

Radio compatibility: protocol probing via `crossfireTelemetryPush` etc.; supported
resolutions hard-coded; requires EdgeTX 2.5+ and **ELRS TX module baud >= 1.87 M**
(`LUA/README.md:17-25`). Background script on connect: `MSP_API_VERSION`, `MSP_NAME`,
`MSP_PILOT_CONFIG` (sets TX timers and GV1-9 from FC `model_param1..3`, sets model name),
`MSP_TELEMETRY_CONFIG` (reads mode and the 40 ids to build the decoder), `MSP_SET_RTC`.

Adjustment functions (`rc_adjustments.h`, count 83): 1 RATE_PROFILE, 2 PID_PROFILE,
3 LED_PROFILE, 4 OSD_PROFILE, 5-7 P/R/Y srate, 8-10 rc rate, 11-13 expo, 14-25 PIDF
gains per axis, 26-27 yaw stop gains, 28-32 yaw and pitch feed-forwards, 33-38 cutoffs,
39-44 rescue, 45-47 level and trainer gains, 48-55 governor gains, 56-60 B and O gains,
61-63 cross coupling, 64-65 acc trim, 66-67 inertia precomp, 68-71 setpoint boost,
72-75 yaw dynamics, 76-81 governor throttles and headspeed, 82 BATTERY_PROFILE.
`adjustmentRange_t`: function, enable channel (0xff always), enable range, adjust
channel, range1, range2, min, max, step; up to 42 ranges. Stepped mode decrements in
range1 and increments in range2 with 100 ms trigger and 200 ms repeat; continuous mode
maps range1 linearly to min..max. Changes beep and mark config dirty but are not saved.

## 8. Docs on TX setup

`FW/docs/Governor.md`: throttle channel has a stop range and an active range mapped
0-100 % from the receiver microsecond settings (example 1100-1900 us on ELRS, 988/2012
endpoints); arming requires the stop range; handover throttle default 25 %; throttle
types NORMAL (stick or switch, full resolution), SWITCH (idle region direct, above
handover the value selects target headspeed), FUNCTION (thirds: <33 % idle, <66 % auto,
else run; ELRS example OFF 988 / IDLE 1250 / AUTO 1500 / RUN 1750 us). Explicit note that
ELRS wide low-resolution channels are unsuitable for NORMAL and SWITCH types. Governor
modes OFF/LIMIT/DIRECT/ELECTRIC/NITRO.

Not found in either repo: a recommended switch layout, a recommended ELRS packet rate, or
a recommended telemetry ratio.

## 9. Transmitter vs FC responsibilities (from code)

Transmitter must:
1. Send 0x16 RC frames where 172/992/1811 map to 988/1500/2012 us; default map CH1 Roll,
   CH2 Pitch, CH3 Throttle, CH4 Yaw, CH5 Collective, CH6+ AUX.
2. Send linear sticks centred at 1500 with +/-510 us travel; no expo, rates, curves or
   collective pitch curves.
3. Present a throttle channel whose off state is below about 1036 us (988 on ELRS) and
   whose active range matches the FC's throttle range; for SWITCH/FUNCTION governor
   throttle types, discrete switch-driven levels. Throttle must be off to arm.
4. Drive AUX channels for modes (ARM, optionally PREARM, RESCUE, ANGLE/HORIZON/TRAINER,
   BEEPER, BLACKBOX, GOVERNOR BYPASS/SUSPEND/FALLBACK, USER1-4) in 5 us steps; ARM must be
   off after link recovery and cycled after any block.
5. Optionally drive AUX channels for adjustment functions.
6. Decode native frames and the 0x88 custom frame; optionally read
   `MSP_TELEMETRY_CONFIG` to learn the configured list, or rely on the startup discovery
   pass.
7. Speak MSP over CRSF for identity, status, profile switching, RTC and EEPROM write if
   wanted.

FC owns: rates/expo and 6 rate profiles; PIDs and 6 PID profiles; governor; rescue;
leveling; mixer/swash/servos; deadband and smoothing; arming logic and safety flags;
failsafe; battery and ESC sensing and cell counting; adjustment semantics; telemetry
sensor selection, intervals and rate limiting; model name and per-model TX parameters via
`MSP_PILOT_CONFIG`.
