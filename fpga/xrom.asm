; xrom.asm -- built-in option ROM for the PC-98 Pocket core.
;
; The NEC 9801 BIOS scans D0000h-DFFFFh in sixteen 4KB slots during POST.
; A slot whose [seg:9] reads AA55h is far-called at offsets
; 0x0C/0x0F/0x12/0x15 (four POST phases).  This image occupies the first
; slot (seg D000) and implements the machine's standard disk-BIOS
; extension protocol:
;
;   * writes its own segment into the XROM dispatch table at
;     0x4B0[devtype] for devtypes 0x3x and 0xBx (the NEC 3-mode / 1.44MB
;     FDD call), so INT 1Bh tail-jumps to seg:0x18 with the caller's
;     register frame on the stack;
;   * sets MEMB_F144_SUP (0x5AE) bits 0-1, marking drives 0/1 as 3-mode
;     capable for DOS-level media selection;
;   * on every call, swaps MEMW_F2HD_P (0x5F8/0x5FA) at a hybrid
;     parameter array whose N=2 record carries the 1.44MB geometry
;     (np21w fdfmt144) while the other records are byte-exact copies of
;     the BIOS's own 2HD table at FD80:1AB7, then re-enters INT 1Bh as
;     a 0x9x call so the BIOS's own FDC/DMA machinery does the work.
;     The pointer is restored afterwards, so ordinary 2HD accesses are
;     unaffected.
;
; Function 4 (sense) is answered locally: a query issued as AH=0x84xx
; gets the 1MB/640KB-capable + 1.44MB-capable bits (per np21w's
; bios1b.c), which the plain 2HD path could not report.
;
; After editing: nasm -f bin -o xrom.bin xrom.asm, then fold the bytes
; into the XROM_BYTES table in fpga/core/chipset/HDL/Chipset.sv.

        cpu 186
        org 0

        times 0x09 db 0
        db 0x55, 0xAA           ; signature word AA55h at offset 9
        db 0x90

        times 0x0C - ($ - $$) db 0x90
e0:     jmp init                ; POST phase entries, all four identical
        times 0x0F - ($ - $$) db 0x90
e1:     jmp init
        times 0x12 - ($ - $$) db 0x90
e2:     jmp init
        times 0x15 - ($ - $$) db 0x90
e3:     jmp init
        times 0x18 - ($ - $$) db 0x90

; ---- disk-BIOS extension entry (fixed 0x18 by the 0x4B0 protocol) ----
; Entered by far jmp from the INT 1Bh dispatcher with DS=0, BP=SP and
; the caller's frame on the stack:
;   [bp+0]=AX [2]=BX [4]=CX [6]=DX [8]=BP [10]=ES [12]=DI [14]=SI
;   [16]=DS [18]=IP [20]=CS [22]=FLAGS
xrom_disk:
        push si
        push di
        mov  si, [bp+0]         ; saved AX: AL=devtype AH=function
        mov  al, [bp+1]
        and  al, 0x0F
        cmp  al, 0x04
        je   fn_sense           ; the only answer the 2HD path cannot give

        ; swap the F2HD param pointer at our hybrid array for this call
        push word [0x05FA]
        push word [0x05F8]
        mov  word [0x05F8], fdpara
        mov  ax, cs
        mov  [0x05FA], ax

        ; rebuild the caller's registers with devtype rewritten to 0x9x,
        ; then re-dispatch through INT 1Bh itself
        mov  ax, si
        and  al, 0x0F
        or   al, 0x90
        mov  bx, [bp+2]
        mov  cx, [bp+4]
        mov  dx, [bp+6]
        mov  es, [bp+0x0A]
        mov  di, [bp+8]
        xchg di, bp             ; BP = caller's buffer pointer, DI = frame
        int  0x1B
        xchg di, bp             ; BP = frame anchor again
        pop  word [0x05F8]
        pop  word [0x05FA]
        jmp  done               ; AH/CF carry the sub-call's status

fn_sense:
        mov  ax, si
        xor  ah, ah
        test al, 0x80           ; caller's density flag
        jz   .flags
        or   ah, 0x01           ; 2HD-class media answer
.flags: mov  cx, si
        and  cx, 0x8F40
        cmp  cx, 0x8400         ; "does this drive do 1.44?" query form
        jne  done
        or   ah, 0x0C           ; 1MB/640KB-capable | 1.44MB-capable

done:
        mov  [bp+1], ah         ; saved AH = status byte
        and  byte [bp+0x16], 0xFE
        cmp  ah, 0x20           ; the BIOS's own rule: >=0x20 sets CF
        jb   .noflag
        or   byte [bp+0x16], 0x01
.noflag:
        pop  di
        pop  si
        pop  ax
        pop  bx
        pop  cx
        pop  dx
        pop  bp
        pop  es
        pop  di
        pop  si
        pop  ds
        iret

init:
        push ax
        push ds
        xor  ax, ax
        mov  ds, ax
        mov  byte [0x04D0], 0xFF ; slot occupied: later POST passes skip us
        or   byte [0x05AE], 0x03 ; drives 0/1 are 3-mode (1.44MB) capable
        mov  ax, cs
        mov  al, ah             ; seg>>8 for the XROM dispatch table
        mov  [0x04B3], al       ; devtype 0x3x -> this ROM
        mov  [0x04BB], al       ; devtype 0xBx -> this ROM
        pop  ds
        pop  ax
        retf

; Per-unit record pointers, indexed by unit*2.  The BIOS dereferences
; them inside whatever segment 0x5FA holds, so while the pointer is
; swapped these offsets are relative to this ROM's own segment.
fdpara: dw rec144, rec144, rec144, rec144

; N-records, 8 bytes each: {MFM R/W EOT,GPL | MFM FMT SC,GPL |
;                           FM R/W EOT,GPL | FM FMT SC,GPL}
; rec144 is the BIOS's own 2HD record table (FD80:1AB7) with the N=2
; (512B) record replaced by the 1.44MB geometry, np21w's fdfmt144.
rec144: db 0x00,0x00, 0x00,0x00, 0x1A,0x07, 0x1A,0x1B
        db 0x1A,0x0E, 0x1A,0x36, 0x0F,0x0E, 0x0F,0x2A
        db 0x12,0x1B, 0x12,0x54, 0x08,0x1B, 0x08,0x3A
        db 0x08,0x35, 0x08,0x74, 0x00,0x00, 0x00,0x00
