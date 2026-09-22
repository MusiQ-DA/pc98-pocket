/* PicoRV32 disk / OSD softcore memory map.
 * ROM holds the firmware image (loaded into the softcore sprom via firmware.vh);
 * RAM holds .data/.bss and the stack. The OSD framebuffer is a separate MMIO
 * region (0x4xxxxxxx), so RAM has the whole 0x1xxxxxxx data region. Addresses
 * must match the address decode in softcpu_subsystem.
 *
 * The RAM is 2K, sized from the image rather than by habit: .data + .bss are
 * 772 bytes and the deepest stack the image can reach is about 416 bytes
 * (measured from -fstack-usage frames over the call graph, interrupt chain
 * included), so a stack overflow needs to be three times deeper than anything
 * built today. softcpu_subsystem.sv carries the same numbers; keep them in
 * step if either side moves. */
MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 2K
}

SECTIONS {
  __stacktop = ORIGIN(RAM) + LENGTH(RAM);

  . = ORIGIN(ROM);
  .text :
  {
    start*(.text)
    *(.text)
    *(.text.*)
    *(.rodata)
    *(.rodata.*)
  } > ROM

  . = ORIGIN(RAM);
  .data :
  {
    . = ALIGN(4);
    _data_start = .;
    *(.sdata)
    *(.sdata.*)
    *(.data)
    *(.data.*)
    _data_end = .;
  } > RAM AT> ROM

  .bss :
  {
    . = ALIGN(4);
    _bss_start = .;
    *(.sbss)
    *(.sbss.*)
    *(.bss)
    *(.bss.*)
    _bss_end = .;
  } > RAM

  _idata_start = LOADADDR(.data);
}
