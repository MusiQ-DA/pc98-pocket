; raw_hma -- real-mode access to the HMA (FFFF:0010-FFFF:FFFF) with the A20
; gate open, the way DOS=HIGH and an XMS driver use it (PM286 build): DS:
; and ES: stores and loads, LES of an HMA far pointer and a list walk
; through it (FreeDOS's kernel walks its lists with les bx,[...] /
; mov al,[es:bx+4]), code run from the HMA, and the gate closed again
; (the wrap back to 0000).
;
; Results at 0600h (scripts/sim_z86_tests.sh):
;   600 word at FFFF:0010 via DS            34 12
;   602 word at 0000:0000 (no alias)        CD AB
;   604 byte [es:bx+4] after LES -> HMA     5A
;   605 list walk: nodes visited            04
;   606 sum of the walk's tags              0A
;   607 code in the HMA ran (far call/retf) C3
;   608 word at FFFF:FFFE (top of the HMA)  EF BE
;   60A A20 closed: FFFF:0010 reads 0:0     CD AB
bits 16
cpu 286
org 0x400
    cli
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x0800
    cmp byte [0x05F0],0xA5
    jne first_run
    mov ax,0xFFFF               ; second run, after OUT 0F0h: A20 closed
    mov ds,ax
    mov ax,[0x0010]
    xor bx,bx
    mov ds,bx
    mov [0x060A],ax
    hlt
first_run:
    mov word [0x0000],0xABCD
    out 0xF2,al                 ; A20 open
    mov ax,0xFFFF
    mov ds,ax
    mov word [0x0010],0x1234
    mov word [0xFFFE],0xBEEF
    ; a list in the HMA: node = {far next (4), tag (1)}, at FFFF:0100,
    ; 0200, 0300, 0400; the last next = FFFF:FFFF
    mov bx,0x0100
    mov cl,1
.mk:
    lea ax,[bx+0x100]
    mov [bx],ax
    mov word [bx+2],0xFFFF
    mov [bx+4],cl
    inc cl
    add bx,0x100
    cmp bx,0x0500
    jne .mk
    mov word [0x0400],0xFFFF
    mov byte [0x0204],0x5A      ; node 2's tag rewritten: 1+5A+3+4 below
    ; code in the HMA: mov byte [0x607],0xC3 (via SS=0) ; retf
    mov si,hcode
    mov di,0x8000
    mov cx,hcode_end-hcode
.cp:
    mov al,[cs:si]
    mov [di],al
    inc si
    inc di
    loop .cp
    xor ax,ax
    mov ds,ax
    mov ax,[0x0000]
    mov [0x0602],ax
    mov es,ax
    ; DS:[0x10] of FFFF
    push ds
    mov ax,0xFFFF
    mov ds,ax
    mov ax,[0x0010]
    pop ds
    mov [0x0600],ax
    ; far pointer FFFF:0200 at 0000:0700, LES and [es:bx+4]
    mov word [0x0700],0x0200
    mov word [0x0702],0xFFFF
    les bx,[0x0700]
    mov al,[es:bx+4]
    mov [0x0604],al
    ; walk from FFFF:0100
    mov word [0x0700],0x0100
    les bx,[0x0700]
    xor dx,dx
.walk:
    inc dh
    add dl,[es:bx+4]
    les bx,[es:bx]
    cmp bx,0xFFFF
    jne .walk
    mov [0x0605],dh
    sub dl,0x5A-2               ; 1 + 5A + 3 + 4 = 62h -> 0A
    mov [0x0606],dl
    call 0xFFFF:0x8000
    mov ax,0xFFFF
    mov es,ax
    mov ax,[es:0xFFFE]
    mov [0x0608],ax
    ; close the gate the only way a 286 PC-98 has: OUT 0F0h (the bench's
    ; +f0reset resets the CPU); the second run reads the wrap
    mov byte [0x05F0],0xA5
    out 0xF0,al
    hlt

hcode:
    mov byte [ss:0x0607],0xC3
    retf
hcode_end:
