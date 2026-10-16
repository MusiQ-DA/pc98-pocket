bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x0800
    ; table at 0x4B0: entry 9 = 0x5A; IVT byte 9 = 0x08 (stale-BX answer)
    mov byte [0x09],0x08
    mov byte [0x4B9],0x5A
    ; 1. BX written right before XLAT (the BIOS INT 1Bh entry shape)
    xor bx,bx
    mov ax,0x2790
    shr al,4
    mov bx,0x04B0
    xlat
    mov [0x600],al
    ; 2. table byte stored right before XLAT
    mov bx,0x04B0
    mov al,9
    mov byte [0x4B9],0x77
    xlat
    mov [0x601],al
    ; 3. MOV AL,moffs right after a store to the same byte
    mov byte [0x4C0],0x33
    mov al,[0x4C0]
    mov [0x602],al
    ; 4. store via A2, then load via modrm
    mov al,0x44
    mov [0x4C1],al
    mov ah,[0x4C1]
    mov [0x603],ah
    ; 5. push then BP-relative read of the pushed word
    mov bp,sp
    mov ax,0x6655
    push ax
    mov dx,[bp-2]
    mov [0x604],dx
    ; 6. STOSB then immediate load of the same byte
    mov ax,ds
    mov es,ax
    mov di,0x4C2
    mov al,0x77
    stosb
    mov cl,[0x4C2]
    mov [0x606],cl
    hlt
