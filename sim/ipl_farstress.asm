; ipl_farstress.asm -- boot-sector far-transfer stress for REAL hardware.
; Loaded by the PC-98 BIOS at the IPL address it picks for the media:
;   2HD    -> phys 0x1FC00, CS=0x1FC0
;   other  -> phys 0x1FE00, CS=0x1FE0   (np21w bios/bios1b.c boot_fd1)
; so EVERY self-reference uses the runtime CS, never a hardcoded segment.
; IMPORTANT: the non-2HD path only loads 512 bytes (0x200), so this whole
; program -- code + the seg2 source that gets copied -- must fit in 512.
[BITS 16]
org 0

MBX_SEG equ 0x5000          ; mailbox segment -> phys 0x50000
TAB_SEG equ 0x4000          ; far-pointer table segment -> phys 0x40000
; mailbox: +0 'FS', +2 iter, +4 status(0/AC/EE), +6 bad CS, +8 opidx, +10 retcs,
;          +0x40 breadcrumb (last stage reached)
; table (DS=TAB_SEG):
;   [0x00] entry CS (the "expected" segment for CS-verify checks)
;   [0x100] {func_ret,  cs}    same-seg far call
;   [0x104] {seg2_func, 0x3000} cross-seg far call
;   [0x108] {seg2_func, 0x3000} for [bx]
;   [0x10C] {seg2_func, 0x3000} for [bx+disp]
;   [0x110] {seg2_jtgt, 0x3000} indirect far jump
;   [0x114] {fail,      cs}    seg2 -> fail return
;   [0x118] {return,    cs}    seg2_jtgt variable return (set per op)

start:
    cli
    mov ax, cs                  ; actual load segment (0x1FC0 or 0x1FE0)
    mov ds, ax                  ; DS = my code seg (seg2 copy source)
    mov ax, 0x6000
    mov ss, ax
    mov sp, 0xFFFE
    mov ax, MBX_SEG
    mov es, ax
    mov byte [es:0], 'F'
    mov byte [es:1], 'S'
    mov word [es:4], 0
    mov byte [es:0x40], 1
    ; IVT[0x40] -> inthandler (CS=load seg)
    mov ax, cs
    xor bx, bx
    mov es, bx
    mov word [es:0x100], inthandler - start
    mov [es:0x102], ax
    mov ax, MBX_SEG
    mov es, ax
    mov byte [es:0x40], 2
    ; copy seg2 source to phys 0x30000 (CS=0x3000); DS still = my code seg
    mov ax, 0x3000
    mov es, ax
    xor di, di
    mov si, seg2_src - start
    mov cx, seg2_len
    rep movsb
    mov ax, MBX_SEG
    mov es, ax
    mov byte [es:0x40], 3
    ; DS -> table segment; stays TAB for the rest
    mov ax, TAB_SEG
    mov ds, ax
    mov ax, cs
    mov [0x00], ax              ; entry CS
    mov word [0x0100], func_ret - start
    mov [0x0102], ax
    mov word [0x0104], seg2_func - seg2_src
    mov word [0x0106], 0x3000
    mov word [0x0108], seg2_func - seg2_src
    mov word [0x010A], 0x3000
    mov word [0x010C], seg2_func - seg2_src
    mov word [0x010E], 0x3000
    mov word [0x0110], seg2_jtgt - seg2_src
    mov word [0x0112], 0x3000
    mov word [0x0114], fail - start
    mov ax, cs
    mov [0x0116], ax
    mov byte [es:0x40], 4
    mov di, 0
    mov byte [es:0x40], 5

mainloop:
    mov [es:2], di
    mov byte [es:8], 0          ; op0: far call same-seg -> func_ret
    call far [0x0100]
    mov byte [es:0x40], 0x10
    mov byte [es:8], 1          ; op1: far call [bx] -> seg2_func (retf)
    mov bx, 0x0108
    call far [bx]
    mov byte [es:0x40], 0x11
    mov byte [es:8], 2          ; op2: far call [bx+disp] -> seg2_func
    mov bx, 0x0100
    call far [bx+0x000C]
    mov byte [es:0x40], 0x12
    mov byte [es:8], 3          ; op3: software int + iret
    int 0x40
    mov byte [es:0x40], 0x13
    mov byte [es:8], 4          ; op4: pusha/popa
    pusha
    popa
    mov byte [es:0x40], 0x14
    mov byte [es:8], 5          ; op5: push-frame retf -> cs_check
    push cs
    push word (cs_check - start)
    retf
cs_check:
    mov ax, cs
    cmp ax, [0]                 ; ds=TAB -> entry cs
    je op6
    mov byte [es:8], 5
    jmp fail
op6:
    mov byte [es:0x40], 0x15
    mov byte [es:8], 6          ; op6: direct far jmp -> seg2_jtgt (jmp back)
    mov word [0x0118], after_j1 - start
    mov ax, cs
    mov [0x011A], ax            ; [0x118] = {after_j1, cs}
    jmp 0x3000:(seg2_jtgt - seg2_src)
after_j1:
    mov byte [es:0x40], 0x16
    mov byte [es:8], 7          ; op7: indirect far jmp [si] -> seg2_jtgt
    mov word [0x0118], after_j2 - start
    mov ax, cs
    mov [0x011A], ax            ; [0x118] = {after_j2, cs}
    mov si, 0x0110
    jmp far [si]
after_j2:
    mov byte [es:0x40], 0x17
    inc di
    cmp di, 2000
    jge short .alldone
    jmp mainloop
.alldone:
    mov word [es:4], 0x00AC     ; PASS
    hlt
fail:
    mov [es:6], ax
    mov word [es:4], 0x00EE
    hlt

; same-seg far-called func: verify CS==entry cs, retf
func_ret:
    push ax
    mov ax, cs
    cmp ax, [0]
    je fr_ok
    mov ax, cs
    mov [es:10], ax
    jmp fail
fr_ok:
    pop ax
    retf
inthandler:
    push ax
    pop ax
    iret

; ---- second-segment code, copied to phys 0x30000 (CS=0x3000) ----
seg2_src:
seg2_func:                      ; far-call target: verify CS==0x3000, retf
    push ax
    push es
    mov ax, MBX_SEG
    mov es, ax
    mov ax, cs
    cmp ax, 0x3000
    je s2_ok
    mov [es:10], ax
    pop es
    pop ax
    mov byte [es:8], 0x52
    jmp far [0x0114]            ; -> fail (DS=TAB preserved)
s2_ok:
    pop es
    pop ax
    retf
seg2_jtgt:                      ; far-jump target: probe ptr words, jmp far [0x118]
    push ax
    push es
    mov ax, MBX_SEG
    mov es, ax
    mov ax, cs
    mov [es:0x10], ax           ; mbx[0x10] = current CS here (expect 0x3000)
    mov ax, [0x0118]
    mov [es:0x12], ax           ; mbx[0x12] = data-read of ptr offset word
    mov ax, [0x011A]
    mov [es:0x14], ax           ; mbx[0x14] = data-read of ptr segment word
    pop es
    pop ax
    jmp far [0x0118]            ; -> variable return (after_j1 / after_j2)
seg2_src_end:
seg2_len equ seg2_src_end - seg2_src
