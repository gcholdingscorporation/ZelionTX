/*
 * ZelionTX firmware entry point.
 *
 * Phase 1 bring-up build: initialise the board through the EdgeTX platform
 * layer, start the RTOS, draw a frame counter and the live analog inputs with
 * LVGL. Nothing here is flight code yet.
 *
 * Copyright (C) 2026 ZelionTX contributors. GPL-2.0-only.
 */

#include <stdio.h>

#include "board.h"
#include "hal/adc_driver.h"
#include "hal/key_driver.h"
#include "hal/switch_driver.h"
#include "hal/watchdog_driver.h"
#include "lcd.h"
#include "os/sleep.h"
#include "os/task.h"
#include "os/time.h"
#include "stm32_hal.h"

#include <lvgl/lvgl.h>

extern const etx_hal_adc_driver_t _adc_driver;

// ---------------------------------------------------------------------------
// UI task: LVGL at 30 ms
// ---------------------------------------------------------------------------
static task_handle_t uiTaskId;
TASK_DEFINE_STACK(uiStack, 8 * 1024);

static lv_obj_t* titleLabel;
static lv_obj_t* counterLabel;
static lv_obj_t* inputsLabel;

static void buildScreen()
{
  lv_obj_t* scr = lv_scr_act();
  lv_obj_set_style_bg_color(scr, lv_color_hex(0x10161C), 0);
  lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);

  titleLabel = lv_label_create(scr);
  lv_obj_set_style_text_color(titleLabel, lv_color_hex(0xE4E9EE), 0);
  lv_obj_set_style_text_font(titleLabel, &lv_font_montserrat_28, 0);
  lv_label_set_text(titleLabel, "ZelionTX " ZX_VERSION " (" ZX_GIT_SHA ")");
  lv_obj_align(titleLabel, LV_ALIGN_TOP_LEFT, 12, 10);

  counterLabel = lv_label_create(scr);
  lv_obj_set_style_text_color(counterLabel, lv_color_hex(0xE0684F), 0);
  lv_obj_set_style_text_font(counterLabel, &lv_font_montserrat_20, 0);
  lv_label_set_text(counterLabel, "frame 0");
  lv_obj_align(counterLabel, LV_ALIGN_TOP_LEFT, 12, 52);

  inputsLabel = lv_label_create(scr);
  lv_obj_set_style_text_color(inputsLabel, lv_color_hex(0x97A5B3), 0);
  lv_obj_set_style_text_font(inputsLabel, &lv_font_montserrat_14, 0);
  lv_label_set_text(inputsLabel, "");
  lv_obj_align(inputsLabel, LV_ALIGN_TOP_LEFT, 12, 88);
}

static void uiTask()
{
  lcdInitDisplayDriver();
  backlightEnable(BACKLIGHT_LEVEL_MAX);
  buildScreen();

  uint32_t frame = 0;
  char buf[512];
  time_point_t next_tick = time_point_now();

  while (task_running()) {
    frame++;
    if ((frame % 4) == 0) {
      snprintf(buf, sizeof(buf), "frame %lu", (unsigned long)frame);
      lv_label_set_text(counterLabel, buf);

      int n = 0;
      uint8_t max = adcGetMaxInputs(ADC_INPUT_ALL);
      for (uint8_t i = 0; i < max && n < (int)sizeof(buf) - 16; i++) {
        n += snprintf(buf + n, sizeof(buf) - n, "in%02u %5u%s", i,
                      getAnalogValue(i), ((i % 4) == 3) ? "\n" : "   ");
      }
      lv_label_set_text(inputsLabel, buf);
    }
    lv_timer_handler();
    WDG_RESET();
    sleep_until(&next_tick, 30);
  }
}

// ---------------------------------------------------------------------------
// Sampling task: ADC at 4 ms (stands in for the RC loop until link/ exists)
// ---------------------------------------------------------------------------
static task_handle_t sampleTaskId;
TASK_DEFINE_STACK(sampleStack, 1024);

static void sampleTask()
{
  time_point_t next_tick = time_point_now();
  while (task_running()) {
    adcRead();
    sleep_until(&next_tick, 4);
  }
}

// ---------------------------------------------------------------------------
extern "C" int main()
{
  NVIC_SetPriorityGrouping(NVIC_PRIORITYGROUP_4);

  boardInit();
  adcInit(&_adc_driver);
  keysInit();
  switchInit();

  task_create(&uiTaskId, uiTask, "ui", uiStack, 8 * 1024, 1);
  task_create(&sampleTaskId, sampleTask, "sample", sampleStack, 1024, 4);

  RTOS_START();
  return 0;
}
