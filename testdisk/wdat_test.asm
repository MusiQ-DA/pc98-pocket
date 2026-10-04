; ============================================================================
; wdat_test.asm -- PC-9801 2HD boot sector: the NEC ITF's GRCG probe, isolated.
;
; Replays the ITF self-test at F81EA2 byte for byte:
;   GRCG on (0x7C = 0x80, TDW, mask 0), tiles {33,55,00,00} via 0x7E,
;   slave GDC CSRW {00,40,08} (EAD 0x4000), WDAT 0xFFFF, wait fifo-empty,
;   GRCG off, then compare A800:0 = 0x3333 and B000:0 = 0x5555.
;
; The verdict and the raw readbacks are written to marker RAM a JTAG probe can
; read (rdabs): 0x70030/2 = the two words, 0x70034/6 = G and E for completeness,
; 0x70038 = 'PA' or 'FA'.
;
; Assemble: nasm -f bin -o wdat_test.bin wdat_test.asm   (sector0, <=1024 B)
; ============================================================================
BITS 16
CPU 186
ORG 0x0000

SGDC_P  equ 0xA0                 ; slave (graphics) GDC param/status
SGDC_C  equ 0xA2                 ; slave  GDC          cmd/read
MODE2   equ 0x6A
GR_MODE equ 0x7C
GR_TILE equ 0x7E
MARK    equ 0x7003               ; markers live at 0x7003x (seg 0x7003:0)

        jmp short start
        times 0x20-($-$$) db 0

start:
        cli
        cld
        mov ax, cs
        mov ds, ax
        mov ss, ax
        mov sp, 0x0400

        ; ---------- slave GDC: 400-line single partition (draw_test setup) --
        mov al, 0x01
        out MODE2, al
        mov al, 0x83
        out MODE2, al
        mov al, 0x85
        out MODE2, al

        mov al, 0x47             ; PITCH
        out SGDC_C, al
        mov al, 80
        out SGDC_P, al

        mov al, 0x70             ; SCROLL -> PRAM partition 0
        out SGDC_C, al
        xor al, al
        out SGDC_P, al
        out SGDC_P, al
        out SGDC_P, al
        mov al, 0x19
        out SGDC_P, al
        xor al, al
        mov cx, 12
.zp:    out SGDC_P, al
        loop .zp
        mov al, 0x6B             ; START -> graphics disp_on
        out SGDC_C, al

        ; ---------- seed the compare words with a non-tile sentinel ---------
        mov ax, 0xA800
        mov es, ax
        xor di, di
        mov word [es:di], 0xDEAD  ; if WDAT stays raw this survives as FFFF
        mov ax, 0xB000            ;   or DEAD; tiles overwrite either way
        mov es, ax
        mov word [es:di], 0xBEEF

        ; ---------- the ITF probe, verbatim --------------------------------
        mov al, 0x80             ; GRCG on: TDW, mask 0
        out GR_MODE, al
        mov al, 0x33
        out GR_TILE, al          ; tile[0] -> B
        mov al, 0x55
        out GR_TILE, al          ; tile[1] -> R
        xor al, al
        out GR_TILE, al          ; tile[2] -> G
        out GR_TILE, al          ; tile[3] -> E

        mov al, 0x49             ; CSRW
        out SGDC_C, al
        xor al, al
        out SGDC_P, al           ; EAD byte0 = 0x00
        mov al, 0x40
        out SGDC_P, al           ; EAD byte1 = 0x40
        mov al, 0x08
        out SGDC_P, al           ; EAD byte2 = 0x08
        mov al, 0x20             ; WDAT, replace, 2 params
        out SGDC_C, al
        mov al, 0xFF
        out SGDC_P, al
        out SGDC_P, al           ; data = 0xFFFF -> draw server runs here

.wait:  in  al, SGDC_P           ; fifo-empty = status bit 2
        test al, 0x04
        jz  .wait

        xor al, al
        out GR_MODE, al          ; GRCG off

        ; ---------- read back ----------------------------------------------
        mov ax, MARK
        mov ds, ax
        xor di, di
        mov ax, 0xA800
        mov es, ax
        mov ax, [es:0]
        mov [ds:0x30], ax        ; want 0x3333
        mov ax, 0xB000
        mov es, ax
        mov ax, [es:0]
        mov [ds:0x32], ax        ; want 0x5555
        mov ax, 0xB800
        mov es, ax
        mov ax, [es:0]
        mov [ds:0x34], ax        ; want 0x0000
        mov ax, 0xE000
        mov es, ax
        mov ax, [es:0]
        mov [ds:0x36], ax        ; want 0x0000 (analogue) or untouched

        mov ax, 0x4150           ; 'PA'
        cmp word [ds:0x30], 0x3333
        jne .fail
        cmp word [ds:0x32], 0x5555
        jne .fail
        jmp short .verdict
.fail:  mov ax, 0x4146           ; 'FA'
.verdict:
        mov [ds:0x38], ax

.hang:  jmp .hang

        times 1024-($-$$) db 0
