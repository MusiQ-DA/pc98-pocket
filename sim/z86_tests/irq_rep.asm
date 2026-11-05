; Interruptible REP: long string ops under a periodic INTR (tb +irq=<clocks>).
; The 80286 takes an interrupt between REP iterations with CX/SI/DI updated
; and the return address on the instruction's first prefix; IRET resumes it.
; z86 used to sample INTR only between instructions, so a 16000-word
; `rep stosw` held IRQ0 off for ~50 ms on hardware.
;
; Every REP below must leave exactly the results of an uninterrupted run;
; the handler counts its runs, how many landed on a REP's first prefix
; (taken mid-REP), and how many returned anywhere else inside a REP
; instruction's bytes (a resume that lost a prefix).
;
; Results (tb dump "mem 0600"):
;   0600 w  handler runs
;   0602 w  runs that returned to a REP's first prefix (taken mid-REP)
;   0604 w  runs that returned inside a REP's bytes past its first prefix
;   0606 w  failed-check bitmask, tests 1-16 (0 = all good)
;   0608 b  AC once the program reached the end
;   061E b  last byte `rep outsb` wrote to port 061Eh (expect 5D)
bits 16
org 0x1000          ; clear of the 0600 result block (tb +org=1000)

RUNS  equ 0x600
HITS  equ 0x602
BADIP equ 0x604
FAIL  equ 0x606
DONE  equ 0x608
RS    equ 0x6E0         ; current REP's first byte, 0 outside one
RE    equ 0x6E2         ; and the byte after it
PORTW equ 0x6E8         ; IN reads tb memory at the port address
PORTB equ 0x61E

N16   equ 16000         ; bytes / words in the long runs

; REPI <insn>: run one REP-prefixed instruction with its bounds published
%macro REPI 1+
    mov word [cs:RS],%%s
    mov word [cs:RE],%%e
%%s: %1
%%e:
    pushf
    mov word [cs:RS],0
    mov word [cs:RE],0
    popf
%endmacro

; EXPECT a, b, bit: FAIL |= bit unless a == b (flags clobbered)
%macro EXPECT 3
    cmp %1,%2
    je %%ok
    or word [cs:FAIL],%3
%%ok:
%endmacro

    cli
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,0x3000
    mov word [0x80],h
    mov word [0x82],0
    mov di,RUNS
    mov cx,8
.clr: mov word [di],0
    add di,2
    loop .clr
    mov word [RS],0
    mov word [RE],0
    mov word [PORTW],0xBEEF
    cld

    ; source pattern: 2000:2i = i ^ 5A3C, i < 8000 (plain loop, no REP)
    mov ax,0x2000
    mov es,ax
    xor si,si
.pat: mov ax,si
    xor ax,0x5A3C
    mov bx,si
    shl bx,1
    mov [es:bx],ax
    inc si
    cmp si,N16/2
    jb .pat
    mov ax,0x1000
    mov es,ax
    mov word [es:N16*2],0x1111      ; sentinel past the stosw run
    sti

    ; ---- 1: rep stosw, 16000 words at 1000:0000 ----------------------
    mov ax,0x1000
    mov es,ax
    xor di,di
    mov cx,N16
    mov ax,0xA55A
    REPI rep stosw
    EXPECT cx,0,0x0001
    EXPECT di,N16*2,0x0001
    xor bx,bx
.c1: cmp word [es:bx],0xA55A
    jne .f1
    add bx,2
    cmp bx,N16*2
    jb .c1
    cmp word [es:bx],0x1111
    je .k1
.f1: or word [cs:FAIL],0x0002
.k1:

    ; ---- 2: es rep movsw (source override), DS wrong on purpose ------
    mov ax,0x2000
    mov es,ax
    mov ax,0x5000
    mov ds,ax
    xor si,si
    mov di,0x8000
    mov cx,N16/2
    REPI es rep movsw
    xor ax,ax
    mov ds,ax
    EXPECT cx,0,0x0004
    EXPECT si,N16,0x0004
    EXPECT di,0x8000+N16,0x0004
    call cmp_es_8000                ; ES:0 vs ES:8000, N16 bytes
    jz .k2
    or word [cs:FAIL],0x0008
.k2:

    ; ---- 3: rep es movsb (REP first, then the override) --------------
    mov ax,0x5000
    mov ds,ax
    xor si,si
    mov di,0xC000
    mov cx,N16
    REPI rep es movsb
    xor ax,ax
    mov ds,ax
    EXPECT cx,0,0x0010
    EXPECT di,0xC000+N16,0x0010
    xor bx,bx
.c3: mov al,[es:bx]
    cmp al,[es:bx+0xC000]
    jne .f3
    inc bx
    cmp bx,N16
    jb .c3
    jmp .k3
.f3: or word [cs:FAIL],0x0020
.k3:

    ; ---- 4: es repe cmpsb, equal all the way --------------------------
    mov ax,0x5000
    mov ds,ax
    xor si,si
    mov di,0x8000
    mov cx,N16
    REPI es repe cmpsb
    pushf
    pop bx
    xor ax,ax
    mov ds,ax
    EXPECT cx,0,0x0040
    EXPECT si,N16,0x0040
    and bx,0x40
    EXPECT bx,0x40,0x0040            ; ZF=1

    ; ---- 5: es repe cmpsb, first difference at byte 12345 ------------
    xor byte [es:0x8000+12345],0x80
    mov ax,0x5000
    mov ds,ax
    xor si,si
    mov di,0x8000
    mov cx,N16
    REPI es repe cmpsb
    pushf
    pop bx
    xor ax,ax
    mov ds,ax
    EXPECT cx,N16-12346,0x0080
    EXPECT si,12346,0x0080
    EXPECT di,0x8000+12346,0x0080
    and bx,0x40
    EXPECT bx,0,0x0080               ; ZF=0
    xor byte [es:0x8000+12345],0x80

    ; ---- 6: repne scasw, no match over 8000 words ----------------------
    mov di,0x8000
    mov cx,N16/2
    mov ax,0xFFFF
    REPI repne scasw
    pushf
    pop bx
    EXPECT cx,0,0x0100
    EXPECT di,0x8000+N16,0x0100
    and bx,0x40
    EXPECT bx,0,0x0100

    ; ---- 7: cs rep lodsw with DS wrong ---------------------------------
    ; (source through CS = 0000: 0000:60C0-7FFF, last word 6B6B)
    xor ax,ax
    mov ds,ax
    mov si,0x8000-N16/2             ; 4000 words ending below 8000h
    mov cx,N16/4
    mov word [0x7FFE],0x6B6B        ; the last word lodsw reads
    mov ax,0x5000
    mov ds,ax
    REPI cs rep lodsw
    mov bx,ax
    xor ax,ax
    mov ds,ax
    EXPECT cx,0,0x0200
    EXPECT si,0x8000,0x0200
    EXPECT bx,0x6B6B,0x0200

    ; ---- 8: rep insw from port 06E8h into 3000:0000 --------------------
    mov ax,0x3000
    mov es,ax
    xor di,di
    mov dx,PORTW
    mov cx,4000
    REPI rep insw
    EXPECT cx,0,0x0400
    EXPECT di,8000,0x0400
    xor bx,bx
.c8: cmp word [es:bx],0xBEEF
    jne .f8
    add bx,2
    cmp bx,8000
    jb .c8
    jmp .k8
.f8: or word [cs:FAIL],0x0800
.k8:

    ; ---- 9: es rep outsb, 4000 bytes of 2000:0000 to port 061Eh -------
    ; (the last byte, 2000:0F9F = high byte of word 1999 ^ 5A3C = 5D,
    ;  is checked from the tb dump: an I/O write is not snooped)
    mov ax,0x2000
    mov es,ax
    mov ax,0x5000
    mov ds,ax
    xor si,si
    mov dx,PORTB
    mov cx,4000
    REPI es rep outsb
    xor ax,ax
    mov ds,ax
    EXPECT cx,0,0x1000
    EXPECT si,4000,0x1000

    ; ---- 10: std rep stosb, 20000 bytes down from 3000:FFFF ------------
    mov ax,0x3000
    mov es,ax
    mov di,0xFFFF
    mov cx,20000
    mov al,0x77
    std
    REPI rep stosb
    cld
    EXPECT cx,0,0x2000
    EXPECT di,0xFFFF-20000,0x2000
    mov bx,0xFFFF-20000+1
.c10: cmp byte [es:bx],0x77
    jne .f10
    inc bx
    jnz .c10
    jmp .k10
.f10: or word [cs:FAIL],0x4000
.k10:

    ; ---- 11: rep movsw with CX=0 does nothing --------------------------
    mov si,0x1234
    mov di,0x5678
    xor cx,cx
    REPI rep movsw
    EXPECT si,0x1234,0x8000
    EXPECT di,0x5678,0x8000

    mov byte [cs:DONE],0xAC
    cli
    times 8 nop
    hlt

; ZF=1 when ES:0 .. ES:N16-1 equals ES:8000 .. (plain loop)
cmp_es_8000:
    xor bx,bx
.l: mov ax,[es:bx]
    cmp ax,[es:bx+0x8000]
    jne .r
    add bx,2
    cmp bx,N16
    jb .l
    xor ax,ax                       ; ZF=1
.r: ret

h:  push bp
    mov bp,sp
    push ax
    inc word [cs:RUNS]
    mov ax,[bp+2]                   ; return IP
    cmp ax,[cs:RS]
    jne .n
    inc word [cs:HITS]
    jmp .x
.n: cmp ax,[cs:RS]
    jbe .x
    cmp ax,[cs:RE]
    jae .x
    inc word [cs:BADIP]
.x: pop ax
    pop bp
    iret
