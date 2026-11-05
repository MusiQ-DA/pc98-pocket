; raw_pm -- z86's minimal 80286 protected mode (PM286): LGDT/SGDT, LMSW/SMSW,
; descriptor bases on MOV/POP sreg, far JMP/CALL/RETF, LES, extended memory
; on port F and the hole above it, the A20 gate both ways, and OUT 0F0h
; (tb_z86_loop +f0reset) as the only way back to real mode.
;
;   nasm -f bin -o raw_pm.bin raw_pm.asm ; one hex byte per line -> raw_pm.hex
;   tb_z86_loop built with +define+PM286 (scripts/sim_z86_tests.sh PM286=1)
;
; Results at 0600h (expected bytes in scripts/sim_z86_tests.sh):
;   600 SGDT: limit 3F 00, base 00 20 00, FF
;   606 SMSW in PM: F1 FF
;   608 ext word via DS=10h [0]       34 12
;   60A real 0000:0000 untouched      CD AB
;   60C hole read (base 300000h)      FF FF
;   60E top word of extended memory   5A A5
;   610 POP DS in PM, then [0]        34 12
;   612 HMA word written in real mode with A20 open, read in PM: 21 43
;   614 LES in PM: ES:BX -> ext       34 12
;   616 far CALL / RETF in PM         CC
;   617 byte at base 012345h + 0, read back in PM: 77
;   618 after OUT 0F0h: SMSW          F0 FF
;   61A after reset, FFFF:0010 with A20 closed reads 0000:0000: CD AB
;   61C after reset, 1234:0005 (= 12345h) in real mode: 77
;   61D the run count: F6 (from the bench's F4 fill: once to the reset,
;       once after)
bits 16
cpu 286
org 0x400
    cli
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x0800
    inc byte [0x61D]
    cmp byte [0x5F0],0xA5
    jne first_run
    jmp after_reset
first_run:
    mov word [0x0000],0xABCD
    ; ---- the GDT at 2000h -------------------------------------------
    mov di,0x2000
    mov ax,ds
    mov es,ax
    cld
    mov si,gdt
    mov cx,(gdt_end-gdt)/2
    rep movsw
    mov si,gdtr
    lgdt [si]
    sgdt [0x600]
    ; ---- real mode, A20 open: the HMA reaches extended memory --------
    out 0xF2,al
    mov ax,0xFFFF
    mov ds,ax
    mov word [0x20],0x4321      ; linear 100010h
    xor ax,ax
    mov ds,ax
    ; ---- enter protected mode -----------------------------------------
    mov ax,1
    lmsw ax
    jmp 0x18:pm_entry           ; base 0: offsets stay linear
pm_entry:
    mov ax,0x20
    mov es,ax                   ; ES base 600h
    smsw ax
    mov [es:0x06],ax
    mov ax,0x10
    mov ds,ax                   ; DS base 100000h
    mov word [0x0000],0x1234
    mov ax,[0x0000]
    mov [es:0x08],ax
    mov ax,0x40
    mov ds,ax                   ; DS base 0
    mov ax,[0x0000]
    mov [es:0x0A],ax
    mov ax,0x30
    mov ds,ax                   ; DS base 300000h: past EXT_MB=2
    mov word [0x0000],0x5555
    mov ax,[0x0000]
    mov [es:0x0C],ax
    mov ax,0x28
    mov ds,ax                   ; DS base 2FFFF0h
    mov word [0x000E],0xA55A
    mov ax,[0x000E]
    mov [es:0x0E],ax
    push word 0x10
    pop ds
    mov ax,[0x0000]
    mov [es:0x10],ax
    mov ax,[0x0010]             ; 100010h, the HMA store
    mov [es:0x12],ax
    mov word [es:0x40],0x0000   ; far pointer 10:0000 at 640h
    mov word [es:0x42],0x0010
    push es
    les bx,[es:0x40]
    mov ax,[es:bx]
    pop es
    mov [es:0x14],ax
    call 0x18:far_fn
    mov ax,0x38
    mov ds,ax                   ; DS base 012345h
    mov byte [0x0000],0x77
    mov al,[0x0000]
    mov [es:0x17],al
    mov ax,0x40
    mov ds,ax
    mov byte [0x5F0],0xA5
    out 0xF0,al                 ; CPU reset: back to real mode
    hlt
far_fn:
    mov byte [es:0x16],0xCC
    retf

after_reset:
    smsw ax
    mov [0x618],ax
    mov ax,0xFFFF
    mov ds,ax
    mov ax,[0x0010]             ; A20 closed: linear 0000:0000
    xor bx,bx
    mov ds,bx
    mov [0x61A],ax
    mov ax,0x1234
    mov ds,ax
    mov al,[0x0005]
    mov ds,bx
    mov [0x61C],al
    hlt

align 2
gdtr:   dw 0x003F                ; 8 descriptors -- 40h lies past it, unchecked
        dd 0x002000
gdt:
    dq 0
    db 0xFF,0xFF, 0x00,0x20,0x00, 0x93, 0,0      ; 08 the GDT
    db 0xFF,0xFF, 0x00,0x00,0x10, 0x93, 0,0      ; 10 100000h
    db 0xFF,0xFF, 0x00,0x00,0x00, 0x9B, 0,0      ; 18 code, base 0
    db 0xFF,0xFF, 0x00,0x06,0x00, 0x93, 0,0      ; 20 600h
    db 0xFF,0xFF, 0xF0,0xFF,0x2F, 0x93, 0,0      ; 28 2FFFF0h
    db 0xFF,0xFF, 0x00,0x00,0x30, 0x93, 0,0      ; 30 300000h
    db 0xFF,0xFF, 0x45,0x23,0x01, 0x93, 0,0      ; 38 012345h
    db 0xFF,0xFF, 0x00,0x00,0x00, 0x93, 0,0      ; 40 base 0 (past the limit)
gdt_end:
