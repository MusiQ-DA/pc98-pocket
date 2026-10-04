; ============================================================================
; wdat_test2.asm -- PC-9801 2HD boot sector: three probes into the firmware
; GDC service channel, splitting where the ITF's WDAT-through-GRCG write dies.
;
;   PROBE A  svc write sanity, NO charger: GRCG off, CSRW EAD 0x4000,
;            WDAT 0x22 (CLEAR) params {00,00}. Firmware reads the word and
;            writes back v&data = 0 -- two plain own-plane svc writes of 0x00.
;            A800:0 word -> 0x0000 if the svc write lands, 0xDEAD if the
;            channel is dead end to end.
;   PROBE B  CPU-path TDW control: GRCG on (TDW mask 0), tiles {33,55,00,00},
;            guest word write 0xFFFF to A800:8, GRCG off, read the four
;            planes at offset 8 -> {3333,5555,0000,0000}. Proves the armed
;            charger expands a guest write this boot, so a probe-C failure
;            is specific to the svc leg, not the charger.
;   PROBE C  the ITF sequence on a fresh offset: seeds, GRCG on, tiles,
;            CSRW {08,40,08} (EAD 0x4008 -> plane B word 8 -> byte 0x10),
;            WDAT 0x20 params {FF,FF}, wait fifo-empty, GRCG off, read the
;            planes at 0x10 -> {3333,5555,0000,0000} if tiles land.
;
; Markers at physical 0x70060+ (seg 0x7006): A gives two words, B four,
; C four plus a spare pair at 0x20 in case the write lands a word late,
; then 'PA'/'FA'.
;
; Assemble: nasm -f bin -o wdat_test2.bin wdat_test2.asm  (sector0, <=512 B)
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

        ; ---------- seeds: distinctive per-plane sentinels, GRCG off ------
        mov ax, 0xA800
        mov es, ax
        mov word [es:0x00], 0xDEAD     ; probe A target
        mov word [es:0x08], 0x1111     ; probe B TDW target
        mov word [es:0x10], 0xAAAA     ; probe C target
        mov word [es:0x20], 0x1212     ; probe C off-by-a-word spare
        mov ax, 0xB000
        mov es, ax
        mov word [es:0x00], 0xBEEF
        mov word [es:0x08], 0x2222
        mov word [es:0x10], 0xBBBB
        mov word [es:0x20], 0x3434
        mov ax, 0xB800
        mov es, ax
        mov word [es:0x08], 0x3333
        mov word [es:0x10], 0xCCCC
        mov ax, 0xE000
        mov es, ax
        mov word [es:0x08], 0x4444
        mov word [es:0x10], 0xDDDD

        ; ================= PROBE A =======================================
        ; GRCG never armed. WDAT clear-mode writes 0x00 to A800:0/1 through
        ; the service channel -- a plain own-plane write with no charger.
        mov al, 0x49             ; CSRW
        out SGDC_C, al
        xor al, al
        out SGDC_P, al           ; EAD byte0 = 0x00
        mov al, 0x40
        out SGDC_P, al           ; EAD byte1 = 0x40 -> plane B, word 0
        mov al, 0x08
        out SGDC_P, al           ; EAD byte2 = 0x08 (ITF's own high bits)
        mov al, 0x22             ; WDAT, CLEAR mode (op&3 = 2), 2 params
        out SGDC_C, al
        xor al, al
        out SGDC_P, al
        out SGDC_P, al           ; code = 0x0000 -> v &= data clears the word
        call wait_fifo

        mov ax, MARK
        mov ds, ax
        mov ax, 0xA800
        mov es, ax
        xor di, di
        mov ax, [es:di]
        mov [ds:0x00], ax        ; want 0x0000 (svc write landed)
        mov ax, 0xB000
        mov es, ax
        mov ax, [es:di]
        mov [ds:0x02], ax        ; want 0xBEEF (no cross-plane bleed)

        ; ================= PROBE B =======================================
        ; CPU-path TDW control: armed charger + a guest write.
        call grcg_on
        mov ax, 0xA800
        mov es, ax
        mov word [es:0x08], 0xFFFF     ; the TDW write
        call grcg_off

        mov di, 0x08
        mov bx, 0x04
        call read4               ; want {3333,5555,0000,0000} at M4..MA

        ; ================= PROBE C =======================================
        ; The ITF sequence, byte for byte, at word 8 = byte offset 0x10.
        call grcg_on
        mov al, 0x49             ; CSRW
        out SGDC_C, al
        mov al, 0x08
        out SGDC_P, al           ; EAD byte0 = 0x08 -> word 8 = byte 0x10
        mov al, 0x40
        out SGDC_P, al           ; EAD byte1 = 0x40 -> plane B
        mov al, 0x08
        out SGDC_P, al           ; EAD byte2 = 0x08
        mov al, 0x20             ; WDAT, replace, 2 params
        out SGDC_C, al
        mov al, 0xFF
        out SGDC_P, al
        out SGDC_P, al           ; data = 0xFFFF -> draw server runs here
        call wait_fifo
        call grcg_off

        mov di, 0x10
        mov bx, 0x0C
        call read4               ; want {3333,5555,0000,0000} at MC..M12
        mov ax, 0xA800
        mov es, ax
        mov ax, [es:0x20]
        mov [ds:0x14], ax        ; spare: catches an off-by-a-word write
        mov ax, 0xB000
        mov es, ax
        mov ax, [es:0x20]
        mov [ds:0x16], ax        ; spare

        ; ---------- verdict ----------------------------------------------
        mov ax, 0x4150           ; 'PA'
        cmp word [ds:0x00], 0x0000     ; probe A cleared the word
        jne .fail
        cmp word [ds:0x04], 0x3333     ; probe B: TDW fanned the tiles out
        jne .fail
        cmp word [ds:0x06], 0x5555
        jne .fail
        cmp word [ds:0x0C], 0x3333     ; probe C: the svc write took tiles
        jne .fail
        cmp word [ds:0x0E], 0x5555
        jne .fail
        jmp short .verdict
.fail:  mov ax, 0x4146           ; 'FA'
.verdict:
        mov [ds:0x18], ax

.hang:  jmp .hang

; ------------------------------------------------------------------------
; grcg_on: arm TDW with mask 0 and tiles {33,55,00,00}. Clobbers AL.
grcg_on:
        mov al, 0x80
        out GR_MODE, al
        mov al, 0x33
        out GR_TILE, al          ; tile[0] -> B
        mov al, 0x55
        out GR_TILE, al          ; tile[1] -> R
        xor al, al
        out GR_TILE, al          ; tile[2] -> G
        out GR_TILE, al          ; tile[3] -> E
        ret

; grcg_off: disarm. Clobbers AL.
grcg_off:
        xor al, al
        out GR_MODE, al
        ret

; wait_fifo: bounded wait on the slave's fifo-empty status bit (~1 s).
; Clobbers AL, CX, DX.
wait_fifo:
        mov dx, 0x0040
.o:     mov cx, 0xFFFF
.i:     in  al, SGDC_P
        test al, 0x04
        jnz .d
        loop .i
        dec dx
        jnz .o
.d:     ret

; read4: copy word [plane:DI] for B,R,G,E into [DS:BX..BX+7]. DI is the
; byte offset inside each plane window. Clobbers AX, ES.
read4:
        mov ax, 0xA800
        mov es, ax
        mov ax, [es:di]
        mov [ds:bx], ax
        mov ax, 0xB000
        mov es, ax
        mov ax, [es:di]
        mov [ds:bx+2], ax
        mov ax, 0xB800
        mov es, ax
        mov ax, [es:di]
        mov [ds:bx+4], ax
        mov ax, 0xE000
        mov es, ax
        mov ax, [es:di]
        mov [ds:bx+6], ax
        ret

        times 1024-($-$$) db 0
