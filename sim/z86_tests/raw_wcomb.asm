; raw_wcomb -- store combining vs the whole-line install (z86_cache WCOMB).
; Each turn fills a 16-byte line with REP STOSW (a whole combine bank),
; stores to another line (the bank swaps and the full one leaves), then
; stores into the full line again -- that store has to wait for the bank
; to leave and lands right around the edge the line is installed in the
; cache -- and reads both words back. A stale installed line returns the
; REP STOSW value instead of the later store.
;
; Results (tb dump "mem 0600"):
;   0600 w  failed reads (0 = good)
;   0602 w  turns run
;   0608 b  AC once the program reached the end
bits 16
org 0x400
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov word [0x600],0
    mov word [0x602],0
    cld
    mov si,0                  ; turn counter
turn:
    ; line X = 0x2000 + (turn & 0x7F) * 16, Y = X + 0x1000
    mov bx,si
    and bx,0x7F
    shl bx,4
    add bx,0x2000
    ; 1) fill line X with p1 = turn ^ 0x5A5A
    mov ax,si
    xor ax,0x5A5A
    mov di,bx
    mov cx,8
    rep stosw
    ; 2) a store into another line: the full bank swaps out
    mov [bx+0x1000],ax
    ; 3) the full line again, word 1 (= p2 = turn ^ 0xC3C3)
    mov dx,si
    xor dx,0xC3C3
    mov [bx+2],dx
    ; 4) read back: word 1 must be p2, word 2 must still be p1
    cmp [bx+2],dx
    je .k1
    inc word [0x600]
.k1:
    cmp [bx+4],ax
    je .k2
    inc word [0x600]
.k2:
    ; vary the gap before the next turn (0..7 nops' worth)
    mov cx,si
    and cx,7
    jcxz .k3
.d: loop .d
.k3:
    inc si
    inc word [0x602]
    cmp si,600
    jb turn
    mov byte [0x608],0xAC
    hlt
