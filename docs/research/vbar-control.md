# Mikado VBar Control and VBar NEO: the connected-system model

Status of this note: **secondary sources only.** The primary pages (mikado-heli.de,
vstabi.info, the Touch owner's manual) are blocked from this environment, so the
statements below come from search-engine summaries of those pages and of the Model
Aviation review. They are consistent with each other. Verify against the manual
(`VBar_Control_Touch_201_EN.pdf`) before treating any single statement as exact.

## The architectural idea

- **The flybarless unit is the model.** "Each NEO contains the software for the
  aircraft that it is in. There are no model memories, and there is no programming to
  access if you switch on the Touch without powering up a NEO receiver." Setup
  information is stored in each VBar; the transmitter holds no model parameters.
- **Consequence stated by users:** you can never fly with the wrong model memory; the
  cost is that you cannot edit a model's parameters without powering the aircraft.
- **Binding selects the aircraft.** "Select Transmitter Setup, Bind from the menu.
  Select the VBar (serial number) of the VBar you are about to set up." Identity is the
  unit's serial number, not a slot on the radio.
- **Setup wizard on bind.** "After the NEO is bound to the Touch, a setup wizard will
  send basic software settings to the NEO (for example, is it an airplane or a heli?)."
  Setup is driven from the radio and written into the unit.
- **Flight parameters and banks edited from the radio, stored in the unit.** Bank
  setups can be saved separately ("Edit Bank"), whole setups as `.sec` files; the
  event log can be exported as PDF.
- **Event log and live log flow to the radio.** "VBar NEO provides a live log of your
  VBar flybarless controller, and the last VBar event log files will also be saved on
  your VBar Control transmitter for later analysis." Storage on the radio of "VBar
  event log, VBar Control event log, GPS way points, voltage/current logging."
- **Telemetry and talking telemetry.** Voltages, current, rpm, speed, power
  consumption; "Talking Telemetry Pro", "Talking Switches Pro", "Custom Log Pro",
  temperature graph on the radio and in the cloud after a flight.
- **Vibration analysis on the radio.** "Real time logging and real time vibration
  analysis are readable from the transmitter"; "Vibration Analysis Pro", "Oscilloscope"
  apps.
- **ESC setup from the radio.** "ESCs with VBar Control support can be programmed
  directly from the radio"; bidirectional Kontronik telemetry.
- **Updates through the radio.** The Touch has WiFi; "over-the-air online-update your
  VBar NEO flybarless systems via WiFi"; an app store; "VBar Control Manager" on the PC
  for apps and updates; a cloud for logs.
- **Receiver integration.** VBar NEO ships with a built-in VLink receiver, so link and
  flybarless unit are one device; a VLink satellite lets a VBar Control fly a heli that
  has a third-party receiver for setup flights.

## Mapping to Rotorflight plus ExpressLRS (what exists today)

| VBar feature | Rotorflight / ELRS equivalent available to a transmitter | Status |
|---|---|---|
| Unit stores the whole model | Rotorflight stores everything; `MSP_PILOT_CONFIG` (12) carries model name, `modelId`, `model_param1..3`; `MSP_NAME` (10); `MSP_UID` (160) gives a unique board id | exists |
| Bind selects the aircraft by serial | ELRS bind phrase or UID on the receiver; on link-up the FC answers `MSP_UID` and `MSP_NAME` | exists |
| Setup wizard writes basic settings into the unit | `MSP_SET_RX_MAP`, `MSP_SET_MODE_RANGE`, `MSP_SET_ADJUSTMENT_RANGE`, `MSP_SET_TELEMETRY_CONFIG`, `MSP_SET_PILOT_CONFIG`, `MSP_SET_RC_CONFIG`, `MSP_EEPROM_WRITE` | exists |
| Flight parameters and banks edited from the radio | PID profiles, rate profiles, governor, rescue, mixer, servos, filters, battery profiles all readable and writable over MSP; the Rotorflight Lua suite proves it works over CRSF | exists, slow link |
| Setup backup file | No single dump over MSP; a backup means reading every config message (as the Configurator does) and writing a file | feasible, needs a message list per API version |
| Event log from the unit to the radio | Rotorflight has no event log over MSP; `MSP_STATUS` flags, arming-disable flags, governor and rescue state in telemetry allow the radio to build one | radio-side synthesis only |
| Live log / vibration analysis | Rotorflight blackbox writes to the FC's flash; no streaming over CRSF at useful rates | not feasible over the link |
| ESC setup from the radio | `MSP_ESC_PARAMETERS` (217/218); the Lua suite has pages for AM32, BLHeli_S, Bluejay, FLYROTOR, HobbyWing V5, Scorpion, XDFly/OMP/ZTW, YGE | exists |
| Update the unit through the radio | FC firmware needs DFU over USB; not possible over CRSF. ELRS receiver WiFi update mode can be triggered from the radio through the parameter protocol; the module is flashed through the radio's USB passthrough | partial |
| Talking telemetry | Radio-side voice alerts (already in ZelionDash) | exists |
| App store, cloud | Out of scope | no |

Sources (search summaries of): mikado-heli.de VBar Control Touch product and manual
pages; vstabi.info "Basic Transmitter Operation", "VBar NEO/EVO FAQ", "VBar NEO",
"Model Status", "Update for VBar Control touch", "Vibration Analysis Pro", "Talking
Telemetry", "Step 06a: ESC with Telemetry"; Model Aviation review "Mikado VBar Control
Touch Transmitter"; ManualsLib "VBar NEO Quick Start".
