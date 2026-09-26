; ============================================================================
; draw_test.asm -- PC-9801 2HD drawing-test boot sector.
;
; The BIOS loads floppy sector 0 (1024 bytes) to 1FE0:0000 and jumps to it.
; This program paints a deterministic test card so the core's drawing paths can
; be checked on hardware with one glance:
;
;   * 16 horizontal colour bands  -- one per palette index. Exercises all four
;     GVRAM planes (B=A8000, R=B0000, G=B8000, E=E0000) through the plain
;     per-plane windows, so the {E,G,R,B} bit->index mapping and the SDRAM
;     write path are proven plane by plane.
;   * a solid GRCG box          -- GRCG TDW mode writes tile[p] to every plane
;     on one window access; tiles {FF,00,FF,00} make cyan (index 5). If the
;     tile-counter bug survived, all four tiles would hold the last byte and
;     the box would come out black instead.
;   * text labels               -- the TVRAM char/attribute path.
;   * a blinking block cursor   -- master GDC CSRW + CSRFORM, the exact
;     multi-byte commands the io_write_n dedup fix restored.
;
; Assemble: nasm -f bin -o draw_test.bin draw_test.asm   (sector0, <=1024 B)
; Image:    pad draw_test.bin to 1024 B for sector 0, then the raw image to
;           1,261,568 B (77 cyl x 8 spt x 2 head x 1024 B, PC-98 2HD).
; ============================================================================
BITS 16
CPU 186                          ; V30 supports the 186 set (push imm, imul, shl)
ORG 0x0000

; ---- I/O ports ----
MGDC_P  equ 0x60                 ; master (text) GDC   param W / status R
MGDC_C  equ 0x62                 ; master GDC          cmd   W / read R
SGDC_P  equ 0xA0                 ; slave  (graphics) GDC param/status
SGDC_C  equ 0xA2                 ; slave  GDC          cmd/read
MODE2   equ 0x6A                 ; mode F/F2 + GDC clock
GR_MODE equ 0x7C                 ; GRCG mode (also resets the tile counter)
GR_TILE equ 0x7E                 ; GRCG tile register[counter++]

        jmp short start
        times 0x20-($-$$) db 0   ; skip the PC-98 IPL header area

; ---------------------------------------------------------------------------
start:
        cli
        cld                      ; lodsb/stosb run forwards regardless of BIOS DF
        mov ax, cs
        mov ds, ax               ; data reads come from the boot sector image
        mov ss, ax
        mov sp, 0x0400           ; small stack inside our own segment

        ; ================= graphics plane: bring up a known linear map ======
        mov al, 0x01
        out MODE2, al            ; mode2 bit0 -> analogue 16-colour, E live
        mov al, 0x83
        out MODE2, al            ; gdc_clk bit0 = 1
        mov al, 0x85
        out MODE2, al            ; gdc_clk bit1 = 1  -> 5 MHz, PITCH = bytes

        mov al, 0x47             ; PITCH
        out SGDC_C, al
        mov al, 80
        out SGDC_P, al           ; 80 bytes per raster line

        mov al, 0x70             ; SCROLL -> PRAM partition 0
        out SGDC_C, al
        xor al, al
        out SGDC_P, al           ; SAD lo
        out SGDC_P, al           ; SAD hi   = word address 0
        out SGDC_P, al           ; LEN lo
        mov al, 0x19
        out SGDC_P, al           ; LEN hi   = 0x1900 -> 400 lines
        xor al, al
        mov cx, 12               ; partitions 1-3 unused
.zp:    out SGDC_P, al
        loop .zp
        mov al, 0x6B             ; START -> graphics disp_on
        out SGDC_C, al

        ; ================= text labels ======================================
        ; cheap writes first so a sim timeout still leaves visible evidence
        mov ax, 0xA000
        mov es, ax
        mov ah, 0xE1             ; visible, white
        mov si, str_title
        mov bx, 0                ; row 0 cell 0
        call putstr
        mov si, str_bands
        mov bx, 3*160            ; row 3
        call putstr
        mov si, str_grcg
        mov bx, 4*160            ; row 4
        call putstr
        mov si, str_cur
        mov bx, 5*160            ; row 5
        call putstr

        ; ================= cursor ===========================================
        ; master GDC: CSRFORM one byte (0x8F = enable + 16-line rows) keeps the
        ; seeded top0/bottom15 full block; CSRW places it under the labels.
        mov al, 0x4B             ; CSRFORM
        out MGDC_C, al
        mov al, 0x8F
        out MGDC_P, al
        mov al, 0x49             ; CSRW
        out MGDC_C, al
        mov al, 6*80 & 0xFF      ; cell = row6 col0 = 480
        out MGDC_P, al
        mov al, (6*80 >> 8) & 0xFF
        out MGDC_P, al
        xor al, al
        out MGDC_P, al           ; dot nibble

        ; ================= 16 horizontal colour bands =======================
        ; band b -> palette index b over rows [b*25, b*25+25); 25*80 = 2000 B.
        ; For each plane p write 0xFF where bit p of the band index is set.
        xor bp, bp               ; band = 0..15
.band:  xor si, si               ; plane table byte offset 0,2,4,6
        mov cx, 4
.pl:    push cx
        mov bx, si
        shr bx, 1                ; bx = plane index 0..3
        mov ax, bp
        mov cl, bl
        shr ax, cl               ; band >> plane
        and al, 1
        neg al                   ; -> 0x00 or 0xFF
        mov bx, si
        mov es, [planes+bx]      ; ds == cs, so this is our table
        imul di, bp, 2000        ; band's first byte in the plane
        mov cx, 2000
        rep stosb                ; fill es:di, al
        add si, 2
        pop cx
        loop .pl
        inc bp
        cmp bp, 16
        jb .band

        ; ================= GRCG tile box ====================================
        ; TDW: one write paints all unmasked planes with their tile byte.
        mov al, 0x80             ; GRCG on, TDW, mask 0 -> all four planes
        out GR_MODE, al          ; resets the tile counter to 0
        mov al, 0xFF
        out GR_TILE, al          ; tile0 -> B
        mov al, 0x00
        out GR_TILE, al          ; tile1 -> R
        mov al, 0xFF
        out GR_TILE, al          ; tile2 -> G
        mov al, 0x00
        out GR_TILE, al          ; tile3 -> E   -> index 5 (cyan)
        ; box: rows 160..239, byte-columns 24..55 (a 32-byte wide rectangle
        ; centred on screen, plainly over the colour bands)
        mov ax, 0xA800           ; any window works; GRCG reaches every plane
        mov es, ax
        mov bx, 160*80 + 24      ; row 160, byte column 24
        mov dx, 80               ; rows 160..239
.grow:  mov di, bx
        mov cx, 32
        mov al, 0xFF
        rep stosb                ; TDW: data ignored, tile lands on all planes
        add bx, 80
        dec dx
        jnz .grow
        xor al, al
        out GR_MODE, al          ; GRCG back off

.hang:  jmp .hang                ; static test card; reset to rerun

; ---------------------------------------------------------------------------
; putstr: ds:si -> NUL-terminated string, es = A000, bx = char byte offset
;         (2 x cell index), ah = attribute. char_lo to +0, char_hi 0 to +1,
;         attribute to +0x2000. Clobbers al, bx, si.
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

; ---------------------------------------------------------------------------
planes: dw 0xA800, 0xB000, 0xB800, 0xE000     ; B, R, G, E
str_title: db "PC-98 DRAW TEST", 0
str_bands: db "BANDS: 16 colours, one per palette index", 0
str_grcg:  db "GRCG box: cyan = 4 tiles landed right", 0
str_cur:   db "CURSOR: blinking block on the line below", 0
