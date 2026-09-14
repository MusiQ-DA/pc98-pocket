# PicoRV32 disk-softcore firmware build (LLVM toolchain, rv32im).
# Produces firmware.vh, the $readmemh init image for the softcore ROM.

OBJS = start.o main.o disk_tds.o fdd_service.o ide_service.o scsi_service.o \
       vkb_draw.o vkb_layout.o vkb_ui.o \
       settings_ui.o key_bind.o dpad.o sdramtest.o postmon.o osd_font.o
DEPS = $(OBJS:.o=.d)

# Everything that can change the built image. Hashed into firmware.srchash so CI
# can tell a genuinely stale firmware.vh from a mere toolchain difference:
# different clang versions lay identical sources out differently, so rebuilding
# in CI and byte-comparing the image is pure noise. What actually needs catching
# is someone editing the C and not re-running make, and a source hash catches
# exactly that -- with no compiler needed on the checking side.
SRC_FINGERPRINT = $(sort $(wildcard *.c) $(wildcard *.h) $(wildcard *.S)) \
                  system.ld Makefile ../fpga/config.tcl

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
CFLAGS  = --target=riscv32 -march=rv32im -std=c99 -Os -mno-relax -ffreestanding -Wall -Werror -Wundef -MMD -MP $(HW_DEFINES) $(EXTRA_DEFINES)
ASFLAGS = --target=riscv32 -march=rv32im -mno-relax -Wall -Werror -MMD -MP

all: firmware.vh firmware.srchash

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

firmware.srchash: $(SRC_FINGERPRINT)
	@shasum -a 256 $(SRC_FINGERPRINT) | shasum -a 256 | cut -d' ' -f1 > $@
	@echo "source fingerprint: $$(cat $@)"

# The single definition of the fingerprint, so CI cannot drift from the build.
# Computing the file list in a shell instead invites exactly that: an unquoted
# $(ls ...) word-splits in bash and does not in zsh, which is how the first
# attempt at this silently hashed one long filename.
.PHONY: srchash-print srchash-verify
srchash-print:
	@shasum -a 256 $(SRC_FINGERPRINT) | shasum -a 256 | cut -d' ' -f1

# The softcore is built with ENABLE_DIV(0) -- picorv32_pcpi_div was 216 ALMs
# on a device that is 97 per cent full. A div/rem instruction would not be a
# wrong answer there, it would be an ILLEGAL INSTRUCTION TRAP, and the compiler
# emits them from a bare `/` or `%` without a word. So the absence is a claim,
# and this is the gate: ide_service.c's udiv32 and the menu's compares are what
# keep it true.
nodiv-verify: firmware.elf
	@n=$$($(OBJDUMP) -d firmware.elf | awk '{print $$3}' \
	      | grep -cE '^(div|divu|rem|remu)$$' || true); \
	 if [ "$$n" != "0" ]; then \
	   echo "$$n division instruction(s) in the image, but the softcore has no divider:"; \
	   $(OBJDUMP) -d --symbolize-operands firmware.elf \
	     | awk '/^[0-9a-f]+ </{fn=$$2} /\t(div|divu|rem|remu)\t/{print "  ", fn, $$0}'; \
	   echo "use udiv32() (ide_service.c) or a compare, or re-enable ENABLE_DIV in softcpu_subsystem.sv"; \
	   exit 1; \
	 fi; \
	 echo "no division instructions -- the softcore needs no divider"

srchash-verify: nodiv-verify
	@want=$$(shasum -a 256 $(SRC_FINGERPRINT) | shasum -a 256 | cut -d' ' -f1); \
	 have=$$(cat firmware.srchash 2>/dev/null || echo "<missing>"); \
	 echo "sources  : $$want"; echo "committed: $$have"; \
	 if [ "$$want" != "$$have" ]; then \
	   echo "firmware.vh is stale for these sources -- run make and commit firmware.vh + firmware.srchash"; \
	   exit 1; \
	 fi; \
	 echo "firmware.vh matches its sources"

clean:
	rm -f *.o *.d firmware.elf firmware.bin firmware.vh firmware.srchash

check-format:
	clang-format --dry-run --Werror $(wildcard *.c *.h)

-include $(DEPS)

.PHONY: all clean check-format
