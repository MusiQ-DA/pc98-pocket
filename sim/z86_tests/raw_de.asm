; raw_de -- the 80286 divide-error and BOUND faults.
;
; On the 80286 #DE (DIV/IDIV overflow, AAM 0) and #BR (BOUND) are FAULTS:
; the pushed IP is the faulting instruction's own (its prefixes included),
; and the pushed FLAGS are the interrupted ones, IF included, so the
; handler's IRET restores them. z86 pushed the 8086's IP_AFTER, and pushed
; FLAGS after GETVEC had already cleared IF (and BOUND pushed no FLAGS at
; all). Falcom's Lord Monarch installs an INT 0 handler that checks the
; pushed FLAGS' bits 12-14 (clear on a 286) and then adds 2 to the pushed IP
; to skip the DIV -- with IP_AFTER that lands mid-instruction.
;
; Results at 0600h, three bytes per fault:
;   pushed IP - the instruction's address (00), pushed IF (01),
;   pushed FLAGS bits 12-15 (00 on a 286)
; then IF after the last IRET (01) and a canary (5A).
;   nasm -f bin -o raw_de.bin raw_de.asm ; one hex byte per line -> raw_de.hex
bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0x0800
    mov word [0*4],handler
    mov word [0*4+2],0
    mov word [5*4],handler
    mov word [5*4+2],0
    mov word [0x5F8],0          ; bounds: 0..0x10
    mov word [0x5FA],0x10
    mov si,0x600
    sti                         ; no interrupt source in the bench: IF is data here

    ; 1. DIV r/m8 by zero (2 bytes)
    mov word [0x5F0],f1
    mov word [0x5F2],2
    mov ax,0x1234
    mov cl,0
f1: div cl

    ; 2. ES: DIV r/m16 overflow (prefix + 2 bytes): the prefix's address
    mov word [0x5F0],f2
    mov word [0x5F2],3
    mov dx,0x0010
    xor ax,ax
    mov cx,1
f2: es div cx

    ; 3. IDIV r/m8 overflow (-128*... : AX=8000h / -1 -> out of range)
    mov word [0x5F0],f3
    mov word [0x5F2],2
    mov ax,0x8000
    mov bl,0xFF
f3: idiv bl

    ; 4. AAM 0 (2 bytes)
    mov word [0x5F0],f4
    mov word [0x5F2],2
f4: aam 0

    ; 5. BOUND out of range (4 bytes), vector 5
    mov word [0x5F0],f5
    mov word [0x5F2],4
    mov bx,0x50
f5: bound bx,[0x5F8]

    pushf
    pop ax
    shr ax,9
    and al,1
    mov [si],al
    mov byte [si+1],0x5A
    cli
    hlt

handler:
    push bp
    mov bp,sp
    push ax
    mov ax,[bp+2]               ; pushed IP
    sub ax,[0x5F0]
    mov [si],al
    mov ax,[bp+6]               ; pushed FLAGS
    shr ax,9
    and al,1
    mov [si+1],al
    mov al,[bp+7]
    and al,0xF0
    mov [si+2],al
    add si,3
    mov ax,[0x5F0]              ; resume after the faulting instruction
    add ax,[0x5F2]
    mov [bp+2],ax
    pop ax
    pop bp
    iret
