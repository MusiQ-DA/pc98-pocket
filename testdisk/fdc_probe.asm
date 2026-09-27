; fdc_probe.asm -- FDC status + PIO sector read, injected at SEG:0000 via JTAG.
; Runs in IRQ context (triggered through a hijacked vector).
;
; What it does:
;   1. snapshots MSR (0x90), drive port (0xBE)
;   2. SPECIFY with ND=1 (PIO mode), RECALIBRATE, SENSE INT
;   3. READ DATA sec C0/H0/R1/N=3 -> 1024 bytes via data port (no DMA)
;      into sector_buf (seg:0400 = phys SEG*16+0x400)
;   4. reads 7 result bytes
;   5. prints hex: MSR BE | rST0 rPCN | ST0 ST1 ST2 C H R | run
;
; Compare the sector_buf dump against the .hdm image to split "upstream of
; the DMA" (tds/BRAM/fifo) from "the DMA write itself".

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
        push    bp

        mov     ax, cs
        mov     ds, ax
        mov     es, ax              ; sector_buf/res_buf live in our segment
        inc     byte [runcount]

        ; drain the keyboard byte our hijacked vector preempted: without this
        ; the 8251 keeps it pending and IRQ1 never re-fires, so the probe can
        ; only ever run once per boot.
        mov     dx, 0x41
        in      al, dx

        ; ---- snapshot status ----
        mov     dx, 0x90
        in      al, dx
        mov     [buf+0], al             ; MSR
        mov     dx, 0xBE
        in      al, dx
        mov     [buf+1], al             ; 0xBE

        ; ---- FDC soft reset: 0x94 bit7 0->1 edge -> sw_reset -> S_IDLE ----
        mov     dx, 0x94
        xor     al, al
        out     dx, al                  ; ctrl_q[7] := 0 (prime the edge)
        mov     cx, 0x2000
.rst0:  loop    .rst0
        mov     al, 0x80
        out     dx, al                  ; rising edge -> reset_pending -> reset
        mov     cx, 0x4000
.rst1:  loop    .rst1

        ; ---- drop DMAE so no stray DMAC cycle can fire ----
        mov     dx, 0x94
        mov     al, 0x08                ; keep motor-attn bit3, clear bit4 DMAE
        out     dx, al

        ; ---- SPECIFY: 0x03, 0xDF, 0x03 (ND=1) ----
        call    wcmd
        mov     al, 0x03
        call    wd92
        call    wcmd
        mov     al, 0xDF
        call    wd92
        call    wcmd
        mov     al, 0x03                ; HLT=1, ND=1 -> PIO mode
        call    wd92

        ; ---- RECALIBRATE drive 0 ----
        call    wcmd
        mov     al, 0x07
        call    wd92
        call    wcmd
        xor     al, al
        call    wd92

        ; wait ~200ms for seek/attn
        mov     bp, 60
.d1:    mov     cx, 0xFFFF
.d1l:   loop    .d1l
        dec     bp
        jnz     .d1

        ; ---- SENSE INTERRUPT STATUS -> ST0, PCN ----
        call    wcmd
        mov     al, 0x08
        call    wd92
        call    wres
        jc      .sifail
        call    rd92
        mov     [buf+2], al             ; ST0
        call    wres
        jc      .sifail
        call    rd92
        mov     [buf+3], al             ; PCN
        jmp     .doread
.sifail:
        mov     word [buf+2], 0xFFFF

.doread:
        ; ---- READ DATA: 46 00 00 00 01 03 08 1B FF ----
        call    wcmd
        mov     al, 0x46                ; MFM read
        call    wd92
        call    wcmd
        xor     al, al                  ; unit = HD<<2|US = 0
        call    wd92
        call    wcmd
        xor     al, al                  ; C = 0
        call    wd92
        call    wcmd
        xor     al, al                  ; H = 0
        call    wd92
        call    wcmd
        mov     al, 0x08                ; R = 8 = EOT: a single-sector read so
                                        ; the result phase actually arrives
        call    wd92
        call    wcmd
        mov     al, 0x03                ; N = 3 (1024B)
        call    wd92
        call    wcmd
        mov     al, 0x08                ; EOT = 8
        call    wd92
        call    wcmd
        mov     al, 0x1B                ; GPL
        call    wd92
        call    wcmd
        mov     al, 0xFF                ; DTL
        call    wd92

        ; ---- drain 1024 data bytes ----
        mov     di, sector_buf
        mov     cx, 1024
.rd:
        call    wres
        jc      .rdtimo
        call    rd92
        stosb
        loop    .rd
.rdtimo:
        mov     [buf+8], cl             ; leftover count (0 = full read)
        mov     [buf+9], ch

        ; ---- 7 result bytes ----
        mov     di, res_buf
        mov     cx, 7
.rs:
        call    wres
        jc      .rdone
        call    rd92
        stosb
        loop    .rs
.rdone:

        ; ---- print: MSR BE ST0s PCN | ST0 ST1 ST2 C H R N | cnt run ----
        mov     ax, 0xA000
        mov     es, ax
        xor     di, di
        mov     si, buf
        mov     cx, 4                   ; MSR BE sST0 sPCN
.pb:    lodsb
        mov     bx, ax
        shr     al, 4
        call    putnib
        mov     al, bl
        call    putnib
        mov     al, ' '
        call    putch
        loop    .pb

        mov     si, res_buf
        mov     cx, 7                   ; ST0 ST1 ST2 C H R N
.rb:    lodsb
        mov     bx, ax
        shr     al, 4
        call    putnib
        mov     al, bl
        call    putnib
        mov     al, ' '
        call    putch
        loop    .rb

        mov     al, [buf+9]             ; bytes NOT read (hi/lo), 0000 = all read
        mov     bx, ax
        shr     al, 4
        call    putnib
        mov     al, bl
        call    putnib
        mov     al, [buf+8]
        mov     bx, ax
        shr     al, 4
        call    putnib
        mov     al, bl
        call    putnib
        mov     al, ' '
        call    putch

        mov     al, [runcount]
        mov     bx, ax
        shr     al, 4
        call    putnib
        mov     al, bl
        call    putnib

        ; EOI so IRQ1 can fire again (we preempted the BIOS handler)
        mov     al, 0x20
        out     0x00, al

        pop     bp
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

; putnib: AL low nibble -> hex char -> TVRAM cell at ES:DI, DI+=2
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

; wcmd: poll MSR for RQM=1,DIO=0 (ready for a command/param byte). no timeout:
; the FDC parks there. CF stays 0.
wcmd:
        push    cx
        mov     cx, 0xFFFF
.wc:    mov     dx, 0x90
        in      al, dx
        test    al, 0x80
        jz      .wcn
        test    al, 0x40
        jz      .ok
.wcn:   loop    .wc
.ok:    pop     cx
        ret

; wres: poll MSR for RQM=1,DIO=1 (data byte available). CF=1 on timeout.
; The JTAG mgmt pump refills the fifo at scan speed (~8 ms/byte, a whole
; sector in seconds), so the first-byte wait needs minutes, not ~ms: bp outer
; wraps the 64K inner poll. Once the fifo is full the controller streams and
; later iterations never reach the outer loop.
wres:
        push    cx
        push    bp
        mov     bp, 600
.wr0:   mov     cx, 0xFFFF
.wr:    mov     dx, 0x90
        in      al, dx
        test    al, 0x80
        jz      .wrn
        test    al, 0x40
        jnz     .ok
.wrn:   loop    .wr
        dec     bp
        jnz     .wr0
        stc
        pop     bp
        pop     cx
        ret
.ok:    clc
        pop     bp
        pop     cx
        ret

; wd92: write AL to data port 0x92 (clobbers DX)
wd92:
        mov     dx, 0x92
        out     dx, al
        ret

; rd92: read data port 0x92 into AL (clobbers DX)
rd92:
        mov     dx, 0x92
        in      al, dx
        ret

        align 16
runcount: db 0
buf:      times 16 db 0
res_buf:  times 8  db 0

        align 256
sector_buf:
