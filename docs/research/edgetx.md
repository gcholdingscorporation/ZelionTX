# EdgeTX architecture notes (for ZelionTX fork planning)

Source examined: EdgeTX `main` at `96ab274` (version 3.0.0 "dev"). Git submodules
(FreeRTOS, lvgl, stb, uf2, AccessDenied) were **not** checked out in the clone, so
RTOS/LVGL sources themselves were not inspected, only EdgeTX's use of them.

## 1. Repository layout and build system

Top level: `radio/` (firmware), `companion/` (Qt desktop app + simulator host),
`cmake/`, `tools/` (codegen, `hwdef_schema.json`), `docs/`, `web/` (Svelte/WASM
simulator), `CMakePresets.json`, `Justfile`.

`radio/src/` subdirectories (approximate C/C++ LOC):

| Dir | LOC | Contents |
|---|---|---|
| top-level `.cpp/.h` | ~30.6k | `edgetx.cpp` (init/main/per10ms), `mixer.cpp` (1417), `switches.cpp` (1218), `functions.cpp`, `main.cpp` (`perMain`), `audio.cpp`, `datastructs_private.h` (1243), `dataconstants.h`, `tasks.cpp`, `mixer_scheduler.cpp`, `sdcard.*`, `logs.cpp`, `trainer.cpp`, `gvars.cpp`, `curves.cpp`, `timers.cpp`, `usb_joystick.cpp`, `bluetooth.cpp`, `gps*.cpp`, `gyro.cpp`, `cli.cpp` |
| `gui/` | ~89k | `colorlcd/` 57k (LVGL GUI), `128x64/` 9.9k, `212x64/` 9.2k, `common/stdlcd` 9.4k |
| `targets/` | ~63k | `common/arm/stm32/` 25k (STM32 drivers F2/F4/H7/H7RS), per-board dirs incl. `tx16smk3/`, `tx15/`, `simu/` |
| `storage/` | ~33.6k | `yaml/` 30k (generated per-flavour YAML tables), `sdcard_yaml.cpp`, `modelslist.cpp` |
| `translations/` | ~34k | 19 languages |
| `lua/` | ~16.7k | Lua 5.3.6 bindings |
| `telemetry/` | ~10.9k | per-protocol parsers |
| `pulses/` | ~10k | per-protocol TX drivers |
| `boards/` | ~11.8k | `generic_stm32/`, `hw_defs/*.json` (58 boards), `rm-h750/`, `jumper-h750/` |
| `hal/` | ~3.3k | HAL interface headers |
| `os/` | ~1.4k | RTOS abstraction (FreeRTOS / native) |
| `tasks/` | 321 | `mixer_task.cpp` |
| `thirdparty/` | large | STM32 HAL, CMSIS, FatFs, Lua, USB lib, lz4 |

Build: CMake superbuild (`CMakeLists.txt:33-149`) configures a `native` sub-build
(simulator, companion, gtests) and an `arm-none-eabi` sub-build. Firmware requires
**Arm GNU Toolchain 14.2.rel1** exactly (`radio/src/CMakeLists.txt:571-574`, override
with `USE_UNSUPPORTED_TOOLCHAIN`). Flags: `-mcpu -mthumb -Os`, no exceptions/RTTI,
function/data sections, newlib-nano, `--gc-sections`.

Target selection: `-DPCB=<X9D|X10|PL18|TX15|TX16SMK3|...>` plus `-DPCBREV=`.
`PCB` picks `targets/<dir>/CMakeLists.txt`; `PCBREV` picks the concrete radio,
e.g. `targets/taranis/CMakeLists.txt:260-274` (`PCBREV=BOXER` sets
`DEFAULT_INTERNAL_MODULE CROSSFIRE`). `FLAVOUR` drives `-DRADIO_<NAME>` and picks
`boards/hw_defs/<flavour>.json`.

Feature-trimming CMake options (`radio/src/CMakeLists.txt:14-64`,
`targets/common/arm/CMakeLists.txt:1-25`): `LUA`, `LUA_MIXER`, `HELI`, `FLIGHT_MODES`,
`CURVES`, `GVARS`, `GUI`, `AUDIO`, `BOOTLOADER`, `USBJ_EX`, `CLI`,
`ENABLE_SERIAL_PASSTHROUGH`, `LOG_TELEMETRY`, `XJT`, `PPM`, `DSM2`, `DSMP`, `SBUS`,
`CROSSFIRE`, `AFHDS2`, `AFHDS3`, `MULTIMODULE`, `GHOST`, `INTERNAL_MODULE_<...>`,
`MODULE_SIZE_STD/SML` (unset both to drop the external bay), `BLUETOOTH`, `TEMPLATES`,
`TRANSLATIONS=<lang>`, `DEBUG`.

## 2. Hardware abstraction

Source of truth is a C `hal.h` per target family (`targets/taranis/hal.h`,
`targets/horus/hal.h`, one per H7 target) full of `#if defined(RADIO_X)` pin macros.
`cmake/Macros.cmake:89-113` preprocesses `hal.h` and a Python generator emits
`boards/hw_defs/<flavour>.json` (committed), then Jinja templates render generated
`.inc/.h` files (`hal_adc_inputs.inc`, `stm32_switches.inc`, `stm32_keys.inc`, ...).

HAL interface headers (`radio/src/hal/`): `adc_driver.h`, `key_driver.h`,
`switch_driver.h`, `serial_driver.h` (`etx_serial_driver_t`: init/sendBuffer/getByte/
copyRxBuffer/setBaudrate/setReceiveCb/setIdleCb), `module_port.h` (`etx_module_port_t`,
`modulePortInitSerial`), `module_driver.h` (`etx_proto_driver_t`), `timer_driver.h`,
`audio_driver.h` (32 kHz), `usb_driver.h`, `gpio.h`, `i2c_driver.h`, `flash_driver.h`,
`storage.h`, `watchdog_driver.h`, `trainer_driver.h`, `rotary_encoder.h`.
Backlight/LCD/haptic/power are per-target `.cpp` files, not HAL headers.

STM32 implementations: `targets/common/arm/stm32/` (`stm32_serial_driver.cpp`,
`stm32_usart_driver.cpp`, `stm32_adc.cpp`, `stm32_switch_driver.cpp`, DMA, timers,
`diskio_sdio/spi/spi_flash`, `audio_dac_driver.cpp`, `usb_driver.cpp`,
`mixer_scheduler_driver.cpp`, `f2/ f4/ h7/`). Board glue: `boards/generic_stm32/`.

## 3. RTOS and main loop

FreeRTOS (kernel submodule; V11 per SysView config). `FreeRTOSConfig.h`: preemptive,
1 kHz tick, 5 priorities, static allocation, software timers, tick hook calls
`lv_tick_inc(1)` on colour radios. Thin abstraction in `os/{task,timer,sleep,time,async}.h`.

| Task | Priority | Stack | Period | Body |
|---|---|---|---|---|
| mixer | idle+4 | 400 words | HW timer, 850 us to 50 ms | wait notification, `doMixerCalculations()`, `pulsesSendChannels()`, `doMixerPeriodicUpdates()`, USB joystick, watchdog (`tasks/mixer_task.cpp:145-211`) |
| audio | idle+3 | 400 | 4 ms | `audioQueue.wakeup()` |
| menus | idle+1 | 8 KiB colour / 2000 B | 50 ms (`MENU_TASK_PERIOD`) | `edgeTxInit()`, then `perMain()` loop |
| FreeRTOS timer task | 2 | 1024 | | runs `per10ms()` and all `async_call_isr` deferred calls, i.e. **telemetry frame parsing runs here** |

Boot: `main()` (`edgetx.cpp:1681`) -> `boardInit()`, `modulePortInit()`, `pulsesInit()`,
`initLvgl()`, `tasksStart()`. `menusTask` runs `edgeTxInit()` (`edgetx.cpp:1457-1679`).
`perMain()` (`main.cpp:554-660`) handles USB, SD mount, backlight, key lock, then
`MainWindow::instance()->run()`.

Mixer/module timing: `mixer_scheduler.cpp` keeps a period per module. A 1 MHz hardware
timer (`mixer_scheduler_driver.cpp:31-80`) fires, reloads with the current period, and
notifies the mixer task. Period resolution: internal module period, else external, else
1 ms if USB joystick, else 4 ms. Bounds `MIN_REFRESH_RATE 850 us`, `MAX_REFRESH_RATE 50 ms`.
**One mixer pass equals one module frame.**

## 4. Mixer / stick pipeline

`doMixerCalculations()`: `getADC()` -> `getSwitchesPosition()` -> `evalMixes()`.

1. ADC -> calibrated: `hal/adc_driver.cpp` (jitter filter), `g_eeGeneral.calib[]`.
   `evalInputs()` (`mixer.cpp:558-656`): `anaIn(i) - 1024`, dead zone, throttle reverse,
   trainer substitution -> `calibratedAnalogs[]`; `applyExpos()` (`mixer.cpp:186`) walks
   `g_model.expoData[]`; `evalTrims()`.
2. `evalMixes()` (`mixer.cpp:1142-1281`): flight-mode fades, `evalFlightModeMixes()`
   (`:755-1140`): logical switches every 10 ms, `#if HELI` swash (`:762-830`), the mix
   loop over `g_model.mixData[]` (src, weight, offset, curve, switch, ADD/MUL/REPL,
   delay/slow, flight modes) into `chans[i]`.
3. `evalFunctions()` (`functions.cpp:176-465`) every 10 ms.
4. `applyLimits()` (`mixer.cpp:267-337`): override, trainer, output curve, min/max/offset/
   centre, reverse -> `channelOutputs[i]` in -1024..+1024.
5. `pulsesSendChannels()` -> `pulsesSendNextFrame()` (`pulses/pulses.cpp:534-577`) passes
   16 channels to `drv->sendPulses`.

Key structs (`datastructs_private.h`): `ModelData` (:757), `RadioData` (:1021),
`MixData` (:121), `ExpoData` (:146), `LimitData` (:166), `LogicalSwitchData` (:182),
`CustomFunctionData` (:199), `FlightModeData` (:238), `CurveHeader`, `GVarData`,
`TimerData`, `SwashRingData`, `ScriptData`, `TelemetrySensor` (:412), `ModuleData` (:501).
Counts (`dataconstants.h:44-94`): 32 channels, 64 mixers, 64 expos, 64 logical switches,
64 special functions, 9 flight modes, 32 inputs, 32 curves, 3 timers, 40/60/99 telemetry
sensors, 60 models.

Essential for "sticks -> 16 CRSF channels": ADC/calibration, switch reading
(`switches.cpp:389-460`, `getSwitch()` :684), a minimal expo/limits path, trims.
Optional: logical switches, special functions, GVARs, flight modes with fade, heli swash
(FC does CCPM), trainer, Lua mixer sources, timers, throttle trace, override channel.

## 5. Module / protocol layer (`radio/src/pulses/`)

Driver interface `etx_proto_driver_t` (`hal/module_driver.h:42-70`): `init`, `deinit`,
`sendPulses(ctx, buffer, channels, nChannels)`, `processData`/`processFrame`,
`onConfigChange`, `txCompleted`. `pulses.cpp:266-365` maps `MODULE_TYPE_*` to drivers;
`_init_module` (:376) calls `drv->init`, board hook, `modulePortSetPower`.

Module ports (`hal/module_port.h`): internal module table
`boards/generic_stm32/module_ports.cpp:416-453`: one `ETX_MOD_PORT_UART` port,
`ETX_MOD_DIR_TX_RX | ETX_MOD_FULL_DUPLEX`, STM32 serial driver, `INTMODULE_FIFO_SIZE` 512
on colour radios. `set_pwr` toggles `INTMODULE_PWR_GPIO`; `set_bootcmd` toggles the ELRS
boot pin used for flashing.

CRSF driver `pulses/crossfire.cpp` (484 lines):
- `crossfireInit()` (:381-452): internal -> `INT_CROSSFIRE_BAUDRATE`, full duplex 8N1,
  registers UART IDLE-line callback -> `telemetryFrameTrigger_ISR`. Sets
  `mixerSchedulerSetPeriod(module, CROSSFIRE_PERIOD(module))`.
- Baud rates (`telemetry/crossfire.h:96-103`): `{115200, 400000, 921600, 1870000,
  3750000, 5250000}`, default frame periods `{16,4,2,2,2,2}` ms. Internal baud from
  `g_eeGeneral.internalModuleBaudrate`.
- `createCrossfireChannelsFrame()` (:96-149): `[0xEE][25][0x16]` + 16 x 11-bit
  (`val = 0x3E0 + pulses*4/5`, clamp 0..0x7C0) + **ELRS arming status byte** (bit0 armed,
  0x02 = CH5 mode) + CRC8. 27 bytes total (test vectors in `tests/crossfire.cpp`).
- Also `createCrossfireModelIDFrame` (0x32/0x05), `createCrossfirePingFrame` (0x28),
  `createCrossfireBindFrame` (0x32/0x10/0x01). `setupPulsesCrossfire()` (:151-215):
  Lua output buffer takes precedence over channels; module-alive tracking
  (`MODULE_ALIVE_TIMEOUT` 500 ms) re-sends ModelID after a module reset; state machine
  MODELID -> ping until DEVICE_INFO -> channels.
- `crossfireSetupMixerScheduler()` (:217-225): if `ModuleSyncStatus.isValid()` (updated
  within 2 s) use `getAdjustedRefreshRate()` else default. ELRS sync: 0x3A frames with
  subtype 0x10 carry interval and offset in 0.1 us (`telemetry/crossfire.cpp:381-399`)
  -> `ModuleSyncStatus::update()`; `getAdjustedRefreshRate()` (`telemetry.cpp:538-562`)
  clamps to 850 us..50 ms so the mixer period converges to the module's packet rate.
- RX path: `crossfireProcessFrame()` (:284-329) validates header (0xEA or 0xC8), length
  (`TELEMETRY_RX_PACKET_SIZE` 128), CRC, defragments, then
  `processCrossfireTelemetryFrame()`.

## 6. Telemetry framework (`radio/src/telemetry/`)

Dispatch: UART IDLE ISR -> `telemetryFrameTrigger_ISR` (`telemetry.cpp:249`) ->
`async_call_isr(_poll_frame)` -> FreeRTOS timer task: copy RX buffer, `drv->processFrame()`.
`telemetryWakeup()` (:295-392), called from `doMixerPeriodicUpdates`, evaluates
calculated sensors and runs alarm checks every 1 s. `telemetryInterrupt10ms()` ages
sensors (`TELEMETRY_SENSOR_TIMEOUT_START` 125, about 20 s) and `telemetryStreaming`.

Storage: `g_model.telemetrySensors[]` (`TelemetrySensor`: id, instance, label, unit,
precision, type, logs, filter, ...) paired with runtime `telemetryItems[]`
(`TelemetryItem`, `telemetry_sensors.h:31-107`: value, min/max, timeout, unions for
cells/GPS/text). `setTelemetryValue()` (`telemetry_sensors.cpp:506-580`) matches or
**auto-discovers** into a free slot.

CRSF parser `telemetry/crossfire.cpp`: static `crossfireSensors[]` (:41-80).
`processCrossfireTelemetryFrame()` (:141-448) handles 0x07 vario, 0x02 GPS, 0x03 GPS
time, 0x09 baro, 0x0A airspeed, 0x0C RPM, 0x0D temp, 0x0E cells, **0x14 link stats**
(LQ drives `telemetryData.rssi` and streaming), 0x16 channels (trainer), 0x1C/0x1D,
0x08 battery, 0x1E attitude, 0x21 flight mode text, 0x3A sync. Under `#if LUA` the
`default:` branch handles 0x29 DEVICE_INFO (detects "ELRS", version) and **pushes every
other frame (0x2B params, MSP, 0x88 custom) raw to Lua FIFOs**. There is no native
handling of MSP, parameter or Rotorflight custom frames in C++.

Logging: `logs.cpp` writes CSV to `/LOGS/<model>-<date>.csv` for sensors flagged `logs`.

## 7. Lua integration (`radio/src/lua/`, Lua 5.3.6)

Compiled out entirely with `-DLUA=OFF` (`radio/src/CMakeLists.txt:246-248`); note that
DEVICE_INFO parsing in `telemetry/crossfire.cpp:419-446` sits inside `#if defined(LUA)`
and must be lifted out if Lua is dropped. Memory caps `LUA_MEM_MAX` 6 MB on SDRAM targets.

Scheduling: `luaTask()` is called from `guiMain()` in the 50 ms menus task; scripts are
coroutines pre-empted every 100 instructions after 50 ms. Script kinds: mixer, function,
telemetry, standalone (`/SCRIPTS/TOOLS`, where the ELRS configurator runs), widgets.

CRSF API (`api_general.cpp:1141-1200`): `crossfireTelemetryPop()` (256-byte input FIFO)
and `crossfireTelemetryPush(cmd, data)` (writes into `outputTelemetryBuffer`, sent in
place of the next channels frame). Nothing Rotorflight-specific exists in C++.

## 8. GUI families

- stdlcd (128x64, 212x64): framebuffer + SPI driver, function-pointer menu stack,
  `guiMain(evt)` at 50 ms. About 10k LOC per family plus 9.4k common.
- colorlcd: LVGL submodule branch `release/v8.2`. `lv_conf.h`: 16-bit colour,
  `LV_DISP_DEF_REFR_PERIOD 30 ms`, heap 2/4/8 MB in SDRAM, custom DMA2D flush with double
  frame buffers (`gui/colorlcd/lcd.cpp:42-165`). `lv_timer_handler()` runs from
  `MainWindow::run()` which the menus task calls every **50 ms**, so UI frame rate is at
  most 20 Hz with partial redraws. Widgets refresh each pass via
  `ViewMain::refreshWidgets()`. Structure: `libui/` (Window/Page/Form/Button/Choice/
  NumberEdit wrapping `lv_obj_t`), `mainview/` (ViewMain, Layout, Widget factories),
  17 zone layouts, 7 built-in widgets, YAML theme manager, `model/`, `radio/`, `module/`.
  Fonts are precompiled LVGL bitmaps (88 MB of source). Displays: 480x272, 480x320,
  800x480 (TX16S MK3), 320x240.

## 9. Storage

SD card (or internal flash presented as one path namespace) holds everything:
`/MODELS/model00..99.yml`, `/RADIO/radio.yml`, `/LOGS`, `/SOUNDS/<lang>`, `/SCRIPTS`,
`/THEMES`, `/WIDGETS`, `/FIRMWARE`. FatFs via `hal/fatfs_diskio.cpp`; H7 boards use
QSPI NOR plus SDIO. YAML engine in `storage/yaml/` driven by **generated** tables
(`tools/generate-yaml.sh` using libclang over `datastructs_private.h`). Dirty tracking
with delayed flush (`storageCheck()`). RTC backup RAM keeps a compressed copy of model
and radio settings for recovery after a watchdog reset.

## 10. Audio / haptic

`AudioQueue`: 16 fragments, 3 x 10 ms buffers at 32 kHz, contexts for priority tones,
normal tones/WAV, vario, background music, mixed every 4 ms in the audio task. WAV from
`/SOUNDS/<lang>/SYSTEM` (number vocabulary lives there). Hardware: DAC+DMA on F2/F4,
VS1053B on X12S/X10, TAS2505 over I2S on H7 RadioMaster boards. Haptic: 4-entry queue
ticked from the audio path, PWM or GPIO driver.

## 11. USB

`usb_driver.cpp:168-205` registers one class per mode: HID joystick (classic or
`USBJ_EX` per-channel mapping, 1 ms updates from the mixer task), mass storage (SD as
LUN 0), CDC ACM serial (usable for CLI, telemetry mirror, passthrough), DFU.

## 12. Hardware targets and memory

- STM32F205xE (X9D, X7, X9-Lite, TX12, T-Pro v1, ...): 512 K flash, 128 K RAM, mono LCD.
- STM32F407xE/xG (Zorro, Pocket, TX12 MK2, Boxer, MT12, GX12, T20, T14, T-Pro V2, ...):
  512 K/1 M flash, 128 K RAM + 64 K CCM, mono LCD.
- STM32F429xI (X10, X12S, T16, TX16S, T18, T15, PL18, NV14, ...): 2 M flash, 192 K RAM +
  64 K CCM + 8/32 M SDRAM, colour LCD.
- STM32H750xB (T15 Pro, ST16, PA01, **TX15**, GX15, **TX16S MK3**, T22, V12, C14): 128 K
  internal flash (bootloader), code copied from 8 M QSPI NOR into SDRAM, 128 K DTCM,
  512 K D1 RAM, 8/32 M SDRAM, colour LCD. Board packages `boards/rm-h750`,
  `jumper-h750`, `helloradio-h750`.

Radios with an internal CRSF/ELRS module: F4 class TPROS, BUMBLEBEE, T14, T12MAX, T20,
LR3PRO, TX12MK2, MT12, BOXER, GX12, ZORRO, POCKET, V14; F429 class T15, V16 (and TX16S,
T16, T18, F16, X10 list CRSF as selectable); PL18U/EL18/NB4P; **all H7 targets** (T15PRO,
PA01, TX15, GX15, TX16SMK3, T22, V12, C14) list `CRSF` as the only internal module.

## 13. Licensing

`LICENSE` is GPL-2.0 (June 1991). Source headers say "under the terms of the GNU General
Public License version 2" with no "or later" clause (`mixer.cpp:10-13`). LVGL (MIT),
FreeRTOS (MIT), Lua (MIT), FatFs (BSD-like), STM32 HAL (BSD-3) are permissive.

## 14. Simulator / desktop testing

`radio/src/targets/simu/`: native driver stubs (ADC, switches, fake module serial ports,
FatFs on a host directory, LCD, audio). Targets: `simu` (SDL2 + ImGui desktop simulator),
`libsimulator` (loaded by Companion), `wasi-module` (WASM for the web simulator).
`radio/src/tests/`: gtest suite `gtests-radio` covering mixer, crossfire channel packing
and arming byte, switches, functions, yaml, model, module ports, lua, colour LCD.

## Reuse verdict from the ZelionTX perspective

Reusable as-is: `targets/common/arm/stm32/`, `boards/generic_stm32/`, per-board
`board.cpp`/`hal.h` for the chosen radios, linker scripts, bootloader; `hal/` headers;
FreeRTOS + `os/` + `tasks.cpp` skeleton + `mixer_scheduler.*`; `pulses/crossfire.cpp`
channel packing, arming byte, ModelID/ping/bind, sync handling; `telemetry/crossfire.cpp`
frame parsing; `crc.cpp`; hw_defs generator; simulator stubs and gtest harness; FatFs,
STM32 HAL, USB library.

Reusable with modification: `pulses/pulses.cpp` (CRSF only), `telemetry/telemetry.cpp`
pipeline and `TelemetryItem` (drop other protocols, lift the Lua gating, add native
0x88/MSP handling), mixer core reduced to inputs/limits, data structures and YAML engine
with a much smaller schema, audio queue, `sdcard.*`, `logs.cpp`, LVGL wrapper and
`libui/` primitives and fonts, USB CDC and MSC.

Discard: all non-CRSF protocol drivers and parsers, `io/` updaters, Lua interpreter
(unless kept deliberately), logical switches, special functions, GVARs, flight modes,
timers, trainer, heli swash, templates, wizard, bluetooth, gps, gyro, spacemouse, vario,
PDM recorder, CLI, RTC backup path, 19 translations, companion, web, wasm, 212x64 GUI,
LVGL layouts/widgets/themes factories, Lua widgets, RGB LED code, unused fonts.
