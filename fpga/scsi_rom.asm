; scsi_rom.asm -- the PC-9801-55's disk BIOS for the PC-98 Pocket core.
;
; The NEC option-ROM format, the 0x4B0 XROM dispatch table and the INT 1Bh
; register frame are the same protocol fpga/xrom.asm implements for the
; 1.44MB FDD path; this image lives in the next window down (D200, the
; -55's slot) and handles the SCSI device classes 0x2x (LBA) and 0xAx (CHS).
; Everything else -- FDD classes, other option ROMs -- never reaches here:
; the BIOS's own dispatcher indexes the table by AL's high nibble.
;
; The board side it talks to is fpga/core/pc98_scsi.sv: an indirect index
; at 0xCC0, the control-register file at 0xCC2 (auto-incrementing), the
; byte buffer port at 0xCC6 (independent read/write pointers), the command
; toggle at index 0x18, and SCSI status at index 0x17. The firmware service
; (firmware/scsi_service.c) reads the CDB from control registers 0x03..0x0E,
; works against the mounted HDD image and completes with auxstatus bit 7
; plus a status byte -- TEST UNIT READY, REQUEST SENSE, FORMAT (a safe
; no-op there), READ/WRITE(6,10), INQUIRY, MODE SENSE, READ CAPACITY, and
; friends. One command carries at most 16 x 512-byte sectors; this BIOS
; chunks anything larger itself.
;
; Function coverage mirrors np21w bios/sxsibios.c for the SCSI classes:
;   fn1 verify    fn3 init      fn4 sense (x04 ready / x24 set / x44 query /
;   fn5 write     fn6 read      x84 geometry read)
;   fn7 nop       fnA setsec    fnC change-info
;   fnD format    fnF nop       else -> 0x40
; Status follows the house rule everywhere: AH < 0x20 succeeds (CF clear),
; AH >= 0x20 is an error (CF set). SCSI sense keys map to NEC codes:
; NOT READY -> 0x60, ILLEGAL REQUEST -> 0xD0, anything else -> 0x20.
;
; Geometry: the mounted image is a flat 512-byte-sector file, so the ROM
; exposes np21w's flat-image geometry of 8 surfaces x 25 sectors, cylinders
; = sectors / 200 (clamped to 0xFFFF = 640 MB), stored in the NEC scsiinf
; 4-byte form {spt, heads|cylhi, cyl_lo, inf_hi} -- the layout np21w keeps
; at 0x460 (taken here, that area is busy on this BIOS) -- at 0x05A0, in a
; measured-free work-area gap ahead of MEMB_F144_SUP at 0x5AE.
;
; Boot: the system BIOS has no built-in HDD boot at all (its per-class
; iterator only serves the FDD classes), so this ROM does what a real -55
; does -- at POST entry 0x12, after both FDD attempts, it reads the IPL
; (two sectors at LBA 0, 1024 bytes) to 1FC0:0000 and far-calls it with the
; register set the NEC boot code hands down, a proper stack and a RETF
; frame back to our own return path for a polite bail to BASIC.
;
; After editing: nasm -f bin -o scsi_rom.bin scsi_rom.asm, then fold the
; bytes into fpga/core/scsi_rom.hex (one byte per line, 4096 entries) for
; the $readmemh in fpga/core/pc98_scsi_rom.sv.

        cpu 186
        org 0

        times 0x09 db 0
        db 0x55, 0xAA           ; signature word AA55h at offset 9
        db 0x90

        times 0x0C - ($ - $$) db 0x90
post0:  jmp post_init           ; pass 1: claim, register, probe
        times 0x0F - ($ - $$) db 0x90
post1:  jmp post_init           ; pass 2: same, idempotent
        times 0x12 - ($ - $$) db 0x90
post2:  jmp post_boot           ; pass 3: boot attempt, after both FDD tries
        times 0x15 - ($ - $$) db 0x90
post3:  retf                    ; pass 4: nothing to add to the class sweep
        times 0x18 - ($ - $$) db 0x90

; ==================== disk-BIOS extension entry (0x18) ====================
; Entered by far jmp from the INT 1Bh dispatcher with DS=0, BP=SP and the
; caller's frame on the stack:
;   [bp+00]=AX(AL devtype,AH fn) [bp+02]=BX(bytes) [bp+04]=CX(cyl / LBA lo)
;   [bp+06]=DX(DL sec|LBA hi, DH head) [bp+08]=BP(buffer off)
;   [bp+0A]=ES(buffer seg) [bp+0C]=DI [bp+0E]=SI [bp+10]=DS
;   [bp+12]=IP [bp+14]=CS [bp+16]=FLAGS
; The BIOS tail-jumps here through 0000:04B0[devtype nibble]. We handle
; unit 0 only -- a single HDD image is mounted.

%define GEO      0x05A0        ; 4-byte scsiinf record: spt, heads|cylhi, inf
%define GEOEQUIP 0x05A4        ; bit0: unit 0 present
%define BOOTSS   0x05A6        ; saved SS/SP around the IPL far call
%define BOOTSP   0x05A8

%define WAIT_SHORT 4           ; mailbox poll outer loops (x ~64K inner)
%define WAIT_LONG  48          ; formats and first commands may dawdle

scsi_disk:
        push si                         ; [bp-2]
        push di                         ; [bp-4]
        push ax                         ; [bp-6]  lba bits 0-15
        push ax                         ; [bp-8]  lba bits 16-31
        push ax                         ; [bp-10] whole sectors remaining
        push ax                         ; [bp-12] tail byte count
        push ax                         ; [bp-14] blocks in the command
        push ax                         ; [bp-16] opcode
        push ax                         ; [bp-18] mode: 0 read, 1 verify, 2 write

        mov  si, [bp+0]                 ; caller's AX: AL=devtype, AH=fn
        test si, 0x000F                 ; one mounted image: unit 0 only
        jnz  .badunit
        mov  al, [bp+1]                 ; function low nibble
        and  al, 0x0F
        cmp  al, 0x01
        je   fn_verify
        cmp  al, 0x03
        je   fn_nop                     ; init: probe happened at POST
        cmp  al, 0x04
        je   fn_sense
        cmp  al, 0x05
        je   fn_write
        cmp  al, 0x06
        je   fn_read
        cmp  al, 0x07
        je   fn_nop                     ; recalibrate: nothing moves
        cmp  al, 0x0A
        je   fn_setsec
        cmp  al, 0x0C
        je   fn_chginf
        cmp  al, 0x0D
        je   fn_format
        cmp  al, 0x0F
        je   fn_nop
        mov  ah, 0x40                   ; unknown function on our device
        jmp  done
.badunit:
        mov  ah, 0x60                   ; unit not present
        jmp  done

; ---- fn 4: sense -------------------------------------------------------
; AH=0x04 TEST UNIT READY; AH=0x24 install caller's geometry;
; AH=0x44 "how many parameter words"; AH=0x84 read geometry.
fn_sense:
        mov  ax, si
        cmp  ah, 0x24
        je   sense_set
        cmp  ah, 0x44
        je   sense_q44
        cmp  ah, 0x84
        je   sense_read
        ; TEST UNIT READY
        xor  cl, cl
        mov  al, 0x00
        call emit_op6
        mov  bx, WAIT_SHORT
        call scsi_go
        jc   .nr
        test al, al
        jnz  .cc
        xor  ah, ah
        jmp  done
.nr:    mov  ah, 0x60
        jmp  done
.cc:    call sense_map
        jmp  done

sense_set:                              ; AH=0x24: DL=spt DH=heads(+cylhi)
        mov  al, [bp+6]                 ;       CX=cyl  BX=sector size
        mov  [GEO+0], al
        mov  dx, [bp+4]
        mov  al, [bp+7]
        test dh, 0xF0                   ; caller's cyl bits 12-15 ride in
        jz   .ns                        ;       the DH high nibble
        mov  ah, dh
        and  ah, 0xF0
        or   al, ah
.ns:    mov  [GEO+1], al
        mov  ax, dx
        and  ax, 0x0FFF
        test dh, 0xF0
        jz   .ne
        or   ax, 0x4000                 ; extended-cylinder flag
.ne:    mov  cx, [bp+2]
        cmp  cx, 512
        jne  .a
        or   ax, 0x1000
.a:     cmp  cx, 1024
        jne  .b
        or   ax, 0x2000
.b:     mov  [GEO+2], ax                ; hwsec bit 0, like np21w's sense path
        xor  ah, ah
        jmp  done

sense_q44:                              ; AH=0x44: BX = 2 if hwsec else 1
        mov  cx, 1
        test byte [GEO+3], 0x80
        jz   .w
        mov  cx, 2
.w:     mov  [bp+2], cx
        xor  ah, ah
        jmp  done

sense_read:                             ; AH=0x84: geometry -> CX/DX, BX=size
        mov  dl, [GEO+0]
        mov  dh, [GEO+1]
        and  dh, 0x0F
        mov  cl, [GEO+2]
        mov  ch, [GEO+3]
        and  ch, 0x0F
        test byte [GEO+3], 0x40         ; extended cylinders?
        jz   .nx
        mov  al, [GEO+1]
        and  al, 0xF0
        or   ch, al                     ; cyl bits 12-15 back into CH
.nx:    mov  [bp+6], dx
        mov  [bp+4], cx
        mov  al, [GEO+3]
        xor  ah, ah
        mov  cl, 4
        shr  ax, cl
        and  ax, 0x03                   ; size-class bits
        mov  cl, al
        mov  ax, 0x0100                 ; 256 << class
        shl  ax, cl
        mov  [bp+2], ax
        xor  ah, ah
        jmp  done

; ---- fn A: setsec -------------------------------------------------------
; np21w: succeeds only when BH&3 selects our 512-byte sector.
fn_setsec:
        mov  al, [bp+3]                 ; caller's BH
        and  al, 0x03
        cmp  al, 0x02
        jne  .bad
        xor  ah, ah
        jmp  done
.bad:   mov  ah, 0x40
        jmp  done

; ---- fn C: change-information -------------------------------------------
; A non-removable image never changes: CX = 0 = "same since last call".
fn_chginf:
        mov  word [bp+4], 0
        xor  ah, ah
        jmp  done

; ---- fn D: format --------------------------------------------------------
; Whole-disk when the function's bit7 is set, else the named track --
; which on np21w must name the track's first sector (DL=0). The mounted
; image is already media-complete; the command is issued so real format
; flows see a compliant target, and the firmware answers it as a no-op.
fn_format:
        test byte [bp+1], 0x80
        jnz  .go                        ; whole-disk: no position needed
        mov  al, [bp+6]
        or   al, al
        jz   .pos
        mov  ah, 0x30                   ; mid-track format: not defined
        jmp  done
.pos:   call get_lba                    ; validates CX/DH/DL vs geometry
        jc   done
.go:    xor  cl, cl
        mov  al, 0x04                   ; FORMAT UNIT
        call emit_op6
        mov  bx, WAIT_LONG
        call scsi_go
        jc   .to
        test al, al
        jnz  .cc
        xor  ah, ah
        jmp  done
.to:    mov  ah, 0x60
        jmp  done
.cc:    call sense_map
        jmp  done

; ---- fn 7 / fn F / fn 3: no state to change ------------------------------
fn_nop:
        xor  ah, ah
        jmp  done

; ---- fn 1 / 5 / 6: transfers ---------------------------------------------
; BX bytes (0 = the whole 64 KB) at ES:BP, position per get_lba.
fn_read:
        mov  word [bp-18], 0
        jmp  xfer
fn_verify:
        mov  word [bp-18], 1
        jmp  xfer
fn_write:
        mov  word [bp-18], 2
xfer:
        mov  byte [bp-16], 0x28         ; READ10
        cmp  word [bp-18], 2
        jne  .op
        mov  byte [bp-16], 0x2A         ; WRITE10
.op:    call get_lba                    ; -> BX:SI = LBA
        jc   done
        mov  [bp-6], si
        mov  [bp-8], bx
        mov  ax, [bp+2]                 ; byte count -> sectors + tail
        call set_counts
        cmp  word [bp-18], 2            ; writes must be whole sectors:
        jne  .buf                       ; a tail would leave the sector's
        cmp  word [bp-12], 0            ; balance undefined (np21w pads with
        je   .buf                       ; its own buffer; we refuse cleanly)
        mov  ah, 0xD0
        jmp  done
.buf:   mov  es, [bp+0x0A]              ; caller's buffer
        mov  di, [bp+8]
.lp:    mov  ax, [bp-10]
        or   ax, ax
        jz   .tail
        cmp  ax, 16                     ; the board's buffer: 16 sectors
        jbe  .n
        mov  ax, 16
.n:     mov  [bp-14], ax
        sub  [bp-10], ax
        mov  ch, al                     ; CX = n * 512 bytes of payload
        xor  cl, cl
        add  cx, cx
        cmp  word [bp-18], 2            ; write: stream to the board first
        jne  .issue
        call buf_out
.issue: call issue_xfer                 ; CDB + command; lba advances
        jc   done
        mov  cx, [bp-14]                ; the mailbox poll ate CX: rebuild
        shl  cx, 9                      ; n blocks * 512 payload bytes
        cmp  word [bp-18], 0            ; read: pull the payload
        jne  .v
        call pull_in
        jmp  .lp
.v:     cmp  word [bp-18], 1            ; verify: pull-and-discard
        jne  .lp
        call pull_skip
        jmp  .lp
.tail:  mov  ax, [bp-12]
        or   ax, ax
        jz   .ok
        mov  word [bp-12], 0
        mov  word [bp-14], 1            ; one sector carries the tail
        push ax
        call issue_xfer
        pop  cx
        jc   done
        cmp  word [bp-18], 0            ; reads deliver the tail bytes;
        jne  .ok                        ; verify just lets them pass
        call pull_in
.ok:    xor  ah, ah
        jmp  done

; ============================ epilogue ===================================
done:
        mov  [bp+1], ah                 ; status back through the frame
        and  byte [bp+0x16], 0xFE       ; CF clear
        cmp  ah, 0x20                   ; the BIOS's own rule: >=0x20 is error
        jb   .nc
        or   byte [bp+0x16], 0x01       ; CF set
.nc:    lea  sp, [bp-4]                 ; drop the locals
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

; ============================ SCSI plumbing ==============================
; emit_op6 -- a group-0 CDB (6 bytes): AL=opcode, CL=byte 4 (alloc/count).
; Written at control-register index 0x03, where the firmware reads it.
emit_op6:
        mov  dx, 0xCC0
        mov  ah, al
        mov  al, 0x03
        out  dx, al
        mov  al, ah
        mov  dx, 0xCC2
        out  dx, al                     ; cdb[0] opcode
        xor  al, al
        out  dx, al                     ; cdb[1]
        out  dx, al                     ; cdb[2]
        out  dx, al                     ; cdb[3]
        mov  al, cl
        out  dx, al                     ; cdb[4]
        xor  al, al
        out  dx, al                     ; cdb[5] control
        ret

; emit_cap -- READ CAPACITY (10-byte CDB, only the opcode nonzero).
emit_cap:
        mov  dx, 0xCC0
        mov  al, 0x03
        out  dx, al
        mov  dx, 0xCC2
        mov  al, 0x25
        out  dx, al
        xor  al, al
        mov  cl, 9
.z:     out  dx, al
        loop .z
        ret

; emit_rw10 -- READ10/WRITE10: AL=opcode, BX:SI=LBA, CL=block count.
emit_rw10:
        mov  dx, 0xCC0
        mov  ah, al
        mov  al, 0x03
        out  dx, al
        mov  al, ah
        mov  dx, 0xCC2
        out  dx, al                     ; cdb[0] opcode
        xor  al, al
        out  dx, al                     ; cdb[1] reserved/LUN
        mov  al, bh
        out  dx, al                     ; cdb[2] lba 24-31
        mov  al, bl
        out  dx, al                     ; cdb[3] lba 16-23
        mov  ax, si
        push ax
        mov  al, ah
        out  dx, al                     ; cdb[4] lba 8-15
        pop  ax
        out  dx, al                     ; cdb[5] lba 0-7
        xor  al, al
        out  dx, al                     ; cdb[6] reserved
        out  dx, al                     ; cdb[7] blocks hi (never >16)
        mov  al, cl
        out  dx, al                     ; cdb[8] blocks lo
        xor  al, al
        out  dx, al                     ; cdb[9] control
        ret

; scsi_go -- commit the command and wait for the firmware's completion.
; In: BX = outer poll bound. Out: CF=1 timeout; else AL = SCSI status byte.
scsi_go:
        mov  dx, 0xCC0
        mov  al, 0x18
        out  dx, al
        mov  dx, 0xCC2
        mov  al, 0x20                   ; CMD: toggles cmd_req, firmware runs
        out  dx, al
        mov  dx, 0xCC0
.o:     mov  cx, 0                      ; ~64K of polls per outer count
.p:     in   al, dx                     ; auxstatus bit 7: command finished
        test al, 0x80                   ; (the read also clears it)
        jnz  .done
        loop .p
        dec  bx
        jnz  .o
        stc                             ; firmware never answered
        ret
.done:  mov  dx, 0xCC0
        mov  al, 0x17                   ; SCSI status byte
        out  dx, al
        mov  dx, 0xCC2
        in   al, dx
        clc
        ret

; issue_xfer -- one transfer command for the current chunk.
; [bp-6]/[bp-8]=LBA, [bp-14]=blocks, [bp-16]=opcode. Advances the lba on
; success. CF+AH on failure.
issue_xfer:
        mov  si, [bp-6]
        mov  bx, [bp-8]
        mov  cx, [bp-14]
        mov  ax, [bp-16]
        call emit_rw10
        mov  bx, WAIT_LONG
        call scsi_go
        jc   .to
        test al, al
        jnz  .cc
        mov  ax, [bp-14]
        add  [bp-6], ax
        adc  word [bp-8], 0
        clc
        ret
.to:    mov  ah, 0x60
        stc
        ret
.cc:    call sense_map
        stc
        ret

; sense_map -- REQUEST SENSE after a CHECK CONDITION; AH = NEC status.
sense_map:
        mov  cl, 0x12                   ; 18-byte fixed sense data
        mov  al, 0x03
        call emit_op6
        mov  bx, WAIT_SHORT
        call scsi_go
        jc   .tmout
        test al, al
        jnz  .self                      ; sense itself failed
        mov  dx, 0xCC6
        mov  cx, 18
        xor  bx, bx
.rl:    in   al, dx
        cmp  cx, 16                     ; byte 2: sense key
        jne  .n1
        mov  bl, al
.n1:    cmp  cx, 6                      ; byte 12: ASC
        jne  .n2
        mov  bh, al
.n2:    loop .rl
        cmp  bl, 0x02                   ; NOT READY
        je   .nr
        cmp  bl, 0x05                   ; ILLEGAL REQUEST
        je   .il
        cmp  bl, 0x07                   ; DATA PROTECT
        je   .dp
        mov  ah, 0x20                   ; error, generic
        ret
.nr:    mov  ah, 0x60                   ; unit not ready
        ret
.il:    mov  ah, 0xD0                   ; out of range / bad command
        ret
.dp:    mov  ah, 0x70                   ; write protected
        ret
.tmout: mov  ah, 0x60
        ret
.self:  mov  ah, 0x20
        ret

; pull_in -- CX bytes from the board's buffer to ES:DI; ES walks on wrap.
pull_in:
        mov  dx, 0xCC6
.p:     in   al, dx
        mov  es:[di], al
        inc  di
        jnz  .n
        mov  ax, es
        add  ax, 0x1000
        mov  es, ax
.n:     loop .p
        ret

; pull_skip -- drain CX bytes of buffer the caller does not want.
pull_skip:
        mov  dx, 0xCC6
.p:     in   al, dx
        loop .p
        ret

; buf_out -- CX bytes from ES:DI into the board's buffer.
buf_out:
        mov  dx, 0xCC6
.p:     mov  al, es:[di]
        out  dx, al
        inc  di
        jnz  .n
        mov  ax, es
        add  ax, 0x1000
        mov  es, ax
.n:     loop .p
        ret

; ============================ position ====================================
; get_lba -- the caller's position to a linear sector in BX:SI.
; CHS (AL&0x80): CX=cylinder, DH=head, DL=zero-based sector -- bounds per
;   np21w's sxsi_pos (0xD0 on any out-of-range).
; LBA (AL&0x7F): pos = DL:CX for our <16M-sector images, bound pos<totals.
get_lba:
        mov  bl, [GEO+0]                ; sectors/track
        mov  bh, [GEO+1]
        and  bh, 0x0F                   ; surfaces
        or   bl, bl
        jz   .err                       ; not probed: no geometry
        or   bh, bh
        jz   .err
        mov  ax, [GEO+2]
        and  ax, 0x0FFF                 ; cylinders
        test byte [GEO+3], 0x40
        jz   .nx
        mov  dl, [GEO+1]
        and  dl, 0xF0                   ; cyl bits 12-15 live in inf[1] hi
        mov  dh, dl
        xor  dl, dl
        or   ax, dx
.nx:    mov  di, ax                     ; DI = cylinder bound
        test byte [bp+0], 0x80
        jnz  .chs
        ; LBA mode: DL is bits 16-23 of the position, CX the low word.
        mov  bl, [bp+6]                 ; DL
        xor  bh, bh
        mov  si, [bp+4]                 ; CX
        push si                         ; totals = cylinders * (8*25)
        push bx
        mov  ax, di
        mov  cx, 200
        mul  cx                         ; DX:AX = total sectors
        pop  bx
        pop  si
        cmp  bx, dx
        ja   .err
        jb   .okl
        cmp  si, ax
        jae  .err
.okl:   clc
        ret
.chs:
        mov  al, [bp+6]                 ; sector < spt
        cmp  al, bl
        jae  .err
        mov  al, [bp+7]                 ; head < surfaces
        cmp  al, bh
        jae  .err
        mov  ax, [bp+4]                 ; cylinder < cylinders
        cmp  ax, di
        jae  .err
        ; pos = (cyl*heads + head) * spt + sector   (DX:AX intermediates)
        mov  cl, bh
        xor  ch, ch
        mul  cx                         ; DX:AX = cyl * heads
        mov  cl, [bp+7]
        add  ax, cx                     ; + head   -> t = DX:AX
        adc  dx, 0
        mov  cl, bl                     ; spt
        push dx
        mul  cx                         ; DX:AX = t_lo * spt
        mov  si, ax
        mov  bx, dx
        pop  ax
        mul  cx                         ; DX:AX = t_hi * spt (AX suffices)
        add  bx, ax
        mov  al, [bp+6]                 ; + sector
        xor  ah, ah
        add  si, ax
        adc  bx, 0                      ; BX:SI = linear sector
        clc
        ret
.err:   mov  ah, 0xD0
        stc
        ret

; set_counts -- AX byte count -> [bp-10] whole sectors, [bp-12] tail bytes.
; Zero means the whole 64 KB, np21w's convention.
set_counts:
        or   ax, ax
        jnz  .n
        mov  word [bp-10], 128          ; 65536 bytes
        mov  word [bp-12], 0
        ret
.n:     mov  cx, ax
        mov  al, ah
        xor  ah, ah
        shr  ax, 1                      ; bytes >> 9
        mov  [bp-10], ax
        mov  ax, cx
        and  ax, 0x01FF
        mov  [bp-12], ax
        ret

; ============================ init & boot =================================
; disk_init -- probe the mounted image and publish its geometry.
; Clobbers AX BX CX DX SI DI; DS=0 throughout.
disk_init:
        push ds
        pop  es
        cld
        mov  di, GEO
        xor  ax, ax
        mov  cx, 3
        rep  stosw                      ; clear the record + equip byte
        mov  byte [GEOEQUIP], 0
        ; TEST UNIT READY -- is an image there at all?
        xor  cl, cl
        mov  al, 0x00
        call emit_op6
        mov  bx, WAIT_SHORT
        call scsi_go
        jc   .out
        test al, al
        jnz  .out
        ; READ CAPACITY -> last lba + block size (8 bytes)
        call emit_cap
        mov  bx, WAIT_SHORT
        call scsi_go
        jc   .out
        test al, al
        jnz  .out
        mov  dx, 0xCC6
        in   al, dx
        mov  bh, al
        in   al, dx
        mov  bl, al
        in   al, dx
        mov  ch, al
        in   al, dx
        mov  cl, al                     ; BX:CX = last lba
        in   al, dx
        in   al, dx
        in   al, dx
        in   al, dx                     ; drain the block-size word
        add  cx, 1
        adc  bx, 0                      ; BX:CX = total sectors
        ; cylinders = totals / 200 (8 heads x 25 spt), capped at 0xFFFF
        mov  dx, bx
        mov  ax, cx
        cmp  dx, 200
        jae  .cap
        mov  cx, 200
        div  cx                         ; AX = cylinders
        or   ax, ax
        jz   .out                       ; <200 sectors: not a usable disk
        mov  cx, ax
        jmp  .have
.cap:   mov  cx, 0xFFFF
.have:  mov  byte [GEO+0], 25           ; spt
        mov  al, ch
        and  al, 0xF0                   ; cyl bits 12-15 -> surfaces hi nibble
        or   al, 0x08                   ; 8 surfaces
        mov  [GEO+1], al
        mov  ax, cx
        and  ax, 0x0FFF
        or   ax, 0x9000                 ; hwsec=1 | 512-byte class
        test ch, 0xF0
        jz   .ne
        or   ax, 0x4000                 ; extended cylinders
.ne:    mov  [GEO+2], ax
        or   byte [GEOEQUIP], 0x01
.out:   ret

; post_common -- the scan's contract: claim our flag slot, register the
; SCSI devtypes in the XROM table. BX = our window's flag-table byte.
post_common:
        mov  byte [bx], 0xFF            ; window claimed; later passes find
                                        ; bit 6 set and keep calling us
        mov  ax, cs
        mov  al, ah                     ; our segment's high byte (0xD2)
        mov  [0x04B2], al               ; devtype 0x2x -- SCSI, LBA calls
        mov  [0x04BA], al               ; devtype 0xAx -- SCSI, CHS calls
        ret

post_init:                              ; entries 0x0C and 0x0F
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push es
        push ds
        xor  ax, ax
        mov  ds, ax
        mov  es, ax
        call post_common
        call disk_init
        pop  ds
        pop  es
        pop  bp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        retf

post_boot:                              ; entry 0x12: after both FDD tries
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push es
        push ds
        xor  ax, ax
        mov  ds, ax
        mov  es, ax
        call post_common
        call disk_init
        cmp  byte [GEOEQUIP], 0
        je   .out                       ; nothing mounted: leave it to BASIC
        ; the IPL: two sectors at LBA 0 -> 1FC0:0000
        mov  ax, 0x1FC0
        mov  es, ax
        xor  di, di
        xor  si, si
        xor  bx, bx
        mov  cl, 2
        mov  ax, 0x28                   ; READ10
        call emit_rw10
        mov  bx, WAIT_LONG
        call scsi_go
        jc   .out
        test al, al
        jnz  .out                       ; read failed: fall through to BASIC
        mov  dx, 0xCC6
        mov  cx, 0x400
.pb:    in   al, dx
        mov  es:[di], al
        inc  di
        loop .pb
        ; registers down to the NEC convention, a real stack, and a RETF
        ; back to .post_ret in case the IPL wants out.
        mov  byte [0x0584], 0xA0        ; DISK_BOOT: a SCSI unit booted
        mov  [BOOTSS], ss
        mov  [BOOTSP], sp
        mov  ax, 0x0020
        mov  ss, ax
        mov  sp, 0x01DC
        push cs
        mov  ax, post_ret
        push ax                         ; the IPL's RETF target
        mov  ax, 0x00A0                 ; DA/UA of the booted device
        mov  bx, 0x0400                 ; bytes read
        mov  cx, 0x0200                 ; cyl 0 | 512-byte class (sense form)
        mov  dx, 0x0000                 ; head 0, sector 0: HD is zero-based
        xor  bp, bp
        mov  si, 0x1FC0
        mov  di, 0x055C                 ; DISK_EQUIP pointer
        mov  es, si
        push si
        xor  ax, ax
        push ax
        retf                            ; -> 1FC0:0000

.out:   pop  ds
        pop  es
        pop  bp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        retf

post_ret:                               ; the IPL asked out: restore the
        xor  ax, ax                     ; POST frame and let the scan run on
        mov  ds, ax
        mov  ss, [BOOTSS]
        mov  sp, [BOOTSP]
        pop  ds
        pop  es
        pop  bp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        retf

        times 0x1000 - ($ - $$) db 0xFF ; the window is 4 KB
