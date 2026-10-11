; ============================================================================
; wdat_test3.asm -- PC-9801 2HD boot sector: a LONG armed-GRCG WDAT so the
; GVRAM sequencer's svc walk is observable on the JTAG probe (slot 0x31).
;
; Same shape as probe C of wdat_test2, but VECTW first loads DC=0x3FFF so
; gdc_wdat's loop count is 16384 words -- the service channel stays busy for
; tens of milliseconds while the guest parks at the end. Slot 0x31 read
; mid-draw shows {svc_req, svc_done, svc_hold, fsm, plane} live; slot 0x32
; shows the draw handshake. Markers: a 'GO' flag at 0x70060 so the read
; confirms the program reached the wait, plus the first plane bytes for the
; usual tile check once the draw retires.
;
; Assemble: nasm -f bin -o wdat_test3.bin wdat_test3.asm  (sector0, <=512 B)
; ============================================================================
BITS 16
CPU 186
ORG 0x0000

SGDC_P  equ 0xA0                 ; slave (graphics) GDC param/status
SGDC_C  equ 0xA2                 ; slave  GDC          cmd/read
MODE2   equ 0x6A
GR_MODE equ 0x7C
GR_TILE equ 0x7E
MARK    equ 0x7006               ; markers live at 0x7006x (seg 0x7006:0)

        jmp short start
        times 0x20-($-$$) db 0

start:
        cli
        cld
        mov ax, cs
        mov ds, ax
        mov ss, ax
        mov sp, 0x0400

        ; ---------- slave GDC: 400-line single partition ------------------
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

        ; ---------- seeds -------------------------------------------------
        mov ax, 0xA800
        mov es, ax
        mov word [es:0x10], 0xAAAA
        mov ax, 0xB000
        mov es, ax
        mov word [es:0x10], 0xBBBB
        mov ax, 0xB800
        mov es, ax
        mov word [es:0x10], 0xCCCC
        mov ax, 0xE000
        mov es, ax
        mov word [es:0x10], 0xDDDD

        ; ---------- GRCG on, tiles {33,55,00,00} ---------------------------
        mov al, 0x80
        out GR_MODE, al
        mov al, 0x33
        out GR_TILE, al
        mov al, 0x55
        out GR_TILE, al
        xor al, al
        out GR_TILE, al
        out GR_TILE, al

        ; ---------- VECTW: ope=0, DC=0x3FFF -> leng 16384 words -----------
        mov al, 0x4C             ; VECTW, 11 params
        out SGDC_C, al
        xor al, al
        out SGDC_P, al           ; ope = 0
        mov al, 0xFF
        out SGDC_P, al           ; DC lo
        mov al, 0x3F
        out SGDC_P, al           ; DC hi -> 0x3FFF
        xor al, al
        mov cx, 8
.vp:    out SGDC_P, al           ; D/D2/D1/DM = 0
        loop .vp

        ; ---------- CSRW EAD 0x4008 -> plane B, word 8 -> byte 0x10 -------
        mov al, 0x49
        out SGDC_C, al
        mov al, 0x08
        out SGDC_P, al
        mov al, 0x40
        out SGDC_P, al
        mov al, 0x08
        out SGDC_P, al

        ; ---------- WDAT 0x20 {FF,FF} -> draw server runs -----------------
        mov al, 0x20
        out SGDC_C, al
        mov al, 0xFF
        out SGDC_P, al
        out SGDC_P, al

        ; ---------- do NOT wait: flag 'GO' and park -----------------------
        mov ax, MARK
        mov ds, ax
        mov word [ds:0x00], 0x4F47     ; 'GO'
.hang:  jmp .hang

        times 1024-($-$$) db 0
