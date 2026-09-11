/*
 * Compatibility shim for the vendored EdgeTX platform layer.
 *
 * A handful of EdgeTX drivers reach into the application layer: they read
 * calibration and a few settings from g_eeGeneral, a few model fields from
 * g_model, and call storage and mixer-scheduler hooks. This file provides
 * those symbols so the drivers link unchanged. Every entry here is a debt to
 * retire: the goal (risk R-1 in the proposal) is to replace each with a
 * ZelionTX-owned source of truth and shrink this file to nothing.
 *
 * Copyright (C) 2026 ZelionTX contributors. GPL-2.0-only.
 */

#include "edgetx.h"

// Radio and model settings as EdgeTX's drivers expect them. Zero-initialised;
// calibration and settings will be loaded by ZelionTX's own storage layer and
// copied into the fields the drivers read.
RadioData g_eeGeneral;
ModelData g_model;

// Channel outputs read by the USB HID joystick code.
int16_t channelOutputs[MAX_OUTPUT_CHANNELS];

// Storage dirty-flag hook called from calibration code.
void storageDirty(uint8_t) {}

// Mixer scheduler hooks used by the timer ISR. Until link/ exists the RC loop
// is not driven by the module, so a fixed 4 ms period is reported and the
// trigger is ignored.
uint16_t getMixerSchedulerPeriod() { return 4000; }
void mixerSchedulerISRTrigger() {}

// 10 ms tick counter used by timing macros in a few drivers.
volatile tmr10ms_t g_tmr10ms = 0;

// ---------------------------------------------------------------------------
// Symbols referenced by drivers that EdgeTX defines in application files
// ---------------------------------------------------------------------------
#include "gyro.h"
#include "hal/imu.h"

// bootloader/boot_uf2.cpp defines this for the bootloader; the firmware's
// I/O expander poll checks it. Never suspended in ZelionTX.
bool suspendI2CTasks = false;

// haptic.cpp's 5 ms tick, called from the timer ISR. Haptic comes later.
void per5ms() {}

// Audio driver bring-up is deferred; board.cpp calls this unconditionally.
int audioInit() { return 0; }

// No IMU use in ZelionTX; board.cpp probes for one at boot.
imu_read_fn imuDetect(const etx_imu_t*, uint8_t) { return nullptr; }
void gyroStart(imu_read_fn) {}

// Stick names used by the generated analog input tables (English only for now;
// all UI strings move to one table in ui/).
const char STR_STICK_NAMES0[] = "Rud";
const char STR_STICK_NAMES1[] = "Ele";
const char STR_STICK_NAMES2[] = "Thr";
const char STR_STICK_NAMES3[] = "Ail";
