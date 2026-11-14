; ems_np21w -- the EMS bank registers (pc98_ems98, np21w io/emsio.c) through
; the real memory path: z86 (PM286, EXT_MB=8) + z86_cache + cpu_bus_bridge
; + RAM.sv + sdram_mp, in tb_mem_perf (+define+TB_PM286, +ems=<this .hex>).
;
; np21w banks the C0000-CFFFF windows onto the CPU's own extended memory,
; addr = (t << 20) + ((page & 0FCh) << 12), so EMS megabyte 1 page 0 is
; linear 100000h -- FFFF:0010 in real mode with the A20 gate open. A byte
; stored through either name must read back through the other, both ways
; round (a window store kills z86_cache's line for that word; a port-F store
; drains before the uncached window read). IN 08E9h is 00h for t = 1..8
; (maxmem = the 8 MB of extended memory) and FFh for t = 0, 9 and 15.
;
;   nasm -f bin -o ems_np21w.bin ems_np21w.asm ; one hex byte per line
;
; Every result goes out on the bench's log port (OUT 88FCh,AL); the
; expected streams are in scripts/sim_ems.sh. Loaded at 1000:0000.
bits 16
cpu 286
org 0

%macro res 0
    mov dx,0x88FC
    out dx,al
%endmacro
%macro outb 2
    mov dx,%1
    mov al,%2
    out dx,al
%endmacro

    cli
    xor ax,ax
    mov ss,ax
    mov sp,0x0800
    cld
    out 0xF2,al                 ; A20 open
    mov ax,0xFFFF
    mov es,ax                   ; ES:0010 = linear 100000h
    mov ax,0xC000
    mov ds,ax                   ; DS:0000 = window 0

    ; r0: IN 08E9h at reset (t = 0)                         FF
    mov dx,0x08E9
    in al,dx
    res
    ; r1: prime the cached line at 100000h through port F   11
    mov byte [es:0x0010],0x11
    mov al,[es:0x0010]
    res
    ; map window 0 := t=1 page 0 (linear 100000h)
    outb 0x08E9,1
    outb 0x08E1,0
    ; r2: the port-F byte through the window                11
    mov al,[0x0000]
    res
    ; r3: a window store, read back through port F          5A
    mov byte [0x0000],0x5A
    mov al,[es:0x0010]
    res
    ; r4: a port-F store, read back through the window      A5
    mov byte [es:0x0011],0xA5
    mov al,[0x0001]
    res
    ; r5: window 1 := t=1 page 4 (linear 104000h); store
    ;     via the window, read FFFF:4033 = 104023h          3C
    outb 0x08E3,4
    mov byte [0x4023],0x3C
    mov al,[es:0x4033]
    res
    ; r6: window 2 := page 7 -- only page & 0FCh counts, so
    ;     it shows 104000h as well                          3C
    outb 0x08E5,7
    mov al,[0x8023]
    res
    ; r7: t = 0 then a page write unmaps window 3 (hole)    FF
    outb 0x08E9,0
    outb 0x08E7,0
    mov al,[0xC000]
    res
    ; r8: window 0 untouched by that                        5A
    mov al,[0x0000]
    res
    ; r9: t = 9 is not fitted: the page write is dropped    5A
    outb 0x08E9,9
    outb 0x08E1,0x10
    mov al,[0x0000]
    res
    ; r10..r17: IN 08E9h for t = 1..8                       00 x 8
    ; r18, r19: t = 9 and t = 15                            FF FF
    mov cx,1
.scan:
    mov dx,0x08E9
    mov al,cl
    out dx,al
    in al,dx
    res
    inc cx
    cmp cx,10
    jb .scan
    outb 0x08E9,15
    in al,dx
    res
    ; r20: t = 2 page 0 is linear 200000h, past HMA -- the store lands
    ;      in SDRAM word 0x900000 (the bench checks it by peek)    5A
    outb 0x08E9,2
    outb 0x08E1,0
    mov byte [0x0000],0x77
    mov al,0x5A
    res
    ; done
    outb 0x88FE,0xFF
.halt:
    hlt
    jmp .halt
