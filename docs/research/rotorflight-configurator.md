# Rotorflight Configurator: MSP payload layouts and telemetry definitions

Source: `rotorflight-configurator` at `725c7f1`, GPL-3.0, NW.js + jQuery + Svelte 5
hybrid. All multi-byte values little-endian (`src/js/injected_methods.js:36-50`).
API gate: `API_VERSION_RTFL_MIN 12.6.0`, `MAX 12.10.0` (`src/js/configurator.svelte.js`).
Payload layouts branch on 12.7 / 12.8 / 12.9 in `src/js/msp/MSPHelper.js`.

MSP framing (`src/js/msp.svelte.js`): codes <= 254 use MSP v1 (`$M<`, len8, code8,
payload, XOR checksum); codes > 254 use MSP v2 (`$X<`, flag, code16 LE, len16 LE,
payload, CRC8-DVB-S2 over bytes 3..end).

## MSP code table (`src/js/msp/MSPCodes.js`)

1 API_VERSION, 2 FC_VARIANT, 3 FC_VERSION, 4 BOARD_INFO, 5 BUILD_INFO, 10/11 NAME/SET,
12/13 PILOT_CONFIG/SET, 14/15 FLIGHT_STATS/SET, 32/33 BATTERY_CONFIG/SET, 34/35
MODE_RANGES/SET_MODE_RANGE, 36/37 FEATURE_CONFIG/SET, 42/43 MIXER_CONFIG/SET, 44/45
RX_CONFIG/SET, 52/53 ADJUSTMENT_RANGES/SET, 61/62 ARMING_CONFIG/SET, 64/65 RX_MAP/SET,
66/67 RC_CONFIG/SET, 68 SET_REBOOT, 73/74 TELEMETRY_CONFIG/SET, 75/76 FAILSAFE_CONFIG/SET,
94/95 PID_PROFILE/SET, 99 ARMING_DISABLE, 101 STATUS, 105 RC, 108 ATTITUDE, 109 ALTITUDE,
110 ANALOG, 111 RC_TUNING, 112 PID_TUNING, 113 RC_COMMAND, 114 RX_CHANNELS, 116 BOXNAMES,
119 BOXIDS, 120 SERVO_CONFIGURATIONS, 123 ESC_SENSOR_CONFIG, 130 BATTERY_STATE,
131 MOTOR_CONFIG, 139 MOTOR_TELEMETRY, 140/141 HELI_CONFIG/SET (no decoder), 142/143
GOVERNOR_CONFIG/SET, 144/145 RPM_FILTER/SET, 146/147 RESCUE_PROFILE/SET, 148/149
GOVERNOR_PROFILE/SET, 154/155 RPM_FILTER_V2/SET, 170/171 MIXER_INPUTS/SET, 172/173
MIXER_RULES/SET, 175/176 BATTERY_PROFILE/SET, 183 COPY_PROFILE, 190/191 MIXER_OVERRIDE,
192/193 SERVO_OVERRIDE, 194/195 MOTOR_OVERRIDE, 200 SET_RAW_RC, 202 SET_PID_TUNING,
204 SET_RC_TUNING, 205 ACC_CALIBRATION, 208 RESET_CONF, 210 SELECT_SETTING,
212 SET_SERVO_CONFIGURATION, 239/240 SET_ACC_TRIM/ACC_TRIM, 246/247 SET_RTC/RTC,
250 EEPROM_WRITE, 254 DEBUG. v2: 0x3000 BETAFLIGHT_BIND, 0x3003 SEND_DSHOT_COMMAND,
0x4000/1 SMARTFUEL_CONFIG/SET. There is no `MSP_ESC_SENSOR_DATA`; ESC live data comes via
`MSP_MOTOR_TELEMETRY` 139.

## Payload layouts (decode side, `MSPHelper.js process_data`)

- API_VERSION: u8 protocol, u8 major, u8 minor. FC_VARIANT: 4 ASCII chars ("RTFL").
  FC_VERSION: u8 major, minor, patch. BUILD_INFO: 11 chars date, 8 chars time, 7 chars
  git rev, u8 len + version string.
- BOARD_INFO: 4 chars identifier, u16 version, u8 type, u8 capabilities bits, four
  length-prefixed strings (target, board, design, manufacturer), 32 bytes signature,
  u8 mcu type, u8 configuration state (0 bare, 1 custom defaults, 2 configured), u16
  sample rate, u32 configuration problems.
- STATUS: u16 pid cycle us, u16 gyro cycle, u16 active sensors, u32 mode flags (bit i =
  i-th BOXNAMES entry), u8 compat, u16 RT load /10 %, u16 CPU load /10 %, u8 flag count +
  extra bytes, u8 arming-disable count, u32 arming-disable flags, u8 extra flags, u8
  configuration state, u8 PID profile (0-based), u8 num profiles, u8 rate profile, u8 num
  rate profiles, u8 motor count, u8 servo count, u8 gyro detection flags.
- BATTERY_STATE: u8 state, u8 cells, u16 capacity mAh, u16 used mAh, u16 voltage /100 V,
  u16 current /100 A, u8 charge %, (>= 12.9) u8 battery profile.
- ANALOG: u8 legacy voltage, u16 mAh, u16 rssi 0..1023, s16 amperage /100, u16 voltage /100.
- RC: N x u16. ATTITUDE: s16 roll /10, s16 pitch /10, s16 yaw deg. ALTITUDE: s32 /100 m.
- MOTOR_TELEMETRY: u8 count, per motor u32 rpm, u16 invalid percent (10000 = 100 %),
  u16 voltage mV, u16 current mA, u16 mAh, s16 temp 0.1 C, s16 temp2 0.1 C.
- RC_TUNING (rate profile): u8 rates_type; for roll, pitch, yaw, collective: u8 rc_rate
  /100, u8 expo /100, u8 srate /100, u8 response time, u16 accel limit; (>= 12.8)
  setpoint boost gain and cutoff per axis, yaw dynamic ceiling gain, deadband gain and
  filter; (>= 12.9) u8 cyclic ring, u8 cyclic polar. SET_RC_TUNING mirrors it.
- PID_TUNING: 3 axes x 4 u16 (P, I, D, F), then 3 x u16 B, then 2 x u16 O.
- PID_PROFILE: 43 u8 fields (pid mode, error decay times and limits, error rotation,
  error limits, gyro and dterm cutoffs, iterm relax, yaw stop gains, yaw precomp, feed
  forwards, level and horizon strengths, acro trainer, cross coupling, offset limits,
  bterm cutoffs), plus (>= 12.8) yaw inertia precomp gain and cutoff.
- RESCUE_PROFILE: u8 mode (0 off, 1 on, 2 on + alt hold), u8 flip mode, flip gain, level
  gain, pullup time, climb time, flip time, exit time, u16 pullup collective, climb
  collective, hover collective, hover altitude, alt P/I/D, max collective, max rate,
  max accel.
- GOVERNOR_PROFILE: u16 headspeed, u8 gain, P, I, D, F, TTA gain, TTA limit, yaw FF,
  cyclic FF, collective FF, max throttle, (>= 12.7) min throttle, (>= 12.9) fallback drop,
  u16 flags.
- GOVERNOR_CONFIG: u8 mode (>= 12.9: 0 OFF, 1 LIMIT, 2 DIRECT, 3 ELECTRIC, 4 NITRO), u16
  startup, spoolup, tracking, recovery, throttle hold timeout, lost headspeed timeout,
  autorotation timeout, bailout time, min entry time, u8 handover throttle, filters,
  (>= 12.8) spoolup min throttle, (>= 12.9) d filter, u16 spooldown, u8 throttle type,
  reserved, idle throttle, auto throttle, 9 x u8 bypass curve.
- SELECT_SETTING: one byte, `profileIndex` for PID profile or `rateIndex + 128` for rate
  profile, 0-based. EEPROM_WRITE: empty payload, often followed by SET_REBOOT.
- ARMING_DISABLE: u8 (1 = disable arming).
- TELEMETRY_CONFIG / SET: u8 inverted, u8 half duplex, u32 legacy sensor bitfield,
  (>= 12.7) u8 pinswap, u8 crsf_telemetry_mode (0 native, 1 custom), u16 rate Hz, u16
  ratio, then exactly **40 x u8 sensor id slots** (`CRSF_TELEMETRY_SENSOR_LENGTH 40`),
  zeros compacted on read and padded on write. Array order is transmission order.
- RX_CONFIG: u8 provider (CRSF = 9), u8 inverted, u8 half duplex, u16 pulse min, u16
  pulse max, u8 spi protocol, u32 spi id, u8 spi channel count, (>= 12.7) u8 pinswap.
- RX_MAP: N x u8. RC_CONFIG: u16 centre, u16 deflection, u16 arm throttle, u16 min
  throttle, u16 max throttle, u8 deadband, u8 yaw deadband.
- MODE_RANGES: 4 bytes per entry: u8 box id, u8 aux index, s8 start, s8 end
  (pwm = 1500 + 5 x v). MODE_RANGES_EXTRA: u8 count, per entry box id, logic (0 OR,
  1 AND), linked to. SET_MODE_RANGE: u8 index + 6 bytes.
- ADJUSTMENT_RANGES: 14 bytes per entry: u8 function, u8 enable channel, s8 start, s8 end,
  u8 adjust channel, s8 range1 start/end, s8 range2 start/end, s16 min, s16 max, u8 step.
  Channel 255 = always on.
- MOTOR_CONFIG: u16 min/max throttle, u16 min command, compat bytes, u8 dshot telemetry,
  u8 protocol, u16 pwm rate, u8 unsynced, 4 x u8 poles, 4 x u8 rpm lpf, 2 x u16 main gear
  ratio, 2 x u16 tail gear ratio.
- SERVO_CONFIGURATIONS: u8 count, 16 bytes per servo (u16 mid, s16 min, max, rneg, rpos,
  rate, u16 speed, s16 flags: bit0 reverse, bit1 geo correction).
- MIXER_CONFIG: u8 main rotor dir, u8 tail mode, u8 tail idle, s16 tail trim, u8 swash
  type (0 none, 1 direct, 2 CCPM120, 3 CCPM135, 4 CCPM140, 5 FPM90L, 6 FPM90V), u8 ring,
  s16 phase, u16 pitch limit, 3 x s16 trim, u8 rpm correction, s8 geo correction,
  (>= 12.8) tilt corrections.
- MIXER_INPUTS: 6 bytes per input (s16 rate, min, max); ids 0 none, 1-5 stabilised
  R/P/Y/C/T, 6-10 RC command, 11-15 RC channel, 16-18 AUX1-3, 19-28 CH9-18.
- BOXNAMES: `;`-separated names. BOXIDS: N x u8 permanent ids in the same order.

## CRSF custom telemetry sensor ids (`src/tabs/receiver/telemetry/sensors.js`)

The configurator stores ids and labels only, no units or scales. Max 40 enabled
sensors; list order is wire order. Ids: 0 NONE, 1 HEARTBEAT, 2 BATTERY, 3 BATTERY_VOLTAGE,
4 BATTERY_CURRENT, 5 BATTERY_CONSUMPTION, 6 BATTERY_CHARGE_LEVEL, 7 BATTERY_CELL_COUNT,
8 BATTERY_CELL_VOLTAGE, 9 BATTERY_CELL_VOLTAGES, 10 CONTROL, 11-14 PITCH/ROLL/YAW/
COLLECTIVE_CONTROL, 15 THROTTLE_CONTROL, 16 ESC1_DATA, 17-28 ESC1 VOLTAGE, CURRENT,
CAPACITY, ERPM, POWER, THROTTLE, TEMP1, TEMP2, BEC_VOLTAGE, BEC_CURRENT, STATUS, MODEL,
29 ESC2_DATA, 30-41 ESC2 same order, 42-45 ESC/BEC/BUS/MCU_VOLTAGE, 46-49 ESC/BEC/BUS/
MCU_CURRENT, 50-52 ESC/BEC/MCU_TEMP, 53-56 AIR/MOTOR/BATTERY/EXHAUST_TEMP, 57 HEADING,
58 ALTITUDE, 59 VARIOMETER, 60 HEADSPEED, 61 TAILSPEED, 62 MOTOR_RPM, 63 TRANS_RPM,
64 ATTITUDE, 65-67 ATTITUDE_PITCH/ROLL/YAW, 68 ACCEL, 69-71 ACCEL_X/Y/Z, 72 GPS,
73 GPS_SATS, 74 GPS_PDOP, 75 GPS_HDOP, 76 GPS_VDOP, 77 GPS_COORD, 78 GPS_ALTITUDE,
79 GPS_HEADING, 80 GPS_GROUNDSPEED, 81 GPS_HOME_DISTANCE, 82 GPS_HOME_DIRECTION,
83 GPS_DATE_TIME, 84 LOAD, 85-87 CPU/SYS/RT_LOAD, 88 MODEL_ID, 89 FLIGHT_MODE,
90 ARMING_FLAGS, 91 ARMING_DISABLE_FLAGS, 92 RESCUE_STATE, 93 GOVERNOR_STATE,
94 GOVERNOR_FLAGS, 95 PID_PROFILE, 96 RATES_PROFILE, 97 BATTERY_PROFILE, 98 LED_PROFILE,
99 ADJFUNC, 100-107 DEBUG_0..7, 108 RPM, 109 TEMP (native list only, >= 12.9).

Native mode (>= 12.8) offers FLIGHT_MODE, BATTERY, ATTITUDE, ALTITUDE, GPS (+RPM, TEMP on
>= 12.9). Below 12.8 native mode uses a legacy u32 bitfield.

## Modes and adjustments

Box ids are read live from BOXNAMES/BOXIDS; the only static list is demo data. The
locale also knows GOVERNOR FALLBACK / SUSPEND / BYPASS and MSP OVERRIDE. ARM is treated
as active when the arm-switch arming-disable flag is set.

Adjustment function ids and ranges (`src/js/tabs/adjustments.js`): 0 None, 1 RateProfile
1-6, 2 PIDProfile 1-6, 3 LEDProfile 1-4, 4 OSDProfile 1-3, 5-7 axis rates 0-255, 8-10 rc
rates, 11-13 expo 0-100, 14-25 PIDF 0-250, 26-27 yaw stop gains 25-250, 28-32 feed
forwards, 33-38 cutoffs, 39-40 rescue collectives 0-1000, 41 hover altitude 0-2500,
42-44 rescue alt PID, 45-47 level/horizon/trainer gains, 48-55 governor, 56-60 B and O,
61-63 cross coupling, 64-65 acc trim -300..300, (>= 12.8) 66-75 inertia precomp,
setpoint boost, yaw dynamics, (>= 12.9) 76-81 governor throttles/headspeed/yaw FF,
82 BatteryProfile 1-6.

## Rates tab

`rates_type` 0 NONE, 1 BETAFLIGHT, 2 RACEFLIGHT, 3 KISS, 4 ACTUAL, 5 QUICKRATES,
6 ROTORFLIGHT (>= 12.9 only). Six rate profiles. Rotorflight type labels "Rate / Shape /
Expo": Rate 10-1000 step 5 (default 250, yaw 400), Shape 0-127 (default 12), Expo 0-100
(default 40, yaw 50, collective 0), collective Rate 0-25 step 0.25 (default 12.5). Curve
`shape = srate/16 + 2; out = rcRate x (cmd x (1 - expo) + sign(cmd) x |cmd|^shape x expo)`
in deg/s. Shared per-axis dynamics: response time ms, max acceleration deg/s^2.

## Flight-mode and arming-disable strings

Flight mode: bit i of STATUS mode = i-th BOXNAMES entry. Arming-disable names
(`src/js/tabs/status.js`): 0 NO_GYRO, 1 FAILSAFE, 2 RX_FAILSAFE, 3 BAD_RX_RECOVERY,
4 BOXFAILSAFE, 5 GOVERNOR, 6 RPM_SIGNAL (>= 12.8; CRASH before), 7 THROTTLE, 8 ANGLE,
9 BOOT_GRACE_TIME, 10 NOPREARM, 11 LOAD, 12 CALIBRATING, 13 CLI, 14 CMS_MENU, 15 BST,
16 MSP, 17 PARALYZE, 18 GPS, 19 RESC, 20 RPMFILTER, 21 REBOOT_REQ, 22 DSHOT_BITBANG,
23 ACC_CALIB, 24 MOTOR_PROTO, (>= 12.9) 25 OVERRIDE, then ARM_SWITCH last.
Tooltips in `locales/en/messages.json:898-1010`.

Caveats: `MSP_HELI_CONFIG` has no decoder; telemetry units and scales are not in the
configurator, they come from the firmware.
