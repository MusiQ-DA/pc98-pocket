; An OUT that withdraws INTR (port 71h under tb +irqclr, like a PIT
; channel-0 write clearing the PC-98 master's IRR0) must not be followed by
; an acknowledge: the 8259 would answer with IRQ7's vector, and the BIOS's
; INT 0Fh spurious path EOIs whatever else is in service.
bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x3000
    mov word [0x80],h
    mov word [0x82],0
    mov word [0x600],0
    sti
    mov cx,3000
l:  out 0x71,al
    inc word [0x602]
    out 0x71,al
    mov bx,[0x602]
    add bx,cx
    out 0x71,al
    loop l
    cli
    hlt
h:  inc word [0x600]
    iret
