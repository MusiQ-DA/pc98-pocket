; far-transfer / stack stress test for zet+bridge  (v2: jmp far + modrm + 2 segs)
; code at phys 0x10000 (CS=0x1000, IP=0); second code seg at 0x30000 (CS=0x3000)
; reset stub at 0xFFFF0
[BITS 16]
section .text

; pad so code lands at file offset / phys 0x10000
times 0x10000 db 0

start:
    cli
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    mov ax, 0x2000
    mov ss, ax
    mov sp, 0xFFFE

    ; IVT[0x40] -> inthandler
    xor ax, ax
    mov es, ax
    mov word [es:0x100], inthandler - start
    mov word [es:0x102], 0x1000
    mov ax, 0x1000
    mov es, ax

    ; far-pointer table (DS):
    ;  [0x0100] -> func_ret   (call far [0x0100])
    ;  [0x0104] -> seg2_func  (call far [bx] to seg 0x3000)
    ;  [0x0108] -> seg2_jtgt2 (jmp far [si] to seg 0x3000)
    mov word [0x0100], func_ret - start
    mov word [0x0102], 0x1000
    mov word [0x0104], seg2_func - seg2_base
    mov word [0x0106], 0x3000
    mov word [0x0108], seg2_jtgt2 - seg2_base
    mov word [0x010A], 0x3000
    ; a [bx+disp8] and [si+disp16] variant: point table mid-way
    mov word [0x0110], seg2_alt - seg2_base
    mov word [0x0112], 0x3000

    mov di, 0

mainloop:
    mov ax, di
    out 0x20, al               ; progress marker

    ; 1) direct far call + retf (same seg)
    call 0x1000:(func_ret - start)

    ; 2) indirect far call [direct addr]
    call far [0x0100]

    ; 3) indirect far call [bx]
    mov bx, 0x0104
    call far [bx]

    ; 4) indirect far call [bx+disp16]
    mov bx, 0x0100
    call far [bx+0x0010]

    ; 5) software int + iret
    int 0x40

    ; 6) pusha/popa
    pusha
    popa

    ; 7) push-frame far transfer: push cs;push off;retf
    push 0x1000
    push word (cs_check - start)
    retf
cs_check:
    mov ax, cs
    cmp ax, 0x1000
    je cs_ok
    mov al, 0xEE
    out 0x30, al
    hlt
cs_ok:
    ; 8) jmp far direct to seg2_jtgt (which jmp-fars back)
    jmp 0x3000:(seg2_jtgt - seg2_base)
after_jmpback:

    ; 9) jmp far [si] indirect to seg2_jtgt
    mov si, 0x0108
    jmp far [si]
after_jmpback2:

    inc di
    cmp di, 300
    jl mainloop

    mov al, 0xAC
    out 0x30, al
    hlt

; ----------------------------------------------------------------
func_ret:
    pusha
    mov ax, cs
    cmp ax, 0x1000
    je fr_ok
    mov al, 0xE1
    out 0x21, al
fr_ok:
    popa
    mov al, 0x11
    out 0x21, al
    retf

inthandler:
    push ax
    mov al, 0x22
    out 0x22, al
    pop ax
    iret

; pad to 0x30000 for the second code segment
times 0x30000 - ($ - $$) db 0
seg2_base:

; far-called into CS=0x3000; verify cs, then retf back to 0x1000
seg2_func:
    push ax
    mov ax, cs
    cmp ax, 0x3000
    je s2_ok
    mov al, 0xE2               ; wrong cs on cross-seg call
    out 0x23, al
s2_ok:
    pop ax
    mov al, 0x33
    out 0x23, al
    retf

; called via [bx+disp16] table
seg2_alt:
    push ax
    mov ax, cs
    cmp ax, 0x3000
    je s2a_ok
    mov al, 0xE3
    out 0x24, al
s2a_ok:
    pop ax
    mov al, 0x44
    out 0x24, al
    retf

; jmp far direct target: jmp-fars straight back to after_jmpback
seg2_jtgt:
    push ax
    mov ax, cs
    cmp ax, 0x3000
    je s2j_ok
    mov al, 0xE4
    out 0x25, al
s2j_ok:
    pop ax
    mov al, 0x55
    out 0x25, al
    jmp 0x1000:(after_jmpback - start)

; jmp far [si] indirect target: jmp-fars back to after_jmpback2
seg2_jtgt2:
    push ax
    mov ax, cs
    cmp ax, 0x3000
    je s2j2_ok
    mov al, 0xE5
    out 0x26, al
s2j2_ok:
    pop ax
    mov al, 0x66
    out 0x26, al
    jmp 0x1000:(after_jmpback2 - start)

; pad to 0xFFFF0 then reset vector
times 0xFFFF0 - ($ - $$) db 0
resetvec:
    jmp 0x1000:0x0000
