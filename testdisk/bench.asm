; ============================================================================
; bench.asm -- bare-metal PC-9801 benchmark IPL (no DOS).
;
; Two stages, one NASM -f bin output:
;
;   section .ipl  (file offset 0,      sector C0/H0/R1, loaded by BIOS at
;                 1FE0:0000, only the low 512 bytes are guaranteed delivered)
;   section .s2   (file offset 1024.., sectors C0/H0/R2..R8, loaded by stage1
;                 through BIOS INT 1Bh to 0x2000:0000, then far-jumped to)
;
; Timing: PIT counter0 (uPD8253) is reprogrammed to mode 2, divisor 0
; (65536).  Mode 2 is chosen over the BIOS's mode 3 because a real 8253
; decrements once per clock in mode 2 (clean full-range down-count, period
; 65536 clocks = 26.67ms at the 2.4576MHz input); np2kai/np21w model both
; modes as the same remaining-clocks-to-event counter, so the numbers stay
; comparable between FPGA RTL and emulator.
;
; Short tests are chunked so each chunk is < one 65536-tick period; the
; elapsed ticks are (v0 - v1) mod 65536 summed per chunk -- immune to IRQ
; behaviour.  The FDC test exceeds one period, so an INT 08h handler (chained
; to the BIOS tick handler, which does the EOI itself) counts counter0 wraps
; and the measurement uses an absolute position: pos = wraps*65536 - count.
;
; Results: each test prints "NN NAME .... TTTTTTTTTT" to text VRAM (0xA000)
; and appends a record {id, tick_lo, tick_hi, units_lo, units_hi} to the
; mailbox at physical 0x70000 (word array).  word[0] = 0xBEEF is written
; only after ALL tests are done -- that flag tells the host the mailbox is
; valid.  word[1] = number of test records written (record i at word 2+5i).
;
; The program then far-jumps to the stage1 "done" loop at linear 0x1FF00
; (1FE0:0100).  The np2kai watch hook prints the mailbox when PC hits it.
; ============================================================================

BITS 16
CPU 186                             ; V30 supports the 186 set

; ---- I/O ports ----
PIT_CH0     equ 0x71                ; counter0 data
PIT_CMD     equ 0x77                ; control
PIC_CMD     equ 0x00                ; master i8259 command (OCW2/OCW3/ICW1)
PIC_IMR     equ 0x02                ; master i8259 mask register
GR_MODE     equ 0x7C                ; GRCG mode (0 = off -> planar writes)
TVRAM       equ 0xA000              ; text vram segment (80x25, char+attr)
MBX_SEG     equ 0x7000              ; mailbox segment (phys 0x70000)
SCR_SEG     equ 0x5000              ; scratch buffer A (phys 0x50000)
SCR2_SEG    equ 0x5800              ; scratch buffer B (phys 0x58000)
S2_SEG      equ 0x2000              ; stage2 load/exec segment

MBX_SENT    equ 0                   ; mailbox word offsets
MBX_COUNT   equ 1
MBX_RECS    equ 2                   ; first record word index, 5 words each

MEMB_DISK_BOOT equ 0x0584           ; BIOS BDA: boot drive byte (0x90+drv 2HD)

NTESTS      equ 14                  ; number of test records emitted

; ============================================================================
section .ipl vstart=0x0000
; ============================================================================

        jmp short s1_start
        times 0x20-($-$$) db 0      ; PC-98 IPL header area

s1_start:
        cli
        cld
        mov ax, cs                  ; 1FE0
        mov ds, ax
        mov ax, 0x3000              ; stack in unused RAM (must NOT sit inside
        mov ss, ax                  ; the 0x20000 staging area -- the DMA read
        mov sp, 0x0400              ; below would smash a stack there)

        ; ---- load C0/H0/R2..R8 (7 sectors = 7168 B) -> 2000:0000 ----------
        mov ax, S2_SEG
        mov es, ax
        xor bp, bp                  ; ES:BP = destination buffer
        mov bx, 7*1024              ; byte count
        call s1_bootdrv             ; AL = BDA boot-drive byte (0x90+drv 2HD)
        mov ah, 0x96                ; read(06) | seek(10) | 2HD-2head(80)
        xor cl, cl                  ; C = 0
        xor dh, dh                  ; H = 0
        mov dl, 2                   ; R = 2 (first sector after the IPL)
        mov ch, 3                   ; N = 3 -> 1024 B/sector
        int 0x1b
        test ah, ah
        jnz .s1err
        jmp S2_SEG:0x0000           ; far jump -> CS=2000 IP=0 = s2_start

.s1err:                             ; 'E' + AH hex on row 0, then halt
        mov cx, 0xA000
        mov es, cx
        xor di, di
        mov byte [es:0], 'E'
        mov byte [es:1], 0
        mov byte [es:0x2000], 0xE1
        mov di, 2
        mov bl, ah
        shr bl, 4
        call .nib
        mov bl, ah
        call .nib
.h:     jmp short .h
.nib:                               ; bl lo-nibble -> hex char at es:di
        and bl, 0x0F
        add bl, '0'
        cmp bl, '9'
        jbe .n2
        add bl, 'A'-'9'-1
.n2:    mov [es:di], bl
        mov byte [es:di+1], 0
        mov byte [es:di+0x2000], 0xE1
        add di, 2
        ret

; s1_bootdrv -> AL = BIOS boot-drive byte (BDA 0x584), >=0x90 else 0x90
s1_bootdrv:
        push es
        xor  ax, ax
        mov  es, ax
        mov  al, [es:MEMB_DISK_BOOT]
        pop  es
        cmp  al, 0x90
        jae  .r
        mov  al, 0x90
.r:     ret

        times 0x100-($-$$) db 0
bench_done:                         ; linear 0x1FF00 -- np2kai hook watches it
        jmp short bench_done

        times 512-($-$$) db 0x90    ; end of the BIOS-delivered window
        times 1024-($-$$) db 0x90   ; pad stage1 to the full 1024-byte sector

; ============================================================================
section .s2 vstart=0x0000
; ============================================================================

s2_start:
        mov ax, cs                  ; 2000
        mov ds, ax
        mov ss, ax
        mov sp, 0x6000              ; stack phys 0x26000, clear of everything
        cld

        ; ---- banner on row 0 ----
        mov ax, TVRAM
        mov es, ax
        mov si, str_title
        xor bx, bx
        call putstr
        mov word [rowpos], 160      ; first result row

        jmp s2_init_cont            ; keep the helper below out of the flow
; ----------------------------------------------------------------------------
; bootdrv -> AL = BIOS boot-drive byte (BDA 0x584), >=0x90 else 0x90 fallback
bootdrv:
        push es
        xor  ax, ax
        mov  es, ax
        mov  al, [es:MEMB_DISK_BOOT]
        pop  es
        cmp  al, 0x90
        jae  .r
        mov  al, 0x90
.r:     ret
s2_init_cont:

        ; ---- zero the mailbox ----
        mov ax, MBX_SEG
        mov es, ax
        xor di, di
        xor ax, ax
        mov cx, 64
        rep stosw

        ; ---- install INT 08h (IRQ0) handler, chained to the BIOS tick ----
        cli
        xor ax, ax
        mov es, ax
        mov bx, [es:0x20]           ; vector 08h lives at 0000:0020
        mov [old08], bx
        mov bx, [es:0x22]
        mov [old08+2], bx
        mov word [es:0x20], int8_isr
        mov [es:0x22], cs

        ; ---- reprogram PIT counter0: mode 2, divisor 0 = 65536 ----------
        mov al, 0x34                ; ch0 | lobyte+hibyte | mode 2
        out PIT_CMD, al
        xor al, al
        out PIT_CH0, al
        out PIT_CH0, al
        mov word [wraps], 0

        ; ---- unmask IRQ0 in the master PIC ----
%ifndef BENCH_NOIRQ
        in  al, PIC_IMR
        and al, 0xFE
        out PIC_IMR, al
        sti
%endif

        ; ---- GRCG off so the A800 window is a plain plane ----------------
        xor al, al
        out GR_MODE, al

        ; ---- run the test table ----
        mov si, test_table
.next:
        lodsw                       ; id (0 = end)
        test ax, ax
        jz  .alldone
        mov [m_id], ax
        lodsw
        mov [m_proc], ax
        lodsw
        mov [m_nch], ax
        lodsw
        mov [m_u0], ax
        lodsw
        mov [m_u1], ax
        lodsw
        mov [m_name], ax
        push si                     ; measure() clobbers si (putstr lodsb,
        call measure                ; putu32 mov si,bx) -- keep table cursor
        pop  si
        jmp .next

.alldone:
        ; mailbox[1] = record count, mailbox[0] = 0xBEEF sentinel LAST
        mov ax, MBX_SEG
        mov es, ax
        mov word [es:MBX_COUNT*2], NTESTS
        mov word [es:MBX_SENT*2], 0xBEEF

        ; restore the BIOS tick vector (politeness), then halt on the
        ; watched address so the emulator-side hook sees final results
        cli
        xor ax, ax
        mov es, ax
        mov bx, [old08]
        mov [es:0x20], bx
        mov bx, [old08+2]
        mov [es:0x22], bx
        jmp S2_SEG:bench_done2      ; linear 0x20F00 -> np2kai hook dumps mbox

; ----------------------------------------------------------------------------
; int8_isr -- IRQ0 (PIT counter0 wrap): bump [cs:wraps], chain to the BIOS
; tick handler with an iret-shaped frame (its own EOI+IRET returns to us).
int8_isr:
        inc  word [cs:wraps]
        pushf
        call far [cs:old08]
        iret

; ----------------------------------------------------------------------------
; latch_read -> AX = counter0 latched count (down-counting, period 65536)
latch_read:
        mov al, 0x00                ; latch counter0
        out PIT_CMD, al
        in  al, PIT_CH0
        mov ah, al
        in  al, PIT_CH0
        xchg al, ah
        ret

; ----------------------------------------------------------------------------
; snap -> DX:AX = absolute tick position = wraps*65536 - count.
; Only used for the FDC test (a call can exceed one 26.7ms period).
snap:
        cli
        call latch_read
        mov dx, [cs:wraps]
        sti
        neg ax                      ; -count mod 65536; CF set unless 0
        sbb dx, 0
        ret

; ----------------------------------------------------------------------------
; measure -- run one table entry.
;   [m_proc]  chunk routine, called [m_nch] times; each chunk < 65536 ticks.
;             procs may clobber all registers; state lives in CS variables.
;   id 12 (FDC) uses absolute-position timing instead of chunked deltas.
measure:
        mov ax, TVRAM
        mov es, ax
        mov bx, [rowpos]
        mov si, [m_name]
        call putstr

        mov word [acc], 0
        mov word [acc+2], 0

        cmp byte [m_id], 12
        je  .abs

.mloop:                             ; chunked path
        call latch_read
        mov [vtmp], ax
        call word [m_proc]
        call latch_read
        mov bx, ax
        mov ax, [vtmp]
        sub ax, bx                  ; (v0 - v1) mod 65536; chunk < period
        add [acc], ax
        adc word [acc+2], 0
        dec word [m_nch]
        jnz .mloop
        jmp .report

.abs:
        call snap
        mov [vtmp], ax              ; pos0 lo
        mov [vtmp+2], dx            ; pos0 hi
        call word [m_proc]
        call snap                   ; dx:ax = pos1
        sub ax, [vtmp]
        sbb dx, [vtmp+2]
        mov [acc], ax
        mov [acc+2], dx

.report:
        ; append mailbox record {id, tick_lo, tick_hi, units_lo, units_hi}
        ; vars live in CS(=DS) -- read them with ds intact and write through
        ; es, or the field reads would hit 0x70xxx instead of 0x20xxx.
        push es
        mov ax, MBX_SEG
        mov es, ax
        mov bx, [m_rec]
        mov ax, [m_id]
        mov [es:bx], ax
        mov ax, [acc]
        mov [es:bx+2], ax
        mov ax, [acc+2]
        mov [es:bx+4], ax
        mov ax, [m_u0]
        mov [es:bx+6], ax
        mov ax, [m_u1]
        mov [es:bx+8], ax
        pop es
        add word [m_rec], 10

        ; print decimal ticks at column 12 of this row
        mov ax, TVRAM
        mov es, ax
        mov bx, [rowpos]
        add bx, 24
        mov ax, [acc]
        mov dx, [acc+2]
        call putu32
        add word [rowpos], 160
        ret

; ----------------------------------------------------------------------------
; putstr -- ds:si NUL-terminated -> es:bx (char at +0, attr 0xE1 at +0x2000)
putstr:
.l:     lodsb
        test al, al
        jz .d
        mov [es:bx], al
        mov byte [es:bx+1], 0
        mov byte [es:bx+0x2000], 0xE1
        add bx, 2
        jmp .l
.d:     ret

; ----------------------------------------------------------------------------
; putu32 -- DX:AX unsigned -> decimal at es:bx, 10 columns, leading spaces.
putu32:
        push bp
        mov  bp, sp
        sub  sp, 12                 ; digit buffer at [bp-11..bp-2]
        mov  si, bx                  ; screen position
        mov  di, bp
        dec  di                      ; write digits downward from bp-1
        mov  bx, 10
        mov  cx, 10
.dl:    push cx
        mov  cx, ax                  ; save lo
        mov  ax, dx                  ; hi
        xor  dx, dx
        div  bx                      ; ax = hi/10, dx = hi%10
        xchg ax, cx                  ; ax = lo, cx = hi/10
        div  bx                      ; ax = lo' quot, dx = remainder
        add  dl, '0'
        mov  [di], dl
        dec  di
        mov  dx, cx                  ; dx:ax = full quotient
        pop  cx
        loop .dl
        ; copy 10 chars to screen, blanking leading zeros
        inc  di
        mov  cx, 10
        xor  bx, bx                  ; bx=0 until first nonzero digit
.cp:    mov  al, [di]
        cmp  al, '0'
        jne  .keep
        test bx, bx
        jnz  .keep
        cmp  cx, 1                   ; always print the last digit
        je   .keep
        mov  al, ' '
        jmp  .emit
.keep:  mov  bx, 1
.emit:  mov  [es:si], al
        mov  byte [es:si+1], 0
        mov  byte [es:si+0x2000], 0xE1
        inc  di
        add  si, 2
        loop .cp
        mov  sp, bp
        pop  bp
        ret

; ----------------------------------------------------------------------------
; test chunk routines ---------------------------------------------------------
; ----------------------------------------------------------------------------

; 1: ALU chain -- 500 iterations of add/adc/xor/sub/add
t_alu:
        mov cx, 500
        mov ax, 0x1234
        mov bx, 0x9ABC
        mov dx, 0x5555
        mov si, 0x0F0F
        mov bp, 0x0033
.l:     add ax, bx
        adc ax, dx
        xor ax, si
        sub ax, bp
        add bx, ax
        loop .l
        ret

; 2: loop instruction itself -- 500 x loop (empty body baseline)
t_loop:
        mov cx, 500
.l:     loop .l
        ret

; 3: mul -- 200 x mul bx
t_mul:
        mov cx, 200
        mov ax, 0x7654
        mov bx, 17
.l:     mul bx                      ; dx:ax = ax*bx
        add ax, dx                  ; keep ax moving
        loop .l
        ret

; 4: rep stosw 2048 words (4KB) into 0x5000:cycling offset
t_stosw:
        mov ax, SCR_SEG
        mov es, ax
        mov di, [scr_off]
        mov ax, 0x55AA
        mov cx, 2048
        rep stosw
        add word [scr_off], 4096
        and word [scr_off], 0x7FFF  ; stay inside the 32KB window
        ret

; 5: rep movsw 2048 words: 0x50000+off -> 0x58000+off
t_movsw:
        mov ax, SCR2_SEG
        mov es, ax
        mov ax, SCR_SEG
        mov ds, ax
        mov si, [scr_off]
        mov di, [scr_off]
        mov cx, 2048
        rep movsw
        add word [scr_off], 4096
        and word [scr_off], 0x7FFF
        push cs
        pop  ds
        ret

; 6: rep lodsw 2048 words from 0x50000+off (pure read)
t_lodsw:
        mov ax, SCR_SEG
        mov ds, ax
        mov si, [scr_off]
        mov cx, 2048
        rep lodsw
        add word [scr_off], 4096
        and word [scr_off], 0x7FFF
        push cs
        pop  ds
        ret

; 7: rep stosw 2048 words into TVRAM (8KB window over 2 chunks)
t_tvram:
        mov ax, TVRAM
        mov es, ax
        mov di, [tv_off]
        mov ax, 0xE120
        mov cx, 2048
        rep stosw
        add word [tv_off], 4096
        and word [tv_off], 0x1FFF   ; 8KB window
        ret

; 8: rep stosb 4096 bytes into the GVRAM plane window at A800
t_gvram:
        mov ax, 0xA800
        mov es, ax
        mov di, [gv_off]
        mov al, 0x3C
        mov cx, 4096
        rep stosb
        add word [gv_off], 4096
        and word [gv_off], 0x3FFF   ; 16KB worth
        ret

; 9: in al,0x71 x512 (I/O read latency)
t_in:
        mov cx, 512
        mov dx, PIT_CH0
.l:     in  al, dx
        loop .l
        ret

; 10: near call x500
t_near:
        mov cx, 500
.l:     call near_sub
        loop .l
        ret
near_sub:
        ret

; 11: far call x500 (same-segment far call + retf)
t_far:
        mov cx, 500
.l:     call S2_SEG:far_sub
        loop .l
        ret
far_sub:
        retf

; 13: near call x500, sector-aligned -- same as t_near but the whole loop
;     sits inside one 32B prefetch sector (isolates boundary-thrash).
        align 32
t_near2:
        mov cx, 500
.l:     call near2_sub
        loop .l
        ret
near2_sub:
        ret

; 14: push/pop x500, sector-aligned -- stack traffic only, minimal code.
        align 32
t_ppop:
        mov cx, 500
.l:     push ax
        pop  bx
        loop .l
        ret

; 12: FDC -- two INT 1Bh calls, whole cylinders 0 and 1 (32 x 1024B).
;     fdc_st collects the AH status bytes into the units_hi record field.
t_fdc:
        mov word [fdc_st], 0
        mov ax, SCR_SEG             ; buffer phys 0x50000, 16KB per call
        mov es, ax
        xor bp, bp
        mov bx, 16*1024
        call bootdrv                ; AL = 0x90+unit
        mov ah, 0x96                ; read|seek|2HD
        xor cl, cl                  ; cyl 0
        xor dh, dh                  ; head 0
        mov dl, 1                   ; R = 1
        mov ch, 3                   ; N = 3
        int 0x1b
        mov [fdc_st], ah
        mov ax, SCR_SEG
        mov es, ax
        xor bp, bp
        mov bx, 16*1024
        call bootdrv
        mov ah, 0x96
        mov cl, 1                   ; cyl 1
        xor dh, dh
        mov dl, 1
        mov ch, 3
        int 0x1b
        mov [fdc_st+1], ah
        mov ax, [fdc_st]
        mov [m_u1], ax              ; AH status -> units_hi of the record
        ret

; ----------------------------------------------------------------------------
; data ------------------------------------------------------------------------
str_title:  db "PC98 BENCH  pit0 mode2 div65536  tick=1/2.4576MHz", 0

; test table: id, proc, nchunks, units_lo, units_hi, name
test_table:
        dw 1,  t_alu,   20, 10000, 0, s_alu
        dw 2,  t_loop,  20, 10000, 0, s_loop
        dw 3,  t_mul,   20,  4000, 0, s_mul
        dw 4,  t_stosw,  8, 32768, 0, s_stosw
        dw 5,  t_movsw,  8, 32768, 0, s_movsw
        dw 6,  t_lodsw,  8, 32768, 0, s_lodsw
        dw 7,  t_tvram,  2,  8192, 0, s_tvram
        dw 8,  t_gvram,  4, 16384, 0, s_gvram
        dw 9,  t_in,    16,  8192, 0, s_in
        dw 10, t_near,  20, 10000, 0, s_near
        dw 11, t_far,   20, 10000, 0, s_far
        dw 13, t_near2, 20, 10000, 0, s_near2
        dw 14, t_ppop,  20, 10000, 0, s_ppop
        dw 12, t_fdc,    1,    32, 0, s_fdc
        dw 0

s_alu:   db "01 ALU5OP   ", 0
s_loop:  db "02 LOOP     ", 0
s_mul:   db "03 MUL      ", 0
s_stosw: db "04 STOSW32K ", 0
s_movsw: db "05 MOVSW32K ", 0
s_lodsw: db "06 LODSW32K ", 0
s_tvram: db "07 TVRAM8K  ", 0
s_gvram: db "08 GVRAM16K ", 0
s_in:    db "09 IN71     ", 0
s_near:  db "10 NEARCALL ", 0
s_far:   db "11 FARCALL  ", 0
s_near2: db "13 NEAR2ALGN", 0
s_ppop:  db "14 PUSHPOP  ", 0
s_fdc:   db "12 FDC32SEC ", 0

; ----------------------------------------------------------------------------
; variables (all in CS = 0x2000)
wraps:      dw 0                    ; counter0 wrap count (IRQ0 handler)
old08:      dd 0                    ; saved INT 08h vector
vtmp:       dd 0
acc:        dd 0
rowpos:     dw 160
m_id:       dw 0
m_proc:     dw 0
m_nch:      dw 0
m_u0:       dw 0
m_u1:       dw 0
m_name:     dw 0
m_rec:      dw MBX_RECS*2           ; mailbox record cursor (byte offset)
scr_off:    dw 0
tv_off:     dw 0
gv_off:     dw 0
fdc_st:     dw 0

        times 0x0F00-($-$$) db 0    ; park the done loop at a fixed address:
bench_done2:                        ; linear 0x20F00 -- np2kai hook watches it
        jmp short bench_done2
