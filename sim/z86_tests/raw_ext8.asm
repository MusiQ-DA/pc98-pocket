; raw_ext8 -- the 8 MB extended memory (z86_cache EXT_MB=8, core_top's
; map: linear 100000h-8FFFFFh is SDRAM 0x800000-0xFFFFFF) with the A20 gate
; open: patterns at the bottom (100000h), the middle (4FFFFFh) and the top
; (8FFFF0h-8FFFFFh), the hole right above it (900000h reads FF, a store
; there goes nowhere), and no alias into the low megabyte. Run again with
; +extoff (the OSD's Ext Memory = None): every extended read is FF.
;
;   nasm -f bin -o raw_ext8.bin raw_ext8.asm ; one hex byte per line -> .hex
;   tb_z86_loop built with +define+PM286 +define+EXT_MB=8
;
; Results at 0600h (expected bytes in scripts/sim_z86_tests.sh):
;   600 hole read (base 900000h) after a store there   FF FF
;   602 word at 100000h                                34 12
;   604 word at 10FFFEh                                88 77
;   606 byte at 4FFFFFh                                5A
;   607 (pad)                                          00
;   608 word at 4FFFFCh                                A5 C3
;   60A word at 8FFFF0h                                EF BE
;   60C word at 8FFFFEh, the top word                  96 69
;   60E real 0000:0000 untouched (no alias)            CD AB
;   610 word at 100000h again, after every other store 34 12
;   612 done marker                                    5A
bits 16
cpu 286
org 0x400
    cli
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x0800
    mov word [0x0000],0xABCD
    mov di,0x2000
    mov ax,ds
    mov es,ax
    cld
    mov si,gdt
    mov cx,(gdt_end-gdt)/2
    rep movsw
    mov si,gdtr
    lgdt [si]
    out 0xF2,al                 ; A20 open
    mov ax,1
    lmsw ax
    jmp 0x18:pm_entry
pm_entry:
    mov ax,0x20
    mov es,ax                   ; ES base 600h: the results
    ; ---- stores --------------------------------------------------------
    mov ax,0x10
    mov ds,ax                   ; 100000h
    mov word [0x0000],0x1234
    mov word [0xFFFE],0x7788
    mov ax,0x28
    mov ds,ax                   ; 4F0000h
    mov byte [0xFFFF],0x5A
    mov word [0xFFFC],0xC3A5
    mov ax,0x30
    mov ds,ax                   ; 8F0000h
    mov word [0xFFF0],0xBEEF
    mov word [0xFFFE],0x6996
    mov ax,0x38
    mov ds,ax                   ; 900000h: the hole
    mov word [0x0000],0x1111
    mov ax,[0x0000]
    mov [es:0x00],ax
    ; ---- read back -----------------------------------------------------
    mov ax,0x10
    mov ds,ax
    mov ax,[0x0000]
    mov [es:0x02],ax
    mov ax,[0xFFFE]
    mov [es:0x04],ax
    mov ax,0x28
    mov ds,ax
    mov al,[0xFFFF]
    mov [es:0x06],al
    mov byte [es:0x07],0x00
    mov ax,[0xFFFC]
    mov [es:0x08],ax
    mov ax,0x30
    mov ds,ax
    mov ax,[0xFFF0]
    mov [es:0x0A],ax
    mov ax,[0xFFFE]
    mov [es:0x0C],ax
    mov ax,0x40
    mov ds,ax                   ; base 0
    mov ax,[0x0000]
    mov [es:0x0E],ax
    mov ax,0x10
    mov ds,ax
    mov ax,[0x0000]
    mov [es:0x10],ax
    mov byte [es:0x12],0x5A
    hlt

align 2
gdtr:   dw 0x0047
        dd 0x002000
gdt:
    dq 0
    db 0xFF,0xFF, 0x00,0x20,0x00, 0x93, 0,0      ; 08 the GDT
    db 0xFF,0xFF, 0x00,0x00,0x10, 0x93, 0,0      ; 10 100000h
    db 0xFF,0xFF, 0x00,0x00,0x00, 0x9B, 0,0      ; 18 code, base 0
    db 0xFF,0xFF, 0x00,0x06,0x00, 0x93, 0,0      ; 20 600h
    db 0xFF,0xFF, 0x00,0x00,0x4F, 0x93, 0,0      ; 28 4F0000h
    db 0xFF,0xFF, 0x00,0x00,0x8F, 0x93, 0,0      ; 30 8F0000h
    db 0xFF,0xFF, 0x00,0x00,0x90, 0x93, 0,0      ; 38 900000h, the hole
    db 0xFF,0xFF, 0x00,0x00,0x00, 0x93, 0,0      ; 40 base 0
gdt_end:
