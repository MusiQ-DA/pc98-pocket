// OSD font staging: fill the OSD GPU's glyph RAM at boot.
//
// The font used to be $readmemh'd into the bitstream from
// firmware/font/font_8x8.vh -- a glyph set of IBM CP437 and NEC font.rom
// lineage, which is copyrighted font data and can neither live in a public
// repository nor ride along inside the CI bitstream artifact. The BIOS ROMs
// already avoid that by shipping as user-placed data slots; the font now
// follows the same idea. softcpu_subsystem's region 0x7 is a CPU-writable
// window over the glyph RAM, and this fills it once at boot:
//
//   1. font.rom's 8x8 ANK bank -- the first 2 KB of the file: 256 glyphs x 8
//      bytes, MSB = leftmost dot, 1 = dot on, the geometry and polarity the
//      GPU reads (np2kai font/fontv98.c's V98 layout) -- is staged in through
//      the target-dataslot read path, two 1 KB chunks because the disk
//      bridge's RAM is 1 KB. font.rom is a required data slot the user
//      already places, so this adds no file and no user step; if the read
//      fails the base glyphs just stay blank.
//   2. Every slot the ANK does not carry the right glyph for is overwritten
//      with a glyph drawn for this core (the table below): the settings
//      frame, the cursor marker, the arrows and triangles, the tilde, and the
//      VKB key symbols. All of these are original drawings -- the CP437
//      shapes they replace are not -- so nothing NEC or IBM derived is
//      committed here.
//
// JIS X 0201 notes: 0x5C is the yen sign in the ANK (the VKB's yen key labels
// itself with it), 0xA1-0xDF are half-width katakana, and the ANK's 0x7E is
// an overline, patched to a tilde because the shifted-legend strings print
// one.

#include "softcpu_regs.h"

// Slot id candidates for font.rom, tried in order. First the PC-98's CURRENT
// numbering (Font=11, since the floppies took 3/4 and the firmware 12), then
// the earlier PC-98 numbering (Font=3) and the XT-era one (Font=201), kept in
// case the ids ever get renumbered again. Ordering is load-bearing: id 3 is
// Floppy A now, and a disk in drive A would stage its first 2 KB as glyphs
// when 11 -- a REQUIRED slot -- has failed for some other reason. The BIOS at
// id 1 must NOT be in this list: it would stage the BIOS's first 2 KB as
// glyphs, which is exactly the garble the first hardware run showed. Under
// the live data.json no listed id can name another file, so a failed read
// costs one error round trip.
static const uint16_t font_slot_candidates[] = { 11u, 3u, 201u };

// The ANK bank is 2 KB and the bridge RAM holds 1 KB, so the copy runs as two
// target-dataslot reads. A shorter bound than the disk spin: this runs once
// at boot, before the OSD first draws, and a failed candidate must not hold
// the machine up for the disk path's seconds of margin.
#define FONT_SPIN_LIMIT 500000u

// Read 1 KB of font.rom at file_off into the font window. Non-zero on success.
static int font_stage_chunk(uint16_t slot, uint32_t file_off)
{
    *FDD_TDS_ID = slot;
    *FDD_TDS_OFFSET = file_off;
    *FDD_TDS_BRIDGE = FDD_BRIDGE_BASE;
    *FDD_TDS_LENGTH = 1024u;
    *FDD_TDS_CLR = 1u;
    *FDD_TDS_TRIG = FDD_TDS_READ;
    uint32_t to = FONT_SPIN_LIMIT;
    uint32_t st;
    while (!((st = *FDD_TDS_STATUS) & FDD_TDS_DONE) && --to) {
    }
    if (to == 0u || (st & FDD_TDS_ERR)) {
        return 0;
    }
    // The bridge RAM holds the chunk little-endian, byte 0 of the file in the
    // low byte of word 0, so words drop straight into the window (which is
    // word-addressed with byte enables). FDD_BRAM_RDATA auto-increments.
    volatile uint32_t *win = (volatile uint32_t *) FONT_WIN;
    *FDD_BRAM_ADDR = 0u;
    for (uint32_t w = 0u; w < 256u; w++) {
        win[(file_off >> 2) + w] = *FDD_BRAM_RDATA;
    }
    return 1;
}

typedef struct {
    uint8_t code;
    uint8_t rows[8];
} osd_glyph_t;

// This core's own glyphs, patched over the ANK once it has landed. Bit 7 of
// each row byte is the glyph's leftmost pixel, matching the GPU's read.
//
// Provenance, because it is the point of this file: the seven VKB key
// symbols (0x01-0x07, vkb_layout.c's G_*) are the hand-drawn glyphs the core
// shipped before the ANK swap, carried over unchanged. Everything else below
// is drawn here for this core -- deliberately not the CP437 shapes that
// previously occupied those slots -- so the table is free of IBM/NEC font
// lineage.
static const osd_glyph_t osd_own_glyphs[] = {
    // 0x01-0x07: G_END, G_HOME, G_PGUP, G_PGDN, G_SHIFT, G_RET, G_PRTSC.
    { 0x01, { 0x02, 0x32, 0x1A, 0xFE, 0x1A, 0x32, 0x02, 0x00 } },
    { 0x02, { 0x80, 0x98, 0xB0, 0xFE, 0xB0, 0x98, 0x80, 0x00 } },
    { 0x03, { 0x18, 0x3C, 0x7E, 0x18, 0x7E, 0x18, 0x18, 0x00 } },
    { 0x04, { 0x18, 0x18, 0x7E, 0x18, 0x7E, 0x3C, 0x18, 0x00 } },
    { 0x05, { 0x00, 0x18, 0x3C, 0x66, 0xE7, 0x24, 0x3C, 0x00 } },
    { 0x06, { 0x02, 0x02, 0x02, 0x32, 0x62, 0xFE, 0x60, 0x30 } },
    { 0x07, { 0x7E, 0x42, 0x42, 0xFF, 0x81, 0x81, 0xBD, 0xFF } },
    // 0x10: settings cursor / submenu marker (settings_ui.c G_MARKER).
    { 0x10, { 0x40, 0x60, 0x70, 0x78, 0x70, 0x60, 0x40, 0x00 } },
    // 0x18-0x1B: the arrows (GL_UP/GL_DOWN/GL_RIGHT/GL_LEFT; keypad and ROLL
    // legends, the settings hint).
    { 0x18, { 0x10, 0x38, 0x7C, 0x10, 0x10, 0x10, 0x10, 0x00 } },
    { 0x19, { 0x10, 0x10, 0x10, 0x10, 0x7C, 0x38, 0x10, 0x00 } },
    { 0x1A, { 0x00, 0x08, 0x04, 0xFE, 0x04, 0x08, 0x00, 0x00 } },
    { 0x1B, { 0x00, 0x20, 0x40, 0xFE, 0x40, 0x20, 0x00, 0x00 } },
    // 0x1E/0x1F: triangles (the key picker's scroll indicators).
    { 0x1E, { 0x10, 0x10, 0x38, 0x38, 0x7C, 0x7C, 0xFE, 0x00 } },
    { 0x1F, { 0xFE, 0x7C, 0x7C, 0x38, 0x38, 0x10, 0x10, 0x00 } },
    // 0x7E: tilde. The ANK's is the JIS overline; the legends spell a tilde.
    { 0x7E, { 0x00, 0x00, 0x00, 0x42, 0x99, 0x00, 0x00, 0x00 } },
    // The settings frame (settings_ui.c G_TL/G_TR/G_BL/G_BR/G_HORIZ/G_VERT).
    // Single 1px lines: the vertical on column 3, the horizontal on row 3, so
    // corners and runs tile into a continuous box.
    { 0xB3, { 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10 } }, // vertical
    { 0xBF, { 0x00, 0x00, 0x00, 0xF0, 0x10, 0x10, 0x10, 0x10 } }, // top right
    { 0xC0, { 0x10, 0x10, 0x10, 0x1F, 0x00, 0x00, 0x00, 0x00 } }, // bottom left
    { 0xC4, { 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00 } }, // horizontal
    { 0xD9, { 0x10, 0x10, 0x10, 0xF0, 0x00, 0x00, 0x00, 0x00 } }, // bottom right
    { 0xDA, { 0x00, 0x00, 0x00, 0x1F, 0x10, 0x10, 0x10, 0x10 } }, // top left
};

void osd_font_load(void)
{
    volatile uint32_t *win = (volatile uint32_t *) FONT_WIN;
    for (uint32_t c = 0u;
            c < (uint32_t) (sizeof(font_slot_candidates) / sizeof(font_slot_candidates[0])); c++) {
        if (font_stage_chunk(font_slot_candidates[c], 0u) &&
                font_stage_chunk(font_slot_candidates[c], 1024u)) {
            break;
        }
    }
    for (uint32_t i = 0u; i < (uint32_t) (sizeof(osd_own_glyphs) / sizeof(osd_own_glyphs[0]));
            i++) {
        const osd_glyph_t *g = &osd_own_glyphs[i];
        uint32_t base = (uint32_t) g->code * 2u; // two words per glyph
        win[base + 0u] = (uint32_t) g->rows[0] | ((uint32_t) g->rows[1] << 8) |
                         ((uint32_t) g->rows[2] << 16) | ((uint32_t) g->rows[3] << 24);
        win[base + 1u] = (uint32_t) g->rows[4] | ((uint32_t) g->rows[5] << 8) |
                         ((uint32_t) g->rows[6] << 16) | ((uint32_t) g->rows[7] << 24);
    }
}
