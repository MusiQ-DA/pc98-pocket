bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    cmp byte [0x700],0x55
    je second
    mov byte [0x700],0x55
    mov al,0
    out 0xF0,al
    hlt
    jmp $
second:
    mov byte [0x600],0x77
    hlt
