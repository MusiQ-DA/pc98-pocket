; rep-string-op under interrupt stress.
; Hammer rep movsb / rep stosb / repe cmpsb in a loop while the PIC fires
; interrupts. Verify: (a) the copy lands correctly, (b) a stack canary is not
; clobbered, (c) SS stays == CS. A rep+IRQ resume bug would corrupt
; memory/stack -> the mechanism that puts a data segment into CS.
bits 16
org 0

MBX   equ 0x5000          ; mailbox segment (phys 0x50000)
; tb layout: [2]=iters(word) [4]=status(byte AC/EE) [8]=opfail(byte)
;            [0x0a]=badcs(word)
SRCLEN equ 32

start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    ; fill source pattern in-CS
    mov cx, SRCLEN
    xor si, si
.fill:
    mov al, cl
    xor al, 0x5a
    mov [si+srcpat], al
    inc si
    loop .fill

    ; stack in-CS
    mov ax, cs
    mov ss, ax
    mov sp, 0x2000

    ; fill whole IVT with irq_handler in our seg (vector 0x40 is injected)
    xor ax, ax
    mov ds, ax
    mov cx, 256
    xor si, si
.ivt:
    mov word [si],   irq_handler
    mov ax, cs
    mov [si+2], ax
    add si, 4
    loop .ivt
    mov ax, cs
    mov ds, ax

    ; --- master PIC: ICW + unmask IRQ0, so the timer actually interrupts ---
    ; ports: ICW1->0x00, ICW2/3/4 + OCW1->0x02. vector base 0x08 (IRQ0=INT 08),
    ; slave on IRQ7 (PC-98 cascade), 8086 mode.
    mov al, 0x11
    out 0x00, al
    mov al, 0x08
    out 0x02, al
    mov al, 0x80
    out 0x02, al
    mov al, 0x01
    out 0x02, al
    mov al, 0xFE          ; unmask IRQ0 only (vsync IRQ2 stays masked)
    out 0x02, al
    ; --- PIT counter0: mode 3 square wave, reload 0x4000 (~1.6 kHz tick) ---
    mov al, 0x36
    out 0x77, al
    mov al, 0x00
    out 0x71, al
    mov al, 0x40
    out 0x71, al

    sti

    xor bp, bp            ; iteration counter (rep ops clobber di)

mainloop:
    ; rep movsb: srcpat -> es:0x4800:dstbuf
    mov ax, cs
    mov ds, ax
    mov si, srcpat
    mov ax, 0x4800
    mov es, ax
    mov di, dstbuf_off
    mov cx, SRCLEN
    cld
    rep movsb
    ; rep stosb -> dstbuf2
    mov ax, 0x4800
    mov es, ax
    mov di, dstbuf2_off
    mov al, 0x77
    mov cx, SRCLEN
    rep stosb
    ; verify: repe cmpsb src vs dst
    mov ax, cs
    mov ds, ax
    mov si, srcpat
    mov ax, 0x4800
    mov es, ax
    mov di, dstbuf_off
    mov cx, SRCLEN
    repe cmpsb
    jnz .cmpfail
    ; stack integrity: interrupts push+pop must be balanced -> SP==0x2000
    mov ax, sp
    cmp ax, 0x2000
    jne .spbad
    ; SS must equal CS (iret/retf must not have loaded a data segment)
    mov ax, ss
    mov bx, cs
    cmp ax, bx
    jne .ssbad
    inc bp
    mov ax, 0x5000
    mov es, ax
    mov [es:2], bp
    cmp bp, 1200
    jge .alldone
    jmp mainloop

.cmpfail:
    mov ax, 0x5000
    mov es, ax
    mov byte [es:8], 0x01
    jmp .report
.spbad:
    mov ax, 0x5000
    mov es, ax
    mov byte [es:8], 0x02
    mov [es:0x0a], sp
    jmp .report
.ssbad:
    mov ax, 0x5000
    mov es, ax
    mov byte [es:8], 0x03
.report:
    mov ax, 0x5000
    mov es, ax
    mov ax, cs
    mov [es:0x0a], ax
    mov byte [es:4], 0xee
    hlt

.alldone:
    mov ax, 0x5000
    mov es, ax
    mov [es:2], bp
    mov ax, cs
    mov [es:0x0a], ax
    mov byte [es:4], 0xac
    hlt

irq_handler:
    mov al, 0x20          ; OCW2: non-specific EOI to the master PIC (port 0x00)
    out 0x00, al
    iret

srcpat:   times SRCLEN db 0
dstbuf_off  equ 0x0000
dstbuf2_off equ 0x0100

    times 0x1fe-($-$$) db 0
    db 0x55, 0xaa
