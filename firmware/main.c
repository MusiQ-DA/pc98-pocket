// Softcore firmware entry point: bring up the peripherals, then loop servicing disk
// requests and settings while the timer interrupt draws the OSD. The disk and OSD work
// lives in fdd_service.c, scsi_service.c, and the vkb/settings units.

#include "key_bind.h"
#include "settings_ui.h"
#include "sdramtest.h"
#include "softcpu_regs.h"

void gdc_poll(void);
#include "osd_font.h"
#include "vkb_ui.h"

// The OSD runs from a periodic timer interrupt (see irq() and start.S) so blocking disk
// transfers cannot starve it. ~1 ms at the softcore clock (clk_chipset / 6).
#ifndef CHIPSET_HZ
#define CHIPSET_HZ 42954545u
#endif
#define TIMER_PERIOD (CHIPSET_HZ / 6u / 1000u)

extern void timer_start(uint32_t cycles);
extern void irq_mask(uint32_t mask);

// Read a floppy-size register twice and return it only if the samples agree, else 0. The
// size crosses clock domains per-bit and can tear as it changes from 0 to the image size;
// two matching reads reject a half-updated value, and the caller retries on the next poll.
static uint32_t stable_size(volatile uint32_t *reg)
{
    uint32_t a = *reg;
    uint32_t b = *reg;
    return (a == b) ? a : 0;
}

int main(void)
{
    // Start with both hard disks absent so the BIOS boots from floppy until (and unless)
    // an image mounts.
    // No IDE on a PC-98 -- see PERIPHERALS' XT2IDE block. The disk is the
    // PC-9801-55 SCSI window instead.
    scsi_init();
    vkb_ui_init();

    // The guest stays held until settings are staged: wait for the dataslot load (settings_load
    // reads it), adopt the saved settings, then release.
    while (!DATASLOTS_READY(*CONT1_KEY))
        ;
    // Load the OSD font before anything can draw it: the glyph RAM is blank at
    // reset (its old baked-in image was CP437/NEC-derived and had to leave the
    // bitstream), so the first CHAR op must not run until font.rom's ANK bank
    // and this core's own glyphs have landed. See osd_font.c.
    osd_font_load();
    key_bind_init(); // stage the default button map, which settings_load then overrides from the
                     // save
    settings_load();

    // Fill the OPNA rhythm store while the guest is still held: the six ADPCM-A
    // voices then play from the first key-on instead of mid-boot. Returns 0
    // when rhythm.bin is absent or the build is slim -- the service loop
    // retries anyway in case the deferload binding lands late.
    uint32_t rhythm_done = rhythm_load();

#ifdef SDRAM_SELFTEST
    // Diagnostic build (docs/P0_SELFTEST_SPEC.md): walk guest SDRAM from here,
    // with the 8088 still held, and leave the verdict on screen. Deliberately
    // never releases the guest -- the point of this build is the readout, and
    // letting a machine with broken RAM run would only overwrite it.
    sdram_selftest_run();
    for (;;)
        ;
#endif

#ifndef SDRAM_SELFTEST
    scsi_init();
#endif

    *SOFT_GUEST_HOLD = 0;

    // Arm the timer and enable only its interrupt (bit 0); the fault interrupts stay
    // masked so an illegal instruction still traps rather than looping in irq().
    timer_start(TIMER_PERIOD);
    irq_mask(0xFFFFFFFEu);

    // Images are deferload (optional, menu-picked at will), so mount lazily on a drive's
    // first non-zero size, and for a floppy again on each rebind-toggle flip: fdd_mount's
    // eject/insert re-arms floppy.v's media-change line, the only signal a same-size swap
    // gives (hard disks reload the core, so they mount once).
    uint32_t mounted_a = 0;
    uint32_t mounted_b = 0;
    uint32_t mounted_hdd = 0;
    uint32_t settings_sized = 0;        // Settings size declared in the datatable yet
    uint32_t rebind_seen = *FDD_REBIND; // last-seen rebind toggles
    uint32_t jt_fdd_seen = 0;           // last-executed JTAG FDD command seq

    for (;;) {
        // Declare the Settings size once the datatable is populated (retried because the
        // softcore may run before the host has written the table).
        if (!settings_sized) {
            settings_sized = slot_declare_size(SETTINGS_SLOT_ID, SETTINGS_SLOT_BYTES);
        }
        if (!rhythm_done) {
            rhythm_done = rhythm_load();
        }

        uint32_t rebind = *FDD_REBIND;
        if (!mounted_a || ((rebind ^ rebind_seen) & FDD0_REBIND_BIT)) {
            uint32_t sectors = stable_size(FDD0_DISK_SIZE);
            if (sectors != 0) {
                fdd_mount(0, sectors);
                mounted_a = 1;
            }
        }
        if (!mounted_b || ((rebind ^ rebind_seen) & FDD1_REBIND_BIT)) {
            uint32_t sectors = stable_size(FDD1_DISK_SIZE);
            if (sectors != 0) {
                fdd_mount(1, sectors);
                mounted_b = 1;
            }
        }
        rebind_seen = rebind;

        // JTAG FDD commands (probe write slot 0x85 -> FDD_JTCTL, debug builds
        // only: the register reads 0 without PC98_PROBE_EXTRA). A seq change
        // runs cmd once; FDD_JTSTAT echoes the result for probe read 0x26.
        // A JTAG eject survives the auto-mount because mounted_x stays set --
        // same shape as the OSD eject -- and an unbind is only re-armed by a
        // real host rebind.
        uint32_t jt = *FDD_JTCTL;
        if (((jt >> 8) & 0xFF) != jt_fdd_seen) {
            jt_fdd_seen = (jt >> 8) & 0xFF;
            uint32_t cmd = jt & 0xF;
            uint32_t drv = (jt >> 4) & 0x3;
            uint32_t ok = 0;
            if (drv < 2) {
                switch (cmd) {
                case JT_FDD_EJECT:
                    fdd_eject(drv);
                    ok = 1;
                    break;
                case JT_FDD_INSERT:
                    fdd_insert(drv);
                    ok = fdd_is_inserted(drv);
                    break;
                case JT_FDD_MOUNT: {
                    uint32_t s = stable_size(drv ? FDD1_DISK_SIZE : FDD0_DISK_SIZE);
                    if (s != 0) {
                        fdd_mount(drv, s);
                        if (drv == 0) mounted_a = 1; else mounted_b = 1;
                        ok = 1;
                    }
                    break;
                }
                case JT_FDD_UNBIND:
                    fdd_unbind(drv);
                    ok = 1;
                    break;
                case JT_FDD_STAT:
                    ok = 1;
                    break;
                default:
                    break;
                }
            }
            *FDD_JTSTAT = ((fdd_mounted_sectors(drv) & 0xFFF) << 20) |
                          ((ok & 1) << 17) |
                          ((uint32_t) fdd_is_inserted(drv) << 16) |
                          (jt_fdd_seen << 8) | (drv << 4) | cmd;
        }

        if (!mounted_hdd) {
            uint32_t sectors = slot_bytes(HDD0_SLOT_ID) / SECTOR_BYTES;
            if (sectors != 0) {
                scsi_mount(sectors);
                mounted_hdd = 1;
            }
        }

        // Both polls walk the CHIPSET management bus, which arbitrates with
        // the guest cycle-by-cycle -- on the metal this fires tens of
        // thousands of holds a second through the whole boot, and no bench
        // models it (the benches have no softcore). With nothing mounted
        // there is nothing to poll: gate the traffic on a disk being present,
        // and a diskless boot runs with the guest bus entirely its own.
        if (mounted_a || mounted_b)
            fdd_poll();
        gdc_poll();
        if (mounted_hdd)
            scsi_poll();
        settings_service(); // persist any OSD changes into the save window

        // Quiet the polls.
        //
        // Every management-bus access takes the guest's bus through the
        // arbiter, so this loop was the only traffic this core added while the
        // guest booted -- tens of thousands of holds a second, unmodelled by
        // any bench and new since the last build that reached BASIC (the GDC
        // engine and the disk service are both recent). ~1 ms of spacing keeps
        // the FDD far inside its budget (a 1024-byte sector every ~16 ms) and
        // the GDC engine inside its draw latency, and cuts the hold rate ~100x.
        for (volatile uint32_t q = 0; q < 40000u; q++) {
        }
    }

    return 0;
}

// Timer interrupt handler: re-arm the timer, service the OSD, and return the saved
// context unchanged.
uint32_t *irq(uint32_t *regs, uint32_t irq_bits)
{
    (void) irq_bits;
    timer_start(TIMER_PERIOD);
    vkb_ui_tick();
    return regs;
}
