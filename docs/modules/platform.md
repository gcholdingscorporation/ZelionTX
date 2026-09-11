# platform/ — vendored EdgeTX platform layer

Owns: board init, pin maps, ADC, switches, keys, UART with DMA, module port power
and boot pin, LCD flush and DMA2D, backlight, touch, rotary, audio, haptic, storage
(SDIO, QSPI, FatFs), USB classes, watchdog, FreeRTOS wrapper, linker scripts, the
UF2 bootloader, and the desktop simulator stubs. Everything above the HAL is
ZelionTX's own code in `src/`.

Source: EdgeTX commit `96ab2745d1bc0025c5508ac8a3b862f34cf97c6e`, copied by
`tools/vendor-edgetx.sh` (decision D-19). See `platform/VENDORED.md` for the list.

## Build environment (established 2026-09-11)

What it took to build stock EdgeTX for the TX15 in a clean Ubuntu 24.04 container,
which is the phase 0 proof that the toolchain and generators work before any
trimming starts:

| Need | What works | Notes |
|---|---|---|
| Arm GCC 14.2 | xPack `arm-none-eabi-gcc` 14.2.1-1.1 from GitHub releases (`tools/setup-toolchain.sh`) | Arm's own download host returned 403 through the proxy. EdgeTX pins 14.2.rel1 and accepts other builds with `USE_UNSUPPORTED_TOOLCHAIN=YES`. |
| CMake, Ninja | Ubuntu packages (3.28, 1.11) | |
| Python packages | `tools/requirements.txt`: pydantic 2, jinja2, pillow, lz4, rich, requests | `pydantic` and `rich` are not in EdgeTX's documented list but the hardware-definition generator imports them. |
| libclang | `clang-18` and `libclang-18` plus the `clang` Python binding at the same major (`pip install "clang==18.*"`) | EdgeTX's `find_clang.py` looks for an unversioned `libclang.so` under `/usr/lib/llvm-*/lib`; Ubuntu ships only `libclang-18.so.1`, so `ln -s libclang-18.so.1 /usr/lib/llvm-18/lib/libclang.so` is required. Only the `datacopy` generator (RTC backup RAM) uses it; ZelionTX drops that feature, so this dependency disappears after phase 1. |
| Generator ordering | Build `hal_settings hal_pwm_sticks hal_keys hal_adc_inputs` before `firmware` | Under Ninja parallelism the USB bootloader objects compile before `hal_settings.h` is generated. ZelionTX's CMake declares the dependency explicitly. |
| Submodules | `lvgl` (EdgeTX fork, branch release/v8.2), `FreeRTOS`, `uf2`, `stb` | Fetched with `git submodule update --init --depth 1`. |

## Bring-up checklist per board (phase 1)

To be filled in during phase 1 with the owner's bench reports. One row per driver:
what was flashed, what was observed, pass or fail, date.

| Driver | TX15 | TX16S Mk3 | GX15 |
|---|---|---|---|
| Boot to blank LVGL screen with frame counter | | | |
| Backlight and brightness | | | |
| ADC: sticks, pots, sliders on serial console | | | |
| Switches and keys | | | |
| Rotary encoder | | | |
| Touch (Mk3) | | | |
| Audio tone | | | |
| Haptic | | | |
| Storage mount and file write | | | |
| USB mass storage | | | |
| USB CDC serial | | | |
| Internal module power and boot pin | | | |
| Internal UART loopback | | | |
| RTC | | | |
| Battery voltage and charger state | | | |
| Power off | | | |
