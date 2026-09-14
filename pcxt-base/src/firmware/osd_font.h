#ifndef OSD_FONT_H
#define OSD_FONT_H

// Fill the OSD GPU's glyph RAM (softcpu_subsystem region 0x7) from font.rom's
// 8x8 ANK bank plus this core's own symbol glyphs. Call once, after the
// dataslot load is ready and before the first OSD draw (see main.c).
void osd_font_load(void);

#endif
