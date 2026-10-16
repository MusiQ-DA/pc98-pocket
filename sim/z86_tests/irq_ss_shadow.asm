bits 16
org 0x1000
    xor ax,ax
    mov ds,ax
    mov word [0x80],h
    mov word [0x82],0
    mov ax,0x300
    mov ss,ax
    mov sp,0x0800          ; stack A: 3000:0800 = 03800
    sti
    mov cx,400
l:  mov ax,0x400
    mov ss,ax
    mov sp,0x0C00          ; stack B: 4000:0C00 = 04C00
    nop
    mov ax,0x300
    mov ss,ax
    mov sp,0x0800
    nop
    loop l
    cli
    hlt
h:  inc word [cs:0x6F0]
    iret
