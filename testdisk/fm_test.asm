; ============================================================================
; fm_test.asm -- PC-9801 OPNA sound-source comparison boot sector.
;
; Plays each OPNA source alone in turn (FM / SSG / ADPCM-A rhythm / all),
; with the source name on screen, so the core and np21w can be compared
; source by source with the same register stream.
;
; part0 = 0x188 addr / 0x189 data  (FM ch1-3, SSG, rhythm total level)
; part1 = 0x18A addr / 0x18B data  (ADPCM-A pan/level/key-on), gated by
;                                   port 0xA460 bit0, set first.
; FM voice: 2-op chain (OP1 -> OP2, ALG=0; OP3/4 unused), ch1-3 triad.
; SSG voice: tone on A/B/C, volume 11. Rhythm: six voices one at a time.
;
; Assemble: nasm -f bin -o fm_test.bin fm_test.asm    (<= 512 B)
; ============================================================================
BITS 16
CPU 186
ORG 0x0000

OPNA_A0 equ 0x188
OPNA_A1 equ 0x18A
EXTGATE equ 0xA460              ; bit0 enables the 0x18A/0x18B pair

        jmp short start
        times 0x20-($-$$) db 0  ; skip the PC-98 IPL header area

; ---------------------------------------------------------------------------
start:
        cli
        cld
        mov ax, cs
        mov ds, ax
        mov ss, ax
        mov sp, 0x0400

        mov dx, EXTGATE
        mov al, 0x01
        out dx, al              ; extended register pair on

        mov ax, 0xA000
        mov es, ax
        mov ah, 0xE1
        mov si, str_title
        mov bx, 0
        call putstr

        ; ---- one-time voice setup: single init table (reg,data, 0xFF ends)
        ; FM ch1-3 voices (ALG=0 2-op, TL/AR/RR per slot) are table entries
        ; too -- the code loop they replaced cost more than the 48 data
        ; bytes the entries add.
        mov si, init_tab
.itab:  lodsb
        cmp al, 0xFF
        je .idone
        mov bl, al
        lodsb
        mov ah, al
        mov al, bl
        call wr0
        jmp .itab
.idone:
        ; rhythm: total level max, per-voice pan centre + level max
        mov al, 0x11
        mov ah, 0x3F
        call wr0
        xor cl, cl
.pan:   mov al, cl
        mov ah, 0xC0
        call wr1
        mov al, cl
        add al, 6
        mov ah, 0x3F
        call wr1
        inc cl
        cmp cl, 6
        jb .pan

        ; ---- section loop --------------------------------------------------
.main:  ; 1) FM only
        mov si, str_fm
        call status
        call ssg_off
        call rhy_off
        call fm_on
        call wait4
        call fm_off

        ; 2) SSG only
        mov si, str_ssg
        call status
        mov al, 0x07
        mov ah, 0x38            ; mixer: tone A/B/C on
        call wr0
        call wait4
        call ssg_off

        ; 3) Rhythm only
        mov si, str_rhy
        call status
        mov bp, 3
.rhy:   mov si, rhy_seq
        mov cx, 6
.rv:    lodsb
        mov ah, al
        mov al, 0x0D
        call wr1
        push cx
        call wait1
        pop cx
        loop .rv
        dec bp
        jnz .rhy
        call rhy_off

        ; 4) All together
        mov si, str_all
        call status
        call fm_on
        mov al, 0x07
        mov ah, 0x38
        call wr0
        mov al, 0x0D
        mov ah, 0x3F            ; all six voices on
        call wr1
        call wait4
        call fm_off
        call ssg_off
        call rhy_off
        jmp .main

; ---------------------------------------------------------------------------
; wr0: AL = part0 reg, AH = data (ports > 0xFF, so DX-form I/O)
wr0:    mov dx, OPNA_A0
        out dx, al
        jmp short $+2
.p0:    in  al, dx
        test al, 0x80
        jnz .p0
        mov al, ah
        inc dx
        out dx, al
        ret
; wr1: AL = part1 reg, AH = data
wr1:    mov dx, OPNA_A1
        out dx, al
        jmp short $+2
.p1:    in  al, dx
        test al, 0x80
        jnz .p1
        mov al, ah
        inc dx
        out dx, al
        ret

fm_on:  mov al, 0x28            ; key on ch1-3 OP1+OP2
        mov ah, 0x03
        call wr0
        mov ah, 0x13
        call wr0
        mov ah, 0x23
        call wr0
        ret
fm_off: mov al, 0x28
        mov ah, 0x00
        call wr0
        mov ah, 0x10
        call wr0
        mov ah, 0x20
        call wr0
        ret
ssg_off:
        mov al, 0x07
        mov ah, 0x3F            ; mixer: all off
        call wr0
        ret
rhy_off:
        mov al, 0x0D
        mov ah, 0xBF            ; all voices key off
        call wr1
        ret

; status: clear 16 cells of row 3 then print ds:si there
status: mov ax, 0xA000
        mov es, ax
        mov ah, 0xE1
        mov bx, 3*160
        mov cx, 16
        mov al, ' '
.clr:   mov [es:bx], al
        mov byte [es:bx+1], 0
        add bx, 2
        loop .clr
        mov bx, 3*160
        ; fall through: si already points at the label
putstr:
.l:     lodsb
        test al, al
        jz .d
        mov [es:bx], al
        mov byte [es:bx+1], 0
        mov [es:bx+0x2000], ah
        add bx, 2
        jmp .l
.d:     ret

; wait1 ~0.35 s, wait4 ~1.4 s (5 MHz ballpark; exact time irrelevant)
wait1:  mov cx, 10
        jmp short wdly
wait4:  mov cx, 40
wdly:   push cx
        mov bx, 0xFFFF
.i:     dec bx
        jnz .i
        pop cx
        loop wdly
        ret

; ---------------------------------------------------------------------------
init_tab:                       ; (reg,data), 0xFF ends
        ; FM ch1 (0): ALG=0, PAN=C0, TL/AR/RR for slots 0 and 8
        db 0xB0, 0x00
        db 0xB4, 0xC0
        db 0x40, 0x20, 0x48, 0x20
        db 0x50, 0x1F, 0x58, 0x1F
        db 0x80, 0x0F, 0x88, 0x0F
        ; FM ch2 (1)
        db 0xB1, 0x00
        db 0xB5, 0xC0
        db 0x41, 0x20, 0x49, 0x20
        db 0x51, 0x1F, 0x59, 0x1F
        db 0x81, 0x0F, 0x89, 0x0F
        ; FM ch3 (2)
        db 0xB2, 0x00
        db 0xB6, 0xC0
        db 0x42, 0x20, 0x4A, 0x20
        db 0x52, 0x1F, 0x5A, 0x1F
        db 0x82, 0x0F, 0x8A, 0x0F
        ; FNUM triad (block 4)
        db 0xA0, 0x4D           ; ch1
        db 0xA4, (4 << 3) | 0x02
        db 0xA1, 0x66           ; ch2
        db 0xA5, (4 << 3) | 0x02
        db 0xA2, 0x80           ; ch3
        db 0xA6, (4 << 3) | 0x02
        ; SSG periods A/B/C, mixer off, volumes 11
        db 0x00, 0x88
        db 0x01, 0x08
        db 0x02, 0xB0
        db 0x03, 0x09
        db 0x04, 0xC8
        db 0x05, 0x0A
        db 0x07, 0x3F           ; mixer off until the SSG section
        db 0x08, 0x0B
        db 0x09, 0x0B
        db 0x0A, 0x0B
        db 0xFF
rhy_seq: db 0x01, 0x02, 0x04, 0x08, 0x10, 0x20

str_title: db "OPNA TEST", 0
str_fm:  db "FM", 0
str_ssg: db "SSG", 0
str_rhy: db "RHYTHM", 0
str_all: db "ALL", 0
