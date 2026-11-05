bits 16
org 0x1000
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0x0800
    ; 1. patch an immediate 16 bytes ahead, fall through into it
    mov byte [p1+1],0x22
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
p1: mov al,0x11
    mov [0x600],al          ; 22 on a 286 (more than 6 bytes ahead)
    ; 2. write code then jump backward into the same 32-byte window
    mov byte [p2+1],0x33
    jmp short p2
p2: mov al,0x99
    mov [0x601],al          ; 33
    ; 3. loop that patches its own body each pass
    mov cx,3
    mov bl,0
l3: mov al,0x40
    add bl,al
    inc byte [l3+1]
    loop l3
    mov [0x602],bl          ; 40+41+42 = C3
    ; 4. rep movsb copies a routine, then call it (copy lands near)
    mov si,r4
    mov di,0x1F00
    mov cx,r4e-r4
    cld
    rep movsb
    call 0:0x1F00
    mov [0x603],al          ; 5A
    hlt
r4: mov al,0x5A
    retf
r4e:
