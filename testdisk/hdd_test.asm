; hdd_test.asm -- IPL for the raw SCSI HDD test image. The PC-9801-55 option
; ROM's boot pass (fpga/scsi_rom.asm post_boot) reads two sectors at LBA 0 to
; 1FC0:0000 and far-calls offset 0 with AX=00A0h BX=0400h CX=0200h DX=0
; SI=1FC0h and a RETF frame back to the POST for a polite bail to BASIC.
; There is NO signature check on this path -- whatever sits at offset 0 runs.
;
; Proves the whole chain end to end: dataslot bind -> scsi_mount -> the ROM's
; TEST UNIT READY / READ CAPACITY probe -> READ10 -> these bytes execute.
; Prints "SCSI HDD IPL OK" in text-VRAM row 0, stashes the same string at
; phys 0x40000 for a JTAG readback, and stops so the mark outlives the boot
; (a `retf` instead would return to post_ret and on to BASIC, which clears
; the screen).
;
; Keep the code under 512 bytes: the ROM loads 0x400, but the first sector
; alone is guaranteed on every loader.

        bits 16
        org 0

start:
        cli
        push    cs
        pop     ds                      ; our bytes are at CS = DS
        mov     ax, 0xA000
        mov     es, ax                  ; text VRAM: chars at 0000h, attrs 2000h
        xor     di, di
        mov     si, msg
.put:
        lodsb
        or      al, al
        jz      stash
        mov     [es:di], al
        mov     byte [es:di+1], 0
        mov     byte [es:di+0x2000], 0xE1   ; white, shown -- as fdc_ipl uses
        add     di, 2
        jmp     .put

stash:                                  ; copy the string, NUL included, to
        mov     ax, 0x4000              ; phys 0x40000 for the JTAG side
        mov     es, ax
        xor     di, di
        mov     si, msg
.s:     lodsb
        stosb
        or      al, al
        jnz     .s

hang:   jmp     hang                    ; keep the mark on screen; RESET out

msg:    db "SCSI HDD IPL OK", 0

        times 510-($-$$) db 0x90        ; pad inside the first sector
        db 0xEB, 0xFE                   ; safety net at the sector's tail
