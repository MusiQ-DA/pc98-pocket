; fdc_peek.asm -- minimal: read port 0x92 sixteen times, store, print.
; If the FDC is parked mid-drain, each read returns fifo_q (pops) or reply.
; Injected at SEG:0000 via JTAG, triggered through a hijacked vector.
;
; print line: MSR be | b0..b15 | run
; buf/runcount live at SEG:01E0 (same layout as fdc_probe)

        bits 16
        org 0

start:
        cli
        push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        push    es
        push    si
        push    di

        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        inc     byte [runcount]

        ; snapshot MSR + 0xBE
        mov     dx, 0x90
        in      al, dx
        mov     [buf+0], al
        mov     dx, 0xBE
        in      al, dx
        mov     [buf+1], al

        ; raw reads of the data port, no polling -- whatever comes back, store it
        mov     di, buf+2
        mov     cx, 16
.rd:    mov     dx, 0x92
        in      al, dx
        stosb
        loop    .rd

        ; snapshot MSR again after the reads
        mov     dx, 0x90
        in      al, dx
        mov     [buf+18], al

        ; ---- print ----
        mov     ax, 0xA000
        mov     es, ax
        xor     di, di
        mov     si, buf
        mov     cx, 20              ; MSR BE b0..b15 MSR2
.pb:    lodsb
        mov     bx, ax
        shr     al, 4
        call    putnib
        mov     al, bl
        call    putnib
        mov     al, ' '
        call    putch
        loop    .pb

        mov     al, [runcount]
        mov     bx, ax
        shr     al, 4
        call    putnib
        mov     al, bl
        call    putnib

        ; EOI so IRQ1 can fire again (we preempted the BIOS handler)
        mov     al, 0x20
        out     0x00, al

        pop     di
        pop     si
        pop     es
        pop     ds
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

; ---------------------------------------------------------------- helpers
putnib:
        and     al, 0x0F
        add     al, '0'
        cmp     al, '9'
        jbe     putch
        add     al, 'A'-'9'-1
putch:
        mov     [es:di], al
        mov     byte [es:di+1], 0
        mov     byte [es:di+0x2000], 0xE1
        add     di, 2
        ret

        align 16
runcount: db 0
buf:      times 24 db 0

        align 256
sector_buf:
