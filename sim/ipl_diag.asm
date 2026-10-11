; ipl_diag.asm -- minimal boot-sector diagnostic for REAL hardware.
; Loaded at phys 0x1FC00 (CS=0x1FC0).  Writes a breadcrumb byte to the
; 0x50000 mailbox after EVERY instruction so JTAG can see exactly where the
; CPU stops.  No far transfers, no second segment -- isolates basic fetch.
[BITS 16]
org 0
MBX equ 0x5000
start:
    cli
    mov ax, MBX
    mov es, ax
    mov byte [es:0x00], 'D'     ; sig
    mov byte [es:0x01], 'G'
    ; simple linear breadcrumbs 0x10..0x1f -- one per instruction
    mov ax, 0x1111
    mov byte [es:0x10], 0x01
    mov bx, 0x2222
    mov byte [es:0x11], 0x02
    mov cx, 0x3333
    mov byte [es:0x12], 0x03
    mov dx, 0x4444
    mov byte [es:0x13], 0x04
    ; a near call+ret (no far)
    mov byte [es:0x14], 0x05
    call nearfunc
    mov byte [es:0x15], 0x06
    ; a small rep movsb within our segment -> mailbox+0x200
    mov ax, 0x1FC0
    mov ds, ax
    mov si, srcdata - start
    mov di, 0x0200
    mov cx, 8
    rep movsb
    mov byte [es:0x16], 0x07
    ; a short backward loop (near jmp)
    mov cx, 5
    mov byte [es:0x17], 0x08
loop1:
    mov byte [es:0x18], cl
    loop loop1
    mov byte [es:0x19], 0x09
    ; push/pop stack (SS needed) -- set SS/SP inside our image is risky;
    ; use a scratch stack in a clean segment
    mov ax, 0x6000
    mov ss, ax
    mov sp, 0xFFFE
    push ax
    push bx
    pop bx
    pop ax
    mov byte [es:0x1a], 0x0a
    ; int via our own vector?  skip -- just write pass and loop
    mov byte [es:0x1b], 0x0b
    ; ---- data-read of own code: read DS:0 (the `cli` byte at phys 0x1FC00)
    ; if fetch==data the CPU reads 0xFA; a phantom/stale fetch reads 0x00.
    mov ax, 0x1FC0
    mov ds, ax
    mov al, [0x0000]            ; DS:0 -> phys 0x1FC00 (cli=0xFA)
    mov [es:0x30], al           ; report fetched byte
    mov al, [0x0001]            ; mov ax,0x1fc0 -> 0xB8
    mov [es:0x31], al
    ; ---- CPU write+read probe of the code region (DS:0x300 = phys 0x1FF00,
    ; inside the sector's zero pad -- safe). If it reads back, the data path
    ; works here and the zeros above mean the IPL is fetch-only.
    mov byte [0x0300], 0xAB
    mov al, [0x0300]
    mov [es:0x33], al           ; expect 0xAB if data path works at 0x1FF00
    mov byte [0x0301], 0xCD
    mov al, [0x0301]
    mov [es:0x34], al
    pushf
    pop ax
    mov [es:0x32], ah           ; report flags hi (DF=bit10)
    mov byte [es:0x02], 0xAC    ; PASS marker
forever:
    mov byte [es:0x03], al        ; heartbeat (al varies? keep it simple)
    inc al
    jmp forever
nearfunc:
    mov byte [es:0x1e], 0x0f
    ret
srcdata: db 'Q','W','E','R','T','Y','U','I'
times 1024 - ($ - $$) db 0
