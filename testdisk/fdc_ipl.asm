; fdc_ipl.asm -- IPL that re-reads C0/H0/R1 via FDC PIO (ndma) and stashes the
; sector at 0x4000:0000 for JTAG dump, so "upstream of the DMAC" (dataslot ->
; bridge RAM -> FDC FIFO -> PIO) can be compared byte-for-byte against the
; image, isolating the DMAC write path as the suspect for the dropped bytes
; seen in the DMA-delivered copy at 1FE0:0000.
;
; Must fit the 512-byte IPL window the BIOS actually transfers.
;
; Screen row 0 shows progress marks: I S R D ... P E  (PIO read stages).
; Sector lands at phys 0x40000, result bytes at phys 0x40400.

        bits 16
        org 0

start:
        cli
        mov     ax, cs          ; 1FE0
        mov     ds, ax
        mov     ax, 0x4000      ; sector lands at phys 0x40000
        mov     es, ax
        xor     di, di

        mov     al, 'I'
        call    putmark

        ; ---- FDC soft reset: 0x94 bit7 0->1 edge ----
        mov     dx, 0x94
        xor     al, al
        out     dx, al
        mov     cx, 0x3000
.d0:    loop    .d0
        mov     al, 0x80
        out     dx, al
        mov     cx, 0x3000
.d1:    loop    .d1

        ; ---- SPECIFY (ndma): 03 DF 03 ----
        mov     al, 'S'
        call    putmark
        call    wcmd
        mov     al, 0x03
        call    wd92
        call    wcmd
        mov     al, 0xDF
        call    wd92
        call    wcmd
        mov     al, 0x03
        call    wd92

        ; ---- READ DATA: 46 00 00 00 01 03 08 1B FF ----
        mov     al, 'R'
        call    putmark
        mov     si, cmd
        mov     cx, 9
.sc:    call    wcmd
        lodsb
        call    wd92
        loop    .sc

        mov     al, 'D'
        call    putmark

        ; ---- drain 1024 bytes to ES:0000 (phys 0x40000) ----
        xor     di, di
        mov     cx, 1024
.rd:    mov     dx, 0x90
        in      al, dx
        and     al, 0xC0
        cmp     al, 0xC0
        jne     .rd
        mov     dx, 0x92
        in      al, dx
        stosb
        loop    .rd

        ; ---- 7 result bytes to ES:0400 (phys 0x40400) ----
        mov     al, 'P'
        call    putmark
        mov     cx, 7
.rs:    mov     dx, 0x90
        in      al, dx
        and     al, 0xC0
        cmp     al, 0xC0
        jne     .rs
        mov     dx, 0x92
        in      al, dx
        stosb
        loop    .rs

        mov     al, 'E'
        call    putmark

hang:   jmp     hang

; ---------------------------------------------------------------- helpers
; putmark: AL -> next TVRAM cell (advances markpos). Preserves everything.
putmark:
        push    es
        push    di
        push    ax                      ; char on top: pop order is ax,di,es
        mov     ax, 0xA000
        mov     es, ax
        mov     di, [cs:markpos]
        pop     ax                      ; restore AL before the store
        mov     [es:di], al
        mov     byte [es:di+1], 0
        mov     byte [es:di+0x2000], 0xE1
        add     word [cs:markpos], 2
        pop     di
        pop     es
        ret

; wcmd: poll MSR bit7=1 bit6=0 before writing a command/param byte
wcmd:
        push    dx
        mov     dx, 0x90
.wc:    in      al, dx
        and     al, 0xC0
        cmp     al, 0x80
        jne     .wc
        pop     dx
        ret

; wd92: write AL to data port
wd92:
        push    dx
        mov     dx, 0x92
        out     dx, al
        pop     dx
        ret

markpos: dw 0
cmd:     db 0x46, 0x00, 0x00, 0x00, 0x01, 0x03, 0x01, 0x1B, 0xFF

        times 510-($-$$) db 0x90        ; pad inside the guaranteed window
        db 0xEB, 0xFE                   ; safety net at the window's tail
