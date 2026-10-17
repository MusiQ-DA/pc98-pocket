; HLT waits for an interrupt and resumes after it (the standalone z86 never
; left HLT): five HLTs, each woken by one INTR, then CLI; HLT stops for good.
; [0x600] counts handler runs, [0x602] the instructions after each HLT.
bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x3000
    mov word [0x80],h
    mov word [0x82],0
    mov word [0x600],0
    mov word [0x602],0
    sti
    hlt
    inc word [0x602]
    hlt
    inc word [0x602]
    hlt
    inc word [0x602]
    hlt
    inc word [0x602]
    hlt
    inc word [0x602]
    cli
    hlt
h:  inc word [0x600]
    iret
