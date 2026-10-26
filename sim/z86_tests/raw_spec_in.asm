bits 16
cpu 186
org 0x400
; Each case: a taken branch whose fall-through is IN AL,DX from the stream
; port. The fall-through must not touch the port: the next real IN must
; read the next byte. Stream = 01 02 03 ... ; results at 0600+.
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x800
    mov dx,0x0CC6
    ; 1. JCXZ taken
    xor cx,cx
    jcxz .a
    in al,dx
.a: in al,dx
    mov [0x600],al          ; want 01
    ; 2. JZ taken
    xor bx,bx
    jz .b
    in al,dx
.b: in al,dx
    mov [0x601],al          ; want 02
    ; 3. LOOP taken (CX=2 -> 1)
    mov cx,2
    loop .c
    in al,dx
.c: in al,dx
    mov [0x602],al          ; want 03
    ; 4. JMP short
    jmp short .d
    in al,dx
.d: in al,dx
    mov [0x603],al          ; want 04
    ; 5. JCXZ taken, MOV CX,AX right before (the mode_page shape)
    xor ax,ax
    mov cx,ax
    jcxz .e
    in al,dx
.e: in al,dx
    mov [0x604],al          ; want 05
    ; 6. JNZ taken
    or  cx,1
    jnz .f
    in al,dx
.f: in al,dx
    mov [0x605],al          ; want 06
    ; 7. CALL then RET into IN
    call .g
    in al,dx
    mov [0x606],al          ; want 07
    hlt
.g: ret
