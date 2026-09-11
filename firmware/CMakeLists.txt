# ZelionTX firmware for one STM32H750 radio.
#
# Everything compiled from platform/ is listed here by name. That list is the
# reuse decision of chapter 03: nothing above the hardware abstraction layer is
# taken from EdgeTX unless it appears below.

set(RADIO_DIRECTORY ${ZX_ROOT}/platform/radio)
set(RADIO_SRC_DIR ${RADIO_DIRECTORY}/src)
set(THIRDPARTY_DIR ${RADIO_SRC_DIR}/thirdparty)
set(RTOS_DIR ${THIRDPARTY_DIR}/FreeRTOS)
set(FATFS_DIR ${THIRDPARTY_DIR}/FatFs)
set(STM32_DRIVER_DIR ${RADIO_SRC_DIR}/targets/common/arm/stm32)
set(STM32USB_DIR ${THIRDPARTY_DIR}/STM32_USB_Device_Library)
set(LINKER_DIR ${RADIO_SRC_DIR}/boards/generic_stm32/linker)

list(APPEND CMAKE_MODULE_PATH ${ZX_ROOT}/platform/cmake)
include(Macros)

find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(PYTHON_EXECUTABLE ${Python3_EXECUTABLE})

if(NOT CMAKE_CXX_COMPILER_VERSION VERSION_EQUAL "14.2.1")
  message(WARNING "EdgeTX's platform layer is validated with Arm GCC 14.2.1; you have ${CMAKE_CXX_COMPILER_VERSION}")
endif()

# ---------------------------------------------------------------------------
# Target description (from EdgeTX targets/<radio>/CMakeLists.txt)
# ---------------------------------------------------------------------------
if(ZX_TARGET STREQUAL tx15)
  set(FLAVOUR tx15)
  set(TARGET_DIR tx15)
  set(BOARD rm-h750)
  set(LCD_DRIVER lcd_driver_480.cpp)
  set(TARGET_RADIO_DEFS PCBTX15 RADIO_TX15 SDRAM_8M RGBLEDS_MAX_LEDS=26)
else()
  message(FATAL_ERROR "ZX_TARGET '${ZX_TARGET}' is not wired up yet (tx15 only for now)")
endif()

set(CPU_TYPE STM32H7)
set(CPU_TYPE_FULL STM32H750xB)
set(MCU cortex-m7)
set(FPU_FLAGS -mfloat-abi=hard -mfpu=fpv4-sp-d16)
set(HSE_VALUE 48000000)
set(TARGET_LINKER_DIR stm32h750_sdram)
set(TARGET_EXTRAM_START 0xD0000000)
set(HW_DESC_JSON ${FLAVOUR}.json)

# ---------------------------------------------------------------------------
# Generated hardware definitions (EdgeTX hw_defs JSON -> headers)
# ---------------------------------------------------------------------------
AddHWGenTarget(${HW_DESC_JSON} hal_settings hal_settings.h)
AddHWGenTarget(${HW_DESC_JSON} hal_pwm_sticks hal_pwm_sticks.h)
AddHWGenTarget(${HW_DESC_JSON} hal_keys hal_keys.inc)
AddHWGenTarget(${HW_DESC_JSON} hal_adc_inputs hal_adc_inputs.inc)
AddHWGenTarget(${HW_DESC_JSON} hal_keys_lock hal_keys_lock.h)
AddHWGenTarget(${HW_DESC_JSON} stm32_keys stm32_keys.inc)
AddHWGenTarget(${HW_DESC_JSON} stm32_switches stm32_switches.inc)
AddHWGenTarget(${HW_DESC_JSON} stm32_adc_inputs stm32_adc_inputs.inc)
AddHWGenTarget(${HW_DESC_JSON} stm32_pwm_inputs stm32_pwm_inputs.inc)
set(HW_GEN_TARGETS hal_settings hal_pwm_sticks hal_keys hal_adc_inputs hal_keys_lock
                   stm32_keys stm32_switches stm32_adc_inputs stm32_pwm_inputs)

# EdgeTX version stamp header (a few platform files include it)
set(VERSION_MAJOR 3)
set(VERSION_MINOR 0)
set(VERSION_REVISION 0)
set(VERSION_SUFFIX "-zeliontx")
set(VERSION "3.0.0")
set(VERSION_TAG "")
set(GIT_STR ${ZX_GIT_SHA})
set(CODENAME "zeliontx")
string(TIMESTAMP BUILD_YEAR "%Y")
configure_file(${RADIO_SRC_DIR}/stamp.h.in ${CMAKE_CURRENT_BINARY_DIR}/stamp.h @ONLY)

# ---------------------------------------------------------------------------
# Compiler and preprocessor configuration (mirrors the EdgeTX TX15 build so the
# vendored headers see the same conditionals)
# ---------------------------------------------------------------------------
set(CMAKE_C_FLAGS_RELEASE "" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "" CACHE STRING "" FORCE)
set(CMAKE_C_FLAGS_DEBUG "-g" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG "-g" CACHE STRING "" FORCE)

add_compile_options(
  -mcpu=${MCU} -mthumb ${FPU_FLAGS}
  -Os -g -gdwarf-2 -fomit-frame-pointer
  -fno-exceptions -fdata-sections -ffunction-sections
  -Wall -Wno-address-of-packed-member -Wno-strict-aliasing -Wno-switch
  $<$<COMPILE_LANGUAGE:C>:-Wimplicit>
  $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
  $<$<COMPILE_LANGUAGE:CXX>:-Wno-register>
  $<$<COMPILE_LANGUAGE:CXX>:-std=gnu++17>
)

add_compile_definitions(
  # MCU and board
  STM32 STM32H7 STM32H750XBTx STM32H750xx CPU_TYPE=${CPU_TYPE} CPU_TYPE_FULL=${CPU_TYPE_FULL}
  HSE_VALUE=${HSE_VALUE} SDRAM CCMRAM USE_CUSTOM_EXTI_IRQ STM32_SUPPORT_32BIT_TIMERS
  FIRMWARE_QSPI FIRMWARE_FORMAT_UF2 MANUFACTURER_RADIOMASTER
  PCBHORUS ${TARGET_RADIO_DEFS} FLAVOUR="${FLAVOUR}"
  # Peripherals present on the board
  COLORLCD HARDWARE_TOUCH HARDWARE_KEYS SOFTWARE_KEYBOARD RTCLOCK PWR_BUTTON_PRESS
  BATTERY_CHARGE USB_CHARGER USB_CHARGE_CONTROL HAPTIC AUDIO
  FUNCTION_SWITCHES FUNCTION_SWITCHES_RGB_LEDS RGB_LEDS RGB_LEDS_900NS
  AUX_SERIAL AUX2_SERIAL USB_SERIAL
  # Link: internal ELRS module only
  HARDWARE_INTERNAL_MODULE INTERNAL_MODULE_CRSF DEFAULT_INTERNAL_MODULE=MODULE_TYPE_CROSSFIRE CROSSFIRE
  HARDWARE_EXTERNAL_MODULE HARDWARE_EXTERNAL_MODULE_SIZE_STD
  # Conditionals the vendored headers expect
  CPUARM FREE_RTOS USE_WATCHDOG THREADSAFE_MALLOC TIMERS=3 STORAGE_MODELSLIST
  PPM_LIMITS_SYMETRICAL PPM_CENTER_ADJUSTABLE
  TRANSLATIONS_EN TRANSLATIONS="EN" TRANSLATION_IS_RTL=0
  # ZelionTX
  ZELIONTX ZX_VERSION="${ZX_VERSION}" ZX_GIT_SHA="${ZX_GIT_SHA}"
  LV_CONF_PATH=${ZX_ROOT}/src/lvgl/lv_conf.h
)

include_directories(
  ${ZX_ROOT}/src
  ${CMAKE_CURRENT_BINARY_DIR}
  ${RADIO_SRC_DIR}
  ${RADIO_SRC_DIR}/targets/${TARGET_DIR}
  ${RADIO_SRC_DIR}/boards/${BOARD}
  ${STM32_DRIVER_DIR}
  ${STM32_DRIVER_DIR}/h7
  ${THIRDPARTY_DIR}
  ${THIRDPARTY_DIR}/CMSIS/Include
  ${THIRDPARTY_DIR}/CMSIS/Device/ST/STM32H7xx/Include
  ${THIRDPARTY_DIR}/STM32H7xx_HAL_Driver/Inc
  ${RTOS_DIR}/include
  ${RTOS_DIR}/portable/GCC/ARM_CM4F
  ${FATFS_DIR}
  ${FATFS_DIR}/option
  ${STM32USB_DIR}/Core/Inc
  ${STM32USB_DIR}/Class/CDC/Inc
  ${STM32USB_DIR}/Class/DFU/Inc
  ${STM32USB_DIR}/Class/HID/Inc
  ${STM32USB_DIR}/Class/MSC/Inc
  ${RADIO_SRC_DIR}/gui
  ${RADIO_SRC_DIR}/gui/colorlcd
  ${RADIO_SRC_DIR}/gui/colorlcd/libui
  ${RADIO_SRC_DIR}/gui/colorlcd/layouts
  ${RADIO_SRC_DIR}/gui/colorlcd/mainview
  ${RADIO_SRC_DIR}/gui/colorlcd/controls
  ${RADIO_SRC_DIR}/gui/colorlcd/themes
  ${RADIO_SRC_DIR}/fonts/colorlcd
)

# ---------------------------------------------------------------------------
# Platform sources (all from platform/, listed explicitly)
# ---------------------------------------------------------------------------
set(P ${RADIO_SRC_DIR})
set(S ${STM32_DRIVER_DIR})
set(B ${RADIO_SRC_DIR}/boards/${BOARD})
set(G ${RADIO_SRC_DIR}/boards/generic_stm32)
set(T ${RADIO_SRC_DIR}/targets/${TARGET_DIR})

# CMSIS / start-up
set(CMSIS_SRC
  ${S}/system_init.c
  ${S}/cortex_m_isr.c
  ${S}/h7/system_stm32h7xx.c
  ${S}/h7/vectors_stm32h750xx.c
  ${B}/system_clock.c
)

# STM32 HAL and LL drivers (H7 list from EdgeTX targets/common/arm/stm32/h7)
set(CUBE ${THIRDPARTY_DIR}/STM32H7xx_HAL_Driver/Src/stm32h7xx)
set(STM32CUBE_SRC
  ${CUBE}_ll_gpio.c ${CUBE}_ll_fmc.c ${CUBE}_ll_tim.c ${CUBE}_ll_dma.c ${CUBE}_ll_usart.c
  ${CUBE}_ll_rcc.c ${CUBE}_ll_exti.c ${CUBE}_ll_sdmmc.c ${CUBE}_ll_adc.c ${CUBE}_ll_spi.c
  ${CUBE}_ll_usb.c ${CUBE}_ll_dma2d.c
  ${CUBE}_hal.c ${CUBE}_hal_pwr.c ${CUBE}_hal_pwr_ex.c ${CUBE}_hal_rcc.c ${CUBE}_hal_rcc_ex.c
  ${CUBE}_hal_rtc.c ${CUBE}_hal_i2c.c ${CUBE}_hal_i2c_ex.c ${CUBE}_hal_i2s.c ${CUBE}_hal_sd.c
  ${CUBE}_hal_dma.c ${CUBE}_hal_mdma.c ${CUBE}_hal_pcd.c ${CUBE}_hal_pcd_ex.c ${CUBE}_hal_qspi.c
  ${CUBE}_hal_flash.c ${CUBE}_hal_flash_ex.c ${CUBE}_hal_cortex.c ${CUBE}_hal_sdram.c
  ${CUBE}_hal_gpio.c ${CUBE}_hal_dsi.c ${CUBE}_hal_ltdc.c
)
add_library(stm32cube_ll OBJECT EXCLUDE_FROM_ALL ${STM32CUBE_SRC})
target_compile_definitions(stm32cube_ll PRIVATE USE_FULL_LL_DRIVER)

# FreeRTOS kernel and EdgeTX's RTOS glue
add_library(freertos OBJECT EXCLUDE_FROM_ALL
  ${RTOS_DIR}/list.c ${RTOS_DIR}/queue.c ${RTOS_DIR}/tasks.c ${RTOS_DIR}/event_groups.c
  ${RTOS_DIR}/timers.c ${RTOS_DIR}/stream_buffer.c ${RTOS_DIR}/portable/GCC/ARM_CM4F/port.c
)
set(RTOS_GLUE_SRC
  ${P}/rtos.c
  ${P}/fw_desc.c
  ${P}/syscalls.c
  ${P}/os/async_freertos.cpp
  ${P}/os/sleep_freertos.cpp
  ${P}/os/task_freertos.cpp
  ${P}/os/time_freertos.cpp
  ${P}/os/timer_freertos.cpp
)

# STM32 USB device library and EdgeTX USB device glue
add_library(stm32usb OBJECT EXCLUDE_FROM_ALL
  ${STM32USB_DIR}/Core/Src/usbd_core.c ${STM32USB_DIR}/Core/Src/usbd_ctlreq.c
  ${STM32USB_DIR}/Core/Src/usbd_ioreq.c ${STM32USB_DIR}/Class/CDC/Src/usbd_cdc.c
  ${STM32USB_DIR}/Class/DFU/Src/usbd_dfu.c ${STM32USB_DIR}/Class/MSC/Src/usbd_msc_data.c
  ${STM32USB_DIR}/Class/MSC/Src/usbd_msc_scsi.c ${STM32USB_DIR}/Class/MSC/Src/usbd_msc_bot.c
  ${STM32USB_DIR}/Class/MSC/Src/usbd_msc.c
)
set(USB_GLUE_SRC
  ${S}/usbd_conf.c ${S}/usbd_desc.c ${S}/usb_driver.cpp ${S}/usbd_storage_msd.cpp
  ${S}/usbd_cdc.cpp ${S}/usbd_hid_joystick.c
)

# Generic STM32 drivers
set(STM32_DRIVERS_SRC
  ${S}/stm32_hal.cpp ${S}/timers_driver.cpp ${S}/diskio_spi.cpp ${S}/stm32_exti_driver.cpp
  ${S}/stm32_serial_driver.cpp ${S}/stm32_usart_driver.cpp ${S}/stm32_gpio_driver.cpp
  ${S}/stm32_timer.cpp ${S}/stm32_dma.cpp ${S}/stm32_gpio.cpp ${S}/stm32_adc.cpp
  ${S}/stm32_spi_h7.cpp ${S}/stm32_i2c_driver.cpp ${S}/sdcard_spi.cpp ${S}/diskio_sdio.cpp
  ${S}/abnormal_reboot.cpp ${S}/delays_driver.cpp ${S}/dma2d.cpp ${S}/flash_driver.cpp
  ${S}/pwr_driver.cpp ${S}/rotary_encoder_driver.cpp ${S}/rtc_driver.cpp ${S}/watchdog_driver.cpp
  ${S}/heartbeat_driver.cpp ${S}/mixer_scheduler_driver.cpp ${S}/module_timer_driver.cpp
  ${S}/stm32_pulse_driver.cpp ${S}/stm32_softserial_driver.cpp ${S}/stm32_qspi.cpp
  ${S}/stm32_i2s.cpp ${S}/stm32_switch_driver.cpp ${S}/stm32_rgbleds.cpp
)

# Board (RadioMaster H750 family) and radio-specific files
set(BOARD_SRC
  ${B}/board.cpp ${B}/bsp_io.cpp ${B}/${LCD_DRIVER} ${B}/backlight_driver.cpp
  ${B}/haptic_driver.cpp ${B}/extflash_driver.cpp ${B}/usb_charger_driver.cpp
  ${B}/sdram_driver.cpp ${B}/tp_gt911.cpp
  ${T}/key_driver.cpp
  ${P}/drivers/pca95xx.cpp
)

# Board glue shared by all STM32 radios
set(GENERIC_BOARD_SRC
  ${G}/inputs.cpp ${G}/i2c_bus.cpp ${G}/bl_keys.cpp ${G}/aux_ports.cpp
  ${G}/module_ports.cpp ${G}/analog_inputs.cpp ${G}/switches.cpp ${G}/bor_level.cpp
  ${G}/rgb_leds.cpp ${G}/rgb_6pos.cpp ${G}/battery_voltage.cpp ${G}/led_driver.cpp
)

# Hardware abstraction layer and FatFs
set(HAL_SRC
  ${P}/hal/key_driver.cpp ${P}/hal/module_port.cpp ${P}/hal/adc_driver.cpp
  ${P}/hal/switch_driver.cpp ${P}/hal/usb_driver.cpp ${P}/hal/rgbleds.cpp
  ${P}/hal/storage.cpp ${P}/hal/fatfs_diskio.cpp ${P}/hal/flash_driver.cpp
  ${FATFS_DIR}/ff.c ${FATFS_DIR}/ffunicode.c
)

# LVGL (EdgeTX's curated source list) plus two built-in fonts
include(${RADIO_SRC_DIR}/gui/colorlcd/CMakeListsLVGL.txt)
set(LVGL_SRC ${LVGL_SOURCES})
list(TRANSFORM LVGL_SRC PREPEND ${RADIO_SRC_DIR}/)
list(APPEND LVGL_SRC
  ${THIRDPARTY_DIR}/lvgl/src/font/lv_font_montserrat_14.c
  ${THIRDPARTY_DIR}/lvgl/src/font/lv_font_montserrat_20.c
  ${THIRDPARTY_DIR}/lvgl/src/font/lv_font_montserrat_28.c
)
add_library(lvgl OBJECT EXCLUDE_FROM_ALL ${LVGL_SRC})
target_compile_options(lvgl PRIVATE -O3)

# ---------------------------------------------------------------------------
# ZelionTX sources
# ---------------------------------------------------------------------------
set(ZX_SRC
  ${ZX_ROOT}/src/main.cpp
  ${ZX_ROOT}/src/compat/app_globals.cpp
  ${ZX_ROOT}/src/platform_glue/lcd_glue.cpp
)

# ---------------------------------------------------------------------------
# Firmware target
# ---------------------------------------------------------------------------
add_executable(firmware
  ${CMSIS_SRC} ${RTOS_GLUE_SRC} ${USB_GLUE_SRC} ${STM32_DRIVERS_SRC}
  ${BOARD_SRC} ${GENERIC_BOARD_SRC} ${HAL_SRC} ${ZX_SRC}
  $<TARGET_OBJECTS:stm32cube_ll> $<TARGET_OBJECTS:freertos>
  $<TARGET_OBJECTS:stm32usb> $<TARGET_OBJECTS:lvgl>
)
add_dependencies(firmware ${HW_GEN_TARGETS})
add_dependencies(stm32usb ${HW_GEN_TARGETS})
add_dependencies(lvgl ${HW_GEN_TARGETS})

target_link_options(firmware PRIVATE
  -mcpu=${MCU} -mthumb ${FPU_FLAGS}
  -L${LINKER_DIR} -L${LINKER_DIR}/${TARGET_LINKER_DIR}
  -T${LINKER_DIR}/firmware.ld
  -Wl,--defsym=__EXTRAM_START__=${TARGET_EXTRAM_START}
  -Wl,-Map=firmware.map,--cref,--no-warn-mismatch,--gc-sections
  --specs=nano.specs -lm -lstdc++
)

add_custom_command(TARGET firmware POST_BUILD
  COMMAND ${CMAKE_OBJCOPY} -O binary -R .bootloader firmware.elf firmware.bin
  COMMAND ${PYTHON_EXECUTABLE} ${RADIO_DIRECTORY}/util/elf2uf2.py
          --reboot auto --device "${FLAVOUR}"
          --version "zeliontx-${ZX_VERSION} (${ZX_GIT_SHA})" -i firmware.elf firmware.uf2
  COMMAND ${CMAKE_SIZE_UTIL} firmware.elf > memory-report.txt
  COMMAND ${CMAKE_SIZE_UTIL} firmware.elf
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  COMMENT "firmware.bin, firmware.uf2 and memory-report.txt")
