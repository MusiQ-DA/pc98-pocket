#ifndef VKB_LAYOUT_H
#define VKB_LAYOUT_H

#include <stdint.h>
#include "vkb_draw.h"

// One key of the on-screen layout: a pixel rectangle within the framebuffer.
// scancode is the Set-2 make code (KFPS2KB wants Set-2). Fields are ordered and
// sized to pack the table at 12 bytes per key (a pointer plus six scalars).
// Both legends live in the one `label` string: a dual legend (K2) is written
// "primary\x1fsecondary" -- the separator never occurs in a legend itself --
// which is what let the second pointer go and the table fit the softcore ROM.
#define VKB_LBL_SEP '\x1f'
typedef struct {
    const char *label; // "legend" or "primary\x1fsecondary" (see VKB_LBL_SEP)
    int16_t x, w;      // pixel rect within the framebuffer
    uint8_t y, h;
    uint8_t scancode; // Set-2 make code
    uint8_t face;     // key-face palette index (OSD_KEYFACE / OSD_KEYACCENT)
} vkb_key_t;

// Which table is compiled in: the PC-98 build (config.tcl MACHINE_PC98=1) draws a
// PC-9801 keyboard, the PC/XT build the original 83-key layout. The VKB always
// emits Set-2; for the PC-98-only keys (STOP, KANA, GRPH, XFER, NFER, HELP, ROLL,
// INS, DEL, RO, keypad-/) the PC-98 table substitutes bare Set-2 codes that no
// real keyboard sends -- see the assignment table in vkb_layout.c. The Set-2 ->
// PC-98 translator downstream must decode those codes the same way.

// Which table is compiled in: the PC-98 build (config.tcl MACHINE_PC98=1) draws a
// PC-9801 keyboard, the PC/XT build the original 83-key layout. The VKB always
// emits Set-2; for the PC-98-only keys (STOP, KANA, GRPH, XFER, NFER, HELP, ROLL,
// INS, DEL, RO, keypad-/) the PC-98 table substitutes bare Set-2 codes that no
// real keyboard sends -- see the assignment table in vkb_layout.c. The Set-2 ->
// PC-98 translator downstream must decode those codes the same way.

extern const vkb_key_t vkb_keys[];
extern const int vkb_key_count;

// Whole-keyboard pixel extent for the current geometry constants.
int vkb_width_px(void);
int vkb_height_px(void);

// Repaint one key's border in `color` (a cursor move recolours two borders).
void vkb_key_border(const osd_fb_t *fb, int index, uint8_t color);

// Draw every key into fb; selected < 0 = no cursor, else that key gets a cursor border.
void vkb_draw_keyboard(const osd_fb_t *fb, int selected);

#endif
