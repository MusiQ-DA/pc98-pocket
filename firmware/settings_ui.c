#include "settings_ui.h"

#include "dpad.h"
#include "key_bind.h"
#include "softcpu_regs.h"
#include "vkb_draw.h"
#include "vkb_layout.h"
#include "vkb_ui.h"

// The settings overlay: a CP437-framed panel of submenus, drawn on demand into the shared OSD
// framebuffer and navigated with the D-pad. Each edit updates the value in RAM and pushes it to the
// softcore settings register that drives the machine.

// Panel geometry in character cells, centred in the framebuffer: 8px columns,
// 16px rows (the GPU CHAR op's tall bank -- font.rom's 8x16 ANK, the machine's
// own text face, twice the VKB legend's height). The title row doubles as the
// control-hint row, right-aligned, which leaves nine item rows -- exactly the
// longest menu.
#define PANEL_COLS 44
#define PANEL_ROWS 12
#define PANEL_W    (PANEL_COLS * 8)
#define PANEL_H    (PANEL_ROWS * 16)
#define PANEL_X    ((OSD_FB_WIDTH - PANEL_W) / 2)
#define PANEL_Y    ((OSD_FB_HEIGHT - PANEL_H) / 2)

// Content cells within the frame.
#define ROW_TITLE  1
#define ROW_FIRST  2 // first menu-item row
#define COL_TITLE  2
#define COL_CURSOR 2
#define COL_LABEL  4
#define COL_VALUE  24

// CP437 box-drawing frame and the right-pointing cursor / submenu marker.
#define G_TL     0xDA
#define G_TR     0xBF
#define G_BL     0xC0
#define G_BR     0xD9
#define G_HORIZ  0xC4
#define G_VERT   0xB3
#define G_MARKER 0x10

static const osd_fb_t panel = { PANEL_X, PANEL_Y, PANEL_W, PANEL_H };

// PC-98 builds drop the XT-only hardware knobs (BIOS ROM window, OPL2, C/MS,
// composite) from the menus by #ifndef MACHINE_PC98 -- hidden, never removed:
// the save blob stores setting values by enum index, so the enum order (and
// with it every later setting's slot) is frozen. The settings themselves stay
// compiled in and are still pushed to the machine at boot with their default
// values, exactly as if the rows were there and untouched.

// Every option-valued setting, addressed by id. `value` is the current selection (an index into
// `opts`); it starts at the first option here, and the option order/default is reconciled with the
// machine when each setting is wired.
enum {
    // System
    SET_CPU_SPEED,
    SET_BIOS_WR,
    // Audio & Video
    SET_BOOST,
    SET_SPK_VOL,
    SET_STEREO,
    SET_DISPLAY,
    // Hardware
    SET_EMS,
    SET_EMS_FRAME,
    // Controls
    SET_DPAD,
    SET_GAMEPAD,
    // OSD
    SET_DISK_LED,
    SET_COUNT // new settings append above: the save blob stores values by index
};

// The four speeds the CE generator really makes from the 42.95 MHz chipset clock.
// The PC-98 ladder is the 2.4576 MHz family this machine presents (x2 and x4 are the
// "5 MHz" and "10 MHz" of a PC-9801VM/VX; the third is twice the fast one, still
// cycle-paced) and a fourth that is the chipset clock itself -- not a speed, the
// cycle-inaccurate maximum.
static const char *const opt_cpu[] = { "5 MHz", "10 MHz", "20 MHz", "Turbo (max)" };
static const char *const opt_bios_wr[] = { "None", "EC00", "Main", "All" };
static const char *const opt_boost[] = { "None", "2x", "4x" };
static const char *const opt_level4[] = { "1", "2", "3", "4" };
static const char *const opt_stereo[] = { "None", "25%", "50%", "100%" };
static const char *const opt_dis_en[] = { "Disabled", "Enabled" };
static const char *const opt_display[] = { "Full Color", "Green", "Amber", "B&W", "Red", "Blue",
    "Fuchsia", "Purple" };
static const char *const opt_ems_frame[] = { "C000", "D000", "E000" };
static const char *const opt_dpad[] = { "Numpad", "Numpad w/ Diag.", "Arrows", "WASD", "HJKL",
    "HJKL w/ YUBN" };
static const char *const opt_gamepad[] = { "Keyboard", "Joystick", "Mouse" };

typedef struct {
    const char *const *opts;
    uint8_t count;
    uint8_t value;
} setting_t;

#define SETTING(a)      { (a), (uint8_t) (sizeof(a) / sizeof((a)[0])), 0 }
#define SETTING_D(a, d) { (a), (uint8_t) (sizeof(a) / sizeof((a)[0])), (d) }

// The rows whose hardware left the machine (CGA/HGC graphics, the video 1st
// card, the splash, OPL2, C/MS, composite, the game port) are gone from the
// enum with it. Older blobs still load -- settings_load remaps their indices
// through the version tables below -- and the next save writes version 6.
static setting_t settings[SET_COUNT] = {
    // Index 1 is the faithful clock: a PC-9801VM/VX's V30 at 2.4576 MHz x4.
    // The default is index 2 anyway, because v30_cpu_bridge splits every word
    // access into two byte cycles on the 8-bit chipset -- about 12 CPU clocks
    // where a real 16-bit V30 spends 4 -- so index 2 is the setting whose
    // THROUGHPUT lands nearest a real 10 MHz machine, not index 1. Move the
    // default down to 1 when the 16-bit memory path lands and the split goes
    // away. At index 0 the ITF's 640 KB memory test is a long wait with nothing
    // on screen but its own test pattern.
    SETTING_D(opt_cpu, 2),    // SET_CPU_SPEED
    SETTING(opt_bios_wr),     // SET_BIOS_WR
    SETTING(opt_boost),       // SET_BOOST
    SETTING(opt_level4),      // SET_SPK_VOL
    SETTING(opt_stereo),      // SET_STEREO
    SETTING(opt_display),     // SET_DISPLAY
    SETTING_D(opt_dis_en, 1), // SET_EMS (default Enabled, as the fixed memory map was)
    SETTING(opt_ems_frame),   // SET_EMS_FRAME
    SETTING_D(opt_dpad, DPAD_ARROWS), // SET_DPAD
    SETTING(opt_gamepad),     // SET_GAMEPAD (default Keyboard)
    SETTING_D(opt_dis_en, 1), // SET_DISK_LED (default on)
};

// Compiled defaults, snapshotted at boot before the save is adopted, for Reset to Defaults.
static uint8_t settings_default[SET_COUNT];

// Orchestrated reset state machine, advanced one tick at a time by
// settings_reset_tick (called from vkb_ui_tick, the timer IRQ). ACT_RESET_PC
// runs inside that IRQ, so the multi-second blank cannot spin there: it would
// park the softcore -- and with it fdd/gdc service -- for the whole re-POST.
static uint8_t  reset_phase;
static uint32_t reset_ticks;

// A menu row is a submenu link, an editable option, a controller-button binding, an action, or a
// blank grouping spacer; `arg` selects the target menu, the setting id, the BIND_* button, or the
// action respectively (unused for a spacer).
enum { IT_SUBMENU, IT_OPTION, IT_KEYBIND, IT_ACTION, IT_SPACER, IT_FDD };

typedef struct {
    const char *label;
    uint8_t type;
    uint8_t arg;
} item_t;

enum { MENU_MAIN, MENU_SYSTEM, MENU_AV, MENU_HW, MENU_CONTROLS, MENU_COUNT };
enum { ACT_DEFAULTS, ACT_RESET_PC };

static const item_t items_main[] = {
    { "System", IT_SUBMENU, MENU_SYSTEM },
    { "Audio & Video", IT_SUBMENU, MENU_AV },
    { "Hardware", IT_SUBMENU, MENU_HW },
    { "Controls", IT_SUBMENU, MENU_CONTROLS },
    { "", IT_SPACER, 0 },
    { "Reset to Defaults", IT_ACTION, ACT_DEFAULTS },
    { "", IT_SPACER, 0 },
    { "Reset PC", IT_ACTION, ACT_RESET_PC },
};

// Boot Splash left with the splash itself (the restructure deleted the
// picture module): the setting still exists in the save blob for index
// stability, but there is nothing left to switch.
static const item_t items_system[] = {
    { "CPU Speed", IT_OPTION, SET_CPU_SPEED },
};

static const item_t items_av[] = {
    { "Audio Boost", IT_OPTION, SET_BOOST },
    { "Speaker Volume", IT_OPTION, SET_SPK_VOL },
    { "Stereo Mix", IT_OPTION, SET_STEREO },
    { "Display", IT_OPTION, SET_DISPLAY },
};

// The four joystick rows are gone with the game port: Peripherals answers
// 0x200-0x207 with a stub (joy_data = FF, "no PCjr port on a PC-98"), so the
// options configured a port that does not exist. The settings stay in the
// save blob, same reason as Boot Splash above.
//
// The two Floppy rows are NOT stored settings: the drives' media lives in
// fdd_service, the Pocket menu's data slots are the only way an image gets
// in, and these rows show the live state and eject/re-insert it (A button).
static const item_t items_hw[] = {
    { "Floppy A", IT_FDD, 0 },
    { "Floppy B", IT_FDD, 1 },
    { "", IT_SPACER, 0 },
    { "Lo-tech 2MB EMS", IT_OPTION, SET_EMS },
    { "EMS Frame", IT_OPTION, SET_EMS_FRAME },
    { "", IT_SPACER, 0 },
    { "Disk LED", IT_OPTION, SET_DISK_LED },
};

// Gamepad Mode picks what controller 1 drives: the D-pad preset and button binds below take effect
// only in its Keyboard mode. L1 is absent because it stays the fixed VKB toggle. Each button row
// cycles its binding through Unmapped, the OSD functions, and a key (picked on the virtual
// keyboard); see the IT_KEYBIND handling in settings_input.
static const item_t items_controls[] = {
    { "Gamepad Mode", IT_OPTION, SET_GAMEPAD },
    { "D-pad", IT_OPTION, SET_DPAD },
    { "Button A", IT_KEYBIND, BIND_A },
    { "Button B", IT_KEYBIND, BIND_B },
    { "Button X", IT_KEYBIND, BIND_X },
    { "Button Y", IT_KEYBIND, BIND_Y },
    { "Button R1", IT_KEYBIND, BIND_R1 },
    { "Button Select", IT_KEYBIND, BIND_SELECT },
    { "Button Start", IT_KEYBIND, BIND_START },
};

typedef struct {
    const char *title;
    const item_t *items;
    uint8_t count;
} menu_t;

#define MENU(title, arr) { (title), (arr), (uint8_t) (sizeof(arr) / sizeof((arr)[0])) }

static const menu_t menus[MENU_COUNT] = {
    MENU("Settings", items_main),
    MENU("System", items_system),
    MENU("Audio & Video", items_av),
    MENU("Hardware", items_hw),
    MENU("Controls", items_controls),
};

static uint8_t cur_menu;       // MENU_* currently shown
static uint8_t cur_row;        // cursor index within that menu
static uint8_t return_row;     // main-menu row to restore when a submenu is left
static volatile uint8_t dirty; // a value changed since the last persist

// Per-disk save context (the per-disk table is described with the blob layout
// below): the mounted drive-A image's content hash, its entry index, whether
// the table magic validated, and the round-robin eviction cursor.
static uint8_t  have_table;
static uint32_t disk_hash;
static int      disk_slot = -1;
static uint8_t  evict_i;

static void draw_frame(void)
{
    osd_draw_char16(&panel, 0, 0, G_TL, OSD_KEYEDGE);
    osd_draw_char16(&panel, (PANEL_COLS - 1) * 8, 0, G_TR, OSD_KEYEDGE);
    osd_draw_char16(&panel, 0, (PANEL_ROWS - 1) * 16, G_BL, OSD_KEYEDGE);
    osd_draw_char16(&panel, (PANEL_COLS - 1) * 8, (PANEL_ROWS - 1) * 16, G_BR, OSD_KEYEDGE);
    for (int c = 1; c < PANEL_COLS - 1; c++) {
        osd_draw_char16(&panel, c * 8, 0, G_HORIZ, OSD_KEYEDGE);
        osd_draw_char16(&panel, c * 8, (PANEL_ROWS - 1) * 16, G_HORIZ, OSD_KEYEDGE);
    }
    for (int r = 1; r < PANEL_ROWS - 1; r++) {
        osd_draw_char16(&panel, 0, r * 16, G_VERT, OSD_KEYEDGE);
        osd_draw_char16(&panel, (PANEL_COLS - 1) * 8, r * 16, G_VERT, OSD_KEYEDGE);
    }
}

// Names for the common keys a docked keyboard can bind that the 83-key virtual keyboard omits: the
// E0-extended keys (ext = 1) and the 101-key extras beyond the XT layout (F11/F12, Print Screen,
// Pause). Set-2 codes and ext flag per hid_to_ps2; anything rarer falls back to its raw code.
static const struct {
    uint8_t ext;
    uint8_t code;
    const char *name;
} extra_names[] = { { 1, 0x75, "Up" }, { 1, 0x72, "Down" }, { 1, 0x6B, "Left" },
    { 1, 0x74, "Right" }, { 1, 0x6C, "Home" }, { 1, 0x69, "End" }, { 1, 0x7D, "PgUp" },
    { 1, 0x7A, "PgDn" }, { 1, 0x70, "Insert" }, { 1, 0x71, "Delete" }, { 1, 0x4A, "KP /" },
    { 1, 0x5A, "KP Enter" }, { 1, 0x14, "R Ctrl" }, { 1, 0x11, "R Alt" }, { 0, 0x78, "F11" },
    { 0, 0x07, "F12" }, { 0, 0xE2, "PrtSc" }, { 0, 0xE1, "Pause" } };

// An unnamed key's raw Set-2 scancode in hex ("E0 " prefixing an extended one), so it stays
// identifiable rather than blank.
static const char *hex_scancode(int ext, uint8_t code)
{
    static const char digits[] = "0123456789ABCDEF";
    static char buf[6];
    char *p = buf;
    if (ext) {
        *p++ = 'E';
        *p++ = '0';
        *p++ = ' ';
    }
    *p++ = digits[code >> 4];
    *p++ = digits[code & 0xF];
    *p = '\0';
    return buf;
}

// The current binding for a button's row value: a function or Unmapped label, a plain key's
// virtual-keyboard legend (blank-legend space bar named), a named extra key, else the raw scancode.
static const char *bind_name(int btn)
{
    switch (key_bind_function(btn)) {
    case BTNFN_SETTINGS:
        return "Open Settings";
    case BTNFN_VIDEO:
        return "Switch Video";
    default:
        break;
    }
    uint8_t code = key_bind_code(btn);
    if (code == 0) {
        return "Unmapped";
    }
    int ext = key_bind_ext(btn);
    if (!ext) {
        for (int i = 0; i < vkb_key_count; i++) {
            if (vkb_keys[i].scancode == code) {
                return vkb_keys[i].label[0] ? vkb_keys[i].label : "Space";
            }
        }
    }
    for (uint32_t i = 0; i < sizeof(extra_names) / sizeof(extra_names[0]); i++) {
        if (extra_names[i].ext == ext && extra_names[i].code == code) {
            return extra_names[i].name;
        }
    }
    return hex_scancode(ext, code);
}

// A button binding row cycles through Unmapped, the OSD functions, and a final "pick a key" slot;
// landing on that slot opens the key picker rather than storing a code. The functions carry their
// BTNFN_* sentinel (BTNFN_* + 0xF0); BIND_KEY_SLOT is not a storable code.
#define BIND_KEY_SLOT 0xFFu
static const uint8_t keybind_cycle[] = {
    0x00,                   // Unmapped
    0xF0u + BTNFN_SETTINGS, // Open Settings
    BIND_KEY_SLOT, // pick a key
};
#define KEYBIND_CYCLE_COUNT ((int) (sizeof(keybind_cycle) / sizeof(keybind_cycle[0])))

// Which cycle slot a button's current binding sits on; a keyboard key (matching no code above)
// rests on the final key slot.
static int keybind_slot(int btn)
{
    uint8_t code = key_bind_code(btn);
    for (int i = 0; i < KEYBIND_CYCLE_COUNT; i++) {
        if (keybind_cycle[i] == code) {
            return i;
        }
    }
    return KEYBIND_CYCLE_COUNT - 1;
}

// Per-row cursor slot (keybind_sel) and last-held key (keybind_key + keybind_key_ext bitmap), kept
// because neither survives the roller leaving the key slot: rolling off and back restores the key.
static uint8_t keybind_sel[BIND_COUNT];
static uint8_t keybind_key[BIND_COUNT];
static uint8_t keybind_key_ext; // E0 flag of each remembered key, one bit per button

// True when a button holds a real keyboard key (not Unmapped, not a function).
static int keybind_is_key(int btn)
{
    return key_bind_code(btn) != 0 && key_bind_function(btn) == BTNFN_NONE;
}

// Snapshot a button's current key (code + ext) into the row's memory; a non-key clears it.
static void keybind_remember(int btn)
{
    int is_key = keybind_is_key(btn);
    keybind_key[btn] = is_key ? key_bind_code(btn) : 0;
    if (is_key && key_bind_ext(btn)) {
        keybind_key_ext |= (uint8_t) (1u << btn);
    } else {
        keybind_key_ext &= (uint8_t) ~(1u << btn);
    }
}

// Seed each button row's cursor slot and remembered key from its binding; called when the Controls
// menu opens.
static void keybind_sync(void)
{
    for (int b = 0; b < BIND_COUNT; b++) {
        keybind_sel[b] = (uint8_t) keybind_slot(b);
        keybind_remember(b);
    }
}

// Repaint one menu row: erase its interior (the frame columns stay), then the cursor, label, and
// either the current value (option/binding) or a submenu marker.
static void draw_row(int i)
{
    const item_t *it = &menus[cur_menu].items[i];
    int y = (ROW_FIRST + i) * 16;

    osd_fill_rect(&panel, 8, y, (PANEL_COLS - 2) * 8, 16, OSD_KEYFACE);
    if (it->type == IT_SPACER) {
        return; // a blank row that visually groups the items around it
    }
    if (i == cur_row) {
        osd_draw_char16(&panel, COL_CURSOR * 8, y, G_MARKER, OSD_CURSOR);
    }
    osd_draw_string16(&panel, COL_LABEL * 8, y, it->label, OSD_LABEL);
    if (it->type == IT_OPTION) {
        const setting_t *s = &settings[it->arg];
        osd_draw_string16(&panel, COL_VALUE * 8, y, s->opts[s->value], OSD_LABEL);
    } else if (it->type == IT_KEYBIND) {
        int on_key = keybind_cycle[keybind_sel[it->arg]] == BIND_KEY_SLOT;
        const char *val = (on_key && !keybind_is_key(it->arg)) ? "[Set key]" : bind_name(it->arg);
        osd_draw_string16(&panel, COL_VALUE * 8, y, val, OSD_LABEL);
    } else if (it->type == IT_SUBMENU) {
        osd_draw_char16(&panel, COL_VALUE * 8, y, G_MARKER, OSD_LABEL);
    } else if (it->type == IT_FDD) {
        // Live state, formatted here: "Inserted 1232K" or "Ejected". The size
        // is sectors/2 in KB (512-byte sectors), which is what every PC-98
        // format's label quotes.
        //
        // No / and no %: clang 23 turns the % /= pair this used to carry into
        // a divu/mul/sub sequence, and the softcore has no divider, so that
        // pair is an illegal instruction on hardware (the Makefile's
        // nodiv-verify is the gate). Decimal by repeated subtraction of the
        // place values -- a floppy is four digits at the very most -- and the
        // /2 is a shift, sectors being 512 bytes.
        char buf[18];
        int n = 0;
        if (fdd_is_inserted(it->arg)) {
            static const char word[] = "Inserted ";
            for (int k = 0; word[k]; k++) buf[n++] = word[k];
            uint32_t v = fdd_mounted_sectors(it->arg) >> 1;
            static const uint16_t place[] = { 1000, 100, 10, 1 };
            char digs[4];
            int nd = 0, lead = 1;
            if (v > 9999) v = 9999;
            for (unsigned p = 0; p < sizeof(place) / sizeof(place[0]); p++) {
                int d = 0;
                while (v >= place[p]) { v -= place[p]; d++; }
                if (!lead || d || place[p] == 1) { digs[nd++] = (char) ('0' + d); lead = 0; }
            }
            for (int i = 0; i < nd; i++) buf[n++] = digs[i];
            buf[n++] = 'K';
        } else {
            static const char word[] = "Ejected";
            for (int k = 0; word[k]; k++) buf[n++] = word[k];
        }
        buf[n] = 0;
        osd_draw_string16(&panel, COL_VALUE * 8, y, buf, OSD_LABEL);
    }
}

static void settings_draw(void)
{
    osd_fill_rect(&panel, 0, 0, PANEL_W, PANEL_H, OSD_KEYFACE);
    draw_frame();
    osd_draw_string16(&panel, COL_TITLE * 8, ROW_TITLE * 16, menus[cur_menu].title, OSD_LABEL);
    for (int i = 0; i < menus[cur_menu].count; i++) {
        draw_row(i);
    }
    // Control hint on the title row, right-aligned (CP437 arrows for
    // Left/Right), dimmed as secondary text.
    static const char hint[] = "\x1b\x1a Change   A/B Enter/Back";
    int hx = (PANEL_COLS - 1 - (int) (sizeof(hint) - 1)) * 8;
    osd_draw_string16(&panel, hx, ROW_TITLE * 16, hint, OSD_DISABLED);
}

// Move the cursor within the current menu (wrapping), repainting only the two affected rows.
static void move_cursor(int dir)
{
    int n = menus[cur_menu].count;
    int old = cur_row;
    int nr = cur_row;
    // Step over blank spacer rows so the cursor only ever lands on a real item.
    do {
        nr += dir;
        if (nr < 0) {
            nr = n - 1;
        }
        if (nr >= n) {
            nr = 0;
        }
    } while (menus[cur_menu].items[nr].type == IT_SPACER);
    cur_row = (uint8_t) nr;
    draw_row(old);
    draw_row(cur_row);
}

void settings_open(void)
{
    cur_menu = MENU_MAIN;
    cur_row = 0;
    return_row = 0;
    osd_clear_screen(); // erase any previous overlay
    settings_draw();
}

void settings_reopen(void)
{
    osd_clear_screen(); // erase the key picker
    settings_draw();
}

// Drive one setting into the machine: SET_DPAD expands to the D-pad key_cfg slots, every other
// setting drives its osd_settings register.
static void settings_push(uint32_t i)
{
    if (i == SET_DPAD) {
        dpad_apply(settings[i].value);
    } else {
        *SETTINGS_REG = (i << 8) | settings[i].value;
    }
}

// Restore every setting and button binding to its compiled default and apply
// it live. Also the mount path's fallback when no blob exists to adopt.
static void apply_defaults(void)
{
    for (uint32_t i = 0; i < SET_COUNT; i++) {
        settings[i].value = settings_default[i];
        settings_push(i);
    }
    key_bind_reset();
}

// Restore every setting and button binding to its compiled default, apply it live, and flag the
// save dirty.
static void settings_reset_defaults(void)
{
    apply_defaults();
    dirty = 1;
    settings_draw();
}

int settings_input(uint16_t pressed)
{
    if (pressed & BTN_B) {
        if (cur_menu == MENU_MAIN) {
            return 1; // dismiss the overlay
        }
        cur_menu = MENU_MAIN;
        cur_row = return_row;
        settings_draw();
        return 0;
    }
    if (pressed & (BTN_UP | BTN_DOWN)) {
        move_cursor((pressed & BTN_UP) ? -1 : 1);
        return 0;
    }

    // Left/Right change a row's value; A enters (a submenu, an action, or the key picker); B leaves
    // (handled above). The two roles never overlap, so a stray double-press cannot both navigate
    // and edit.
    const item_t *it = &menus[cur_menu].items[cur_row];
    if (it->type == IT_OPTION) {
        setting_t *s = &settings[it->arg];
        int changed = 1;
        // Wrapped by comparison, not by %. picorv32 is built without
        // ENABLE_DIV -- its divider was 216 ALMs for the six division
        // instructions in this firmware, on a device that is 97 per cent full
        // with the GDC still to come -- and a menu index is always already
        // inside its range, so one compare does what a modulo did.
        if (pressed & BTN_RIGHT) {
            uint8_t v = (uint8_t) (s->value + 1u);
            s->value = (v >= s->count) ? 0u : v;
        } else if (pressed & BTN_LEFT) {
            s->value = s->value ? (uint8_t) (s->value - 1u)
                                : (uint8_t) (s->count - 1u);
        } else {
            changed = 0;
        }
        if (changed) {
            // Drive the change into the machine and flag dirty so the main loop refreshes the save.
            settings_push(it->arg);
            dirty = 1;
            draw_row(cur_row);
        }
    } else if (it->type == IT_SUBMENU) {
        if (pressed & BTN_A) {
            return_row = cur_row;
            cur_menu = it->arg;
            cur_row = 0;
            if (cur_menu == MENU_CONTROLS) {
                keybind_sync();
            }
            settings_draw();
        }
    } else if (it->type == IT_KEYBIND) {
        int btn = it->arg;
        int slot = keybind_sel[btn];
        if ((pressed & BTN_A) && keybind_cycle[slot] == BIND_KEY_SLOT) {
            // Parked on the key slot: open the virtual keyboard as a key picker. It stores the key
            // and returns to this row, or leaves the binding unchanged if cancelled.
            vkb_ui_open_picker(btn);
        } else {
            int dir = (pressed & BTN_RIGHT) ? 1 : (pressed & BTN_LEFT) ? -1 : 0;
            if (dir) {
                // Remember the key being left so rolling back to the key slot restores it.
                if (keybind_cycle[slot] == BIND_KEY_SLOT) {
                    keybind_remember(btn);
                }
                // dir is +1 or -1, so one step can leave the range by one.
                slot += dir;
                if (slot < 0)                     slot = KEYBIND_CYCLE_COUNT - 1;
                else if (slot >= KEYBIND_CYCLE_COUNT) slot = 0;
                keybind_sel[btn] = (uint8_t) slot;
                uint8_t code = keybind_cycle[slot];
                if (code == BIND_KEY_SLOT) {
                    key_bind_set(btn, keybind_key[btn], (keybind_key_ext >> btn) & 1);
                } else {
                    key_bind_set(btn, code, 0);
                }
                settings_mark_dirty();
                draw_row(cur_row);
            }
        }
    } else if (it->type == IT_FDD) {
        // A (or either arrow, since there is no value to step) ejects an
        // inserted drive and re-inserts the remembered image in an empty one.
        if (pressed & (BTN_A | BTN_LEFT | BTN_RIGHT)) {
            if (fdd_is_inserted(it->arg)) {
                fdd_eject(it->arg);
            } else {
                fdd_insert(it->arg);
            }
            draw_row(cur_row);
        }
    } else if (it->type == IT_ACTION) {
        if (pressed & BTN_A) {
            if (it->arg == ACT_RESET_PC) {
                // Orchestrated guest reset: blank the picture and hold the guest, then let
                // settings_reset_tick walk the release. The raster is free-running, so the
                // GDC keeps scanning the old VRAM and the dead screen would stay up until
                // the BIOS repaints over it -- the blank (SOFT_GUEST_HOLD bit1) hides that.
                *SOFT_GUEST_HOLD = 3;
                reset_phase = 1;
                reset_ticks = 0;
                return 1; // close the panel so the re-POST shows on a clean screen
            } else if (it->arg == ACT_DEFAULTS) {
                settings_reset_defaults();
            }
        }
    }
    return 0;
}

void settings_reset_tick(void)
{
    if (reset_phase == 1) {
        if (++reset_ticks >= 2) {        // ~2 ms of hold
            *SOFT_GUEST_HOLD = 2;        // release the guest, keep the blank
            reset_phase = 2;
            reset_ticks = 0;
        }
    } else if (reset_phase == 2) {
        if (++reset_ticks >= 4000) {     // ~4 s ceiling, then unblank anyway
            reset_phase = 0;
            *SOFT_GUEST_HOLD = 0;
        }
    }
}

// Persisted settings live in the nonvolatile dataslot's window in the disk bridge RAM (word
// SETTINGS_WORD, the slot's 0x60000200 address; the low 512 bytes are the disk sector buffer). APF
// loads that window from /Saves at boot and flushes it back when the core is shut down, so the
// softcore only keeps it current. Layout: word0 magic, word1 {version[7:0], count[15:8]}, the
// values packed four per word, then the key-binding block (seven codes + ext byte) four per word. A
// blob older than version 4 predates the menu-group value layout, so it is rejected and the
// compiled defaults load.
//
// VERSION 5 REMOVED ELEVEN SETTINGS whose hardware left the machine, and the values are stored BY
// INDEX, so a version-4 blob's bytes no longer line up; version 6 removes one more (A000, whose
// RAM flag was never read). Each old index maps through the tables below to its new index, or is
// read past when the setting is gone; the blob is rewritten at the current version on the next
// save, so each remap runs once.
//
// VERSION 7 APPENDS THE PER-DISK TABLE. The global blob's bytes are unchanged -- the version bump
// only marks the firmware as table-aware -- so the same bytes still load on version-6 readers.
// TABLE_WORD carries a second magic: the table region was never written by older saves and reads
// back bridge-RAM residue, so the magic (not the version) says the table exists. Each entry is
// {hash, ~hash, block}: hash is the mounted drive-A image's identity (fdd_service.c), ~hash is the
// validity tag that keeps a half-written or stale slot from passing for a profile, and block is
// the same five-word values+bindings packing the blob uses. While a disk is mounted saves go to
// its entry and mounting applies it; with no disk mounted, saves and the live set are global.
#define SETTINGS_MAGIC   0x50435853u
#define SETTINGS_VERSION 7u
#define SETTINGS_WORD    128

// The table occupies the rest of the window: magic at word 135, then seventeen
// 7-word entries through word 254. TABLE_WORD + 1 + ENTRY_COUNT*ENTRY_WORDS =
// 255, so the region ends exactly at the window's last word.
#define TABLE_WORD   (SETTINGS_WORD + 7) // the global blob is seven words
#define TABLE_MAGIC  0x504B5444u         // 'PKTD'
#define BLOCK_WORDS  5                   // the packed values + bindings a profile is
#define ENTRY_WORDS  (BLOCK_WORDS + 2)   // hash, ~hash, then the block
#define ENTRY_COUNT  17

// Version 4's enum order: CPU, CGA, HGC, video-1st, BIOS-wr, splash, OPL2, boost, speaker, stereo,
// C/MS, composite, display, EMS, EMS-frame, A000, joy1, joy2, swap-joy, sync-joy, d-pad, gamepad.
// 0xFF means the row's hardware is gone and its value is dropped. The table lands on the version-5
// index; the v5_to_v6 pass below carries it the rest of the way.
static const uint8_t v4_to_v5[22] = {
    0, 0xFF, 0xFF, 0xFF, 1, 0xFF, 0xFF, 2, 3, 4, 0xFF, 0xFF, 5, 6, 7, 8, 0xFF, 0xFF, 0xFF, 0xFF,
    9, 10,
};
#define SETTINGS_V4_COUNT 22

// Version 5's enum order: CPU, BIOS-wr, boost, speaker, stereo, display, EMS, EMS-frame, A000,
// d-pad, gamepad.
static const uint8_t v5_to_v6[11] = {
    0, 1, 2, 3, 4, 5, 6, 7, 0xFF, 8, 9,
};
#define SETTINGS_V5_COUNT 11

// Write the live values+bindings as one five-word block at `addr`: SET_COUNT
// values packed four per word, then the seven binding codes and the ext
// bitmap. The layout the global blob and every per-disk entry share.
static void block_write(uint32_t addr)
{
    *FDD_BRAM_ADDR = addr;
    uint32_t word = 0;
    for (uint32_t i = 0; i < SET_COUNT; i++) {
        word |= (uint32_t) settings[i].value << ((i & 3) * 8);
        if ((i & 3) == 3 || i == SET_COUNT - 1) {
            *FDD_BRAM_WDATA = word;
            word = 0;
        }
    }
    uint8_t ext = 0;
    for (uint32_t i = 0; i < BIND_COUNT; i++) {
        ext |= (uint8_t) (key_bind_ext(i) << i);
    }
    word = 0;
    for (uint32_t i = 0; i < BIND_COUNT + 1; i++) {
        uint8_t b = (i < BIND_COUNT) ? key_bind_code(i) : ext;
        word |= (uint32_t) b << ((i & 3) * 8);
        if ((i & 3) == 3 || i == BIND_COUNT) {
            *FDD_BRAM_WDATA = word;
            word = 0;
        }
    }
}

// Adopt a five-word block (the layout block_write makes) as the live settings
// and bindings. Values are index-checked the way settings_load's are, so an
// out-of-range byte keeps the index it had.
static void block_apply(uint32_t addr)
{
    *FDD_BRAM_ADDR = addr;
    uint32_t word = 0;
    for (uint32_t i = 0; i < SET_COUNT; i++) {
        if ((i & 3) == 0) {
            word = *FDD_BRAM_RDATA;
        }
        uint8_t v = (word >> ((i & 3) * 8)) & 0xFF;
        if (v < settings[i].count) {
            settings[i].value = v;
        }
    }
    // The binding block follows the values (auto-incrementing read pointer):
    // seven code bytes then the ext bitmap.
    uint8_t codes[BIND_COUNT];
    uint8_t ext = 0;
    for (uint32_t i = 0; i < BIND_COUNT + 1; i++) {
        if ((i & 3) == 0) {
            word = *FDD_BRAM_RDATA;
        }
        uint8_t b = (word >> ((i & 3) * 8)) & 0xFF;
        if (i < BIND_COUNT) {
            codes[i] = b;
        } else {
            ext = b;
        }
    }
    for (uint32_t i = 0; i < BIND_COUNT; i++) {
        key_bind_set(i, codes[i], (ext >> i) & 1);
    }
    // Drive every setting into the machine so the adopted block takes effect.
    for (uint32_t i = 0; i < SET_COUNT; i++) {
        settings_push(i);
    }
}

// The global blob, whole: magic, {version, count} and the block.
// settings_load calls this to normalise a remapped older blob in place;
// settings_service calls it on every flush while no disk is mounted.
static void global_write(void)
{
    *FDD_BRAM_ADDR = SETTINGS_WORD;
    *FDD_BRAM_WDATA = SETTINGS_MAGIC;
    *FDD_BRAM_WDATA = SETTINGS_VERSION | ((uint32_t) SET_COUNT << 8);
    block_write(SETTINGS_WORD + 2);
}

// The context when no profiled disk is mounted -- and the starting point for a
// disk the table has never seen: the global blob if a save exists, else the
// compiled defaults. Older-version blobs were normalised at load, so the block
// is always readable here.
static void apply_global(void)
{
    *FDD_BRAM_ADDR = SETTINGS_WORD;
    uint32_t magic = *FDD_BRAM_RDATA;
    uint32_t head = *FDD_BRAM_RDATA;
    uint32_t version = head & 0xFF;
    if (magic == SETTINGS_MAGIC && version >= 6 && version <= SETTINGS_VERSION) {
        block_apply(SETTINGS_WORD + 2);
    } else {
        apply_defaults();
    }
}

// The table index for a mounted image's hash, or -1. Both hash words must
// agree -- ~hash is the entry's validity tag, so a half-written or stale slot
// never matches.
static int table_find(uint32_t hash)
{
    if (!have_table) {
        return -1;
    }
    for (int e = 0; e < ENTRY_COUNT; e++) {
        *FDD_BRAM_ADDR = (uint32_t) (TABLE_WORD + 1 + e * ENTRY_WORDS);
        uint32_t h = *FDD_BRAM_RDATA;
        uint32_t nh = *FDD_BRAM_RDATA;
        if (h == hash && nh == ~hash) {
            return e;
        }
    }
    return -1;
}

// Where a new disk's profile goes: the first free or corrupt slot, else the
// round-robin victim -- the evicted disk reverts to the global blob next mount.
static int table_alloc(void)
{
    int free_e = -1;
    for (int e = 0; e < ENTRY_COUNT; e++) {
        *FDD_BRAM_ADDR = (uint32_t) (TABLE_WORD + 1 + e * ENTRY_WORDS);
        uint32_t h = *FDD_BRAM_RDATA;
        uint32_t nh = *FDD_BRAM_RDATA;
        if (free_e < 0 && (h == 0 || nh != ~h)) {
            free_e = e;
        }
    }
    if (free_e >= 0) {
        return free_e;
    }
    int e = evict_i;
    evict_i = (uint8_t) ((evict_i + 1) >= ENTRY_COUNT ? 0 : evict_i + 1);
    return e;
}

void settings_load(void)
{
    for (uint32_t i = 0; i < SET_COUNT; i++) {
        settings_default[i] = settings[i].value; // capture defaults before the save overwrites them
    }
    *FDD_BRAM_ADDR = SETTINGS_WORD;
    uint32_t magic = *FDD_BRAM_RDATA;
    uint32_t head = *FDD_BRAM_RDATA;
    uint32_t version = head & 0xFF;
    if (magic == SETTINGS_MAGIC && version >= 4 && version <= SETTINGS_VERSION) {
        if (version >= 6) {
            // Versions 6 and 7 lay the global block out identically; the
            // per-disk table lives behind its own magic.
            block_apply(SETTINGS_WORD + 2);
        } else {
            uint32_t count = (head >> 8) & 0xFF;
            uint32_t values = count;
            if (version == 4) {
                // The v4 blob's count is 22; read every byte (the words are consumed
                // in fours, so the block must be walked whole) and land each on its
                // v5 index where one exists.
                if (values > SETTINGS_V4_COUNT) {
                    values = SETTINGS_V4_COUNT;
                }
            } else {
                // v5 wrote eleven values; all eleven are read so the d-pad and
                // gamepad bytes at the tail still reach their v6 indices.
                if (values > SETTINGS_V5_COUNT) {
                    values = SETTINGS_V5_COUNT;
                }
            }
            uint32_t word = 0;
            for (uint32_t i = 0; i < values; i++) {
                if ((i & 3) == 0) {
                    word = *FDD_BRAM_RDATA;
                }
                uint8_t v = (word >> ((i & 3) * 8)) & 0xFF;
                uint32_t t = i;
                if (version == 4) {
                    t = v4_to_v5[i];
                }
                if (version <= 5 && t != 0xFF) {
                    t = v5_to_v6[t];
                }
                // Ignore an out-of-range value from an older blob.
                if (t != 0xFF && v < settings[t].count) {
                    settings[t].value = v;
                }
            }
            // The binding block follows the values (auto-incrementing read pointer): seven code
            // bytes then the ext bitmap.
            uint8_t codes[BIND_COUNT];
            uint8_t ext = 0;
            for (uint32_t i = 0; i < BIND_COUNT + 1; i++) {
                if ((i & 3) == 0) {
                    word = *FDD_BRAM_RDATA;
                }
                uint8_t b = (word >> ((i & 3) * 8)) & 0xFF;
                if (i < BIND_COUNT) {
                    codes[i] = b;
                } else {
                    ext = b;
                }
            }
            for (uint32_t i = 0; i < BIND_COUNT; i++) {
                key_bind_set(i, codes[i], (ext >> i) & 1);
            }
            // Normalise a remapped blob in place so the global block the mount
            // paths re-apply is always a current-version one.
            global_write();
        }
    }
    // Drive every setting into the machine so it follows the compiled defaults on a fresh boot and
    // the saved values once a blob exists.
    for (uint32_t i = 0; i < SET_COUNT; i++) {
        settings_push(i);
    }
    // The table magic sits right after the blob; its presence decides whether
    // the per-disk entries mean anything at all.
    *FDD_BRAM_ADDR = TABLE_WORD;
    have_table = (uint8_t) (*FDD_BRAM_RDATA == TABLE_MAGIC);
}

void settings_mark_dirty(void)
{
    dirty = 1;
}

void settings_service(void)
{
    if (!dirty) {
        return;
    }
    dirty = 0;
    if (!have_table) {
        // First table-aware save: claim the region with its magic and clear
        // every entry, so an older blob's tail or bridge-RAM residue can
        // never read as a profile.
        have_table = 1;
        *FDD_BRAM_ADDR = TABLE_WORD;
        *FDD_BRAM_WDATA = TABLE_MAGIC;
        for (uint32_t w = 0; w < ENTRY_COUNT * ENTRY_WORDS; w++) {
            *FDD_BRAM_WDATA = 0;
        }
    }
    if (!disk_hash) {
        global_write();
        return;
    }
    int e = disk_slot;
    if (e < 0 || e >= ENTRY_COUNT) {
        e = table_find(disk_hash);
        if (e < 0) {
            e = table_alloc();
        }
        disk_slot = e;
    }
    *FDD_BRAM_ADDR = (uint32_t) (TABLE_WORD + 1 + e * ENTRY_WORDS);
    *FDD_BRAM_WDATA = disk_hash;
    *FDD_BRAM_WDATA = ~disk_hash;
    block_write((uint32_t) (TABLE_WORD + 1 + e * ENTRY_WORDS + 2));
}

// Follow the image mounted in drive A -- fdd_service calls this with the
// image's content hash on every mount and 0 on unbind. Whatever the outgoing
// context still owes is flushed first, then the incoming disk's profile goes
// live; a disk the table has never seen inherits the global blob, and unbind
// returns to it.
void settings_disk_mounted(uint32_t hash)
{
    if (hash == disk_hash) {
        return; // the re-insert or re-mount of the image already in context
    }
    settings_service(); // pending edits belong to the outgoing disk
    disk_hash = hash;
    if (!hash) {
        disk_slot = -1;
        apply_global();
    } else {
        disk_slot = table_find(hash);
        if (disk_slot >= 0) {
            block_apply((uint32_t) (TABLE_WORD + 1 + disk_slot * ENTRY_WORDS + 2));
        } else {
            apply_global();
        }
    }
    keybind_sync(); // the Controls rows cache each button's slot and key
}
