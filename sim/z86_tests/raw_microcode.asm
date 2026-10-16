bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0x0800
    ; 1 CWD -> DX
    xor dx,dx
    mov ax,0x8000
    cwd
    mov [0x600],dx          ; FFFF
    ; 2 MUL -> DX
    xor dx,dx
    mov ax,0x1234
    mov bx,0x0100
    mul bx
    mov [0x602],dx          ; 0012
    ; 3 DIV -> DX (remainder)
    xor dx,dx
    mov ax,1003
    mov bx,10
    div bx
    mov [0x604],dx          ; 0003
    ; 4 LES -> ES used at once
    mov word [0x10E4],0x0000
    mov word [0x10E6],0x0010   ; ES=0010 -> ES:0 = 00100
    mov byte [0x100],0x4F
    les di,[0x10E4]
    mov al,[es:di]
    mov [0x606],al          ; 4F
    xor ax,ax
    mov es,ax
    ; 5 LDS -> DS used at once
    mov word [0x10E8],0x0000
    mov word [0x10EA],0x0020
    mov byte [0x200],0x5E
    lds si,[0x10E8]
    mov al,[0]
    xor bx,bx
    mov ds,bx
    mov [0x607],al          ; 5E
    ; 6 POPA -> regs used at once
    mov ax,0x1111
    mov cx,0x2222
    pusha
    xor ax,ax
    xor cx,cx
    popa
    mov [0x608],cx          ; 2222
    ; 7 LEAVE -> BP
    mov word [0x07F0],0x1234
    mov bp,0x07F0
    leave
    mov [0x60A],bp          ; 1234
    mov sp,0x0800
    ; 8 ENTER -> BP
    mov bp,0x5555
    enter 4,0
    mov [0x60C],bp          ; 07FE
    mov [0x60E],sp          ; 07FA
    mov sp,0x0800
    ; 9 IDIV -> DX
    mov ax,-7
    cwd
    mov bx,2
    idiv bx
    mov [0x610],dx          ; FFFF
    ; 10 IMUL r16 -> DX
    mov ax,-2
    mov bx,3
    imul bx
    mov [0x612],dx          ; FFFF
    ; 11 LODSW -> AX
    mov word [0x10F0],0x7A7B
    mov si,0x10F0
    xor ax,ax
    lodsw
    mov [0x614],ax          ; 7A7B
    ; 12 IMUL r,rm,imm
    mov cx,7
    imul dx,cx,3
    mov [0x616],dx          ; 0015
    ; 13 XCHG reg,reg
    mov ax,0x0102
    mov bx,0x0304
    xchg ax,bx
    mov [0x618],ax          ; 0304
    mov [0x61A],bx          ; 0102
    ; 14 MUL byte -> AH
    mov al,0x10
    mov bl,0x20
    mul bl
    mov [0x61C],ah          ; 02
    ; 15 POPF -> flags then Jcc
    mov ax,0x0001
    push ax
    popf
    mov al,0
    jnc s15
    mov al,1
s15: mov [0x61D],al         ; 01
    hlt
