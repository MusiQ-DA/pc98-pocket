; hdd_test.asm -- IPL for the SCSI HDD test images (testdisk/build_hdd.sh).
;
; The PC-9801-55 option ROM (fpga/scsi_rom.asm post_boot) reaches this from
; the BIOS boot sweep at device 0x0C: two sectors at LBA 0 land at 1FC0:0000
; and are far-called with np21w's hand-off -- AX = 00A0, BX = 0400,
; CX = DX = BP = 0, ES = 1FC0, DISK_BOOT [0:0584] = A0. No signature check:
; whatever sits at offset 0 runs.
;
; It then exercises the disk BIOS the way a DOS IPL and IO.SYS would:
;   1. INT 1Bh AH=84h (sense, geometry) on DA/UA A0
;   2. a CHS read (DA A0) of the disk's LAST sector, C-1/H-1/S-1, which the
;      image builder stamped "GEO!" + its LBA -- a geometry the ROM got
;      wrong reads some other sector
;   3. the same sector through an LBA read (DA 20, DL:CX)
;   4. a write/read-back of scratch LBA 2, then the original put back
; and checks DISK_EQUIPS [0:0482] bit 0 (the "SCSI unit 0 fitted" bit DOS
; reads).
;
; Screen, text VRAM rows 0-2 (hex values):
;   SCSI HDD IPL OK
;   AX=00A0 584=A0 482=01 C=cccc H=hh S=ss B=0200
;   CHS=00/01 LBA=00/01 WR=00/01 PASS        (status / match)
; anything but PASS reads FAIL. The same results land at phys 0x40000 for a
; JTAG readback (scripts/jtag_scsiboot.tcl) and the sim bench:
;   +00 "SCSI HDD IPL OK",0      +10 entry AX BX CX DX BP ES DS (words)
;   +1E [0584] [0482]            +20 sense: DX CX BX, AH, CF
;   +28 chs st/match  +2A lba st/match  +2C wr st/match  +2E 'P'/'F'  +2F A5
; then it parks (JMP $) so the screen outlives the boot; RESET to leave.
;
; Must fit the two sectors the ROM loads (1024 bytes); the stamp the image
; builder writes lives in the disk's last sector, the scratch in LBA 2.

        bits 16
        cpu 186
        org 0

%define RES      0x4000         ; result block segment (phys 0x40000)
%define BUFSEG   0x5000         ; sector buffers at 0x50000 / 0x50200 / 0x50400

start:
        mov     [cs:e_ax], ax
        mov     [cs:e_bx], bx
        mov     [cs:e_cx], cx
        mov     [cs:e_dx], dx
        mov     [cs:e_bp], bp
        mov     [cs:e_es], es
        mov     [cs:e_ds], ds
        cld
        push    cs
        pop     ds

        mov     ax, RES                 ; clear the result block, then the
        mov     es, ax                  ; banner first: it says "we ran"
        xor     di, di
        xor     ax, ax
        mov     cx, 0x18
        rep     stosw
        xor     di, di
        mov     si, banner
        mov     cx, 16
        rep     movsb
        mov     si, e_ax                ; entry registers -> +10
        mov     cx, 7
        rep     movsw
        xor     ax, ax
        mov     ds, ax
        mov     al, [0x0584]
        mov     ah, [0x0482]
        push    cs
        pop     ds
        mov     [es:0x1E], ax

        mov     di, 0                   ; row 0
        mov     si, banner
        call    puts

        ; ---- 1: sense, AH=84h ------------------------------------------
        mov     ax, 0x84A0
        int     0x1B
        mov     [es:0x20], dx
        mov     [es:0x22], cx
        mov     [es:0x24], bx
        mov     [es:0x26], ah
        mov     byte [es:0x27], 0
        jnc     .sok
        mov     byte [es:0x27], 1
.sok:
        ; ---- 2: CHS read of C-1 / H-1 / S-1 ------------------------------
        mov     cx, [es:0x22]
        dec     cx
        mov     dx, [es:0x20]
        sub     dx, 0x0101              ; DH = heads-1, DL = spt-1 (zero-based)
        mov     ax, 0x06A0
        mov     si, 0x28
        call    rd_check
        ; ---- 3: the same sector, LBA form: DL:CX = C*H*S - 1 -------------
        mov     al, [es:0x21]           ; heads
        mul     byte [es:0x20]          ; AX = heads * spt
        mul     word [es:0x22]          ; DX:AX = sectors
        sub     ax, 1
        sbb     dx, 0
        mov     cx, ax
        mov     ax, 0x0620
        mov     si, 0x2A
        call    rd_check

        ; ---- 4: LBA 2 -- save, write a pattern, read back, restore ------
        mov     bp, 0x0400              ; original -> BUFSEG:0400
        mov     ax, 0x0620
        call    xfer2
        jc      .wfail
        push    es
        mov     ax, BUFSEG
        mov     es, ax
        mov     di, 0x0200              ; pattern -> BUFSEG:0200
        mov     cx, 512
        mov     al, 0x3C
.pat:   stosb
        add     al, 0x4B
        loop    .pat
        pop     es
        mov     bp, 0x0200
        mov     ax, 0x0520              ; write
        call    xfer2
        jc      .wfail
        xor     bp, bp                  ; read back -> BUFSEG:0000
        mov     ax, 0x0620
        call    xfer2
        jc      .wfail
        push    ds
        push    es
        mov     ax, BUFSEG
        mov     ds, ax
        mov     es, ax
        xor     si, si
        mov     di, 0x0200
        mov     cx, 256
        repe    cmpsw
        pop     es
        pop     ds
        jne     .wcmp
        mov     byte [es:0x2D], 1
.wcmp:  mov     bp, 0x0400              ; put the original back
        mov     ax, 0x0520
        call    xfer2
        jnc     .wdone
.wfail: mov     [es:0x2C], ah
        or      byte [es:0x2C], 0x80    ; a failed call even if AH was 0
.wdone:
        ; ---- verdict ----------------------------------------------------
        mov     al, 'F'
        cmp     byte [es:0x10], 0xA0    ; entry AL = DA/UA
        jne     .v
        cmp     byte [es:0x1E], 0xA0    ; DISK_BOOT
        jne     .v
        test    byte [es:0x1F], 0x01    ; DISK_EQUIPS bit 0
        jz      .v
        cmp     word [es:0x26], 0       ; sense AH and CF
        jne     .v
        cmp     word [es:0x24], 512
        jne     .v
        cmp     word [es:0x28], 0x0100
        jne     .v
        cmp     word [es:0x2A], 0x0100
        jne     .v
        cmp     word [es:0x2C], 0x0100
        jne     .v
        mov     al, 'P'
.v:     mov     [es:0x2E], al
        mov     byte [es:0x2F], 0xA5

        ; ---- the screen ---------------------------------------------------
        mov     di, 160                 ; row 1
        mov     si, s_ax
        call    puts
        mov     ax, [es:0x10]
        call    hex16
        mov     si, s_584
        call    puts
        mov     al, [es:0x1E]
        call    hex8
        mov     si, s_482
        call    puts
        mov     al, [es:0x1F]
        call    hex8
        mov     si, s_c
        call    puts
        mov     ax, [es:0x22]
        call    hex16
        mov     si, s_h
        call    puts
        mov     al, [es:0x21]
        call    hex8
        mov     si, s_s
        call    puts
        mov     al, [es:0x20]
        call    hex8
        mov     si, s_b
        call    puts
        mov     ax, [es:0x24]
        call    hex16

        mov     di, 320                 ; row 2
        mov     si, s_chs
        mov     bx, 0x28
        call    pair
        mov     si, s_lba
        mov     bx, 0x2A
        call    pair
        mov     si, s_wr
        mov     bx, 0x2C
        call    pair
        mov     si, s_pass
        cmp     byte [es:0x2E], 'P'
        je      .pv
        mov     si, s_fail
.pv:    call    puts

hang:   jmp     hang                    ; keep the result on screen

; rd_check -- AX = function/DA, CX/DX = position; read one sector to
; BUFSEG:0000 and match its stamp: "GEO!" + the LBA the builder wrote.
; ES = RES; SI = result offset (+0 status, +1 match).
rd_check:
        push    es
        push    si
        mov     bx, BUFSEG
        mov     es, bx
        xor     bp, bp
        mov     bx, 512
        int     0x1B
        pop     si
        pop     es
        mov     [es:si], ah
        jnc     .ok
        or      byte [es:si], 0x80
        ret
.ok:    push    ds
        mov     ax, BUFSEG
        mov     ds, ax
        cmp     word [0], 'GE'
        jne     .no
        cmp     word [2], 'O!'
        jne     .no
        ; the LBA the stamp claims vs C*H*S - 1 from the sense
        mov     ax, [4]
        mov     dx, [6]
        pop     ds
        push    ax
        push    dx
        mov     al, [es:0x21]
        mul     byte [es:0x20]
        mul     word [es:0x22]
        sub     ax, 1
        sbb     dx, 0
        pop     cx
        pop     bx
        cmp     ax, bx
        jne     .nm
        cmp     dx, cx
        jne     .nm
        mov     byte [es:si+1], 1
.nm:    ret
.no:    pop     ds
        ret

; xfer2 -- AX = function/DA (LBA form, DA 20), one sector at LBA 2 to/from
; BUFSEG:BP. CF/AH as INT 1Bh leaves them. ES = RES preserved.
xfer2:
        push    es
        mov     bx, BUFSEG
        mov     es, bx
        mov     bx, 512
        mov     cx, 2
        xor     dx, dx
        int     0x1B
        pop     es
        ret

; pair -- label SI, then "ss/mm" for the result pair at ES:BX, and a blank
pair:
        call    puts
        mov     al, [es:bx]
        call    hex8
        mov     al, '/'
        call    putc
        mov     al, [es:bx+1]
        call    hex8
        mov     al, ' '
        jmp     putc

; puts -- NUL-terminated CS:SI at text cell DI (DI advances 2 per char)
puts:
        cs lodsb
        or      al, al
        jz      .d
        call    putc
        jmp     puts
.d:     ret

; putc -- AL at text cell DI: code at A000:DI, attribute E1 at A200:DI
putc:
        push    es
        push    bx
        mov     bx, 0xA000
        mov     es, bx
        mov     [es:di], al
        mov     byte [es:di+1], 0
        mov     byte [es:di+0x2000], 0xE1
        add     di, 2
        pop     bx
        pop     es
        ret

hex16:  push    ax
        mov     al, ah
        call    hex8
        pop     ax
hex8:   push    ax
        shr     al, 4
        call    .n
        pop     ax
.n:     and     al, 0x0F
        add     al, '0'
        cmp     al, '9'
        jbe     putc
        add     al, 7
        jmp     putc

banner: db "SCSI HDD IPL OK", 0
s_ax:   db "AX=", 0
s_584:  db " 584=", 0
s_482:  db " 482=", 0
s_c:    db " C=", 0
s_h:    db " H=", 0
s_s:    db " S=", 0
s_b:    db " B=", 0
s_chs:  db "CHS=", 0
s_lba:  db "LBA=", 0
s_wr:   db "WR=", 0
s_pass: db " PASS", 0
s_fail: db " FAIL", 0

e_ax:   dw 0
e_bx:   dw 0
e_cx:   dw 0
e_dx:   dw 0
e_bp:   dw 0
e_es:   dw 0
e_ds:   dw 0

        times 1024 - ($ - $$) db 0      ; error if the IPL outgrew 2 sectors
