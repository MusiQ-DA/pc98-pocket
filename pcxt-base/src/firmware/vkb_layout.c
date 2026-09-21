#include "vkb_layout.h"

// The K2 macros fold a dual legend into one string ("primary\x1fsecondary"); the
// draw code splits it back out (see VKB_LBL_SEP).
#define K(x, y, w, h, sc, lbl)     { (lbl), (x), (w), (y), (h), (sc), OSD_KEYFACE }
#define K2(x, y, w, h, sc, l1, l2) { (l1 "\x1f" l2), (x), (w), (y), (h), (sc), OSD_KEYFACE }
// Accent-face variants, for the function and control keys.
#define KA(x, y, w, h, sc, lbl)     { (lbl), (x), (w), (y), (h), (sc), OSD_KEYACCENT }
#define K2A(x, y, w, h, sc, l1, l2) { (l1 "\x1f" l2), (x), (w), (y), (h), (sc), OSD_KEYACCENT }

// Arrow glyphs for the keypad arrow legends (drawn in osd_font.c, which
// patches them over the ANK at boot).
#define GL_LEFT  "\x1b" // <-
#define GL_RIGHT "\x1a" // ->
#define GL_UP    "\x18" // ^
#define GL_DOWN  "\x19" // v

// Our own glyphs, patched over the ANK's blank control-code area at boot by
// osd_font.c.
#define G_END   "\x01"
#define G_HOME  "\x02"
#define G_PGUP  "\x03"
#define G_PGDN  "\x04"
#define G_SHIFT "\x05"
#define G_RET   "\x06"
#define G_PRTSC "\x07"

#ifdef MACHINE_PC98

// ---------------------------------------------------------------------------
// PC-9801 keyboard (the VX-class layout: F1-F10 in two columns at the left
// edge, STOP right of BS, a two-row RETURN, and the kana row along the bottom).
//
// The VKB itself still emits Set-2 (the whole pocket_keyboard path is Set-2,
// and the VKB register carries one bare code per event, no E0 prefix). Keys
// that exist on a US keyboard take that key's Set-2 code at the same physical
// position -- the same convention np2kai's SDL host-key table uses, so the
// Set-2 -> PC-98 translator can share one table between the docked keyboard
// and this overlay:
//
//   PC-98 key   Set-2   PC-98 key   Set-2   PC-98 key   Set-2
//   ESC         0x76    @           0x54 ([)  ;          0x4C
//   1..0,-      US row  [           0x5B (])  :          0x52 (')
//   ^           0x55 (=) RETURN      0x5A    SHIFT      0x12 / 0x59
//   ¥           0x0E (`) TAB         0x0D    CTRL       0x14
//   BS          0x66    CAPS         0x58    SPACE      0x29
//
// ("US row": 1..0 and - take the plain Set-2 digit codes 0x16 0x1E 0x26 0x25
// 0x2E 0x36 0x3D 0x3E 0x46 0x45 0x4E; letters, , . / and the keypad likewise
// take their own US codes.)
//
// PC-98-only keys have no Set-2 counterpart, so each carries a bare code that
// no real keyboard ever sends (unassigned in the Set-2 matrix and outside
// hid_to_ps2.sv's output), letting the translator decode them unambiguously.
// PC-98 matrix codes (np2kai keystat.h) are noted for the translator:
//
//   PC-98-only key   matrix   emitted    PC-98-only key   matrix   emitted
//   STOP             0x60     0x08       ROLL UP          0x36     0x19
//   KANA (かな)      0x72     0x0F       ROLL DOWN        0x37     0x1F
//   GRPH             0x73     0x10       INS              0x38     0x20
//   XFER (変換)      0x35     0x13       DEL              0x39     0x28
//   NFER (無変換)    0x51     0x17       _ / RO           0x33     0x2F
//   HELP             0x3F     0x18       keypad /         0x41     0x30
//
// (Keypad Enter reuses RETURN's 0x5A: on PC-98 both are matrix 0x1C, and the
// bare E0-less VKB register cannot spell the keypad Enter's E0 5A anyway.)
//
// Keypad second legends follow the PC-98 keypad's printed arrows and page
// functions (NumLock-off meanings); the emitted code stays the digit's.
// ---------------------------------------------------------------------------

// PC-98-only keys: bare Set-2 codes no real keyboard sends. Defined here, not
// the header: scripts/check_vkb_layout.py parses this file's text (macros of
// the PC98K_ kind) to validate the table.
#define PC98K_STOP   0x08 // PC-98 matrix 0x60
#define PC98K_KANA   0x0F // PC-98 matrix 0x72
#define PC98K_GRPH   0x10 // PC-98 matrix 0x73
#define PC98K_XFER   0x13 // PC-98 matrix 0x35
#define PC98K_NFER   0x17 // PC-98 matrix 0x51
#define PC98K_HELP   0x18 // PC-98 matrix 0x3F
#define PC98K_ROLLUP 0x19 // PC-98 matrix 0x36
#define PC98K_ROLLDN 0x1F // PC-98 matrix 0x37
#define PC98K_INS    0x20 // PC-98 matrix 0x38
#define PC98K_DEL    0x28 // PC-98 matrix 0x39
#define PC98K_RO     0x2F // PC-98 matrix 0x33 (the _ / RO key right of /)
#define PC98K_KPDIV  0x30 // PC-98 matrix 0x41 (E0 4B needs a prefix; see above)

const vkb_key_t vkb_keys[] = {
    // row 0: F1 F2 | ESC 1..0 - ^ ¥ BS STOP | keypad * / + -
    KA(2, 1, 26, 15, 0x05, "F1 "),
    KA(30, 1, 26, 15, 0x06, "F2 "),
    KA(58, 1, 26, 15, 0x76, "ESC"),
    K2(86, 1, 25, 15, 0x16, "1", "!"),
    K2(113, 1, 25, 15, 0x1E, "2", "\""),
    K2(140, 1, 25, 15, 0x26, "3", "#"),
    K2(167, 1, 25, 15, 0x25, "4", "$"),
    K2(194, 1, 25, 15, 0x2E, "5", "%"),
    K2(221, 1, 25, 15, 0x36, "6", "&"),
    K2(248, 1, 25, 15, 0x3D, "7", "'"),
    K2(275, 1, 25, 15, 0x3E, "8", "("),
    K2(302, 1, 25, 15, 0x46, "9", ")"),
    K(329, 1, 25, 15, 0x45, "0"),
    K2(356, 1, 25, 15, 0x4E, "-", "="),
    K2(383, 1, 25, 15, 0x55, "^", "`"),
    // 0x5C, not CP437's 0x9D: in the PC-98 ANK the yen sign lives at 0x5C,
    // which is what the machine's own screen prints for this key.
    K2(410, 1, 25, 15, 0x0E, "\x5C", "|"), // ¥ over |
    KA(437, 1, 32, 15, 0x66, "BS"),
    KA(471, 1, 35, 15, PC98K_STOP, "STOP"),
    KA(516, 1, 28, 15, 0x7C, "*"),
    KA(546, 1, 28, 15, PC98K_KPDIV, "/"),
    KA(576, 1, 28, 15, 0x79, "+"),
    KA(606, 1, 28, 15, 0x7B, "-"),
    // row 1: F3 F4 | TAB Q..P @ [ RETURN | keypad 7 8 9 (and ENTER, 3 rows tall)
    KA(2, 17, 26, 15, 0x04, "F3 "),
    KA(30, 17, 26, 15, 0x0C, "F4 "),
    KA(58, 17, 36, 15, 0x0D, "TAB"),
    K(96, 17, 25, 15, 0x15, "Q"),
    K(123, 17, 25, 15, 0x1D, "W"),
    K(150, 17, 25, 15, 0x24, "E"),
    K(177, 17, 25, 15, 0x2D, "R"),
    K(204, 17, 25, 15, 0x2C, "T"),
    K(231, 17, 25, 15, 0x35, "Y"),
    K(258, 17, 25, 15, 0x3C, "U"),
    K(285, 17, 25, 15, 0x43, "I"),
    K(312, 17, 25, 15, 0x44, "O"),
    K(339, 17, 25, 15, 0x4D, "P"),
    K2(366, 17, 25, 15, 0x54, "@", "~"),
    K2(393, 17, 25, 15, 0x5B, "[", "{"),
    KA(420, 17, 86, 31, 0x5A, G_RET), // RETURN spans the TAB and CTRL rows
    K2(516, 17, 28, 15, 0x6C, "7", G_HOME),
    K2(546, 17, 28, 15, 0x75, "8", GL_UP),
    K2(576, 17, 28, 15, 0x7D, "9", G_PGUP),
    KA(606, 17, 28, 47, 0x5A, "ENT"), // keypad ENTER = RETURN's code, 3 rows tall
    // row 2: F5 F6 | CTRL CAPS A..L ; : ] | keypad 4 5 6. The A row carries
    // CTRL and CAPS both (as on the real board), so its keys run a step narrower.
    KA(2, 33, 26, 15, 0x03, "F5 "),
    KA(30, 33, 26, 15, 0x0B, "F6 "),
    KA(58, 33, 34, 15, 0x14, "CTRL"),
    KA(94, 33, 34, 15, 0x58, "CAPS"),
    K(130, 33, 22, 15, 0x1C, "A"),
    K(154, 33, 22, 15, 0x1B, "S"),
    K(178, 33, 22, 15, 0x23, "D"),
    K(202, 33, 22, 15, 0x2B, "F"),
    K(226, 33, 22, 15, 0x34, "G"),
    K(250, 33, 22, 15, 0x33, "H"),
    K(274, 33, 22, 15, 0x3B, "J"),
    K(298, 33, 22, 15, 0x42, "K"),
    K(322, 33, 22, 15, 0x4B, "L"),
    K2(346, 33, 22, 15, 0x4C, ";", "+"),
    K2(370, 33, 22, 15, 0x52, ":", "*"),
    K2(394, 33, 22, 15, 0x5D, "]", "}"),
    K2(516, 33, 28, 15, 0x6B, "4", GL_LEFT),
    K(546, 33, 28, 15, 0x73, "5"),
    K2(576, 33, 28, 15, 0x74, "6", GL_RIGHT),
    // row 3: F7 F8 | SHIFT Z..M , . / _ SHIFT | keypad 1 2 3
    KA(2, 49, 26, 15, 0x83, "F7 "),
    KA(30, 49, 26, 15, 0x0A, "F8 "),
    KA(58, 49, 34, 15, 0x12, G_SHIFT),
    K(94, 49, 25, 15, 0x1A, "Z"),
    K(121, 49, 25, 15, 0x22, "X"),
    K(148, 49, 25, 15, 0x21, "C"),
    K(175, 49, 25, 15, 0x2A, "V"),
    K(202, 49, 25, 15, 0x32, "B"),
    K(229, 49, 25, 15, 0x31, "N"),
    K(256, 49, 25, 15, 0x3A, "M"),
    K2(283, 49, 25, 15, 0x41, ",", "<"),
    K2(310, 49, 25, 15, 0x49, ".", ">"),
    K2(337, 49, 25, 15, 0x4A, "/", "?"),
    K2(364, 49, 25, 15, PC98K_RO, "_", "\\"),
    KA(391, 49, 115, 15, 0x59, G_SHIFT),
    K2(516, 49, 28, 15, 0x69, "1", G_END),
    K2(546, 49, 28, 15, 0x72, "2", GL_DOWN),
    K2(576, 49, 28, 15, 0x7A, "3", G_PGDN),
    // row 4: F9 F10 | KANA GRPH SPACE XFER NFER HELP ROLLUP ROLLDN INS DEL |
    //        keypad 0 .
    KA(2, 65, 26, 15, 0x01, "F9 "),
    KA(30, 65, 26, 15, 0x09, "F10"),
    KA(58, 65, 36, 15, PC98K_KANA, "KANA"),
    KA(96, 65, 36, 15, PC98K_GRPH, "GRPH"),
    K(134, 65, 98, 15, 0x29, ""),
    KA(234, 65, 36, 15, PC98K_XFER, "XFER"),
    KA(272, 65, 36, 15, PC98K_NFER, "NFER"),
    KA(310, 65, 34, 15, PC98K_HELP, "HELP"),
    KA(346, 65, 44, 15, PC98K_ROLLUP, "ROLL\x18"), // ROLL + up-arrow glyph
    KA(392, 65, 44, 15, PC98K_ROLLDN, "ROLL\x19"), // ROLL + down-arrow glyph
    KA(438, 65, 34, 15, PC98K_INS, "INS"),
    KA(474, 65, 32, 15, PC98K_DEL, "DEL"),
    K2(516, 65, 58, 15, 0x70, "0", "Ins"),
    K2(576, 65, 58, 15, 0x71, ".", "Del"),
};

#else // !MACHINE_PC98

// PC/XT 83-key layout: per-key pixel rectangles within the framebuffer, with
// Set-2 make codes; keys are 1px-rounded. A dual legend (K2) prints its two
// values top-left / bottom-right; the KA/K2A variants give function and control
// keys the accent face.
const vkb_key_t vkb_keys[] = {
    // row 0
    KA(2, 1, 28, 15, 0x05, "F1 "),
    KA(32, 1, 28, 15, 0x06, "F2 "),
    KA(74, 1, 28, 15, 0x76, "Esc"),
    K2(104, 1, 28, 15, 0x16, "1", "!"),
    K2(134, 1, 28, 15, 0x1E, "2", "@"),
    K2(164, 1, 28, 15, 0x26, "3", "#"),
    K2(194, 1, 28, 15, 0x25, "4", "$"),
    K2(224, 1, 28, 15, 0x2E, "5", "%"),
    K2(254, 1, 28, 15, 0x36, "6", "^"),
    K2(284, 1, 28, 15, 0x3D, "7", "&"),
    K2(314, 1, 28, 15, 0x3E, "8", "*"),
    K2(344, 1, 28, 15, 0x46, "9", "("),
    K2(374, 1, 28, 15, 0x45, "0", ")"),
    K2(404, 1, 28, 15, 0x4E, "-", "_"),
    K2(434, 1, 28, 15, 0x55, "=", "+"),
    KA(464, 1, 50, 15, 0x66, GL_LEFT),
    KA(516, 1, 58, 15, 0x77, "NumL"),
    KA(576, 1, 58, 15, 0x7E, "ScrL"),
    // row 1
    KA(2, 17, 28, 15, 0x04, "F3 "),
    KA(32, 17, 28, 15, 0x0C, "F4 "),
    KA(74, 17, 43, 15, 0x0D, "Tab"),
    K(119, 17, 28, 15, 0x15, "Q"),
    K(149, 17, 28, 15, 0x1D, "W"),
    K(179, 17, 28, 15, 0x24, "E"),
    K(209, 17, 28, 15, 0x2D, "R"),
    K(239, 17, 28, 15, 0x2C, "T"),
    K(269, 17, 28, 15, 0x35, "Y"),
    K(299, 17, 28, 15, 0x3C, "U"),
    K(329, 17, 28, 15, 0x43, "I"),
    K(359, 17, 28, 15, 0x44, "O"),
    K(389, 17, 28, 15, 0x4D, "P"),
    K2(419, 17, 28, 15, 0x54, "[", "{"),
    K2(449, 17, 35, 15, 0x5B, "]", "}"),
    KA(486, 17, 28, 31, 0x5A, G_RET),
    K2(516, 17, 28, 15, 0x6C, "7", G_HOME),
    K2(546, 17, 28, 15, 0x75, "8", GL_UP),
    K2(576, 17, 28, 15, 0x7D, "9", G_PGUP),
    KA(606, 17, 28, 15, 0x7B, "-"),
    // row 2
    KA(2, 33, 28, 15, 0x03, "F5 "),
    KA(32, 33, 28, 15, 0x0B, "F6 "),
    KA(74, 33, 50, 15, 0x14, "Ctrl"),
    K(126, 33, 28, 15, 0x1C, "A"),
    K(156, 33, 28, 15, 0x1B, "S"),
    K(186, 33, 28, 15, 0x23, "D"),
    K(216, 33, 28, 15, 0x2B, "F"),
    K(246, 33, 28, 15, 0x34, "G"),
    K(276, 33, 28, 15, 0x33, "H"),
    K(306, 33, 28, 15, 0x3B, "J"),
    K(336, 33, 28, 15, 0x42, "K"),
    K(366, 33, 28, 15, 0x4B, "L"),
    K2(396, 33, 28, 15, 0x4C, ";", ":"),
    K2(426, 33, 28, 15, 0x52, "'", "\""),
    K2(456, 33, 28, 15, 0x0E, "`", "~"),
    K2(516, 33, 28, 15, 0x6B, "4", GL_LEFT),
    K(546, 33, 28, 15, 0x73, "5"),
    K2(576, 33, 28, 15, 0x74, "6", GL_RIGHT),
    KA(606, 33, 28, 47, 0x79, "+"),
    // row 3
    KA(2, 49, 28, 15, 0x83, "F7 "),
    KA(32, 49, 28, 15, 0x0A, "F8 "),
    KA(74, 49, 35, 15, 0x12, G_SHIFT),
    K(111, 49, 28, 15, 0x5D, "\\"),
    K(141, 49, 28, 15, 0x1A, "Z"),
    K(171, 49, 28, 15, 0x22, "X"),
    K(201, 49, 28, 15, 0x21, "C"),
    K(231, 49, 28, 15, 0x2A, "V"),
    K(261, 49, 28, 15, 0x32, "B"),
    K(291, 49, 28, 15, 0x31, "N"),
    K(321, 49, 28, 15, 0x3A, "M"),
    K2(351, 49, 28, 15, 0x41, ",", "<"),
    K2(381, 49, 28, 15, 0x49, ".", ">"),
    K2(411, 49, 28, 15, 0x4A, "/", "?"),
    KA(441, 49, 43, 15, 0x59, G_SHIFT),
    K2A(486, 49, 28, 15, 0x7C, G_PRTSC, "*"),
    K2(516, 49, 28, 15, 0x69, "1", G_END),
    K2(546, 49, 28, 15, 0x72, "2", GL_DOWN),
    K2(576, 49, 28, 15, 0x7A, "3", G_PGDN),
    // row 4
    KA(2, 65, 28, 15, 0x01, "F9 "),
    KA(32, 65, 28, 15, 0x09, "F10"),
    KA(74, 65, 50, 15, 0x11, "Alt"),
    K(126, 65, 298, 15, 0x29, ""),
    KA(426, 65, 58, 15, 0x58, "CapsL"),
    K2(486, 65, 58, 15, 0x70, "0", "Ins"),
    K2(546, 65, 58, 15, 0x71, ".", "Del"),
};

#endif // MACHINE_PC98

const int vkb_key_count = (int) (sizeof(vkb_keys) / sizeof(vkb_keys[0]));

int vkb_width_px(void)
{
    return 636;
}
int vkb_height_px(void)
{
    return 81;
}

void vkb_key_border(const osd_fb_t *fb, int index, uint8_t color)
{
    const vkb_key_t *k = &vkb_keys[index];
    osd_border(fb, k->x, k->y, k->w, k->h, color);
}

static int str_len(const char *s)
{
    int n = 0;
    while (s[n]) {
        n++;
    }
    return n;
}

// Point at the legend separator, or the terminator when the label is single
// ("F1 ") or ends in one ("F1\x1f" -- an empty secondary is drawn as single).
static const char *label_sep(const char *s)
{
    while (*s && *s != VKB_LBL_SEP) {
        s++;
    }
    return s;
}

// Draw the first n glyphs of s: the dual-legend primary is a prefix of label,
// and osd_draw_string would run past the separator.
static void draw_legendn(const osd_fb_t *fb, int x, int y, const char *s, int n, uint8_t color)
{
    for (int i = 0; i < n && s[i]; i++) {
        osd_draw_char(fb, x + i * 8, y, (uint8_t) s[i], color);
    }
}

// Draw s right-aligned so its last glyph sits 3px inside the key's right edge.
static void draw_legend_right(const osd_fb_t *fb, const vkb_key_t *k, int y, const char *s)
{
    osd_draw_string(fb, k->x + k->w - 3 - str_len(s) * 8, y, s, OSD_LABEL);
}

void vkb_draw_keyboard(const osd_fb_t *fb, int selected)
{
    osd_clear_screen();      // erase any previous overlay across the full framebuffer
    osd_clear(fb, OSD_BODY); // the keyboard body fills the VKB region
    for (int i = 0; i < vkb_key_count; i++) {
        const vkb_key_t *k = &vkb_keys[i];
        const char *sep = label_sep(k->label);
        osd_fill_rect(fb, k->x + 1, k->y + 1, k->w - 2, k->h - 2, k->face);
        osd_border(fb, k->x, k->y, k->w, k->h, OSD_KEYEDGE);
        if (*sep && sep[1]) {
            // Dual legend: primary top-left, secondary bottom-right. Splitting them
            // diagonally lets two glyphs share a 15px key without stacking.
            draw_legendn(fb, k->x + 4, k->y + 3, k->label, (int) (sep - k->label), OSD_LABEL);
            draw_legend_right(fb, k, k->y + k->h - 10, sep + 1);
        } else {
            int len = (int) (sep - k->label);
            draw_legendn(fb, k->x + (k->w - len * 8) / 2, k->y + (k->h - 8) / 2 + 1, k->label, len,
                    OSD_LABEL);
        }
    }
    // The selected key is marked by recolouring its border, so cursor moves only
    // need to repaint two borders (see vkb_key_border).
    if (selected >= 0) {
        vkb_key_border(fb, selected, OSD_CURSOR);
    }
}
