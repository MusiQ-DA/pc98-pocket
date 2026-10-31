bits 16
cpu 286
org 0x400
; SuperDepth's OPN board probe (DEPTH.EXE module E384) against a bus where
; nothing answers port 188h/18Ah (tb +ioff: every I/O read is 0xFF). Each
; IN must leave 0xFF in AL; an echo of the OUT data means the IN's result
; never reached AL. Run under +irq so the handler (EOI, the PC-98 shape:
; push ax / mov al,20h / out 0,al / pop ax) lands right after the STI.
; Results at 0600: rounds done (word), bad INs (word), last bad AL.
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x3000
    mov word [0x80],h
    mov word [0x82],0
    mov word [0x600],0
    mov word [0x602],0
    mov byte [0x604],0
    mov cx,400
.rep:
    cli
    mov al,0
    mov dx,0x188
    out dx,al
    mov al,0x7B
    mov dx,0x18A
    out dx,al
    nop
    nop
    nop
    nop
    mov dx,0x18A
    in al,dx
    sti
    cmp al,0x7B
    jnz .a1
    inc word [0x602]
    mov [0x604],al
.a1:
    cmp al,0xFF
    jz .a2
    inc word [0x602]
    mov [0x604],al
.a2:
    cli
    mov al,0
    mov dx,0x188
    out dx,al
    mov al,0x0C
    mov dx,0x18A
    out dx,al
    nop
    nop
    nop
    nop
    mov dx,0x18A
    in al,dx
    sti
    cmp al,0xFF
    jz .a3
    inc word [0x602]
    mov [0x604],al
.a3:
    inc word [0x600]
    loop .rep
    cli
    hlt
h:  push ax
    mov al,0x20
    out 0x00,al
    pop ax
    iret
