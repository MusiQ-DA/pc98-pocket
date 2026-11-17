; ============================================================================
; fm_test.asm -- PC-9801 OPNA sound-source comparison boot sector.
;
; Plays each OPNA source alone in turn (FM / SSG / ADPCM-A rhythm / all),
; with the source name on screen, so the core and np21w can be compared
; source by source with the same register stream.
;
; part0 = 0x188 addr / 0x18A data  (FM ch1-3, SSG, rhythm 0x10-0x1D)
; part1 = 0x18C addr / 0x18E data  (unused here: ADPCM-B and FM ch4-6)
; The -86 board answers on EVEN ports only (np21w cbus/board86.c attaches
; 0x188/0x18A/0x18C/0x18E; the core's opna_cs requires ~address[0]).
; v1/v2 wrote data to 0x189/0x18B -- open bus, so every register write was
; lost and the disk played silent on the Pocket.
; Rhythm is the YM2608 map (part0: 0x10 key-on/dump, 0x11 TL, 0x18-0x1D
; {L,R,-,IL}), not the YM2610 part1 map v1/v2 used.
; FM voice: ALG=7 (every slot a carrier), OP1+OP2 sounding, OP3/OP4 muted
; with TL=0x7F, ch1-3 triad. (v1/v2 used ALG=0, whose only output is OP4 --
; left at TL=0/AR=0 it never attacks on a real YM2608 or fmgen.)
; SSG voice: tone on A/B/C, volume 11. Rhythm: six voices one at a time.
;
; Assemble: nasm -f bin -o fm_test.bin fm_test.asm    (<= 512 B)
; ============================================================================
BITS 16
CPU 186
ORG 0x0000

OPNA_A0 equ 0x188
EXTGATE equ 0xA460              ; bit0: OPNA (extended) mode

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

        mov ax, 0xA000
        mov es, ax
        mov ah, 0xE1
        mov si, str_title
        mov bx, 0
        call putstr

        ; OPNA (extended) mode, as every -86 driver sets it at start
        mov dx, EXTGATE
        mov al, 0x01
        out dx, al

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
        ; rhythm: total level max, then per-voice pan centre + level max
        mov al, 0x11
        mov ah, 0x3F
        call wr0
        mov al, 0x18
.pan:   mov ah, 0xDF            ; L|R, IL=31
        push ax
        call wr0
        pop ax
        inc ax
        cmp al, 0x1E
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

        ; 3) Rhythm only (needs the WAV kit bound -- no baked ROM)
        mov si, str_rhy
        call status
        mov bp, 3
.rhy:   mov si, rhy_seq
        mov cx, 6
.rv:    lodsb
        mov ah, al
        mov al, 0x10
        call wr0
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
        mov al, 0x10
        mov ah, 0x3F            ; all six voices on
        call wr0
        call wait4
        call fm_off
        call ssg_off
        call rhy_off
        jmp .main

; ---------------------------------------------------------------------------
; wr0: AL = part0 reg, AH = data (ports > 0xFF, so DX-form I/O).
; Address to 0x188, data to 0x18A -- the data port is +2, not +1.
; Waits for status bit 7 (busy) first, as drivers do: the chip needs time to
; apply each write (jt12 keeps ONE pending operator update until its slot
; comes round, ~18 us), and an unpaced burst silently drops TL/AR values.
wr0:    mov dx, OPNA_A0
        push ax
.bz:    in al, dx
        test al, 0x80
        jnz .bz
        pop ax
        out dx, al
        jmp short $+2
        jmp short $+2
        mov al, ah
        inc dx
        inc dx
        out dx, al
        ret

; 0x28 is {slot4,slot3,slot2,slot1, 0, ch[2:0]}: slots in the HIGH nibble,
; channel 0-2 (part0) / 4-6 (part1) in the low bits. v1/v2 wrote 03/13/23 --
; channel 3, which does not exist -- so FM was never keyed on at all.
fm_on:  mov al, 0x28            ; key on ch1-3, all four slots
        mov ah, 0xF0
        call wr0
        mov ah, 0xF1
        call wr0
        mov ah, 0xF2
        call wr0
        ret
fm_off: mov al, 0x28
        mov ah, 0x00
        call wr0
        mov ah, 0x01
        call wr0
        mov ah, 0x02
        call wr0
        ret
ssg_off:
        mov al, 0x07
        mov ah, 0x3F            ; mixer: all off
        call wr0
        ret
rhy_off:
        mov al, 0x10
        mov ah, 0xBF            ; dump: all voices key off
        call wr0
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
        ; FM ch1 (0): ALG=7, PAN=C0, TL/AR/RR for slots 0 and 8, slots 4/C muted
        db 0xB0, 0x07
        db 0xB4, 0xC0
        db 0x40, 0x20, 0x48, 0x20
        db 0x44, 0x7F, 0x4C, 0x7F
        db 0x50, 0x1F, 0x58, 0x1F
        db 0x80, 0x0F, 0x88, 0x0F
        ; FM ch2 (1)
        db 0xB1, 0x07
        db 0xB5, 0xC0
        db 0x41, 0x20, 0x49, 0x20
        db 0x45, 0x7F, 0x4D, 0x7F
        db 0x51, 0x1F, 0x59, 0x1F
        db 0x81, 0x0F, 0x89, 0x0F
        ; FM ch3 (2)
        db 0xB2, 0x07
        db 0xB6, 0xC0
        db 0x42, 0x20, 0x4A, 0x20
        db 0x46, 0x7F, 0x4E, 0x7F
        db 0x52, 0x1F, 0x5A, 0x1F
        db 0x82, 0x0F, 0x8A, 0x0F
        ; FNUM triad, block 7 (~1 kHz with MUL=0): block 4 put a pure
        ; ~124 Hz sine below what the Pocket's speaker can reproduce. A4-A6 only latch; A0-A2 commits the
        ; latched high byte, so the high byte MUST be written first.
        db 0xA4, (7 << 3) | 0x02 ; ch1
        db 0xA0, 0x4D
        db 0xA5, (7 << 3) | 0x02 ; ch2
        db 0xA1, 0x66
        db 0xA6, (7 << 3) | 0x02 ; ch3
        db 0xA2, 0x80
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
