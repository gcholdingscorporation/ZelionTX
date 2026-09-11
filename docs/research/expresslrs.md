# ExpressLRS handset-to-module interface notes

Source: ExpressLRS at `a60b68a` (2026-09-10). Paths relative to `src/`. This is the
post-3.5 refactored code: `lib/CrsfProtocol` (router/endpoint/parameter framework),
`lib/Handset` (handset UART), `lib/tx-crsf` (TX-module endpoint and parameter table).

## 1. Layout, targets, builds

- `src/src/tx_main.cpp` (TX firmware), `rx_main.cpp`, `common.cpp` (air-rate tables).
- `src/include/crsf_protocol.h` (CRSF definitions), `common.h` (rate/tlm/switch enums),
  `telemetry_protocol.h`.
- `src/lib/`: `CrsfProtocol/`, `Handset/` (`CRSFHandset.cpp/.h`, `PPMHandset`,
  `AutoDetect`), `tx-crsf/` (`TXModuleEndpoint.cpp`, `TXModuleParameters.cpp`,
  `TXOTAConnector`), `OTA/`, `MSP/`, `CRSF2MSP/`, `Backpack/`, `CRC/`, `CONFIG/`, radio
  drivers, WiFi, BLE, screen, VTX.
- `src/lua/elrs.lua` (967 lines) is the single Lua configurator; version-suffixed
  variants are obsolete.
- Hardware pin definitions live in the separate `ExpressLRS/targets` repo and are read
  from `/hardware.json` at runtime.
- MCUs: ESP32, ESP32-S3, ESP32-C3, ESP8285 only. No STM32 targets remain.
- TX vs RX: `-DTARGET_TX=1` / `-DTARGET_RX=1`. Env names such as
  `Unified_ESP32_2400_TX_via_ETX|UART|WIFI` ("via_ETX" is the upload path through the
  handset, not a different firmware).

## 2. CRSF as implemented (`include/crsf_protocol.h`)

- CRC-8 poly 0xD5, init 0, MSB-first, no reflection (`lib/CRC/crc.cpp:3-30`), computed
  over TYPE byte through end of payload (excludes sync and length).
- `CRSF_SYNC_BYTE 0xC8`, `CRSF_MAX_PACKET_LEN 64` total on wire, payload max 62.
  Length byte counts type + payload + CRC.
- Header `{sync, frame_size, type, payload[]}`. Extended header
  `{device_addr, frame_size, type, dest_addr, orig_addr, payload[]}` used for every
  type `>= 0x28`. On the serial wire byte 0 is always 0xC8 regardless of destination;
  the handset parser accepts 0xEE or 0xC8 as first byte.

Addresses: BROADCAST 0x00, USB 0x10, BLUETOOTH_WIFI 0x12, CURRENT_SENSOR 0xC0, GPS 0xC2,
FLIGHT_CONTROLLER 0xC8, RADIO_TRANSMITTER 0xEA, CRSF_RECEIVER 0xEC, CRSF_TRANSMITTER 0xEE,
ELRS_LUA 0xEF.

Frame types: GPS 0x02, GPS_TIME 0x03, VARIO 0x07, BATTERY_SENSOR 0x08, BARO_ALTITUDE 0x09,
AIRSPEED 0x0A, HEARTBEAT 0x0B, RPM 0x0C, TEMP 0x0D, CELLS 0x0E, LINK_STATISTICS 0x14,
RC_CHANNELS_PACKED 0x16, ATTITUDE 0x1E, FLIGHT_MODE 0x21, DEVICE_PING 0x28,
DEVICE_INFO 0x29, PARAMETER_SETTINGS_ENTRY 0x2B, PARAMETER_READ 0x2C,
PARAMETER_WRITE 0x2D, ELRS_STATUS 0x2E, COMMAND 0x32, HANDSET 0x3A (the "radio id" /
OpenTX sync type), KISS_REQ 0x78, KISS_RESP 0x79, MSP_REQ 0x7A, MSP_RESP 0x7B,
MSP_WRITE 0x7C, ARDUPILOT_RESP 0x80.

Sub-commands: `CRSF_COMMAND_SUBCMD_RX 0x10`, `RX_BIND 0x01`, `MODEL_SELECT_ID 0x05`,
`CRSF_HANDSET_SUBCMD_TIMING 0x10`.

Channel values: 172 = 988 us (-100%), 992 = 1500 us, 1811 = 2012 us (+100%), extended
0..1984 = 880..2120 us. `us = 0.625 * crsf + 880.5`. Helpers `CRSF_to_N`, `N_to_CRSF`,
`CRSF_to_SWITCH3b`, `CRSF_to_BIT` (>992 -> 1), `BIT_to_CRSF` (191/1792).

`crsf_channels_t`: 16 x 11-bit little-endian bitfields, 22 bytes. RC frame
`[0xC8][0x18][0x16][22 bytes][CRC]`. ELRS extension: optional 23rd payload byte
(frame_size 25) with bit0 = armed, bit1 = "arming mode is CH5".

Telemetry payloads (big-endian):
- 0x14 link statistics (10 bytes): uplink RSSI1, RSSI2 (dBm * -1), uplink LQ %, uplink
  SNR (i8 dB), active antenna, rf_Mode (rate enum), uplink TX power (enum), downlink
  RSSI1, downlink LQ, downlink SNR.
- 0x08 battery: voltage u16 0.1 V, current u16 0.1 A, capacity u24 mAh, remaining u8 %.
- 0x02 GPS: lat/lon i32 deg*1e7, speed u16 km/h*10, heading u16 deg*100, altitude
  u16 m+1000, sats u8.
- 0x1E attitude: pitch/roll/yaw i16 rad*10000. 0x21 flight mode: char[16].
- 0x09 baro `{u16 altitude dm+10000, i16 vspeed cm/s}`, 0x07 vario `{i16 cm/s}`,
  0x0C RPM `{source_id, int24 rpm[]}`, 0x0D temp `{source_id, i16 deci-C[]}`,
  0x0E cells `{source_id, u16 mV[]}`.
- 0x0B heartbeat: BE i16 origin address.
- 0x29 device info: after ext header `name\0`, u32 serialNo, u32 hardwareVer,
  u32 softwareVer, u8 fieldCnt, u8 parameterVersion. ELRS sets serialNo 0x454C5253
  ("ELRS"), softwareVer e.g. 0x00030500 for 3.5.0.
- 0x3A sync: u8 subType 0x10, u32 rate BE, u32 offset BE.
- 0x2E ELRS status: u8 pktsBad, u16 pktsGood BE, u8 flags, `msg\0`.
- MSP sizes: request payload 8, response payload 58.

Parameter value types: UINT8 0, INT8 1, UINT16 2, INT16 3, UINT32 4, INT32 5, UINT64 6,
INT64 7, FLOAT 8, TEXT_SELECTION 9, STRING 10, FOLDER 11, INFO 12, COMMAND 13, VTX 15;
`CRSF_FIELD_HIDDEN 0x80` OR-ed into the type byte.

## 3. Handset UART on the module (`lib/Handset/CRSFHandset.cpp`)

- Half duplex when RX and TX pins are the same (external bay S.Port style); full duplex
  with separate pins (typical internal module). ESP32 uses UART0. Half duplex starts
  inverted, full duplex starts non-inverted; auto-baud alternates inversion.
- Baud list `{400000, 115200, 5250000, 3750000, 1870000, 921600, 2250000}` (:42).
  ESP32 measures the pulse width with hardware autobaud and snaps to the nearest entry;
  ESP8285 cycles the list. Auto-baud runs from `UARTwdt()` every 1000 ms when bad >= good
  frames or not connected. A baud outside the list is never accepted.
- Connection: any CRC-valid frame marks the handset connected (:201-215). Disconnect
  stops the hardware timer and forces LQ 0.
- Minimum RC interval by baud (:413-428): 115200 half duplex 5000 us, 115200 full duplex
  4000 us, 400000 -> 2000 us (500 Hz), faster -> 1 us (1000 Hz allowed). The configured
  air rate is demoted to fit and the Lua flag "Baud rate too low" is raised.
- Expected RC interval: `setPacketInterval(interval * numOfSends)` on every rate change
  (`tx_main.cpp:513`): 250 Hz -> 4000 us, 500 Hz -> 2000 us, F1000 -> 1000 us,
  D250 -> 4000 us. Default 5000 us.
- Sync (0x3A) built in `sendSyncPacketToTX()` (:169-199): `rate = interval * 10`
  (units 0.1 us), `offset = measured - 1000` (100 us safety margin). Sent at most every
  200 ms and only right after a valid handset frame; the module never speaks unless the
  handset just spoke. Offset measured in the timer ISR as time since the last handset
  frame, averaged over about 20 ms worth of packets; a late frame forces an immediate
  resync.
- Wrong interval: frames are not rejected. Channel data is latched on receipt and the OTA
  timer sends whatever is latched. No RC frame for >1 s stops RF entirely (receiver
  failsafes). Faster than OTA rate: frames overwritten. Slower: stale data repeats.
- Output budget: `maxPeriodBytes = min(baud/10/(1e6/interval)*0.87, 128)`,
  `maxPacketBytes = min(maxPeriodBytes - max(maxPeriodBytes/2, 26), 64)`; this is also the
  Lua chunk size. Handset telemetry FIFO assumed 128 bytes per period. Module output FIFO
  256 bytes; frames that do not fit are dropped; nothing queued while disconnected.

## 4. Telemetry flow to the handset

- Downlink data reassembled by the stubborn receiver into a 65-byte buffer, pushed into
  the router as coming from the OTA connector and forwarded verbatim to the handset.
  Extended frames go to the connector that owns the destination address (handset owns
  0xEA and 0xEF); broadcast frames go to every other connector. Any telemetry the RX
  emits, including Rotorflight's 0x88 custom frames and MSP responses, reaches the
  handset unmodified.
- Link statistics are generated on the TX every `tlm_report_interval` ms (default 240).
  rf_Mode values come from `expresslrs_RFrates_e` (`common.h:81-118`), for example
  RATE_LORA_2G4_250HZ = 27, RATE_FLRC_2G4_1000HZ = 33. TX power enum 0=0 mW, 1=10,
  2=25, 3=100, 4=500, 5=1000, 6=2000, 7=250, 8=50.
- Telemetry ratio enum: STD 0, NO_TLM 1, 1:128 2, 1:64 3, 1:32 4, 1:16 5, 1:8 6, 1:4 7,
  1:2 8, DISARMED 9 ("Race": STD while disarmed, off while armed). Per-rate defaults:
  2.4G 250 Hz -> 1:64, 500 Hz -> 1:128, 50 Hz -> 1:16.
- Downlink payload budget: 5 bytes per call on 8-byte OTA packets, 10 on 13-byte
  full-res packets. Example 250 Hz at 1:64 is roughly 78 bit/s of telemetry, so the
  parameter protocol relies on chunking and patience.
- Handset-to-FC uplink (MSP writes, parameter writes to the RX) goes through
  `TXOTAConnector::forwardMessage()` only while connected, whole frame <= 65 bytes,
  5 or 10 bytes per uplink slot.

## 5. Parameter ("Lua") protocol

`MAX_CRSF_PARAMETERS 64`; ids assigned from 1 in registration order; id 0 is the root.

- Ping `[0x28][dest 0x00][orig 0xEA]`. Reply 0x29 device info to the requester. Ping also
  clears the module's critical-error flags.
- Read `[0x2C][0xEE][0xEA][fieldId][chunkIndex]`.
- Entry reply `[0x2B][0xEA][0xEE][fieldId][chunksRemaining][data]`. Chunk 0 data starts
  `[parentId][type|hidden][name\0]` then a type-specific body. Concatenate all chunks
  (strip the 2-byte prefix of each) to get the full record; request chunkIndex+1 until
  chunksRemaining is 0.
- Bodies: TEXT_SELECTION `options;sep\0, value u8, min u8, max u8, default u8, units\0`
  (empty options are blanks to skip). UINT8/INT8 `value, min, max, default, units\0`.
  UINT16/INT16 same with u16 BE. FLOAT not emitted by the TX module. STRING/INFO
  `value\0`. FOLDER `name\0` then child ids terminated by 0xFF. COMMAND
  `step u8, timeout u8 (10 ms units), info\0`.
- Write `[0x2D][0xEE][0xEA][fieldId][value BE, size by type]`. COMMAND step machine:
  idle 0, click 1, executing 2, askConfirm 3, confirmed 4, cancel 5, query 6. Handset
  writes 1; module replies with an entry whose step is 2 or 3 and an info string; handset
  polls with 6 every `timeout`; sends 4 or 5; step returns to 0 when done.
- Write with fieldId 0 requests 0x2E ELRS status: bad u8, good u16, flags u8, msg.
  Flags: bit0 connected, bit1 status1, bit2 model mismatch, bit3 armed, bit4 warning1,
  bit5 error "not while connected", bit6 error "baud rate too low", bit7 critical
  warning. Bits 5-7 are modal errors cleared by writing `0x2D id=0x2E value 0`.
- Lua flow: ping every 1 s until a device answers; then load all fields one at a time
  with 0.5 s timeout; after a value edit re-read the parent folder and its sibling fields
  after about 200 ms (folder names carry dynamic status text). "Other Devices" lists
  every 0x29 responder (RX at 0xEC, FC at 0xC8, backpack) and enumerates it the same way.
- TX module parameter list (in order): [RF Band], Packet Rate (options are the rate table
  reversed, slowest first; SX128x string
  `50Hz(-115dBm);100Hz Full(-112dBm);150Hz(-112dBm);250Hz(-108dBm);333Hz Full(-105dBm);500Hz(-105dBm);D250(-104dBm);D500(-104dBm);F500(-104dBm);F1000(-104dBm)`),
  Telem Ratio, Switch Mode (`Wide;Hybrid` for 8-byte rates, `8ch;16ch Rate/2;12ch Mixed`
  for full-res rates), [Antenna Mode], Link Mode `Normal;MAVLink`, Model Match `Off;On`
  with units " (ID: nn)", folder TX Power {Max Power, Dynamic, [Fan Thresh]}, folder VTX
  Administrator, folder WiFi Connectivity, [folder Backpack], [BLE Joystick], Bind
  COMMAND, and an INFO line with the regulatory domain and commit hash.
- Packet Rate, Switch Mode and Link Mode are refused while connected to a receiver
  (flag "not while connected"); telemetry ratio can change any time.

## 6. Model match / model id

- Handset -> module: `[0xC8][0x08][0x32][0xEE][0xEA][0x10][0x05][modelId][CRC]`. Also
  `[0x10][0x01]` enters bind. EdgeTX sends it on module start and model change.
- Effect: selects the per-model config slot (rate, ratio, power, switch mode, model match
  are all per model), triggers sync spam, and moves the module from `awaitingModelId` to
  transmitting. Without it the module times out after `DisconnectTimeoutMs` and uses the
  last model.
- OTA: with Model Match on, `UID5 ^= (~modelId) & 0x3F`; RX reports mismatch in link
  stats; TX raises the model-mismatch flag. Ids are effectively 0..63.

## 7. Switch modes, arming, channel resolution (`lib/OTA/OTA.cpp`)

- 8-byte OTA ("std" rates): CH1-4 10-bit, CH5 (AUX1) 1 bit = armed, remaining switches
  round-robin. Wide: AUX2-8 as 6-bit (64 positions) plus TX power. Hybrid: AUX2-7 as
  3-bit 7-position, AUX8 as 4-bit 16-position.
- 13-byte OTA ("Full res" rates): all channels 10-bit, AUX1 1-bit arm. 8ch: CH1-4 plus
  AUX2-5 every packet. 16ch Rate/2: alternates halves. 12ch Mixed: CH1-4 every packet,
  alternating AUX2-5 / AUX6-9.
- Arming: the OTA packet carries `isArmed`. From a 24-byte RC frame `armed = CH5 > 992`.
  From a 25-byte frame: if status bit1 set use CH5, else use status bit0. The RX rewrites
  CH5 from the arm bit and mirrors it to CH14 in non-16ch modes; in non-16ch modes the RX
  overwrites CH15/CH16 with LQ and RSSI for the FC.
- Switch positions the module expects: two-position 191/1792, three-position
  191/992/1792, six-position bins between 191 and 1792.
- Switch mode is broadcast to the RX in the SYNC packet.

## 8. MSP over CRSF

Two encodings exist:

(a) ELRS-internal "encapsulated MSP" for TX/RX config:
`[0xC8][len][0x7B|0x7C][dest][orig][0x30][size][function][payload][mspCRC XOR][CRSF CRC]`,
function `MSP_ELRS_RXTX_CONFIG 0x2D` with subcommands UID 0x00, BIND_PHRASE 0x01,
MODEL_ID 0x0A.

(b) Betaflight-style chunked MSP over CRSF (`lib/CRSF2MSP/`), the one Rotorflight speaks:
status byte at CRSF byte 5: bits 0-3 sequence, bit 4 new frame, bits 5-6 MSP version
(1 = V1, 2 = V2), bit 7 error. Chunk data from CRSF byte 6, up to 57 bytes per chunk,
MSP frame up to 512 bytes. Body is the MSP frame without `$X<` and without its checksum:
V2 `[flags][function u16 LE][size u16 LE][payload]`. 0x7A request, 0x7B response,
0x7C write. Sequence gaps abort reassembly.

Practical limits: uplink only while connected, whole frame <= 65 bytes, 5 or 10 bytes per
OTA slot, responses at the telemetry ratio rate. Old OpenTX outbound limit gives the
8-byte request payload size.

## 9. TX backpack (brief)

Separate ESP8285 on the module, talked to by the TX MCU over plain serial MSP with ELRS
opcodes (backpack version, bind, WiFi mode, CRSF telemetry forwarding, DVR, head
tracking). The handset never talks to it directly; it only sets Backpack / VTX Admin
parameters through the parameter protocol.

## 10. Boot behaviour and handset requirements

- On boot the module registers connectors, loads config, inits the radio, sets state
  `noCrossfire`. The hardware timer is not running and nothing is transmitted until the
  handset connects. WiFi auto-start is suppressed once a handset is seen.
- No handshake: the first CRC-valid frame at an accepted baud and polarity marks the
  handset connected. RC frames are the keep-alive (at least one valid frame per second
  with bad < good).
- After connect the module waits for the model-select command (or times out) before
  transmitting RC.
- Sync frames arrive every 200 ms; a handset that ignores them still works but with worse
  latency jitter.
- 400000 8N1 is the safest baud (supports up to 500 Hz); use >= 921600 for 1000 Hz.
- Extended frames from the handset should use origin 0xEA.

## 11. Licensing

Repository LICENSE is GPL-3.0. `elrs.lua` header says GPLv2 (adapted from OpenTX).
Re-implementing from this protocol description does not copy code.

## Minimal handset checklist

1. UART 8N1 at 400000 (or a listed higher rate), full duplex for an internal module.
   CRSF parser with CRC-8 0xD5 over type..payload, frames <= 64 bytes.
2. Send 0x16 RC frames (22 bytes, 16 x 11-bit LE, 172..1811, 992 centre) at exactly the
   OTA interval, continuously; never pause > 1 s. Optional 23rd status byte for
   arm-via-switch, otherwise arm on CH5 > 992.
3. Parse 0x3A sync and adjust frame period and phase.
4. On start and model change send 0x32 `[0xEE][0xEA][0x10][0x05][modelId]`.
5. Consume 0x14 link statistics (every 240 ms).
6. Decode forwarded telemetry frames as needed.
7. Native config UI: 0x28 ping, collect 0x29, read fields 1..fieldCnt with 0x2C,
   reassemble 0x2B chunks, write with 0x2D, drive COMMAND fields with the step machine,
   poll 0x2D id 0 for 0x2E status every second, treat flags bits 5-7 as modal errors.
8. Optional: encapsulated MSP 0x7A/0x7C function 0x2D for UID and bind phrase; chunked
   MSP to the FC.
