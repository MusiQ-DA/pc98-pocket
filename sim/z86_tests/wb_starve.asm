; wb_starve -- tb_mem_perf +cursor program: a few GRCG RMW writes leave a
; line dirty in pc98_gvram_seq's buffer with the next line's prefetch armed,
; then the CPU streams main RAM (rep movsw) for a long while. The prefetch
; waits for port A to go quiet before it may read; it must not hold the
; dirty line's write-back off all that time -- the display reads SDRAM, so
; a line left dirty is a stale stripe on screen (lodemnc's map scroll).
; tb_mem_perf +wbdmax=N fails the run when any plane stayed dirty longer.
;   nasm -f bin -o wb_starve.bin wb_starve.asm ; one hex byte per line
bits 16
org 0
    cli
    xor ax,ax
    mov ss,ax
    mov sp,0x0400
    mov al,0x01
    out 0x6A,al             ; analog: four planes
    mov al,0xC0
    out 0x7C,al             ; GRCG on, RMW, all planes
    mov al,0xFF
    out 0x7E,al
    mov al,0x00
    out 0x7E,al
    mov al,0xFF
    out 0x7E,al
    mov al,0x00
    out 0x7E,al
    mov ax,0xA800
    mov es,ax
    mov di,0x0100
    mov cx,4                ; four lines, a masked byte each: fills, a
.lines:                     ; flush of the older slot, the next line's
    mov byte [es:di],0x0F   ; prefetch armed behind the newest
    add di,0x10
    loop .lines
    mov byte [es:0x0131],0xF0 ; the newest line dirty again
    mov ax,0x2000
    mov ds,ax
    mov ax,0x3000
    mov es,ax
    xor si,si
    xor di,di
    mov cx,0x4000
    cld
    rep movsw               ; ~16K words of main-RAM traffic
    mov al,0x00
    out 0x7C,al
    mov al,0xFF
    mov dx,0x88FE
    out dx,al
    jmp $
