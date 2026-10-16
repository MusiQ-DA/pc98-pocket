bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0x0800
    ; 1. LEAVE right after MOV BP
    mov bp,0x07F0
    mov word [0x07F0],0x1234
    mov bp,0x07F0
    leave                    ; SP=07F2, BP=[07F0]=1234
    mov [0x600],bp
    mov [0x602],sp
    mov sp,0x0800
    ; 2. RET right after a store to the return slot
    call t2
    jmp short n2
t2: mov bx,sp
    mov word [bx],r2
    ret
    mov byte [0x604],0xEE    ; wrong path
    jmp short n2
r2: mov byte [0x604],0x11
n2:
    ; 3. IN-free: LODSB right after a store to [SI]
    mov si,0x10D0
    mov byte [0x10D0],0x5C
    lodsb
    mov [0x605],al
    ; 4. MOVSB right after setting SI/DI
    mov byte [0x10D1],0x6D
    mov si,0x10D1
    mov di,0x606
    movsb
    ; 5. POP right after MOV SP
    mov word [0x07E0],0xBEEF
    mov sp,0x07E0
    pop cx
    mov [0x608],cx
    mov sp,0x0800
    ; 6. JMP [BX] right after store to [BX]
    mov bx,0x10E0
    mov word [0x10E0],j6
    jmp word [bx]
    mov byte [0x60A],0xEE
    jmp short n6
j6: mov byte [0x60A],0x22
n6:
    ; 7. CALL [BX] after store, then far ret through stored seg
    mov word [0x10E2],j7
    call word [bx+2]
    jmp short n7
j7: mov byte [0x60B],0x33
    ret
n7:
    ; 8. LES right after stores
    mov word [0x10E4],0xABCD
    mov word [0x10E6],0x1357
    les di,[0x10E4]
    mov [0x60C],di
    mov [0x60E],es
    xor ax,ax
    mov es,ax
    ; 9. PUSHF / POP after flag change
    stc
    pushf
    pop ax
    and al,1
    mov [0x610],al
    ; 10. XCHG mem then read
    mov word [0x10E8],0x4444
    mov ax,0x5555
    xchg ax,[0x10E8]
    mov dx,[0x10E8]
    mov [0x611],dx
    mov [0x613],al
    ; 11. INT then read of the pushed IP from the handler
    mov word [0x0080],h11
    mov word [0x0082],0
    int 0x20
    jmp short n11
h11: mov bp,sp
    mov ax,[bp]
    mov [0x614],ax
    iret
n11:
    ; 12. CMPSB after stores
    mov byte [0x10F0],0x01
    mov byte [0x10F1],0x01
    mov si,0x10F0
    mov di,0x10F1
    cmpsb
    mov al,0
    jnz s12
    mov al,1
s12: mov [0x616],al
    hlt
