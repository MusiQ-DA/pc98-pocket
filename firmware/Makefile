# PicoRV32 disk-softcore firmware build (LLVM toolchain, rv32i_zmmul).
# Produces firmware.vh, the $readmemh init image for the softcore ROM.
#
# Zmmul is the ratified multiply-only subset of M -- exactly what the softcore
# implements (ENABLE_MUL(1), ENABLE_DIV(0) in softcpu_subsystem.sv). rv32im
# leaves div/rem in the ISA, and whether a bare `/` or `%` becomes a real
# division instruction or a strength-reduced sequence is a per-version size
# heuristic: LLVM 23 emits six that Ubuntu's older clang did not, and every
# one is an illegal-instruction trap on hardware. Under zmmul no compiler can
# emit them at all -- division lowers to a __divsi3-family libcall this
# bare-metal link does not provide, so a stray `/` fails the BUILD on every
# toolchain instead of shipping in the ROM.

OBJS = start.o main.o disk_tds.o fdd_service.o scsi_service.o \
       gdc_service.o rhythm.o adpcma_enc.o \
       vkb_draw.o vkb_layout.o vkb_ui.o \
       settings_ui.o key_bind.o dpad.o sdramtest.o osd_font.o
DEPS = $(OBJS:.o=.d)

CC      = clang
LD      = ld.lld
OBJCOPY = llvm-objcopy
SIZE    = llvm-size
OBJDUMP = llvm-objdump

# Hardware feature macros (ENABLE_*) come from the FPGA build config, so the menu
# code always compiles against the feature set of the bitstream it runs in.
# -Wundef makes an #if on a macro that failed to arrive a hard error, not a silent 0.
HW_CONFIG   = ../fpga/config.tcl
# Anchored at the start of the line so a COMMENTED-OUT macro is not picked up.
# The old pattern was '.*VERILOG_MACRO', which matched
#     # set_global_assignment -name VERILOG_MACRO "SDRAM_SELFTEST=1"
# just as happily as the live line, so commenting a macro out in config.tcl
# disabled it for Quartus and left it defined for the firmware. That is how a
# build ended up with the self-test compiled in after it had been switched off,
# and it applies equally to SDRAM_USE_MP.
HW_DEFINES := $(addprefix -D,$(shell sed -n 's/^[[:space:]]*set_global_assignment.*VERILOG_MACRO "\(.*\)"/\1/p' $(HW_CONFIG)))

# -MMD -MP write per-object header dependencies (.d), pulled in by -include below, so
# editing a header rebuilds every object that includes it.
# -ffreestanding is required on newer LLVM (verified on 23.x): with a hosted
# TargetLibraryInfo, LoopIdiomRecognize rewrites the string-measuring loop in
# vkb_layout.c into a call to strlen, which does not exist in this bare-metal
# link (ld.lld: undefined symbol: strlen). Freestanding disables that rewrite.
# EXTRA_DEFINES is for bisecting on hardware: `make EXTRA_DEFINES=-DFOO`.
# The firmware rides on an SD slot, so a marker costs seconds rather than a
# fifteen-minute bitstream -- but only if there is a way to switch one on.
EXTRA_DEFINES ?=
CFLAGS  = --target=riscv32 -march=rv32i_zmmul -std=c99 -Oz -mno-relax -ffreestanding -Wall -Werror -Wundef -MMD -MP $(HW_DEFINES) $(EXTRA_DEFINES)
# -Oz's first hardware run drew a panel with missing fields and never opened
# the keyboard; the -Os build hours earlier was fine, and nothing static
# explains it -- so every file that draws, reads input, or moves disk sectors
# keeps the PROVEN -Os codegen, and -Oz shrinks only the two files whose
# savings (settings_ui 340 B, scsi_service 108 B) are what make the ROM
# budget at all. If those two misbehave it is the settings menu or SCSI,
# never the keyboard.
main.o vkb_ui.o vkb_draw.o vkb_layout.o dpad.o key_bind.o osd_font.o fdd_service.o disk_tds.o gdc_service.o sdramtest.o: CFLAGS := $(subst -Oz,-Os,$(CFLAGS))
ASFLAGS = --target=riscv32 -march=rv32i_zmmul -mno-relax -Wall -Werror -MMD -MP

all: firmware.vh

# The -D values are baked into every object, so a config change rebuilds them all.
$(OBJS): $(HW_CONFIG)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S
	$(CC) $(ASFLAGS) -c $< -o $@

firmware.elf: $(OBJS) system.ld
	$(LD) -T system.ld $(OBJS) -o $@
	$(SIZE) $@

firmware.bin: firmware.elf
	$(OBJCOPY) --keep-section=.text --keep-section=.data --output-target=binary $< $@

firmware.vh: firmware.bin
	hexdump -v -e '4/4 "%08x " "\n"' $< > $@

# The softcore is built with ENABLE_DIV(0) -- picorv32_pcpi_div was 216 ALMs
# on a device that is 97 per cent full. A div/rem instruction would not be a
# wrong answer there, it would be an ILLEGAL INSTRUCTION TRAP. rv32i_zmmul
# already makes emitting one a link failure (the __divsi3-family libcalls do
# not exist here), so this gate should never fire -- it stays as the CI job
# because disassembling the real image is the check that cannot drift.
nodiv-verify: firmware.elf
	@n=$$($(OBJDUMP) -d firmware.elf | awk '{print $$3}' \
	      | grep -cE '^(div|divu|rem|remu)$$' || true); \
	 if [ "$$n" != "0" ]; then \
	   echo "$$n division instruction(s) in the image, but the softcore has no divider:"; \
	   $(OBJDUMP) -d --symbolize-operands firmware.elf \
	     | awk '/^[0-9a-f]+ </{fn=$$2} /\t(div|divu|rem|remu)\t/{print "  ", fn, $$0}'; \
	   echo "use udiv32() (gdc_service.c) or a compare, or re-enable ENABLE_DIV in softcpu_subsystem.sv"; \
	   exit 1; \
	 fi; \
	 echo "no division instructions -- the softcore needs no divider"

clean:
	rm -f *.o *.d firmware.elf firmware.bin firmware.vh firmware.srchash

check-format:
	clang-format --dry-run --Werror $(wildcard *.c *.h)

-include $(DEPS)

.PHONY: all clean check-format nodiv-verify
