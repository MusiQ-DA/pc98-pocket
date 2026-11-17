; ============================================================================
; fmch_test.asm -- PC-9801-86 OPNA per-channel FM check boot sector.
;
; Plays the same tone on FM channel 1..6 one at a time (~1.4 s each, at
; 10 MHz), with "CH1".."CH6" on screen, then loops. Every channel gets the
; identical voice and pitch, so a missing or quieter channel stands out.
;
;   part0 = 0x188 addr / 0x18A data   (ch1-3)
;   part1 = 0x18C addr / 0x18E data   (ch4-6; needs 0xA460 bit0 = 1)
;   key-on 0x28 (part0 only): {slots[7:4], 0, ch[2:0]}, ch = 0,1,2,4,5,6
;
; Voice: ALG=7, S1 carrier at TL 0 (full scale), S2-S4 muted (TL 0x7F), AR 31,
; RR 15, pan L+R, block 7 / fnum 0x24D (~1 kHz). Every write polls busy first.
;
; Assemble: nasm -f bin -o fmch_test.bin fmch_test.asm   (<= 512 B)
; ============================================================================
BITS 16
CPU 186
ORG 0x0000

        jmp short start
        times 0x20-($-$$) db 0

start:
        cli
        cld
        mov ax, cs
        mov ds, ax
        mov ss, ax
        mov sp, 0x0400

        mov dx, 0xA460          ; OPNA (extended) mode
        mov al, 0x01
        out dx, al

        ; ---- voice on all six channels ----------------------------------
        ; di = part (0x188 or 0x18C); cl = channel offset 0..2
        mov di, 0x188
.part:  xor cl, cl
.ch:    mov si, voice
.v:     lodsb                   ; register base
        cmp al, 0xFF
        je .vdone
        add al, cl
        mov bl, al
        lodsb
        mov ah, al
        mov al, bl
        call wr
        jmp .v
.vdone: inc cl
        cmp cl, 3
        jb .ch
        cmp di, 0x18C
        je .loop
        mov di, 0x18C
        jmp .part

        ; ---- one channel at a time ----------------------------------------
.loop:  xor bp, bp              ; 0..5
.next:  mov ax, 0xA000
        mov es, ax
        mov bx, 3*160
        mov byte [es:bx],   'C'
        mov byte [es:bx+2], 'H'
        mov ax, bp
        add al, '1'
        mov [es:bx+4], al
        mov byte [es:bx+1], 0
        mov byte [es:bx+3], 0
        mov byte [es:bx+5], 0
        mov byte [es:bx+0x2000], 0xE1
        mov byte [es:bx+0x2002], 0xE1
        mov byte [es:bx+0x2004], 0xE1

        mov ax, bp              ; key code: 0,1,2 -> 0,1,2 ; 3,4,5 -> 4,5,6
        cmp al, 3
        jb .kc
        inc al
.kc:    mov ah, al
        or ah, 0xF0
        mov di, 0x188
        push ax
        mov al, 0x28
        call wr                 ; key on
        call wait4
        pop ax
        and ah, 0x07
        mov al, 0x28
        call wr                 ; key off
        call wait1

        inc bp
        cmp bp, 6
        jb .next
        jmp .loop

; wr: AL = reg, AH = data, DI = address port (0x188 / 0x18C); data = DI+2.
; Polls busy (status 0 at 0x188, bit 7) before the address write.
wr:     push ax
        mov dx, 0x188
.bz:    in al, dx
        test al, 0x80
        jnz .bz
        pop ax
        mov dx, di
        out dx, al
        jmp short $+2
        jmp short $+2
        mov al, ah
        inc dx
        inc dx
        out dx, al
        ret

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

; (register base, data) per channel; channel offset is added to the base.
; S1 = +0x00, S3 = +0x04, S2 = +0x08, S4 = +0x0C.
voice:  db 0xB0, 0x07           ; FB 0, ALG 7
        db 0xB4, 0xC0           ; L+R
        db 0x40, 0x00           ; S1 TL 0: full scale, so quiet-vs-silent is unambiguous
        db 0x44, 0x7F           ; S3 muted
        db 0x48, 0x7F           ; S2 muted
        db 0x4C, 0x7F           ; S4 muted
        db 0x50, 0x1F           ; S1 AR 31
        db 0x60, 0x00
        db 0x70, 0x00
        db 0x80, 0x0F           ; S1 SL 0 / RR 15
        db 0xA4, (7 << 3) | 0x02 ; block 7 (~1 kHz; block 4 was a ~124 Hz sine the
                                 ; Pocket's speaker cannot reproduce), fnum hi first
        db 0xA0, 0x4D           ; fnum lo commits
        db 0xFF
