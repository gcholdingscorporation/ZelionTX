/*
 * LCD to LVGL glue.
 *
 * Derived from EdgeTX radio/src/gui/colorlcd/lcd.cpp (GPL-2.0) with the theme
 * initialisation removed: ZelionTX styles its own screens. Frame buffers and
 * the LVGL heap live in SDRAM as in EdgeTX.
 *
 * Copyright (C) EdgeTX. Copyright (C) 2026 ZelionTX contributors.
 * GPL-2.0-only.
 */

#include <string.h>

#include "board.h"
#include "dma2d.h"
#include "edgetx_types.h"
#include "lcd.h"

#include <lvgl/lvgl.h>

#if LV_MEM_CUSTOM == 0
char LVGL_MEM_BUFFER[LV_MEM_SIZE] __SDRAM __ALIGNED(16);
extern "C" char* get_lvgl_mem(int nbytes)
{
  (void)nbytes;
  return LVGL_MEM_BUFFER;
}
#endif

pixel_t LCD_FIRST_FRAME_BUFFER[DISPLAY_BUFFER_SIZE] __SDRAM __ALIGNED(64);
pixel_t LCD_SECOND_FRAME_BUFFER[DISPLAY_BUFFER_SIZE] __SDRAM __ALIGNED(64);

static lv_disp_draw_buf_t disp_buf;
static lv_disp_drv_t disp_drv;

static void (*lcd_flush_cb)(lv_disp_drv_t*, uint16_t* buffer,
                            const rect_t& area) = nullptr;

void lcdSetFlushCb(void (*cb)(lv_disp_drv_t*, uint16_t*, const rect_t&))
{
  lcd_flush_cb = cb;
}

extern "C" void lcdFlushed() { lv_disp_flush_ready(&disp_drv); }

void lcdRefresh() {}
void lcdClear() {}

static void flushLcd(lv_disp_drv_t* drv, const lv_area_t* area,
                     lv_color_t* color_p)
{
  // In direct mode only the last flush of a frame is pushed to the panel
  if (drv->direct_mode && !lv_disp_flush_is_last(drv)) {
    lv_disp_flush_ready(drv);
    return;
  }
  if (lcd_flush_cb) {
    rect_t copy_area = {area->x1, area->y1, area->x2 - area->x1 + 1,
                        area->y2 - area->y1 + 1};
    lcd_flush_cb(drv, (uint16_t*)color_p, copy_area);
  } else {
    lcdFlushed();
  }
}

void lcdInitDisplayDriver()
{
  static bool started = false;
  if (started) return;
  started = true;

#if !LV_USE_GPU_STM32_DMA2D
  DMAInit();
#endif

  lv_init();

  memset(LCD_FIRST_FRAME_BUFFER, 0, sizeof(LCD_FIRST_FRAME_BUFFER));
  memset(LCD_SECOND_FRAME_BUFFER, 0, sizeof(LCD_SECOND_FRAME_BUFFER));
  lcdSetInitalFrameBuffer(LCD_FIRST_FRAME_BUFFER);

  lcdInit();
  backlightInit();

  lv_disp_draw_buf_init(&disp_buf, LCD_FIRST_FRAME_BUFFER,
                        LCD_SECOND_FRAME_BUFFER, LCD_W * LCD_H);
  lv_disp_drv_init(&disp_drv);
  disp_drv.draw_buf = &disp_buf;
  disp_drv.flush_cb = flushLcd;
  disp_drv.hor_res = LCD_W;
  disp_drv.ver_res = LCD_H;
  disp_drv.direct_mode = 1;
  lv_disp_drv_register(&disp_drv);
}
