# NEC PC-98 ITF ROM — static analysis

Image: `~/.pc98roms/itf.rom`, 32768 bytes, mapped at guest physical `F8000`–`FFFFF`.
File offset *N* is address `F8000+N`; execution starts at `F800:0000`
(the reset vector at `FFFF0` is `EA 00 00 00 F8`).

Addresses below are written **`F8oooo`** where `oooo` is the 16-bit offset inside
the segment `F800` — i.e. `F8343A` means `F800:343A`, linear `FB43A`. Branch
targets inside the listings are printed as bare 16-bit offsets, so `JZ 012Bh`
means "jump to `F8012B`".

The ROM identifies itself at `F81CE3`:

    Initial Test Firmware       (C) NEC 1988

and can print `Processor is 80386` / `Processor is 70116 (V30)` and
`CPU Clock is 20MHz / 16MHz / 8MHz`, so this is a 386-generation PC-9801
(RA class) ITF.

## 0. How this was produced, and its limits

There is no disassembler on this machine, so one was written for the job:
`scratch/dis8086.py` (a table-driven 8086 decoder) plus `scratch/trace2.py`,
a recursive-descent walker with just enough constant propagation to resolve
this ROM's `MOV BP,imm ; JMP sub` / `JMP BP` calling convention and to expand
the port-table walker. Verification against the two stretches given by hand:

    F80000  FA             CLI
    F80001  B4D5           MOV AH,0D5h
    F80003  9E             SAHF
    F80004  79FE           JNS  0004h        (JNS $-2)
    ...
    F800D0  BEE500         MOV SI,00E5h
    F800D3  FC             CLD
    F800D4  32ED           XOR CH,CH
    F800D6  2EAD           CS:LODSW

Both match. The walker reaches 5106 bytes from the reset vector and 2468 more
from the shadow-ROM continuation at `F80B70`; everything else in the image is
data (GDC parameter blocks, the palette table, the message strings, a 4992-byte
floppy format table) or the protected-mode fragments noted below.

**Two honest caveats.**

1. The brief said "8086/8088 code only". That is not true of this image. The
   ITF uses 386 instructions in several places — `66`-prefixed `REP STOSD` /
   `REP SCASD` / `SHL EAX,16` in the memory tests (`F807EC`, `F81897`,
   `F818BE`), `PUSH imm16` (`F817ED`), `SHL AL,imm8` (`F817BC`), and
   `LGDT`/`LIDT`/`SGDT`/`SIDT`/`SMSW`/`LMSW` in the protected-mode block at
   `F80EC6`–`F80F5B`. The disassembler was extended to cover them. Anything
   decoded as an 8086-only opcode where a 186+/386 opcode exists (`C0`/`C1`,
   `C8`/`C9`, `6x`) is decoded with the 386 meaning.

2. Three transfers are **not resolved**:
   * `F80F5E  EA 64 10 38 00   JMP FAR 38h:1064h` — entry to the protected-mode
     extended-memory test. Selector `38h` is built at `F80F11`–`F80F30` from the
     descriptor template at `F80FE3`; the code at offset `1064h` inside that
     segment was not followed. It returns to real mode by resetting the CPU
     (`OUT 0F0h`) and coming back through `0000:0404`, landing at `F8126C`.
   * `F8130E  EA 9D 15 38 00   JMP FAR 38h:159Dh` — the same, second entry,
     returning to `F81716`.
   * `F81892  EA F8 04 00 00   JMP FAR 0000:04F8` — this one *is* resolved,
     because the ITF writes the six bytes at `0000:04F8` itself three
     instructions earlier; see §4.

   Everything else, including every `JMP BP` / `JMP SP` / `JMP SI` return, is
   resolved and named.

One cosmetic wrinkle: the listings below are linear over each range, and the
ROM has a few one-byte alignment fillers that the control-flow walker skips
(`F801E1`, `F80241`, `F8025B`, `F80285`, `F80321`, `F80683`, `F806E4`,
`F8087E`, `F80905`, `F80917`, `F80BBA`, `F80BC8`, `F80BCE`, `F80BE6`,
`F80BEC`, `F80C08`, `F80C0E`, `F8177F`, `F81AC5`, `F81B15`, `F81F1A`). All of
those are `90h` and decode as `NOP`, so they are harmless. The single
exception is `F806D4`, which holds `74h`; decoded linearly it swallows the
`3E` segment prefix of the real instruction at `F806D5` and shows as
`JZ 0714h`. The listing resynchronises at `F806D8`.

## 1. Annotated disassembly of the initialisation path

### 1.1 `F80000`–`F8004E` — CPU flag and register self-test

No I/O at all. Every conditional jump here is `J** $-2`: if the CPU does not
produce exactly the expected flag, the ROM spins on that instruction forever.
Then a walking-pattern test through `DS/SS/ES/SP/BP/SI/DI` with the four
patterns `FFFF`, `AAAA`, `5555`, `0000`.

```
F80000  FA             CLI                         ; interrupts off for the whole ITF
F80001  B4D5           MOV AH,0D5h                 ; D5h = SF,ZF,AF,PF,CF all set
F80003  9E             SAHF                        ; load AH into FLAGS
F80004  79FE           JNS  4h                     ; each J** $-2 is a self-test trap: wrong flag => hang here forever
F80006  75FE           JNZ  6h
F80008  7BFE           JPO  8h
F8000A  73FE           JNC  0Ah
F8000C  F8             CLC                         ; CF=0
F8000D  3F             AAS                         ; AF is still 1, so AAS must SET CF
F8000E  73FE           JNC  0Eh
F80010  B001           MOV AL,01h
F80012  B402           MOV AH,02h
F80014  F6E4           MUL AH                      ; 1*2 => no overflow
F80016  70FE           JO   16h
F80018  33C0           XOR AX,AX                   ; AH=0 -> SAHF clears SF,ZF,AF,PF,CF
F8001A  9E             SAHF
F8001B  78FE           JS   1Bh
F8001D  74FE           JZ   1Dh
F8001F  7AFE           JPE  1Fh
F80021  72FE           JC   21h
F80023  F9             STC                         ; CF=1
F80024  3F             AAS                         ; AF is now 0, so AAS must CLEAR CF
F80025  72FE           JC   25h
F80027  B07F           MOV AL,7Fh
F80029  B420           MOV AH,20h
F8002B  F6E4           MUL AH                      ; 7Fh*20h=0FE0h => OF set
F8002D  71FE           JNO  2Dh
F8002F  B8FFFF         MOV AX,0FFFFh               ; register/segment-register walking-bit test starts here
F80032  8ED8           MOV DS,AX
F80034  8CDB           MOV BX,DS
F80036  8ED3           MOV SS,BX
F80038  8CD1           MOV CX,SS
F8003A  8EC1           MOV ES,CX
F8003C  8CC2           MOV DX,ES
F8003E  8BE2           MOV SP,DX
F80040  8BEC           MOV BP,SP
F80042  8BF5           MOV SI,BP
F80044  8BFE           MOV DI,SI
F80046  3BF8           CMP DI,AX                   ; DI must equal AX after the chain of moves
F80048  75FE           JNZ  48h
F8004A  2D5555         SUB AX,5555h                ; next pattern: FFFF, AAAA, 5555, 0000
F8004D  73E3           JNC  32h                    ; CF=0 while patterns remain
```

### 1.2 `F8004F`–`F80089` — port `0439h` probe, PPI and keyboard-USART reset

`0439h` is the system-control register. It is read twice (the first read is a
dummy). **If it reads zero** the ROM assumes a genuine cold start and resets the
8255 system port and the keyboard 8251; if not, it skips straight to `F8007F`.
Either way it finishes by writing `(old & 02h) | 34h` back to `0439h`.

```
F8004F  BA3904         MOV DX,439h                 ; --- 0439h: system control register ---
F80052  EC             IN AL,DX                    ; dummy read then real read
F80053  EC             IN AL,DX
F80054  0AC0           OR AL,AL                    ; 0439h == 0 -> cold start, do the full PPI/PIT reset
F80056  7527           JNZ  7Fh                    ; 0439h != 0 -> skip to 007F
F80058  B092           MOV AL,92h                  ; 8255 #1 control: mode set 92h (A=in, B=in, C=out)
F8005A  E637           OUT 37h,AL
F8005C  EB00           JMP SHORT 5Eh
F8005E  EB00           JMP SHORT 60h
F80060  B0FF           MOV AL,0FFh
F80062  E635           OUT 35h,AL                  ; PPI port C := FFh (all output bits high, incl. SHUT0/SHUT1)
F80064  B80003         MOV AX,300h
F80067  E643           OUT 43h,AL                  ; keyboard 8251 command register: 3x 00h = force async idle
F80069  B90A00         MOV CX,0Ah
F8006C  E2FE           LOOP 6Ch
F8006E  FECC           DEC AH
F80070  75F5           JNZ  67h
F80072  B040           MOV AL,40h
F80074  E643           OUT 43h,AL                  ; 8251 internal reset
F80076  B90A00         MOV CX,0Ah
F80079  E2FE           LOOP 79h
F8007B  B05E           MOV AL,5Eh
F8007D  E643           OUT 43h,AL                  ; 8251 mode byte 5Eh (async, 8N1, x16)
F8007F  EC             IN AL,DX                    ; re-read 0439h
F80080  2402           AND AL,02h                  ; keep bit1
F80082  0C34           OR AL,34h                   ; set bits 2,4,5
F80084  EE             OUT DX,AL                   ; 0439h := (old & 02h) | 34h
```

### 1.3 `F80085`–`F800BB` — restart-mode dispatch on PPI port C

This is the PC-98 "shutdown flag" dispatch, and it is the first place a
re-implementation can lose the machine.

* `IN AL,35h` reads 8255 #1 port C (the SHUT0/SHUT1 latch that `F80062` set
  to `FFh` on a cold start).
* **bit 7 == 0** → the ITF assumes it was re-entered by a deliberate CPU reset
  and returns to the caller through `SS:SP` loaded from `0000:0406`/`0000:0404`
  followed by `RETF`. The ITF itself uses this twice (`F80F54` and `F817EA`).
* **bit 7 == 1 and bit 5 == 0** → prints `SYSTEM SHUTDOWN` and hangs at `F800BA`.
* **bit 7 == 1 and bit 5 == 1** → normal cold start at `F800BC`.

```
F80085  B800A0         MOV AX,0A000h
F80088  8EC0           MOV ES,AX
F8008A  E435           IN AL,35h                   ; --- restart-mode dispatch: PPI port C ---
F8008C  A880           TEST AL,80h                 ; bit7 (SHUT0). 0 => "return from reset" path
F8008E  7509           JNZ  99h
F80090  8E160604       MOV SS,[0406h]              ; restore SS:SP from 0000:0404/0406 and RETF -- the PC-98 shutdown-return
F80094  8B260404       MOV SP,[0404h]
F80098  CB             RETF
F80099  A820           TEST AL,20h                 ; bit5. 1 => normal cold start at 00BC
F8009B  751F           JNZ  0BCh
F8009D  BDA300         MOV BP,0A3h                 ; bit5 == 0 => SYSTEM SHUTDOWN message path
F800A0  E99900         JMP 13Ch                    ; display init, returns to 00A3 via JMP BP
F800A3  BCA900         MOV SP,0A9h                 ; wait for text-GDC FIFO, returns to 00A9 via JMP SP
F800A6  E92E04         JMP 4D7h
F800A9  B00D           MOV AL,0Dh
F800AB  E662           OUT 62h,AL                  ; GDC command 0Dh = BCTRL, display ON (text GDC)
F800AD  B00F           MOV AL,0Fh
F800AF  E668           OUT 68h,AL                  ; MODE FF1: reg7 := 1
F800B1  BE341B         MOV SI,1B34h                ; message "SYSTEM SHUTDOWN"
F800B4  BDBA00         MOV BP,0BAh
F800B7  E9111D         JMP 1DCBh
F800BA  EBFE           JMP SHORT 0BAh              ; hang
```

### 1.4 `F800BC`–`F800E4` — PIT channel 1 park, and the port-table walker

```
F800BC  B070           MOV AL,70h                  ; --- normal cold start ---
F800BE  E677           OUT 77h,AL                  ; 8253 control: 70h = counter1, LSB+MSB, mode 0, binary
F800C0  EB00           JMP SHORT 0C2h
F800C2  EB00           JMP SHORT 0C4h
F800C4  B000           MOV AL,00h
F800C6  E673           OUT 73h,AL                  ; counter1 low := 00
F800C8  EB00           JMP SHORT 0CAh
F800CA  EB00           JMP SHORT 0CCh
F800CC  B000           MOV AL,00h
F800CE  E673           OUT 73h,AL                  ; counter1 high := 00 (count 65536, mode 0 = one-shot, never reloads)
F800D0  BEE500         MOV SI,0E5h                 ; --- port-initialisation table walker ---
F800D3  FC             CLD
F800D4  32ED           XOR CH,CH
F800D6  2EAD           CS:LODSW                    ; first word: AL->CL = entry count, AH->DH = high byte of every port
F800D8  8AC8           MOV CL,AL
F800DA  8AF4           MOV DH,AH
F800DC  2EAD           CS:LODSW                    ; each entry: AL = data byte, AH -> DL = low byte of port
F800DE  8AD4           MOV DL,AH
F800E0  EE             OUT DX,AL                   ; DX = DH:DL = the 16-bit port
F800E1  E2F9           LOOP 0DCh
F800E3  FFE6           JMP SI                      ; SI now points past the table -> continue at 0101h
```

The walker at `F800D3`: `SI` points at a table; the first word gives the entry
count in its low byte and the *high* byte of every port in its high byte; each
following word gives the data in its low byte and the *low* byte of the port in
its high byte. When `CX` runs out, `JMP SI` continues execution at the first
byte past the table. It is used three times in this ROM (tables at `00E5`,
`03EE`, `05E6`).

**Table at `F800E5`, decoded:**

```
first word at F800E5 = 000D -> count 13, port high byte 00, table body F800E7..F80100, walker resumes at F80101

    F800E7:  OUT 0011, 44
    F800E9:  OUT 0037, 92
    F800EB:  OUT 0037, 07
    F800ED:  OUT 0050, 00
    F800EF:  OUT 0037, 0D
    F800F1:  OUT 0046, 82
    F800F3:  OUT 0046, 0F
    F800F5:  OUT 0037, 0C
    F800F7:  OUT 0037, 0F
    F800F9:  OUT 0037, 0A
    F800FB:  OUT 006A, 07
    F800FD:  OUT 006A, 04
    F800FF:  OUT 006A, 06
```

### 1.5 `F80101`–`F8013B` — board control, hardware-configuration gate

```
F80101  BADF7F         MOV DX,7FDFh                ; 7FDFh := 93h (386 board control)
F80104  B093           MOV AL,93h
F80106  EE             OUT DX,AL
F80107  EB00           JMP SHORT 109h
F80109  EB00           JMP SHORT 10Bh
F8010B  BA6704         MOV DX,467h                 ; 0467h := 00h
F8010E  B000           MOV AL,00h
F80110  EE             OUT DX,AL
F80111  BA6104         MOV DX,461h                 ; 0461h := 08h (shadow/window control: ROM through, RAM write-protected)
F80114  B008           MOV AL,08h
F80116  EE             OUT DX,AL
F80117  E442           IN AL,42h                   ; --- printer 8255 port B = hardware configuration ---
F80119  A802           TEST AL,02h                 ; bit1 must be 0
F8011B  740E           JZ   12Bh
F8011D  BA3700         MOV DX,37h                  ; bit1 set: PPI-C bit5 := 1 ...
F80120  B00B           MOV AL,0Bh
F80122  EE             OUT DX,AL
F80123  BAF000         MOV DX,0F0h                 ; ... then write 0F0h = CPU RESET, and wait for it
F80126  B000           MOV AL,00h
F80128  EE             OUT DX,AL
F80129  EBFE           JMP SHORT 129h
F8012B  B342           MOV BL,42h                  ; BL = 42h
F8012D  A820           TEST AL,20h                 ; 42h bit5 (clock group)
F8012F  7502           JNZ  133h
F80131  B340           MOV BL,40h                  ; bit5 clear -> BL = 40h
F80133  BA3F04         MOV DX,43Fh                 ; 043Fh := 42h or 40h
F80136  8AC3           MOV AL,BL
F80138  EE             OUT DX,AL
F80139  BD7F05         MOV BP,57Fh                 ; return address for the whole display-init block
```

`IN AL,42h` reads the printer 8255's port B, which on PC-98 doubles as a
hardware-configuration/DIP read. **Bit 1 must read 0**; if it is set the ITF
sets PPI-C bit 5 and writes port `0F0h`, which resets the CPU, then spins
waiting for the reset. Bit 5 then chooses `43Fh := 42h` or `43Fh := 40h`.

### 1.6 `F8013C`–`F8042E` — display (twin µPD7220) initialisation

Called with the return address in `BP` (here `057Fh`). It is one long straight
line of "load a GDC parameter block, wait, load the next", punctuated by DIP-switch
reads that choose between two CRT timings. `AH` selects which GDC the block goes
to: bit 7 = 0 → text GDC (command `62h`, parameters `60h`), bit 7 = 1 → graphic
GDC (command `A2h`, parameters `A0h`); bit 6 = 1 skips the FIFO wait.

```
F8013C  E433           IN AL,33h                   ; --- display initialisation ---
F8013E  A808           TEST AL,08h                 ; DIP SW (port 33h) bit3 = display timing / 24k-31k
F80140  7506           JNZ  148h
F80142  B000           MOV AL,00h
F80144  E66E           OUT 6Eh,AL                  ; 06Eh := 00h
F80146  EB04           JMP SHORT 14Ch
F80148  B001           MOV AL,01h
F8014A  E66E           OUT 6Eh,AL                  ; 06Eh := 01h
F8014C  BBE504         MOV BX,4E5h                 ; GDC block 04E5 (RESET), AH=40h: text GDC, no FIFO wait
F8014F  B440           MOV AH,40h
F80151  BC5701         MOV SP,157h
F80154  E90803         JMP 45Fh
F80157  BBE704         MOV BX,4E7h                 ; GDC block 04E7 (6Fh VSYNC master), text GDC
F8015A  B400           MOV AH,00h
F8015C  BC6201         MOV SP,162h
F8015F  E9FD02         JMP 45Fh
F80162  BBE904         MOV BX,4E9h
F80165  E433           IN AL,33h                   ; 33h bit3 again: pick SYNC parameter block
F80167  A808           TEST AL,08h
F80169  7503           JNZ  16Eh
F8016B  BBF304         MOV BX,4F3h
F8016E  B400           MOV AH,00h
F80170  BC7601         MOV SP,176h
F80173  E9E902         JMP 45Fh
F80176  BBFD04         MOV BX,4FDh                 ; GDC block 04FD (47h PITCH,50h)
F80179  B400           MOV AH,00h
F8017B  BC8101         MOV SP,181h
F8017E  E9DE02         JMP 45Fh
F80181  BB0005         MOV BX,500h                 ; GDC block 0500 (46h ZOOM,00)
F80184  B400           MOV AH,00h
F80186  BC8C01         MOV SP,18Ch
F80189  E9D302         JMP 45Fh
F8018C  BB0305         MOV BX,503h                 ; GDC block 0503 (70h PRAM 0-15)
F8018F  B400           MOV AH,00h
F80191  BC9701         MOV SP,197h
F80194  E9C802         JMP 45Fh
F80197  B001           MOV AL,01h
F80199  E668           OUT 68h,AL                  ; MODE FF1: reg0 := 1
F8019B  B90200         MOV CX,2h
F8019E  BCA401         MOV SP,1A4h
F801A1  E93303         JMP 4D7h                    ; wait 2 x text-GDC vertical sync (04D7)
F801A4  E2F8           LOOP 19Eh
F801A6  BB2905         MOV BX,529h
F801A9  B4C0           MOV AH,0C0h
F801AB  BCB101         MOV SP,1B1h
F801AE  E9AE02         JMP 45Fh
F801B1  BCB701         MOV SP,1B7h
F801B4  E92003         JMP 4D7h
F801B7  BB2B05         MOV BX,52Bh
F801BA  B480           MOV AH,80h
F801BC  BCC201         MOV SP,1C2h
F801BF  E99D02         JMP 45Fh
F801C2  B90200         MOV CX,2h
F801C5  BCCB01         MOV SP,1CBh
F801C8  E90C03         JMP 4D7h
F801CB  E2F8           LOOP 1C5h
F801CD  E442           IN AL,42h                   ; 42h bit3
F801CF  A808           TEST AL,08h
F801D1  740F           JZ   1E2h
F801D3  BB2D05         MOV BX,52Dh
F801D6  E433           IN AL,33h                   ; 33h bit3
F801D8  A808           TEST AL,08h
F801DA  7512           JNZ  1EEh
F801DC  BB3705         MOV BX,537h
F801DF  EB0D           JMP SHORT 1EEh
F801E1  90             NOP
F801E2  BB6B05         MOV BX,56Bh
F801E5  E433           IN AL,33h
F801E7  A808           TEST AL,08h
F801E9  7503           JNZ  1EEh
F801EB  BB7505         MOV BX,575h
F801EE  B480           MOV AH,80h
F801F0  BCF601         MOV SP,1F6h
F801F3  E96902         JMP 45Fh
F801F6  B90200         MOV CX,2h
F801F9  BCFF01         MOV SP,1FFh
F801FC  E9D802         JMP 4D7h
F801FF  E2F8           LOOP 1F9h
F80201  B00F           MOV AL,0Fh
F80203  E6A2           OUT 0A2h,AL                 ; graphic GDC command port := 0Fh (SYNC, DE=1)
F80205  B90200         MOV CX,2h
F80208  BC0E02         MOV SP,20Eh
F8020B  E9C902         JMP 4D7h
F8020E  E2F8           LOOP 208h
F80210  B04F           MOV AL,4Fh
F80212  E67C           OUT 7Ch,AL                  ; GRCG mode register := 4Fh
F80214  B081           MOV AL,81h
F80216  E66A           OUT 6Ah,AL                  ; MODE FF2 := 81h
F80218  E433           IN AL,33h                   ; 33h bit3
F8021A  A808           TEST AL,08h
F8021C  753E           JNZ  25Ch
F8021E  B008           MOV AL,08h
F80220  E668           OUT 68h,AL                  ; MODE FF1: reg4 := 0
F80222  E431           IN AL,31h                   ; DIP SW (port 31h) bit3
F80224  A808           TEST AL,08h
F80226  741A           JZ   242h
F80228  B01F           MOV AL,1Fh
F8022A  E670           OUT 70h,AL                  ; CRT parameter registers 70h/72h/74h
F8022C  B008           MOV AL,08h
F8022E  E672           OUT 72h,AL
```

```
F80230  B008           MOV AL,08h
F80232  E674           OUT 74h,AL
F80234  BB1A05         MOV BX,51Ah
F80237  B400           MOV AH,00h
F80239  BC3F02         MOV SP,23Fh
F8023C  E92002         JMP 45Fh
F8023F  EB5C           JMP SHORT 29Dh
F80241  90             NOP
F80242  B000           MOV AL,00h
F80244  E670           OUT 70h,AL
F80246  B007           MOV AL,07h
F80248  E672           OUT 72h,AL
F8024A  B008           MOV AL,08h
F8024C  E674           OUT 74h,AL
F8024E  BB1505         MOV BX,515h
F80251  B400           MOV AH,00h
F80253  BC5902         MOV SP,259h
F80256  E90602         JMP 45Fh
F80259  EB42           JMP SHORT 29Dh
F8025B  90             NOP
F8025C  B007           MOV AL,07h
F8025E  E668           OUT 68h,AL
F80260  EB00           JMP SHORT 262h
F80262  B009           MOV AL,09h
F80264  E668           OUT 68h,AL
F80266  E431           IN AL,31h
F80268  A808           TEST AL,08h
F8026A  741A           JZ   286h
F8026C  B01E           MOV AL,1Eh
F8026E  E670           OUT 70h,AL
F80270  B011           MOV AL,11h
F80272  E672           OUT 72h,AL
F80274  B010           MOV AL,10h
F80276  E674           OUT 74h,AL
F80278  BB2405         MOV BX,524h
F8027B  B400           MOV AH,00h
F8027D  BC8302         MOV SP,283h
F80280  E9DC01         JMP 45Fh
F80283  EB18           JMP SHORT 29Dh
F80285  90             NOP
F80286  B000           MOV AL,00h
F80288  E670           OUT 70h,AL
F8028A  B00F           MOV AL,0Fh
F8028C  E672           OUT 72h,AL
F8028E  B010           MOV AL,10h
F80290  E674           OUT 74h,AL
F80292  BB1F05         MOV BX,51Fh
F80295  B400           MOV AH,00h
F80297  BC9D02         MOV SP,29Dh
F8029A  E9C201         JMP 45Fh
F8029D  E431           IN AL,31h                   ; 31h bit2
F8029F  A804           TEST AL,04h
F802A1  7404           JZ   2A7h
F802A3  B005           MOV AL,05h
F802A5  E668           OUT 68h,AL                  ; MODE FF1: reg2 := 1
F802A7  B000           MOV AL,00h
F802A9  E676           OUT 76h,AL                  ; 076h := 00h
F802AB  E442           IN AL,42h                   ; 42h bit4
F802AD  A810           TEST AL,10h
F802AF  7504           JNZ  2B5h
F802B1  B041           MOV AL,41h
F802B3  E66A           OUT 6Ah,AL                  ; MODE FF2 := 41h
F802B5  B082           MOV AL,82h
F802B7  E66A           OUT 6Ah,AL
F802B9  B084           MOV AL,84h
F802BB  E66A           OUT 6Ah,AL
F802BD  B007           MOV AL,07h
F802BF  E66A           OUT 6Ah,AL
F802C1  E433           IN AL,33h                   ; 33h bit3 -> graphic GDC SYNC extra parameters
F802C3  A808           TEST AL,08h
F802C5  B8DD2C         MOV AX,2CDDh
F802C8  7503           JNZ  2CDh
F802CA  B88832         MOV AX,3288h
F802CD  E6A0           OUT 0A0h,AL                 ; graphic GDC parameter port
F802CF  8AC4           MOV AL,AH
F802D1  E6A2           OUT 0A2h,AL                 ; graphic GDC command port
F802D3  B006           MOV AL,06h
F802D5  E66A           OUT 6Ah,AL
F802D7  B000           MOV AL,00h
F802D9  E66A           OUT 6Ah,AL
F802DB  B90200         MOV CX,2h
F802DE  BCE402         MOV SP,2E4h
F802E1  E9F301         JMP 4D7h
F802E4  E2F8           LOOP 2DEh
F802E6  BB2905         MOV BX,529h
F802E9  B4C0           MOV AH,0C0h
F802EB  BCF102         MOV SP,2F1h
F802EE  E96E01         JMP 45Fh
F802F1  BCF702         MOV SP,2F7h
F802F4  E9E001         JMP 4D7h
F802F7  BB2B05         MOV BX,52Bh
F802FA  B480           MOV AH,80h
F802FC  BC0203         MOV SP,302h
F802FF  E95D01         JMP 45Fh
F80302  B90200         MOV CX,2h
F80305  BC0B03         MOV SP,30Bh
F80308  E9CC01         JMP 4D7h
F8030B  E2F8           LOOP 305h
F8030D  E442           IN AL,42h
F8030F  A808           TEST AL,08h
F80311  740F           JZ   322h
F80313  BB2D05         MOV BX,52Dh
F80316  E433           IN AL,33h
F80318  A808           TEST AL,08h
F8031A  7512           JNZ  32Eh
F8031C  BB3705         MOV BX,537h
F8031F  EB0D           JMP SHORT 32Eh
F80321  90             NOP
F80322  BB6B05         MOV BX,56Bh
F80325  E433           IN AL,33h
F80327  A808           TEST AL,08h
F80329  7503           JNZ  32Eh
F8032B  BB7505         MOV BX,575h
F8032E  B480           MOV AH,80h
```

```
F80330  BC3603         MOV SP,336h
F80333  E92901         JMP 45Fh
F80336  BB4105         MOV BX,541h
F80339  E433           IN AL,33h
F8033B  A808           TEST AL,08h
F8033D  7503           JNZ  342h
F8033F  BB4405         MOV BX,544h
F80342  B480           MOV AH,80h
F80344  BC4A03         MOV SP,34Ah
F80347  E91501         JMP 45Fh
F8034A  BB4705         MOV BX,547h
F8034D  B480           MOV AH,80h
F8034F  BC5503         MOV SP,355h
F80352  E90A01         JMP 45Fh
F80355  BB4A05         MOV BX,54Ah
F80358  B480           MOV AH,80h
F8035A  BC6003         MOV SP,360h
F8035D  E9FF00         JMP 45Fh
F80360  BB4D05         MOV BX,54Dh
F80363  B480           MOV AH,80h
F80365  BC6B03         MOV SP,36Bh
F80368  E9F400         JMP 45Fh
F8036B  BB5F05         MOV BX,55Fh
F8036E  B480           MOV AH,80h
F80370  BC7603         MOV SP,376h
F80373  E9E900         JMP 45Fh
F80376  BB6905         MOV BX,569h
F80379  B480           MOV AH,80h
F8037B  BC8103         MOV SP,381h
F8037E  E9DE00         JMP 45Fh
F80381  B000           MOV AL,00h
F80383  E66C           OUT 6Ch,AL                  ; border colour register 06Ch := 00h
F80385  B90200         MOV CX,2h
F80388  E460           IN AL,60h                   ; --- text-GDC vertical-sync poll (3 edges, twice) ---
F8038A  A820           TEST AL,20h                 ; port 60h bit5 = VSYNC/VBLANK status
F8038C  75FA           JNZ  388h
F8038E  E460           IN AL,60h
F80390  A820           TEST AL,20h
F80392  74FA           JZ   38Eh
F80394  E460           IN AL,60h
F80396  A820           TEST AL,20h
F80398  75FA           JNZ  394h
F8039A  E2EC           LOOP 388h
F8039C  EB00           JMP SHORT 39Eh
F8039E  EB00           JMP SHORT 3A0h
F803A0  EB00           JMP SHORT 3A2h
F803A2  E4A0           IN AL,0A0h                  ; --- graphic-GDC vertical-sync poll (3 edges) ---
F803A4  A820           TEST AL,20h
F803A6  75F4           JNZ  39Ch
F803A8  EB00           JMP SHORT 3AAh
F803AA  EB00           JMP SHORT 3ACh
F803AC  EB00           JMP SHORT 3AEh
F803AE  E4A0           IN AL,0A0h
F803B0  A820           TEST AL,20h
F803B2  74F4           JZ   3A8h
F803B4  EB00           JMP SHORT 3B6h
F803B6  EB00           JMP SHORT 3B8h
F803B8  EB00           JMP SHORT 3BAh
F803BA  E4A0           IN AL,0A0h
F803BC  A820           TEST AL,20h
F803BE  75F4           JNZ  3B4h
F803C0  EB00           JMP SHORT 3C2h
F803C2  EB00           JMP SHORT 3C4h
F803C4  EB00           JMP SHORT 3C6h
F803C6  B00D           MOV AL,0Dh                  ; 0Dh = BCTRL display ON, to both GDCs
F803C8  E6A2           OUT 0A2h,AL
F803CA  EB00           JMP SHORT 3CCh
F803CC  E662           OUT 62h,AL
F803CE  EB00           JMP SHORT 3D0h
F803D0  E4A0           IN AL,0A0h                  ; wait for graphic-GDC VSYNC once more
F803D2  A820           TEST AL,20h
F803D4  74FA           JZ   3D0h
F803D6  EB00           JMP SHORT 3D8h
F803D8  EB00           JMP SHORT 3DAh
F803DA  EB00           JMP SHORT 3DCh
F803DC  B00C           MOV AL,0Ch                  ; 0Ch = BCTRL display OFF, to both GDCs
F803DE  E6A2           OUT 0A2h,AL
F803E0  EB00           JMP SHORT 3E2h
F803E2  E662           OUT 62h,AL
F803E4  B002           MOV AL,02h
F803E6  E668           OUT 68h,AL                  ; MODE FF1: reg1 := 0
F803E8  BEEE03         MOV SI,3EEh                 ; run the second port table at 03EE
F803EB  E9E5FC         JMP 0D3h
```

**The `F80388` block is where a machine with no working video timing stops.**
`IN AL,60h ; TEST AL,20h` polls the text GDC's status port for the vertical
sync/blank bit and requires it to go **low, then high, then low**, twice
(`CX = 2`); then the same three-edge sequence on the graphic GDC status port
`A0h`, three times. See §3.

**Second port table, at `F803EE`:**

```
first word at F803EE = 0005 -> count 5, port high byte 00, table body F803F0..F803F9, walker resumes at F803FA

    F803F0:  OUT 0068, 02
    F803F2:  OUT 00A8, 37
    F803F4:  OUT 00AA, 15
    F803F6:  OUT 00AC, 26
    F803F8:  OUT 00AE, 04
```

```
F803FA  B001           MOV AL,01h
F803FC  E66A           OUT 6Ah,AL                  ; MODE FF2 := 01h (analogue palette access)
F803FE  BE2F04         MOV SI,42Fh
F80401  B91000         MOV CX,10h
F80404  8AC1           MOV AL,CL                   ; palette index = -CL & 0Fh
F80406  F6D8           NEG AL
F80408  240F           AND AL,0Fh
F8040A  E6A8           OUT 0A8h,AL                 ; palette index register
F8040C  2EAC           CS:LODSB
F8040E  E6AA           OUT 0AAh,AL                 ; green / red / blue components from the table at 042F
F80410  2EAC           CS:LODSB
F80412  E6AC           OUT 0ACh,AL
F80414  2EAC           CS:LODSB
F80416  E6AE           OUT 0AEh,AL
F80418  E2EA           LOOP 404h
F8041A  B000           MOV AL,00h
F8041C  E66A           OUT 6Ah,AL                  ; MODE FF2 := 00h
F8041E  B00F           MOV AL,0Fh
F80420  E668           OUT 68h,AL                  ; MODE FF1: reg7 := 1
F80422  B800A0         MOV AX,0A000h
F80425  8EC0           MOV ES,AX
F80427  26C606E03F00   MOV BYTE PTR ES:[3FE0h],00h ; A000:3FE0 = text-screen line counter used by the message printer
F8042D  FFE5           JMP BP                      ; return to 057Fh (or 00A3h on the shutdown path)
```

Palette table consumed by the loop above (16 × 3 bytes, G/R/B):

```
F8042F  00 00 00 00 00 07 00 07 00 00 07 07 07 00 00 07
F8043F  00 07 07 07 00 07 07 07 04 04 04 00 00 0F 00 0F
F8044F  00 00 0F 0F 0F 00 00 0F 00 0F 0F 0F 00 0F 0F 0F
```

### 1.7 `F8045F`–`F804E4` — the GDC parameter-block writer, and the retrace wait

```
F8045F  BA6200         MOV DX,62h                  ; --- GDC parameter-block writer.  BX -> block, AH bit7: 0=text 1=graphic, bit6: skip FIFO wait ---
F80462  F6C480         TEST AH,80h
F80465  7403           JZ   46Ah
F80467  BAA200         MOV DX,0A2h
F8046A  F6C440         TEST AH,40h
F8046D  751F           JNZ  48Eh
F8046F  F6C480         TEST AH,80h
F80472  7508           JNZ  47Ch
F80474  E460           IN AL,60h                   ; text GDC status port 60h bit2 = FIFO EMPTY
F80476  A804           TEST AL,04h
F80478  74FA           JZ   474h
F8047A  EB12           JMP SHORT 48Eh
F8047C  EB00           JMP SHORT 47Eh
F8047E  EB00           JMP SHORT 480h
F80480  EB00           JMP SHORT 482h
F80482  E4A0           IN AL,0A0h                  ; graphic GDC status port A0h bit2 = FIFO EMPTY
F80484  A804           TEST AL,04h
F80486  74F4           JZ   47Ch
F80488  EB00           JMP SHORT 48Ah
F8048A  EB00           JMP SHORT 48Ch
F8048C  EB00           JMP SHORT 48Eh
F8048E  2E8A0F         MOV CL,CS:[BX]              ; CL = byte count
F80491  43             INC BX
F80492  32ED           XOR CH,CH
F80494  2E8A07         MOV AL,CS:[BX]
F80497  43             INC BX
F80498  FEC5           INC CH
F8049A  FEC9           DEC CL
F8049C  EE             OUT DX,AL                   ; first byte -> command port (62h / A2h)
F8049D  83EA02         SUB DX,0002h                ; DX -= 2 -> parameter port (60h / A0h)
F804A0  0AC9           OR CL,CL
F804A2  7431           JZ   4D5h
F804A4  80FD10         CMP CH,10h                  ; re-check FIFO every 16 bytes
F804A7  7C21           JL   4CAh
F804A9  32ED           XOR CH,CH
F804AB  F6C480         TEST AH,80h
F804AE  7508           JNZ  4B8h
F804B0  E460           IN AL,60h
F804B2  A804           TEST AL,04h
F804B4  74FA           JZ   4B0h
F804B6  EB12           JMP SHORT 4CAh
F804B8  EB00           JMP SHORT 4BAh
F804BA  EB00           JMP SHORT 4BCh
F804BC  EB00           JMP SHORT 4BEh
F804BE  E4A0           IN AL,0A0h
F804C0  A804           TEST AL,04h
F804C2  74F4           JZ   4B8h
F804C4  EB00           JMP SHORT 4C6h
F804C6  EB00           JMP SHORT 4C8h
F804C8  EB00           JMP SHORT 4CAh
F804CA  2E8A07         MOV AL,CS:[BX]
F804CD  43             INC BX
F804CE  FEC5           INC CH
F804D0  FEC9           DEC CL
F804D2  EE             OUT DX,AL
F804D3  EBCB           JMP SHORT 4A0h
F804D5  FFE4           JMP SP                      ; return
F804D7  E460           IN AL,60h                   ; --- wait one text-GDC vertical retrace ---
F804D9  A820           TEST AL,20h                 ; port 60h bit5: wait low, then wait high
F804DB  74FA           JZ   4D7h
F804DD  E460           IN AL,60h
F804DF  A820           TEST AL,20h
F804E1  75FA           JNZ  4DDh
F804E3  FFE4           JMP SP
```

The parameter blocks it walks (`count`, then `count` bytes: the first goes to
the command port, the rest to the parameter port):

```
F804E5  count= 1  cmd=00  params=-
F804E7  count= 1  cmd=6F  params=-
F804E9  count= 9  cmd=0E  params=10 4E 07 25 07 07 90 65
F804F3  count= 9  cmd=0E  params=10 4E 07 25 0D 0F C8 94
F804FD  count= 2  cmd=47  params=50
F80500  count= 2  cmd=46  params=00
F80503  count=17  cmd=70  params=00 00 F0 1F 00 00 10 00 00 00 10 00 00 00 10 00
F80515  count= 4  cmd=4B  params=07 00 3B
F8051A  count= 4  cmd=4B  params=09 00 4B
F8051F  count= 4  cmd=4B  params=0F 00 7B
F80524  count= 4  cmd=4B  params=13 00 9B
F80529  count= 1  cmd=00  params=-
F8052B  count= 1  cmd=6E  params=-
F8052D  count= 9  cmd=0E  params=16 26 03 11 83 07 90 65
F80537  count= 9  cmd=0E  params=16 26 03 11 86 0F C8 94
F80541  count= 2  cmd=4B  params=01
F80544  count= 2  cmd=4B  params=00
F80547  count= 2  cmd=47  params=28
F8054A  count= 2  cmd=46  params=00
F8054D  count=17  cmd=70  params=00 00 F0 1F 00 00 10 00 00 00 10 00 00 00 10 00
F8055F  count= 9  cmd=78  params=00 00 00 00 00 00 00 00
F80569  count= 1  cmd=20  params=-
F8056B  count= 9  cmd=0E  params=06 26 03 11 83 07 90 65
F80575  count= 9  cmd=0E  params=06 26 03 11 86 0F C8 94
```

Decoded as µPD7220 commands: `00`=RESET, `0E`/`0F`=SYNC(DE=0/1),
`6E`/`6F`=VSYNC(slave/master), `46`=ZOOM, `47`=PITCH, `49`=CSRW, `4B`=CCHAR,
`4C`=FIGS, `20`=WDAT, `70`/`78`=PRAM load, `0C`/`0D`=BCTRL (display off/on).

### 1.8 `F8057F`–`F805DF` — ROM checksum and the 8253 setup

```
F8057F  FC             CLD                         ; --- 32 KB ROM checksum ---
F80580  B800F8         MOV AX,0F800h
F80583  8ED8           MOV DS,AX
F80585  33D2           XOR DX,DX
F80587  33F6           XOR SI,SI
F80589  B90040         MOV CX,4000h
F8058C  AD             LODSW                       ; sum even bytes into DL and odd bytes into DH
F8058D  02D0           ADD DL,AL
F8058F  02F4           ADD DH,AH
F80591  E2F9           LOOP 58Ch
F80593  0BD2           OR DX,DX                    ; DX must be 0000
F80595  75FE           JNZ  595h                   ; silent hang -- the display is not usable yet
F80597  33C0           XOR AX,AX
F80599  8ED8           MOV DS,AX
F8059B  BCE005         MOV SP,5E0h
F8059E  B030           MOV AL,30h                  ; --- 8253 PIT setup ---
F805A0  E677           OUT 77h,AL                  ; control 30h = counter0, LSB+MSB, mode 0
F805A2  EB00           JMP SHORT 5A4h
F805A4  EB00           JMP SHORT 5A6h
F805A6  B000           MOV AL,00h
F805A8  E671           OUT 71h,AL                  ; counter0 := 0000
F805AA  EB00           JMP SHORT 5ACh
F805AC  EB00           JMP SHORT 5AEh
F805AE  B000           MOV AL,00h
F805B0  E671           OUT 71h,AL
F805B2  EB00           JMP SHORT 5B4h
F805B4  EB00           JMP SHORT 5B6h
F805B6  BAE603         MOV DX,3E6h
F805B9  E442           IN AL,42h                   ; 42h bit5 selects the PIT input clock constant
F805BB  A820           TEST AL,20h
F805BD  7503           JNZ  5C2h
F805BF  BACD04         MOV DX,4CDh
F805C2  B076           MOV AL,76h
F805C4  E677           OUT 77h,AL                  ; control 76h = counter1, LSB+MSB, mode 3
F805C6  EB00           JMP SHORT 5C8h
F805C8  EB00           JMP SHORT 5CAh
F805CA  8AC2           MOV AL,DL
F805CC  E673           OUT 73h,AL                  ; counter1 := 03E6h (bit5 set) or 04CDh (bit5 clear)
F805CE  EB00           JMP SHORT 5D0h
F805D0  EB00           JMP SHORT 5D2h
F805D2  8AC6           MOV AL,DH
F805D4  E673           OUT 73h,AL
F805D6  EB00           JMP SHORT 5D8h
F805D8  EB00           JMP SHORT 5DAh
F805DA  B0B6           MOV AL,0B6h
F805DC  E677           OUT 77h,AL                  ; control B6h = counter2, LSB+MSB, mode 3
F805DE  FFE4           JMP SP
```

The checksum sums the 16384 words of the ROM into `DL` (even bytes) and `DH`
(odd bytes); **`DX` must come out `0000`** or the ROM spins at `F80595` with no
message, because the display is not up yet. The supplied image passes:
even-byte sum `00`, odd-byte sum `00`.

### 1.9 `F805E0`–`F80620` — third port table, then the 8259 pair

```
F805E0  BEE605         MOV SI,5E6h                 ; run the third port table at 05E6
F805E3  E9EDFA         JMP 0D3h
```

```
first word at F805E6 = 000A -> count 10, port high byte 00, table body F805E8..F805FB, walker resumes at F805FC

    F805E8:  OUT 0029, 00
    F805EA:  OUT 0029, 01
    F805EC:  OUT 0029, 02
    F805EE:  OUT 0029, 03
    F805F0:  OUT 001B, 00
    F805F2:  OUT 0027, 00
    F805F4:  OUT 0021, 00
    F805F6:  OUT 0023, 00
    F805F8:  OUT 0025, 00
    F805FA:  OUT 0011, 40
```

```
F805FC  B011           MOV AL,11h                  ; --- 8259 master: ICW1 11h, ICW2 08h, ICW3 80h, ICW4 1Dh ---
F805FE  E600           OUT 00h,AL
F80600  B008           MOV AL,08h
F80602  E602           OUT 02h,AL
F80604  B080           MOV AL,80h
F80606  E602           OUT 02h,AL
F80608  B01D           MOV AL,1Dh
F8060A  E602           OUT 02h,AL
F8060C  B011           MOV AL,11h
F8060E  E608           OUT 08h,AL                  ; --- 8259 slave: ICW1 11h, ICW2 10h, ICW3 07h, ICW4 09h ---
F80610  B010           MOV AL,10h
F80612  E60A           OUT 0Ah,AL
F80614  B007           MOV AL,07h
F80616  E60A           OUT 0Ah,AL
F80618  B009           MOV AL,09h
F8061A  E60A           OUT 0Ah,AL
F8061C  B400           MOV AH,00h
F8061E  BD7206         MOV BP,672h
```

Master 8259 (`00h`/`02h`): ICW1 `11h`, ICW2 `08h` (vectors 08–0F), ICW3 `80h`
(slave on IR7), ICW4 `1Dh`. Slave 8259 (`08h`/`0Ah`): ICW1 `11h`, ICW2 `10h`
(vectors 10–17), ICW3 `07h`, ICW4 `09h`.

### 1.10 `F80621`–`F80713` — keyboard 8251 primitives and the power-on key scan

```
F80621  33C9           XOR CX,CX                   ; --- keyboard: send command byte AH ---
F80623  E2FE           LOOP 623h
F80625  B037           MOV AL,37h
F80627  E643           OUT 43h,AL                  ; 8251 command 37h (TxEN,DTR,RxE,ER,RTS)
F80629  EB00           JMP SHORT 62Bh
F8062B  EB00           JMP SHORT 62Dh
F8062D  EB00           JMP SHORT 62Fh
F8062F  EB00           JMP SHORT 631h
F80631  EB00           JMP SHORT 633h
F80633  EB00           JMP SHORT 635h
F80635  EB00           JMP SHORT 637h
F80637  EB00           JMP SHORT 639h
F80639  8AC4           MOV AL,AH
F8063B  E641           OUT 41h,AL                  ; data out
F8063D  B94000         MOV CX,40h
F80640  E2FE           LOOP 640h
F80642  EB00           JMP SHORT 644h
F80644  E443           IN AL,43h                   ; status bit0 = TxRDY: wait until the byte has left
F80646  A801           TEST AL,01h
F80648  74F8           JZ   642h
F8064A  B016           MOV AL,16h
F8064C  E643           OUT 43h,AL                  ; 8251 command 16h (RxE,ER,RTS)
F8064E  B90008         MOV CX,800h
F80651  E2FE           LOOP 651h
F80653  FFE5           JMP BP
F80655  B98000         MOV CX,80h                  ; --- keyboard: wait for a byte, ~32768 polls ---
F80658  E2FE           LOOP 658h
F8065A  B90080         MOV CX,8000h
F8065D  EB00           JMP SHORT 65Fh
F8065F  E443           IN AL,43h                   ; status bit1 = RxRDY
F80661  A802           TEST AL,02h
F80663  7504           JNZ  669h
F80665  E2F6           LOOP 65Dh
F80667  FFE5           JMP BP                      ; timeout: return with ZF=1
F80669  B98000         MOV CX,80h
F8066C  E2FE           LOOP 66Ch
F8066E  E441           IN AL,41h                   ; read the byte
F80670  FFE5           JMP BP
```

```
F80672  B306           MOV BL,06h                  ; --- collect up to 6 keys held at power-on ---
F80674  B90030         MOV CX,3000h
F80677  EB00           JMP SHORT 679h
F80679  E443           IN AL,43h                   ; RxRDY
F8067B  A802           TEST AL,02h
F8067D  7505           JNZ  684h
F8067F  E2F6           LOOP 677h
F80681  EB40           JMP SHORT 6C3h              ; nothing pressed -> AH stays 0
F80683  90             NOP
F80684  B90001         MOV CX,100h
F80687  E2FE           LOOP 687h
F80689  E441           IN AL,41h                   ; make code
F8068B  3C60           CMP AL,60h                  ; 60h -> AH bit7
F8068D  7505           JNZ  694h
F8068F  80CC80         OR AH,80h
F80692  EB2B           JMP SHORT 6BFh
F80694  3C70           CMP AL,70h                  ; 70h (SHIFT) -> bit0
F80696  7505           JNZ  69Dh
F80698  80CC01         OR AH,01h
F8069B  EB22           JMP SHORT 6BFh
F8069D  3C74           CMP AL,74h                  ; 74h (CTRL)  -> bit4
F8069F  7505           JNZ  6A6h
F806A1  80CC10         OR AH,10h
F806A4  EB19           JMP SHORT 6BFh
F806A6  3C73           CMP AL,73h                  ; 73h (GRPH)  -> bit3
F806A8  7505           JNZ  6AFh
F806AA  80CC08         OR AH,08h
F806AD  EB10           JMP SHORT 6BFh
F806AF  3C72           CMP AL,72h                  ; 72h (KANA)  -> bit2
F806B1  7505           JNZ  6B8h
F806B3  80CC04         OR AH,04h
F806B6  EB07           JMP SHORT 6BFh
F806B8  3C71           CMP AL,71h                  ; 71h (CAPS)  -> bit1
F806BA  7503           JNZ  6BFh
F806BC  80CC02         OR AH,02h
F806BF  FECB           DEC BL
F806C1  75B4           JNZ  677h
F806C3  8BF0           MOV SI,AX
F806C5  B204           MOV DL,04h
F806C7  B49D           MOV AH,9Dh                  ; keyboard command 9Dh, up to 4 tries, expect FAh (ACK)
F806C9  BDCF06         MOV BP,6CFh
F806CC  E952FF         JMP 621h
F806CF  BDD506         MOV BP,6D5h
F806D2  EB81           JMP SHORT 655h
F806D4  743E           JZ   714h
F806D6  3CFA           CMP AL,0FAh
F806D8  740B           JZ   6E5h
F806DA  3CFC           CMP AL,0FCh
F806DC  74E9           JZ   6C7h
F806DE  FECA           DEC DL
F806E0  75ED           JNZ  6CFh
F806E2  EB30           JMP SHORT 714h
F806E4  90             NOP
F806E5  BA00A0         MOV DX,0A000h               ; A000:3FF6 memory-switch byte -> keyboard command 7xh
F806E8  8EC2           MOV ES,DX
F806EA  268A26F63F     MOV AH,ES:[3FF6h]
F806EF  C0CC04         ROR AH,04h
F806F2  80E40C         AND AH,0Ch
F806F5  80CC70         OR AH,70h
F806F8  B204           MOV DL,04h
F806FA  BD0007         MOV BP,700h
F806FD  E921FF         JMP 621h
F80700  BD0607         MOV BP,706h
F80703  E94FFF         JMP 655h
F80706  740C           JZ   714h
F80708  3CFA           CMP AL,0FAh
F8070A  7408           JZ   714h
F8070C  3CFC           CMP AL,0FCh
F8070E  74EA           JZ   6FAh
F80710  FECA           DEC DL
F80712  75EC           JNZ  700h
```

Six polls of the keyboard receiver, `3000h` iterations each. Whatever make
codes arrive are folded into `AH`: `60h`→bit 7, `71h`(CAPS)→bit 1,
`72h`(KANA)→bit 2, `73h`(GRPH)→bit 3, `74h`(CTRL)→bit 4, `70h`(SHIFT)→bit 0.
If nothing arrives (the normal case) `AH` stays `00h` and the ROM takes the
full-test path. A keyboard interface that is simply absent — status `43h`
reading `00h` (never ready) *or* `FFh` (always ready, data `FFh`) — both give
`AH = 0`, which is the safe outcome.

### 1.11 `F80714`–`F807EB` — boot beep, or the two shortcut paths

```
F80714  8BC6           MOV AX,SI                   ; --- STOP-key dispatch ---
F80716  F6C480         TEST AH,80h                 ; AH bit7 = scan code 60h was held
F80719  7555           JNZ  770h                   ; held -> skip the beep and every RAM/VRAM test
F8071B  BAE603         MOV DX,3E6h
F8071E  E442           IN AL,42h                   ; 42h bit5 -> beep divisor
F80720  A820           TEST AL,20h
F80722  7503           JNZ  727h
F80724  BACD04         MOV DX,4CDh
F80727  B006           MOV AL,06h
F80729  E637           OUT 37h,AL                  ; PPI-C bit3 := 0  (buzzer ON, active low)
F8072B  B90090         MOV CX,9000h
F8072E  E2FE           LOOP 72Eh
F80730  D1E2           SHL DX,1
F80732  B007           MOV AL,07h
F80734  E637           OUT 37h,AL                  ; PPI-C bit3 := 1  (buzzer OFF)
F80736  B076           MOV AL,76h
F80738  E677           OUT 77h,AL                  ; counter1 mode 3, divisor DX then DX*2 -- the two-tone boot beep
F8073A  EB00           JMP SHORT 73Ch
F8073C  EB00           JMP SHORT 73Eh
F8073E  8AC2           MOV AL,DL
F80740  E673           OUT 73h,AL
F80742  EB00           JMP SHORT 744h
F80744  EB00           JMP SHORT 746h
F80746  8AC6           MOV AL,DH
F80748  E673           OUT 73h,AL
F8074A  B006           MOV AL,06h
F8074C  E637           OUT 37h,AL
F8074E  B90090         MOV CX,9000h
F80751  E2FE           LOOP 751h
F80753  D1EA           SHR DX,1
F80755  B007           MOV AL,07h
F80757  E637           OUT 37h,AL
F80759  B076           MOV AL,76h
F8075B  E677           OUT 77h,AL
F8075D  EB00           JMP SHORT 75Fh
F8075F  EB00           JMP SHORT 761h
F80761  8AC2           MOV AL,DL
F80763  E673           OUT 73h,AL
F80765  EB00           JMP SHORT 767h
F80767  EB00           JMP SHORT 769h
F80769  8AC6           MOV AL,DH
F8076B  E673           OUT 73h,AL
F8076D  EB7D           JMP SHORT 7ECh              ; go on to the VRAM tests
```

```
F80770  80E4F9         AND AH,0F9h                 ; mask off KANA and CAPS
F80773  80FC91         CMP AH,91h                  ; STOP+SHIFT+CTRL exactly -> ITF service mode
F80776  7511           JNZ  789h
F80778  32C0           XOR AL,AL
F8077A  E6F2           OUT 0F2h,AL                 ; 0F2h := 00h, 0F6h := 02h
F8077C  0C02           OR AL,02h
F8077E  E6F6           OUT 0F6h,AL
F80780  B0B0           MOV AL,0B0h
F80782  BA6705         MOV DX,567h
F80785  EE             OUT DX,AL                   ; 0567h := B0h
F80786  E90518         JMP 1F8Eh                   ; --- entry to the floppy/ITF service mode (off the normal path) ---
F80789  33C0           XOR AX,AX                   ; STOP held: clear the BIOS work area and skip all tests
F8078B  8ED8           MOV DS,AX
F8078D  8EC0           MOV ES,AX
F8078F  8B1E8004       MOV BX,[0480h]
F80793  80E720         AND BH,20h
F80796  8B160004       MOV DX,[0400h]
F8079A  BF0004         MOV DI,400h
F8079D  B98000         MOV CX,80h
F807A0  FC             CLD
F807A1  F3AB           REP STOSW
F807A3  891E8004       MOV [0480h],BX
F807A7  89160004       MOV [0400h],DX
F807AB  8BDE           MOV BX,SI
F807AD  F6C701         TEST BH,01h
F807B0  7403           JZ   7B5h
F807B2  80CF20         OR BH,20h
F807B5  D0E7           SHL BH,1
F807B7  D0E7           SHL BH,1
F807B9  80E7E0         AND BH,0E0h
F807BC  883E0204       MOV [0402h],BH
F807C0  8A1EC005       MOV BL,[05C0h]
F807C4  8A3E4C05       MOV BH,[054Ch]
F807C8  BF0205         MOV DI,502h
F807CB  B97E00         MOV CX,7Eh
F807CE  F3AB           REP STOSW
F807D0  881EC005       MOV [05C0h],BL
F807D4  883E4C05       MOV [054Ch],BH
F807D8  800E000580     OR BYTE PTR [0500h],80h
F807DD  BA3D05         MOV DX,53Dh
F807E0  B002           MOV AL,02h
F807E2  EE             OUT DX,AL                   ; 053Dh := 02h
F807E3  BA6104         MOV DX,461h
F807E6  B008           MOV AL,08h
F807E8  EE             OUT DX,AL                   ; 0461h := 08h
F807E9  E95F0F         JMP 174Bh
```

* `AH` bit 7 clear (nothing held): two-tone beep on PIT channel 1 through
  PPI-C bit 3, then on to the VRAM tests at `F807EC`.
* `AH` == `91h` after masking (STOP + SHIFT + CTRL): **ITF service mode** at
  `F81F8E` — this is the floppy-based ITF/BIOS updater, and it is the *only*
  path that touches the FDC and the DMA controller. Off the normal boot path.
* otherwise (STOP held alone, etc.): clear the BIOS work area and jump straight
  to the final configuration at `F8174B`, skipping every RAM and VRAM test.

### 1.12 `F807EC`–`F80A95` — VRAM, CG, memory-switch and base-RAM tests

```
F807EC  B800A0         MOV AX,0A000h               ; --- graphic VRAM clear and pattern test (A0000) ---
F807EF  8EC0           MOV ES,AX
F807F1  6633C0         XOR EAX,EAX
F807F4  33FF           XOR DI,DI
F807F6  B9F80F         MOV CX,0FF8h
F807F9  66F3AB         REP STOSD
F807FC  33FF           XOR DI,DI
F807FE  B9F80F         MOV CX,0FF8h
F80801  66F3AB         REP STOSD
F80804  B2FF           MOV DL,0FFh
F80806  8AC2           MOV AL,DL
F80808  8AE2           MOV AH,DL
F8080A  8BF8           MOV DI,AX
F8080C  66C1E010       SHL EAX,10h
F80810  8BC7           MOV AX,DI
F80812  33FF           XOR DI,DI
F80814  B9F80F         MOV CX,0FF8h
F80817  66F3AB         REP STOSD
F8081A  33FF           XOR DI,DI
F8081C  B90008         MOV CX,800h
F8081F  66F3AF         REP SCASD
F80822  7512           JNZ  836h                   ; mismatch -> TEXT VIDEO RAM ERROR
F80824  B9F00F         MOV CX,0FF0h
F80827  AE             SCASB
F80828  750C           JNZ  836h
F8082A  47             INC DI
F8082B  E2FA           LOOP 827h
F8082D  0AD2           OR DL,DL                    ; patterns FF, AA, 55, 00
F8082F  741C           JZ   84Dh
F80831  80EA55         SUB DL,55h
F80834  EBD0           JMP SHORT 806h
F80836  BC3C08         MOV SP,83Ch
F80839  E99BFC         JMP 4D7h
F8083C  B00D           MOV AL,0Dh
F8083E  E662           OUT 62h,AL                  ; display on so the message can be seen
F80840  B00F           MOV AL,0Fh
F80842  E668           OUT 68h,AL
F80844  BE561B         MOV SI,1B56h
F80847  BC4D08         MOV SP,84Dh
F8084A  E97E15         JMP 1DCBh
F8084D  66B820002000   MOV EAX,200020h             ; fill text VRAM with 0020h and the attribute plane with 00E1h
F80853  33FF           XOR DI,DI
F80855  B90008         MOV CX,800h
F80858  66F3AB         REP STOSD
F8085B  66B8E100E100   MOV EAX,0E100E1h
F80861  B9F807         MOV CX,7F8h
F80864  66F3AB         REP STOSD
F80867  BC6D08         MOV SP,86Dh
F8086A  E96AFC         JMP 4D7h
F8086D  B00D           MOV AL,0Dh
F8086F  E662           OUT 62h,AL
F80871  B00F           MOV AL,0Fh
F80873  E668           OUT 68h,AL
F80875  8BC6           MOV AX,SI
F80877  80FC1E         CMP AH,1Eh                  ; AH==1Eh (CTRL+GRPH+KANA+CAPS) -> print the machine information screen
F8087A  7403           JZ   87Fh
F8087C  EB71           JMP SHORT 8EFh
F8087E  90             NOP
```

```
F8087F  BB00A0         MOV BX,0A000h
F80882  8EC3           MOV ES,BX
F80884  BEE31C         MOV SI,1CE3h
F80887  BC8D08         MOV SP,88Dh
F8088A  E93E15         JMP 1DCBh
F8088D  26FE06E03F     INC BYTE PTR ES:[3FE0h]
F80892  26FE06E03F     INC BYTE PTR ES:[3FE0h]
F80897  BADD7F         MOV DX,7FDDh                ; 7FDDh bit2: 0 = 80386 mode, 1 = 70116 (V30) mode
F8089A  EC             IN AL,DX
F8089B  A804           TEST AL,04h
F8089D  7509           JNZ  8A8h
F8089F  BE0E1D         MOV SI,1D0Eh
F808A2  BCB108         MOV SP,8B1h
F808A5  E92315         JMP 1DCBh
F808A8  BE251D         MOV SI,1D25h
F808AB  BCCE08         MOV SP,8CEh
F808AE  E91A15         JMP 1DCBh
F808B1  26FE06E03F     INC BYTE PTR ES:[3FE0h]
F808B6  E442           IN AL,42h                   ; 42h bit5: 0 = 20MHz, 1 = 16MHz
F808B8  A820           TEST AL,20h
F808BA  7509           JNZ  8C5h
F808BC  BE421D         MOV SI,1D42h
F808BF  BCDC08         MOV SP,8DCh
F808C2  E90615         JMP 1DCBh
F808C5  BE591D         MOV SI,1D59h
F808C8  BCDC08         MOV SP,8DCh
F808CB  E9FD14         JMP 1DCBh
F808CE  26FE06E03F     INC BYTE PTR ES:[3FE0h]
F808D3  BE701D         MOV SI,1D70h
F808D6  BCDC08         MOV SP,8DCh
F808D9  E9EF14         JMP 1DCBh
F808DC  26FE06E03F     INC BYTE PTR ES:[3FE0h]
F808E1  BE861D         MOV SI,1D86h
F808E4  BCEA08         MOV SP,8EAh
F808E7  E9E114         JMP 1DCBh
F808EA  26FE06E03F     INC BYTE PTR ES:[3FE0h]
F808EF  8BF0           MOV SI,AX
```

```
F808F1  FC             CLD
F808F2  B800A4         MOV AX,0A400h
F808F5  8EC0           MOV ES,AX
F808F7  B00B           MOV AL,0Bh                  ; MODE FF1: reg5 := 1 (character-generator RAM access on)
F808F9  E668           OUT 68h,AL
F808FB  B4FF           MOV AH,0FFh
F808FD  BA2056         MOV DX,5620h
F80900  BC0609         MOV SP,906h
F80903  EB25           JMP SHORT 92Ah
F80905  90             NOP
F80906  756A           JNZ  972h
F80908  42             INC DX
F80909  81FA8056       CMP DX,5680h
F8090D  75F1           JNZ  900h
F8090F  BA2057         MOV DX,5720h
F80912  BC1809         MOV SP,918h
F80915  EB13           JMP SHORT 92Ah
F80917  90             NOP
F80918  7558           JNZ  972h
F8091A  42             INC DX
F8091B  81FA8057       CMP DX,5780h
F8091F  75F1           JNZ  912h
F80921  0AE4           OR AH,AH
F80923  7456           JZ   97Bh
F80925  80EC55         SUB AH,55h
F80928  EBD3           JMP SHORT 8FDh
F8092A  8AC2           MOV AL,DL                   ; CG code low / high / line select
F8092C  E6A1           OUT 0A1h,AL
F8092E  8AC6           MOV AL,DH
F80930  E6A3           OUT 0A3h,AL
F80932  B000           MOV AL,00h
F80934  E6A5           OUT 0A5h,AL
F80936  8AC4           MOV AL,AH
F80938  33FF           XOR DI,DI
F8093A  B91000         MOV CX,10h
F8093D  47             INC DI
F8093E  AA             STOSB
F8093F  E2FC           LOOP 93Dh
F80941  B020           MOV AL,20h
F80943  E6A5           OUT 0A5h,AL
F80945  8AC4           MOV AL,AH
F80947  33FF           XOR DI,DI
F80949  B91000         MOV CX,10h
F8094C  47             INC DI
F8094D  AA             STOSB
F8094E  E2FC           LOOP 94Ch
F80950  B000           MOV AL,00h
F80952  E6A5           OUT 0A5h,AL
F80954  8AC4           MOV AL,AH
F80956  33FF           XOR DI,DI
F80958  B91000         MOV CX,10h
F8095B  47             INC DI
F8095C  AE             SCASB
F8095D  E1FC           LOOPE 95Bh
F8095F  750F           JNZ  970h
F80961  B020           MOV AL,20h
F80963  E6A5           OUT 0A5h,AL
F80965  8AC4           MOV AL,AH
F80967  33FF           XOR DI,DI
F80969  B91000         MOV CX,10h
F8096C  47             INC DI
F8096D  AE             SCASB
F8096E  E1FC           LOOPE 96Ch
F80970  FFE4           JMP SP
F80972  BE6D1B         MOV SI,1B6Dh                ; KANJI CG RAM ERROR
F80975  BC7B09         MOV SP,97Bh
F80978  E95014         JMP 1DCBh
F8097B  B00A           MOV AL,0Ah
F8097D  E668           OUT 68h,AL                  ; MODE FF1: reg5 := 0
F8097F  B001           MOV AL,01h                  ; MODE FF2 := 01h
F80981  E66A           OUT 6Ah,AL
F80983  B200           MOV DL,00h
F80985  BC8B09         MOV SP,98Bh
F80988  E9660F         JMP 18F1h
F8098B  BC9109         MOV SP,991h
F8098E  E9600F         JMP 18F1h
F80991  B2FF           MOV DL,0FFh
F80993  BC9909         MOV SP,999h
F80996  E9580F         JMP 18F1h
F80999  BC9F09         MOV SP,99Fh
F8099C  E9950F         JMP 1934h
F8099F  7209           JC   9AAh
F809A1  0AD2           OR DL,DL
F809A3  740E           JZ   9B3h
F809A5  80EA55         SUB DL,55h
F809A8  EBE9           JMP SHORT 993h
F809AA  BE981B         MOV SI,1B98h
F809AD  BCB309         MOV SP,9B3h
F809B0  E91814         JMP 1DCBh
F809B3  B000           MOV AL,00h
F809B5  E67C           OUT 7Ch,AL                  ; GRCG off, MODE FF2 := 00h, draw page := 0
F809B7  E66A           OUT 6Ah,AL
F809B9  E6A6           OUT 0A6h,AL
F809BB  E431           IN AL,31h                   ; 31h bit4
F809BD  A810           TEST AL,10h
F809BF  7439           JZ   9FAh
F809C1  B00D           MOV AL,0Dh                  ; MODE FF1: reg6 := 1 (memory-switch area writable)
F809C3  E668           OUT 68h,AL
F809C5  B800A0         MOV AX,0A000h
F809C8  8EC0           MOV ES,AX
F809CA  B0FF           MOV AL,0FFh
F809CC  B90800         MOV CX,8h
F809CF  BBE23F         MOV BX,3FE2h
F809D2  268A27         MOV AH,ES:[BX]              ; read/modify/verify the memory-switch cells A000:3FE2,3FE6,...
F809D5  268807         MOV ES:[BX],AL
F809D8  263807         CMP ES:[BX],AL
F809DB  268827         MOV ES:[BX],AH
F809DE  750D           JNZ  9EDh
F809E0  83C304         ADD BX,0004h
F809E3  E2ED           LOOP 9D2h
F809E5  0AC0           OR AL,AL
F809E7  740D           JZ   9F6h
F809E9  2C55           SUB AL,55h
F809EB  EBDF           JMP SHORT 9CCh
F809ED  BE821B         MOV SI,1B82h                ; MEMORY SWITCH ERROR
F809F0  BCF609         MOV SP,9F6h
F809F3  E9D513         JMP 1DCBh
F809F6  B00C           MOV AL,0Ch                  ; MODE FF1: reg6 := 0
F809F8  E668           OUT 68h,AL
```

```
F809FA  33DB           XOR BX,BX
F809FC  32F6           XOR DH,DH
F809FE  B008           MOV AL,08h
F80A00  E637           OUT 37h,AL                  ; PPI-C bit4 := 0 (parity check off while filling)
F80A02  33C0           XOR AX,AX
F80A04  BC0A0A         MOV SP,0A0Ah
F80A07  E98D0E         JMP 1897h                   ; fill 128 KB at segment BX with EAX
F80A0A  BC100A         MOV SP,0A10h
F80A0D  E9870E         JMP 1897h
F80A10  B009           MOV AL,09h
F80A12  E637           OUT 37h,AL                  ; PPI-C bit4 := 1 (parity check on)
F80A14  B201           MOV DL,01h
F80A16  8AC2           MOV AL,DL
F80A18  8AE2           MOV AH,DL
F80A1A  BC200A         MOV SP,0A20h
F80A1D  E9770E         JMP 1897h
F80A20  BC260A         MOV SP,0A26h
F80A23  E9980E         JMP 18BEh                   ; verify 128 KB
F80A26  7230           JC   0A58h
F80A28  E433           IN AL,33h                   ; 33h bit2 = parity error latch
F80A2A  A804           TEST AL,04h
F80A2C  7521           JNZ  0A4Fh
F80A2E  B2FF           MOV DL,0FFh
F80A30  8AC2           MOV AL,DL
F80A32  8AE2           MOV AH,DL
F80A34  BC3A0A         MOV SP,0A3Ah
F80A37  E95D0E         JMP 1897h
F80A3A  BC400A         MOV SP,0A40h
F80A3D  E97E0E         JMP 18BEh
F80A40  7216           JC   0A58h
F80A42  E433           IN AL,33h
F80A44  A804           TEST AL,04h
F80A46  7507           JNZ  0A4Fh
F80A48  80EA55         SUB DL,55h
F80A4B  73E3           JNC  0A30h
F80A4D  EB15           JMP SHORT 0A64h
F80A4F  BD550A         MOV BP,0A55h                ; parity error report, then CLI/JMP $
F80A52  E97710         JMP 1ACCh
F80A55  FA             CLI
F80A56  EBFE           JMP SHORT 0A56h
F80A58  83EF04         SUB DI,0004h                ; memory error report, then CLI/JMP $
F80A5B  BD610A         MOV BP,0A61h
F80A5E  E9E00F         JMP 1A41h
F80A61  FA             CLI
F80A62  EBFE           JMP SHORT 0A62h
F80A64  33C0           XOR AX,AX
F80A66  8ED8           MOV DS,AX
F80A68  8BC6           MOV AX,SI
F80A6A  F6C401         TEST AH,01h
F80A6D  7403           JZ   0A72h
F80A6F  80CC20         OR AH,20h
F80A72  D0E4           SHL AH,1
F80A74  D0E4           SHL AH,1
F80A76  80E4E0         AND AH,0E0h
F80A79  88260204       MOV [0402h],AH              ; 0000:0402 := shift/ctrl/graph flags
F80A7D  FC             CLD
F80A7E  8CC8           MOV AX,CS
F80A80  8ED8           MOV DS,AX
F80A82  33C0           XOR AX,AX
F80A84  8EC0           MOV ES,AX
F80A86  33FF           XOR DI,DI
F80A88  BE960A         MOV SI,0A96h                ; copy 200h bytes of stub from CS:0A96 to 0000:0000
F80A8B  B90001         MOV CX,100h
F80A8E  F32EA5         REP MOVSW
F80A91  EA00000000     JMP FAR 0h:0h               ; and run it from RAM
```

### 1.13 `F80A96`–`F80B6F` — the ROM-shadow stub, executed from RAM at `0000:0000`

`F80A88` copies `200h` bytes from `CS:0A96` down to `0000:0000` and
`JMP FAR 0000:0000`. The stub must run from RAM because its first act is to
unmap the ITF ROM.

```
F80A96  33E4           XOR SP,SP                   ; --- ROM shadow stub, executes at 0000:0000 ---
F80A98  BA3D04         MOV DX,43Dh
F80A9B  B012           MOV AL,12h
F80A9D  EE             OUT DX,AL                   ; 043Dh := 12h  -- ITF ROM out, system BIOS ROM in
F80A9E  FC             CLD
F80A9F  B800F8         MOV AX,0F800h
F80AA2  8ED8           MOV DS,AX
F80AA4  33D2           XOR DX,DX                   ; checksum F8000-FFFFF
F80AA6  33F6           XOR SI,SI
F80AA8  B90040         MOV CX,4000h
F80AAB  AD             LODSW
F80AAC  02D0           ADD DL,AL
F80AAE  02F4           ADD DH,AH
F80AB0  E2F9           LOOP 0AABh
F80AB2  0BD2           OR DX,DX
F80AB4  F9             STC
F80AB5  7403           JZ   0ABAh
F80AB7  E9A500         JMP 0B5Fh
F80ABA  B800E8         MOV AX,0E800h
F80ABD  8ED8           MOV DS,AX
F80ABF  33D2           XOR DX,DX
F80AC1  33F6           XOR SI,SI                   ; checksum E8000-F7FFF
F80AC3  B90080         MOV CX,8000h
F80AC6  AD             LODSW
F80AC7  02D0           ADD DL,AL
F80AC9  02F4           ADD DH,AH
F80ACB  E2F9           LOOP 0AC6h
F80ACD  0BD2           OR DX,DX
F80ACF  F9             STC
F80AD0  7403           JZ   0AD5h
F80AD2  E98A00         JMP 0B5Fh
F80AD5  F8             CLC
F80AD6  0BE4           OR SP,SP                    ; first pass?
F80AD8  7403           JZ   0ADDh
F80ADA  E98200         JMP 0B5Fh
F80ADD  BA3F04         MOV DX,43Fh
F80AE0  B080           MOV AL,80h
F80AE2  EE             OUT DX,AL                   ; 043Fh := 80h
F80AE3  BA6104         MOV DX,461h
F80AE6  B00E           MOV AL,0Eh
F80AE8  EE             OUT DX,AL                   ; 0461h := 0Eh (shadow RAM writable)
F80AE9  FC             CLD
F80AEA  B80098         MOV AX,9800h
F80AED  8EC0           MOV ES,AX
F80AEF  B800F8         MOV AX,0F800h
F80AF2  8ED8           MOV DS,AX
F80AF4  33FF           XOR DI,DI
F80AF6  33F6           XOR SI,SI
F80AF8  B90040         MOV CX,4000h
F80AFB  F3A5           REP MOVSW                   ; F8000-FFFFF -> 98000
F80AFD  B80088         MOV AX,8800h
F80B00  8EC0           MOV ES,AX
F80B02  B800E8         MOV AX,0E800h
F80B05  8ED8           MOV DS,AX
F80B07  33FF           XOR DI,DI
F80B09  33F6           XOR SI,SI
F80B0B  B90080         MOV CX,8000h
F80B0E  F3A5           REP MOVSW                   ; E8000-F7FFF -> 88000
F80B10  FC             CLD
F80B11  BA6104         MOV DX,461h
F80B14  B00C           MOV AL,0Ch
F80B16  EE             OUT DX,AL                   ; 0461h := 0Ch
F80B17  E4F0           IN AL,0F0h                  ; 0F0h bit5
F80B19  A820           TEST AL,20h
F80B1B  7528           JNZ  0B45h
F80B1D  BA3D05         MOV DX,53Dh
F80B20  B040           MOV AL,40h
F80B22  EE             OUT DX,AL                   ; 053Dh := 40h
F80B23  B80097         MOV AX,9700h
F80B26  8EC0           MOV ES,AX
F80B28  B800D7         MOV AX,0D700h
F80B2B  8ED8           MOV DS,AX
F80B2D  33FF           XOR DI,DI
F80B2F  33F6           XOR SI,SI
F80B31  B90008         MOV CX,800h
F80B34  F3A5           REP MOVSW                   ; D7000 -> 97000
F80B36  BA3D05         MOV DX,53Dh
F80B39  B000           MOV AL,00h
F80B3B  EE             OUT DX,AL
F80B3C  BA3F04         MOV DX,43Fh
F80B3F  B0C2           MOV AL,0C2h
F80B41  EE             OUT DX,AL                   ; 043Fh := C2h
F80B42  EB01           JMP SHORT 0B45h
F80B44  90             NOP
F80B45  BADB7F         MOV DX,7FDBh
F80B48  EC             IN AL,DX                    ; 7FDBh bit6
F80B49  A840           TEST AL,40h
F80B4B  B080           MOV AL,80h
F80B4D  7502           JNZ  0B51h
F80B4F  B082           MOV AL,82h
F80B51  BA3F04         MOV DX,43Fh
F80B54  EE             OUT DX,AL                   ; 043Fh := 80h or 82h
F80B55  BA3D05         MOV DX,53Dh
F80B58  B002           MOV AL,02h
F80B5A  EE             OUT DX,AL                   ; 053Dh := 02h
F80B5B  44             INC SP
F80B5C  E93FFF         JMP 0A9Eh                   ; second pass: re-verify with the shadow active
F80B5F  BA6104         MOV DX,461h
F80B62  B008           MOV AL,08h
F80B64  EE             OUT DX,AL                   ; 0461h := 08h
F80B65  BA3D04         MOV DX,43Dh
F80B68  B010           MOV AL,10h
F80B6A  EE             OUT DX,AL                   ; 043Dh := 10h  -- ITF ROM back in
F80B6B  EA700B00F8     JMP FAR 0F800h:0B70h        ; back into ROM
```

It runs twice (`SP` is the pass counter): pass 1 checksums the real BIOS ROM at
`F8000` and `E8000`, copies both into the shadow RAM at `98000` and `88000`,
optionally copies `D7000`→`97000`, and re-enters; pass 2 re-checksums with the
shadow active. Any bad checksum sets CF and exits to `F80B5F`, which maps the
ITF back in (`043Dh := 10h`) and far-jumps to `F800:0B70`, where CF selects the
`ROM SUM ERROR` message.

### 1.14 `F80B70`–`F80D93` — bank memory, A20, PIT, DMA, PIC and IRQ0 tests

```
F80B70  7309           JNC  0B7Bh                  ; CF set by the stub => ROM SUM ERROR
F80B72  BE461B         MOV SI,1B46h
F80B75  BC7B0B         MOV SP,0B7Bh
F80B78  E95012         JMP 1DCBh
F80B7B  6633C0         XOR EAX,EAX
F80B7E  8ED8           MOV DS,AX
F80B80  8EC0           MOV ES,AX
F80B82  33FF           XOR DI,DI
F80B84  B94000         MOV CX,40h
F80B87  66F3AB         REP STOSD
F80B8A  BA3F04         MOV DX,43Fh
F80B8D  B022           MOV AL,22h
F80B8F  EE             OUT DX,AL                   ; 043Fh := 22h (window in)
F80B90  BB00B0         MOV BX,0B000h
F80B93  8EC3           MOV ES,BX
F80B95  33FF           XOR DI,DI
F80B97  26C70555AA     MOV WORD PTR ES:[DI],0AA55h
F80B9C  26C70555AA     MOV WORD PTR ES:[DI],0AA55h
F80BA1  BA3F04         MOV DX,43Fh
F80BA4  B020           MOV AL,20h
F80BA6  EE             OUT DX,AL                   ; 043Fh := 20h (window out)
F80BA7  26813D55AA     CMP WORD PTR ES:[DI],0AA55h ; B000:0 must have kept AA55h -> bank memory present
F80BAC  7405           JZ   0BB3h
F80BAE  B022           MOV AL,22h
F80BB0  EE             OUT DX,AL
F80BB1  EB08           JMP SHORT 0BBBh
F80BB3  26C7050000     MOV WORD PTR ES:[DI],0h
F80BB8  EB69           JMP SHORT 0C23h
F80BBA  90             NOP
F80BBB  B008           MOV AL,08h
F80BBD  E637           OUT 37h,AL                  ; PPI-C bit4 := 0
F80BBF  FC             CLD
F80BC0  6633C0         XOR EAX,EAX
F80BC3  BCC90B         MOV SP,0BC9h
F80BC6  EB66           JMP SHORT 0C2Eh             ; fill/verify the 64 KB bank window
F80BC8  90             NOP
F80BC9  BCCF0B         MOV SP,0BCFh
F80BCC  EB60           JMP SHORT 0C2Eh
F80BCE  90             NOP
F80BCF  B009           MOV AL,09h
F80BD1  E637           OUT 37h,AL
F80BD3  B201           MOV DL,01h
F80BD5  8AC2           MOV AL,DL
F80BD7  8AE2           MOV AH,DL
F80BD9  8BF8           MOV DI,AX
F80BDB  66C1E010       SHL EAX,10h
F80BDF  8BC7           MOV AX,DI
F80BE1  BCE70B         MOV SP,0BE7h
F80BE4  EB48           JMP SHORT 0C2Eh
F80BE6  90             NOP
F80BE7  BCED0B         MOV SP,0BEDh
F80BEA  EB4C           JMP SHORT 0C38h
F80BEC  90             NOP
F80BED  7234           JC   0C23h
F80BEF  E433           IN AL,33h                   ; parity
F80BF1  A804           TEST AL,04h
F80BF3  752E           JNZ  0C23h
F80BF5  B2FF           MOV DL,0FFh
F80BF7  8AC2           MOV AL,DL
F80BF9  8AE2           MOV AH,DL
F80BFB  8BF8           MOV DI,AX
F80BFD  66C1E010       SHL EAX,10h
F80C01  8BC7           MOV AX,DI
F80C03  BC090C         MOV SP,0C09h
F80C06  EB26           JMP SHORT 0C2Eh
F80C08  90             NOP
F80C09  BC0F0C         MOV SP,0C0Fh
F80C0C  EB2A           JMP SHORT 0C38h
F80C0E  90             NOP
F80C0F  7212           JC   0C23h
F80C11  E433           IN AL,33h
F80C13  A804           TEST AL,04h
F80C15  750C           JNZ  0C23h
F80C17  80EA55         SUB DL,55h
F80C1A  73DB           JNC  0BF7h
F80C1C  800E810420     OR BYTE PTR [0481h],20h
F80C21  EB25           JMP SHORT 0C48h
F80C23  BEB31B         MOV SI,1BB3h                ; EMS ERROR
F80C26  BC2C0C         MOV SP,0C2Ch
F80C29  E99F11         JMP 1DCBh
F80C2C  EB1A           JMP SHORT 0C48h
F80C2E  33FF           XOR DI,DI
F80C30  B90040         MOV CX,4000h
F80C33  66F3AB         REP STOSD
F80C36  FFE4           JMP SP
F80C38  33FF           XOR DI,DI
F80C3A  B90040         MOV CX,4000h
F80C3D  66F3AF         REP SCASD
F80C40  7503           JNZ  0C45h
F80C42  F8             CLC
F80C43  FFE4           JMP SP
F80C45  F9             STC
F80C46  FFE4           JMP SP
F80C48  BA3F04         MOV DX,43Fh
F80C4B  B020           MOV AL,20h
F80C4D  EE             OUT DX,AL                   ; 043Fh := 20h
```

```
F80C4E  33C0           XOR AX,AX
F80C50  8ED8           MOV DS,AX
F80C52  2EC7060080AA55 MOV WORD PTR CS:[8000h],55AAh; --- A20 test: write F800:8000 (linear 100000h) ---
F80C59  813E0000AA55   CMP WORD PTR [0000h],55AAh  ; 0000:0000 must NOT have changed
F80C5F  740A           JZ   0C6Bh
F80C61  BEF61B         MOV SI,1BF6h                ; ADDRESS 20 LINE ERROR, then HLT
F80C64  BC6A0C         MOV SP,0C6Ah
F80C67  E96111         JMP 1DCBh
F80C6A  F4             HLT
F80C6B  C70600000000   MOV WORD PTR [0000h],0h
F80C71  B006           MOV AL,06h
F80C73  E637           OUT 37h,AL                  ; PPI-C bit3 := 0
F80C75  BB1000         MOV BX,10h
F80C78  BE5040         MOV SI,4050h
F80C7B  BF9080         MOV DI,8090h
F80C7E  B90300         MOV CX,3h
F80C81  BA7100         MOV DX,71h
F80C84  BDFFFF         MOV BP,0FFFFh
F80C87  8AC3           MOV AL,BL                   ; --- 8253 read-back test on counters 0,1,2 ---
F80C89  E677           OUT 77h,AL                  ; control: 10h/50h/90h = counter n, LSB only, mode 0
F80C8B  EB00           JMP SHORT 0C8Dh
F80C8D  EB00           JMP SHORT 0C8Fh
F80C8F  8BC5           MOV AX,BP
F80C91  EE             OUT DX,AL
F80C92  EB00           JMP SHORT 0C94h
F80C94  EB00           JMP SHORT 0C96h
F80C96  8AC7           MOV AL,BH
F80C98  E677           OUT 77h,AL                  ; control: 00h/40h/80h = latch counter n
F80C9A  EB00           JMP SHORT 0C9Ch
F80C9C  EB00           JMP SHORT 0C9Eh
F80C9E  EC             IN AL,DX
F80C9F  3AE0           CMP AH,AL
F80CA1  750A           JNZ  0CADh
F80CA3  BE471C         MOV SI,1C47h                ; TIMER ERROR, then HLT
F80CA6  BCAC0C         MOV SP,0CACh
F80CA9  E91F11         JMP 1DCBh
F80CAC  F4             HLT
F80CAD  80FC00         CMP AH,00h
F80CB0  7405           JZ   0CB7h
F80CB2  BD0000         MOV BP,0h
F80CB5  EBD0           JMP SHORT 0C87h
F80CB7  42             INC DX
F80CB8  42             INC DX
F80CB9  8BDE           MOV BX,SI
F80CBB  8BF7           MOV SI,DI
F80CBD  E2C5           LOOP 0C84h
F80CBF  B007           MOV AL,07h
F80CC1  E637           OUT 37h,AL
F80CC3  BCC90C         MOV SP,0CC9h
F80CC6  E9D5F8         JMP 59Eh                    ; re-run the PIT setup
F80CC9  E61B           OUT 1Bh,AL                  ; 01Bh: DMA master clear
F80CCB  B0FF           MOV AL,0FFh
F80CCD  BA0100         MOV DX,1h
F80CD0  B90800         MOV CX,8h
F80CD3  8AD8           MOV BL,AL
F80CD5  8AFB           MOV BH,BL
F80CD7  EE             OUT DX,AL                   ; --- 8237 register read-back on 01,03,05,07,09,0B,0D,0F ---
F80CD8  EB00           JMP SHORT 0CDAh
F80CDA  EE             OUT DX,AL
F80CDB  EB00           JMP SHORT 0CDDh
F80CDD  EC             IN AL,DX
F80CDE  8AE0           MOV AH,AL
F80CE0  EC             IN AL,DX
F80CE1  3BD8           CMP BX,AX
F80CE3  750C           JNZ  0CF1h
F80CE5  42             INC DX
F80CE6  42             INC DX
F80CE7  E2EE           LOOP 0CD7h
F80CE9  0AC0           OR AL,AL
F80CEB  740E           JZ   0CFBh
F80CED  B000           MOV AL,00h
F80CEF  EBDC           JMP SHORT 0CCDh
F80CF1  BE551C         MOV SI,1C55h                ; DMA ERROR, then HLT
F80CF4  BCFA0C         MOV SP,0CFAh
F80CF7  E9D110         JMP 1DCBh
F80CFA  F4             HLT
F80CFB  B040           MOV AL,40h
F80CFD  E611           OUT 11h,AL                  ; DMA command register := 40h
F80CFF  FA             CLI
F80D00  B80000         MOV AX,0h
F80D03  E602           OUT 02h,AL                  ; --- 8259 IMR read-back, master 02h and slave 0Ah ---
F80D05  EB00           JMP SHORT 0D07h
F80D07  E402           IN AL,02h
F80D09  3AE0           CMP AH,AL
F80D0B  740A           JZ   0D17h
F80D0D  BE611C         MOV SI,1C61h                ; TIMER INTERRUPT ERROR, then HLT
F80D10  BC160D         MOV SP,0D16h
F80D13  E9B510         JMP 1DCBh
F80D16  F4             HLT
F80D17  E60A           OUT 0Ah,AL
F80D19  EB00           JMP SHORT 0D1Bh
F80D1B  E40A           IN AL,0Ah
F80D1D  3AE0           CMP AH,AL
F80D1F  740A           JZ   0D2Bh
F80D21  BE611C         MOV SI,1C61h
F80D24  BC2A0D         MOV SP,0D2Ah
F80D27  E9A110         JMP 1DCBh
F80D2A  F4             HLT
F80D2B  0BC0           OR AX,AX
F80D2D  7504           JNZ  0D33h
F80D2F  F7D0           NOT AX
F80D31  EBD0           JMP SHORT 0D03h
F80D33  33C0           XOR AX,AX
F80D35  8EC0           MOV ES,AX
F80D37  FC             CLD
F80D38  BF2000         MOV DI,20h                  ; IRQ0 vector 0000:0020 := F800:0D89
F80D3B  B8890D         MOV AX,0D89h
F80D3E  AB             STOSW
F80D3F  8CC8           MOV AX,CS
F80D41  AB             STOSW
F80D42  B92000         MOV CX,20h
F80D45  32E4           XOR AH,AH
F80D47  FB             STI                         ; IMR is still FFh: no interrupt may arrive
F80D48  F6C4FF         TEST AH,0FFh
F80D4B  740A           JZ   0D57h
F80D4D  BE611C         MOV SI,1C61h
F80D50  BC560D         MOV SP,0D56h
F80D53  E97510         JMP 1DCBh
F80D56  F4             HLT
F80D57  E2EF           LOOP 0D48h
F80D59  B01A           MOV AL,1Ah                  ; counter0 := 001Ah
F80D5B  E671           OUT 71h,AL
F80D5D  33C0           XOR AX,AX
F80D5F  EB00           JMP SHORT 0D61h
F80D61  EB00           JMP SHORT 0D63h
F80D63  E671           OUT 71h,AL
F80D65  B92000         MOV CX,20h
F80D68  B0FE           MOV AL,0FEh
F80D6A  E602           OUT 02h,AL                  ; master IMR := FEh -- unmask IRQ0
F80D6C  F6C4FF         TEST AH,0FFh                ; --- IRQ0 must now fire within 32 polls ---
F80D6F  750C           JNZ  0D7Dh
F80D71  E2F9           LOOP 0D6Ch
F80D73  BE611C         MOV SI,1C61h                ; TIMER INTERRUPT ERROR, then HLT
F80D76  BC7C0D         MOV SP,0D7Ch
F80D79  E94F10         JMP 1DCBh
F80D7C  F4             HLT
F80D7D  32C0           XOR AL,AL
F80D7F  E671           OUT 71h,AL
F80D81  EB00           JMP SHORT 0D83h
F80D83  EB00           JMP SHORT 0D85h
F80D85  E671           OUT 71h,AL
F80D87  EB0B           JMP SHORT 0D94h
F80D89  B4FF           MOV AH,0FFh                 ; IRQ0 handler: AH=FF, mask everything again, EOI
F80D8B  B0FF           MOV AL,0FFh
F80D8D  E602           OUT 02h,AL
F80D8F  B020           MOV AL,20h
F80D91  E600           OUT 00h,AL
F80D93  CF             IRET
```

Three of these are absolute gates, each ending in `HLT`:

* **A20 (`F80C52`)** — writes `55AAh` to `CS:[8000h]` = `F800:8000` = linear
  `100000h` and requires `0000:0000` to be unchanged. A 20-bit-wrapping address
  bus fails here with `ADDRESS 20 LINE ERROR`.
* **8237 (`F80CD7`)** — writes `FFh`/`00h` twice into each of `01,03,05,07,09,0B,0D,0F`
  and reads each back twice; the 16-bit value must match. `DMA ERROR`.
* **IRQ0 (`F80D38`)** — installs a handler at `0000:0020`, checks that *no*
  interrupt arrives while the master IMR is `FFh`, then sets counter 0 to
  `001Ah`, writes `FEh` to the master IMR and requires the interrupt to arrive
  within 32 polls. `TIMER INTERRUPT ERROR`.

### 1.15 `F80D94`–`F80F62` — memory-switch defaults, extended-memory sizing, protected mode

```
F80D94  E431           IN AL,31h                   ; 31h bit4
F80D96  A810           TEST AL,10h
F80D98  7440           JZ   0DDAh
F80D9A  B00D           MOV AL,0Dh
F80D9C  E668           OUT 68h,AL                  ; MODE FF1: reg6 := 1
F80D9E  B800A0         MOV AX,0A000h
F80DA1  8EC0           MOV ES,AX
F80DA3  BBE03F         MOV BX,3FE0h
F80DA6  26C6470248     MOV BYTE PTR ES:[BX+02h],48h
F80DAB  26C6470605     MOV BYTE PTR ES:[BX+06h],05h
F80DB0  26C6470A04     MOV BYTE PTR ES:[BX+0Ah],04h
F80DB5  BADB7F         MOV DX,7FDBh
F80DB8  EC             IN AL,DX                    ; 7FDBh bit6
F80DB9  A840           TEST AL,40h
F80DBB  7505           JNZ  0DC2h
F80DBD  26C6470A03     MOV BYTE PTR ES:[BX+0Ah],03h
F80DC2  26C6470E00     MOV BYTE PTR ES:[BX+0Eh],00h
F80DC7  26C6471201     MOV BYTE PTR ES:[BX+12h],01h
F80DCC  26806716C0     AND BYTE PTR ES:[BX+16h],0C0h
F80DD1  26C6471A00     MOV BYTE PTR ES:[BX+1Ah],00h
F80DD6  B00C           MOV AL,0Ch
F80DD8  E668           OUT 68h,AL                  ; MODE FF1: reg6 := 0
F80DDA  33C0           XOR AX,AX
F80DDC  8ED8           MOV DS,AX
F80DDE  BB0020         MOV BX,2000h
F80DE1  B602           MOV DH,02h
F80DE3  BDE90D         MOV BP,0DE9h                ; "MEMORY 000KB OK" then size the extended memory from segment 2000h up
F80DE6  E9D60B         JMP 19BFh
F80DE9  B800A0         MOV AX,0A000h
F80DEC  8EC0           MOV ES,AX
F80DEE  26A0EA3F       MOV AL,ES:[3FEAh]
F80DF2  2407           AND AL,07h
F80DF4  FEC0           INC AL
F80DF6  D0E0           SHL AL,1
F80DF8  3AF0           CMP DH,AL
F80DFA  7503           JNZ  0DFFh
F80DFC  E99400         JMP 0E93h
F80DFF  B008           MOV AL,08h
F80E01  E637           OUT 37h,AL                  ; PPI-C bit4 := 0 / 1 around each 128 KB block
F80E03  33C0           XOR AX,AX
F80E05  BC0B0E         MOV SP,0E0Bh
F80E08  E98C0A         JMP 1897h
F80E0B  BC110E         MOV SP,0E11h
F80E0E  E9860A         JMP 1897h
F80E11  B009           MOV AL,09h
F80E13  E637           OUT 37h,AL
F80E15  B201           MOV DL,01h
F80E17  8AC2           MOV AL,DL
F80E19  8AE2           MOV AH,DL
F80E1B  BC210E         MOV SP,0E21h
F80E1E  E9760A         JMP 1897h
F80E21  BC270E         MOV SP,0E27h
F80E24  E9970A         JMP 18BEh
F80E27  7257           JC   0E80h
F80E29  E433           IN AL,33h
F80E2B  A804           TEST AL,04h
F80E2D  7548           JNZ  0E77h
F80E2F  B2FF           MOV DL,0FFh
F80E31  8AC2           MOV AL,DL
F80E33  8AE2           MOV AH,DL
F80E35  BC3B0E         MOV SP,0E3Bh
F80E38  E95C0A         JMP 1897h
F80E3B  BC410E         MOV SP,0E41h
F80E3E  E97D0A         JMP 18BEh
F80E41  723D           JC   0E80h
F80E43  E433           IN AL,33h
F80E45  A804           TEST AL,04h
F80E47  752E           JNZ  0E77h
F80E49  80EA55         SUB DL,55h
F80E4C  73E3           JNC  0E31h
F80E4E  81C30020       ADD BX,2000h
F80E52  FEC6           INC DH
F80E54  FEC6           INC DH
F80E56  BD5C0E         MOV BP,0E5Ch
F80E59  E9630B         JMP 19BFh
F80E5C  B800A0         MOV AX,0A000h
F80E5F  8EC0           MOV ES,AX
F80E61  26A0EA3F       MOV AL,ES:[3FEAh]
F80E65  2407           AND AL,07h
F80E67  3C05           CMP AL,05h
F80E69  7202           JC   0E6Dh
F80E6B  B004           MOV AL,04h
F80E6D  FEC0           INC AL
F80E6F  D0E0           SHL AL,1
F80E71  3AF0           CMP DH,AL
F80E73  758A           JNZ  0DFFh
F80E75  EB1C           JMP SHORT 0E93h
F80E77  BD7D0E         MOV BP,0E7Dh
F80E7A  E94F0C         JMP 1ACCh
F80E7D  EB14           JMP SHORT 0E93h
F80E7F  90             NOP
F80E80  83EF04         SUB DI,0004h
F80E83  BD890E         MOV BP,0E89h
F80E86  E9B80B         JMP 1A41h
F80E89  B800A0         MOV AX,0A000h
F80E8C  8EC0           MOV ES,AX
F80E8E  26FE06E03F     INC BYTE PTR ES:[3FE0h]
```

```
F80E93  33C0           XOR AX,AX
F80E95  8ED8           MOV DS,AX
F80E97  D0EE           SHR DH,1
F80E99  FECE           DEC DH
F80E9B  08360105       OR [0501h],DH
F80E9F  E442           IN AL,42h                   ; 42h bit1: 1 -> skip the protected-mode test
F80EA1  A802           TEST AL,02h
F80EA3  7403           JZ   0EA8h
F80EA5  E90C04         JMP 12B4h
F80EA8  FA             CLI
F80EA9  BC3000         MOV SP,30h
F80EAC  8ED4           MOV SS,SP
F80EAE  BCFE00         MOV SP,0FEh
F80EB1  33C0           XOR AX,AX
F80EB3  8ED8           MOV DS,AX
F80EB5  8EC0           MOV ES,AX
F80EB7  FC             CLD
F80EB8  B8FFFF         MOV AX,0FFFFh
F80EBB  BF0080         MOV DI,8000h
F80EBE  B90500         MOV CX,5h
F80EC1  F3AB           REP STOSW
F80EC3  BD0080         MOV BP,8000h
F80EC6  260F015E00     LIDT ES:[BP+00h]            ; LIDT/LGDT/SIDT/SGDT walking-bit test of the descriptor registers
F80ECB  BD0580         MOV BP,8005h
F80ECE  260F015600     LGDT ES:[BP+00h]
F80ED3  BD0090         MOV BP,9000h
F80ED6  260F014E00     SIDT ES:[BP+00h]
F80EDB  BD0590         MOV BP,9005h
F80EDE  260F014600     SGDT ES:[BP+00h]
F80EE3  BF0090         MOV DI,9000h
F80EE6  B90500         MOV CX,5h
F80EE9  F3AF           REP SCASW
F80EEB  7403           JZ   0EF0h
F80EED  E97303         JMP 1263h
F80EF0  0BC0           OR AX,AX
F80EF2  7405           JZ   0EF9h
F80EF4  2D5555         SUB AX,5555h
F80EF7  EBC2           JMP SHORT 0EBBh
F80EF9  FC             CLD
F80EFA  0E             PUSH CS
F80EFB  1F             POP DS
F80EFC  BE630F         MOV SI,0F63h
F80EFF  BF0080         MOV DI,8000h
F80F02  B94000         MOV CX,40h
F80F05  F3A5           REP MOVSW
F80F07  BEE30F         MOV SI,0FE3h
F80F0A  BF0090         MOV DI,9000h
F80F0D  B92000         MOV CX,20h
F80F10  A5             MOVSW
F80F11  B83800         MOV AX,38h
F80F14  AB             STOSW
F80F15  B80087         MOV AX,8700h
F80F18  AB             STOSW
F80F19  33C0           XOR AX,AX
F80F1B  AB             STOSW
F80F1C  E2F2           LOOP 0F10h
F80F1E  B9E000         MOV CX,0E0h
F80F21  B85D10         MOV AX,105Dh
F80F24  AB             STOSW
F80F25  B83800         MOV AX,38h
F80F28  AB             STOSW
F80F29  B80086         MOV AX,8600h
F80F2C  AB             STOSW
F80F2D  33C0           XOR AX,AX
F80F2F  AB             STOSW
F80F30  E2EF           LOOP 0F21h
F80F32  06             PUSH ES
F80F33  1F             POP DS
F80F34  0F011E1080     LIDT [8010h]
F80F39  0F01160880     LGDT [8008h]
F80F3E  33C0           XOR AX,AX
F80F40  8ED8           MOV DS,AX
F80F42  E6F2           OUT 0F2h,AL                 ; 0F2h := 00h, 0F6h := 02h  (A20 / protected-mode gate)
F80F44  B002           MOV AL,02h
F80F46  E6F6           OUT 0F6h,AL
F80F48  0E             PUSH CS
F80F49  686C12         PUSH 126Ch
F80F4C  8C160604       MOV [0406h],SS
F80F50  89260404       MOV [0404h],SP
F80F54  B00E           MOV AL,0Eh                  ; PPI-C bit7 := 0  -- arm the shutdown-return path
F80F56  E637           OUT 37h,AL
F80F58  B80100         MOV AX,1h
F80F5B  0F01F0         LMSW AX                     ; enter protected mode
F80F5E  EA64103800     JMP FAR 38h:1064h           ; unresolved: protected-mode code, selector 38h offset 1064h
```

`F80F5E` is the first unresolved transfer: protected-mode code at selector
`38h`, offset `1064h`. It returns by resetting the CPU (`F81263` /
`F81E98` / `F81E9D` all do `OUT 0F0h` + `HLT`) and coming back through the
`0000:0404` shutdown vector.

### 1.16 `F81263`–`F81312` — protected-mode return paths

```
F81263  B00B           MOV AL,0Bh                  ; PROTECTED MODE ERROR path: PPI-C bit5 := 1 then 0F0h := 00h (CPU reset)
F81265  E637           OUT 37h,AL
F81267  EB00           JMP SHORT 1269h
F81269  E92C0C         JMP 1E98h
```

```
F812B4  E442           IN AL,42h                   ; 42h bit1
F812B6  A802           TEST AL,02h
F812B8  7508           JNZ  12C2h
F812BA  BADD7F         MOV DX,7FDDh
F812BD  EC             IN AL,DX                    ; 7FDDh bit2 (V30 mode)
F812BE  A804           TEST AL,04h
F812C0  7403           JZ   12C5h
F812C2  E98604         JMP 174Bh                   ; -> final configuration
F812C5  FA             CLI
F812C6  BC3000         MOV SP,30h
F812C9  8ED4           MOV SS,SP
F812CB  BCFE00         MOV SP,0FEh
F812CE  33C0           XOR AX,AX
F812D0  8ED8           MOV DS,AX
F812D2  8EC0           MOV ES,AX
F812D4  FC             CLD
F812D5  0E             PUSH CS
F812D6  1F             POP DS
F812D7  BE1614         MOV SI,1416h
F812DA  BF0080         MOV DI,8000h
F812DD  B94000         MOV CX,40h
F812E0  F3A5           REP MOVSW
F812E2  06             PUSH ES
F812E3  1F             POP DS
F812E4  0F011E1080     LIDT [8010h]
F812E9  0F01160880     LGDT [8008h]
F812EE  33C0           XOR AX,AX
F812F0  8ED8           MOV DS,AX
F812F2  E6F2           OUT 0F2h,AL
F812F4  B002           MOV AL,02h
F812F6  E6F6           OUT 0F6h,AL
F812F8  0E             PUSH CS
F812F9  681617         PUSH 1716h
F812FC  8C160604       MOV [0406h],SS
F81300  89260404       MOV [0404h],SP
F81304  B00E           MOV AL,0Eh
F81306  E637           OUT 37h,AL
F81308  B80100         MOV AX,1h
F8130B  0F01F0         LMSW AX
F8130E  EA9D153800     JMP FAR 38h:159Dh           ; unresolved: second protected-mode entry, selector 38h offset 159Dh
```

### 1.17 `F8174B`–`F81896` — final configuration and the hand-over

```
F8174B  33C0           XOR AX,AX                   ; --- final configuration and hand-over ---
F8174D  8ED8           MOV DS,AX
F8174F  BC3000         MOV SP,30h
F81752  8ED4           MOV SS,SP
F81754  BCFE00         MOV SP,0FEh
F81757  B400           MOV AH,00h
F81759  BD5F17         MOV BP,175Fh                ; keyboard: send 00h
F8175C  E9C2EE         JMP 621h
F8175F  B204           MOV DL,04h
F81761  B49F           MOV AH,9Fh                  ; keyboard: send 9Fh (read ID), expect FAh then A0h then 80h
F81763  BD6917         MOV BP,1769h
F81766  E9B8EE         JMP 621h
F81769  BD6F17         MOV BP,176Fh
F8176C  E9E6EE         JMP 655h
F8176F  742C           JZ   179Dh
F81771  3CFA           CMP AL,0FAh
F81773  740B           JZ   1780h
F81775  3CFC           CMP AL,0FCh
F81777  74E8           JZ   1761h
F81779  FECA           DEC DL
F8177B  75E4           JNZ  1761h
F8177D  EB1E           JMP SHORT 179Dh
F8177F  90             NOP
F81780  BD8617         MOV BP,1786h
F81783  E9CFEE         JMP 655h
F81786  7415           JZ   179Dh
F81788  3CA0           CMP AL,0A0h
F8178A  7511           JNZ  179Dh
F8178C  BD9217         MOV BP,1792h
F8178F  E9C3EE         JMP 655h
F81792  7409           JZ   179Dh
F81794  3C80           CMP AL,80h
F81796  7505           JNZ  179Dh
F81798  800E810440     OR BYTE PTR [0481h],40h     ; 0000:0481 bit6 := 1 (new-type keyboard)
F8179D  BADB7F         MOV DX,7FDBh
F817A0  EC             IN AL,DX                    ; 7FDBh bit6
F817A1  A840           TEST AL,40h
F817A3  B080           MOV AL,80h
F817A5  7502           JNZ  17A9h
F817A7  B082           MOV AL,82h
F817A9  BA3F04         MOV DX,43Fh
F817AC  EE             OUT DX,AL                   ; 043Fh := 80h or 82h, then 20h
F817AD  B020           MOV AL,20h
F817AF  EE             OUT DX,AL
F817B0  E4F0           IN AL,0F0h                  ; 0F0h bit6
F817B2  A840           TEST AL,40h
F817B4  750F           JNZ  17C5h
F817B6  BAC40C         MOV DX,0CC4h
F817B9  EC             IN AL,DX                    ; 0CC4h bits0-1 -> 0000:0484
F817BA  2403           AND AL,03h
F817BC  C0E006         SHL AL,06h
F817BF  0C20           OR AL,20h
F817C1  08068404       OR [0484h],AL
F817C5  B406           MOV AH,06h
F817C7  E4F0           IN AL,0F0h                  ; 0F0h bit5
F817C9  A820           TEST AL,20h
F817CB  7503           JNZ  17D0h
F817CD  80CC40         OR AH,40h
F817D0  8AC4           MOV AL,AH
F817D2  BA3D05         MOV DX,53Dh
F817D5  EE             OUT DX,AL                   ; 053Dh := 06h or 46h
F817D6  EB00           JMP SHORT 17D8h
F817D8  B008           MOV AL,08h
F817DA  BA6104         MOV DX,461h
F817DD  EE             OUT DX,AL                   ; 0461h := 08h
F817DE  EB00           JMP SHORT 17E0h
F817E0  BADD7F         MOV DX,7FDDh
F817E3  EC             IN AL,DX                    ; 7FDDh bit2: in 386 mode ...
F817E4  A804           TEST AL,04h
F817E6  7413           JZ   17FBh
F817E8  B00E           MOV AL,0Eh
F817EA  E637           OUT 37h,AL                  ; PPI-C bit7 := 0
F817EC  0E             PUSH CS
F817ED  68FB17         PUSH 17FBh
F817F0  8C160604       MOV [0406h],SS              ; ... save SS:SP at 0000:0404/0406 ...
F817F4  89260404       MOV [0404h],SP
F817F8  E9A206         JMP 1E9Dh                   ; ... and reset the CPU; execution resumes at 17FB through 0000:0404
F817FB  33C0           XOR AX,AX
F817FD  8ED8           MOV DS,AX
F817FF  E442           IN AL,42h                   ; 42h -> 0000:0500 machine-type byte
F81801  8AE0           MOV AH,AL
F81803  D0EC           SHR AH,1
F81805  D0EC           SHR AH,1
F81807  80E430         AND AH,30h
F8180A  80CC40         OR AH,40h
F8180D  A802           TEST AL,02h
F8180F  751D           JNZ  182Eh
F81811  80E4BF         AND AH,0BFh
F81814  800E800403     OR BYTE PTR [0480h],03h
F81819  800E000402     OR BYTE PTR [0400h],02h
F8181E  A820           TEST AL,20h
F81820  7507           JNZ  1829h
F81822  800E840402     OR BYTE PTR [0484h],02h
F81827  EB08           JMP SHORT 1831h
F81829  800E000404     OR BYTE PTR [0400h],04h
F8182E  80CC80         OR AH,80h
F81831  8026010507     AND BYTE PTR [0501h],07h
F81836  B001           MOV AL,01h
F81838  09060005       OR [0500h],AX
F8183C  800E800440     OR BYTE PTR [0480h],40h
F81841  E442           IN AL,42h                   ; 42h bit1 clear -> probe for a 387
F81843  A802           TEST AL,02h
F81845  7513           JNZ  185Ah
F81847  DBE3           ESC 3,BX                    ; FNINIT / FNSTSW AX
F81849  9B             WAIT
F8184A  DFE0           ESC 7,AX
F8184C  0AC0           OR AL,AL
F8184E  750A           JNZ  185Ah
F81850  0F01E0         SMSW AX                     ; set MP in CR0 if a coprocessor answered
F81853  0C02           OR AL,02h
F81855  0F01F0         LMSW AX
F81858  EB00           JMP SHORT 185Ah
F8185A  33C0           XOR AX,AX
F8185C  8ED8           MOV DS,AX
F8185E  BC6418         MOV SP,1864h
F81861  E93AED         JMP 59Eh                    ; re-run the PIT setup one last time
F81864  BC3000         MOV SP,30h
F81867  8ED4           MOV SS,SP
F81869  BCFE00         MOV SP,0FEh
F8186C  E83306         CALL 1EA2h                  ; GRCG / EGC presence test
F8186F  B00F           MOV AL,0Fh
F81871  E637           OUT 37h,AL                  ; PPI-C bit7 := 1 (SHUT0)
F81873  EB00           JMP SHORT 1875h
F81875  EB00           JMP SHORT 1877h
F81877  B00A           MOV AL,0Ah
F81879  E637           OUT 37h,AL                  ; PPI-C bit5 := 0
F8187B  C706F804EEEA   MOV WORD PTR [04F8h],0EAEEh ; 0000:04F8 = EE EA  -> OUT DX,AL ; JMP FAR ...
F81881  C706FA040200   MOV WORD PTR [04FAh],2h     ; 0000:04FA = 02 00  -> offset 0002h
F81887  C706FC0480FD   MOV WORD PTR [04FCh],0FD80h ; 0000:04FC = 80 FD  -> segment FD80h
F8188D  BA3D04         MOV DX,43Dh                 ; DX = 043Dh
F81890  B012           MOV AL,12h                  ; AL = 12h
F81892  EAF8040000     JMP FAR 0h:4F8h             ; --- HAND-OVER: run the stub, which does OUT 043Dh,12h then JMP FAR FD80:0002 ---
```

### 1.18 Helper routines used above

```
F81897  FC             CLD                         ; --- fill 2 x 64 KB at segment BX with EAX ---
F81898  8EC3           MOV ES,BX
F8189A  8BF8           MOV DI,AX
F8189C  66C1E010       SHL EAX,10h
F818A0  8BC7           MOV AX,DI
F818A2  33FF           XOR DI,DI
F818A4  B90040         MOV CX,4000h
F818A7  66F3AB         REP STOSD
F818AA  81C30010       ADD BX,1000h
F818AE  8EC3           MOV ES,BX
F818B0  33FF           XOR DI,DI
F818B2  B90040         MOV CX,4000h
F818B5  66F3AB         REP STOSD
F818B8  81EB0010       SUB BX,1000h
F818BC  FFE4           JMP SP
F818BE  FC             CLD                         ; --- verify 2 x 64 KB at segment BX against EAX; CF=1 on mismatch ---
F818BF  8EC3           MOV ES,BX
F818C1  8BF8           MOV DI,AX
F818C3  66C1E010       SHL EAX,10h
F818C7  8BC7           MOV AX,DI
F818C9  33FF           XOR DI,DI
F818CB  B90040         MOV CX,4000h
F818CE  66F3AF         REP SCASD
F818D1  751B           JNZ  18EEh
F818D3  81C30010       ADD BX,1000h
F818D7  FEC6           INC DH
F818D9  8EC3           MOV ES,BX
F818DB  33FF           XOR DI,DI
F818DD  B90040         MOV CX,4000h
F818E0  66F3AF         REP SCASD
F818E3  7509           JNZ  18EEh
F818E5  81EB0010       SUB BX,1000h
F818E9  FECE           DEC DH
F818EB  F8             CLC
F818EC  FFE4           JMP SP
F818EE  F9             STC
F818EF  FFE4           JMP SP
```

```
F819BF  80FE02         CMP DH,02h                  ; --- print "MEMORY nnnKB OK" ---
F819C2  7409           JZ   19CDh
F819C4  B800A0         MOV AX,0A000h
F819C7  8ED8           MOV DS,AX
F819C9  FE0EE03F       DEC BYTE PTR [3FE0h]
F819CD  BEBF1B         MOV SI,1BBFh
F819D0  BCD619         MOV SP,19D6h
F819D3  E9F503         JMP 1DCBh
F819D6  8BF2           MOV SI,DX
F819D8  A0E03F         MOV AL,[3FE0h]
F819DB  FEC8           DEC AL
F819DD  B4A0           MOV AH,0A0h
F819DF  F6E4           MUL AH
F819E1  8BF8           MOV DI,AX
F819E3  83C712         ADD DI,0012h
F819E6  E431           IN AL,31h
F819E8  A804           TEST AL,04h
F819EA  7403           JZ   19EFh
F819EC  83C712         ADD DI,0012h
F819EF  8BC2           MOV AX,DX
F819F1  80FC10         CMP AH,10h
F819F4  7203           JC   19F9h
F819F6  80EC08         SUB AH,08h
F819F9  32C0           XOR AL,AL
F819FB  D1E8           SHR AX,1
F819FD  D1E8           SHR AX,1
F819FF  B90A00         MOV CX,0Ah
F81A02  33D2           XOR DX,DX
F81A04  F7F1           DIV CX
F81A06  80CA30         OR DL,30h
F81A09  8815           MOV [DI],DL
F81A0B  8BD0           MOV DX,AX
F81A0D  4F             DEC DI
F81A0E  4F             DEC DI
F81A0F  E431           IN AL,31h
F81A11  A804           TEST AL,04h
F81A13  7402           JZ   1A17h
F81A15  4F             DEC DI
F81A16  4F             DEC DI
F81A17  8BC2           MOV AX,DX
F81A19  33D2           XOR DX,DX
F81A1B  F7F1           DIV CX
F81A1D  80CA30         OR DL,30h
F81A20  8815           MOV [DI],DL
F81A22  8BD0           MOV DX,AX
F81A24  4F             DEC DI
F81A25  4F             DEC DI
F81A26  E431           IN AL,31h
F81A28  A804           TEST AL,04h
F81A2A  7402           JZ   1A2Eh
F81A2C  4F             DEC DI
F81A2D  4F             DEC DI
F81A2E  8BC2           MOV AX,DX
F81A30  33D2           XOR DX,DX
F81A32  F7F1           DIV CX
F81A34  80CA30         OR DL,30h
F81A37  8815           MOV [DI],DL
F81A39  8BD6           MOV DX,SI
F81A3B  33C0           XOR AX,AX
F81A3D  8ED8           MOV DS,AX
F81A3F  FFE5           JMP BP
F81A41  8BDF           MOV BX,DI
F81A43  BED11B         MOV SI,1BD1h
F81A46  80FE02         CMP DH,02h
F81A49  7203           JC   1A4Eh
F81A4B  BE0E1C         MOV SI,1C0Eh
F81A4E  BC541A         MOV SP,1A54h
F81A51  E97703         JMP 1DCBh
F81A54  8BFB           MOV DI,BX
F81A56  A0E03F         MOV AL,[3FE0h]
F81A59  FEC8           DEC AL
F81A5B  B4A0           MOV AH,0A0h
F81A5D  F6E4           MUL AH
F81A5F  8BF0           MOV SI,AX
F81A61  83C61A         ADD SI,001Ah
F81A64  E431           IN AL,31h
F81A66  A804           TEST AL,04h
F81A68  7403           JZ   1A6Dh
F81A6A  83C61A         ADD SI,001Ah
F81A6D  8AC6           MOV AL,DH
F81A6F  BC751A         MOV SP,1A75h
F81A72  E9E203         JMP 1E57h
F81A75  8BC7           MOV AX,DI
F81A77  8AC4           MOV AL,AH
F81A79  BC7F1A         MOV SP,1A7Fh
F81A7C  E9D803         JMP 1E57h
F81A7F  8BC7           MOV AX,DI
F81A81  BC871A         MOV SP,1A87h
F81A84  E9D003         JMP 1E57h
F81A87  46             INC SI
F81A88  46             INC SI
F81A89  E431           IN AL,31h
F81A8B  A804           TEST AL,04h
F81A8D  7402           JZ   1A91h
F81A8F  46             INC SI
F81A90  46             INC SI
F81A91  268A4503       MOV AL,ES:[DI+03h]
F81A95  32C2           XOR AL,DL
F81A97  BC9D1A         MOV SP,1A9Dh
F81A9A  E9BA03         JMP 1E57h
F81A9D  268A4502       MOV AL,ES:[DI+02h]
F81AA1  32C2           XOR AL,DL
F81AA3  BCA91A         MOV SP,1AA9h
F81AA6  E9AE03         JMP 1E57h
F81AA9  268A4501       MOV AL,ES:[DI+01h]
F81AAD  32C2           XOR AL,DL
F81AAF  BCB51A         MOV SP,1AB5h
F81AB2  E9A203         JMP 1E57h
F81AB5  268A05         MOV AL,ES:[DI]
F81AB8  32C2           XOR AL,DL
F81ABA  BCC01A         MOV SP,1AC0h
F81ABD  E99703         JMP 1E57h
F81AC0  BCC61A         MOV SP,1AC6h
F81AC3  EB57           JMP SHORT 1B1Ch
F81AC5  90             NOP
F81AC6  33C0           XOR AX,AX
F81AC8  8ED8           MOV DS,AX
F81ACA  FFE5           JMP BP
F81ACC  B008           MOV AL,08h                  ; --- parity-error report ---
F81ACE  E637           OUT 37h,AL
F81AD0  33C0           XOR AX,AX
F81AD2  81E300E0       AND BX,0E000h
F81AD6  BCDC1A         MOV SP,1ADCh
F81AD9  E9BBFD         JMP 1897h
F81ADC  B009           MOV AL,09h
F81ADE  E637           OUT 37h,AL
F81AE0  BEE01B         MOV SI,1BE0h
F81AE3  80FE02         CMP DH,02h
F81AE6  7203           JC   1AEBh
F81AE8  BE1D1C         MOV SI,1C1Dh
F81AEB  BCF11A         MOV SP,1AF1h
F81AEE  E9DA02         JMP 1DCBh
F81AF1  A0E03F         MOV AL,[3FE0h]
F81AF4  FEC8           DEC AL
F81AF6  B4A0           MOV AH,0A0h
F81AF8  F6E4           MUL AH
F81AFA  8BF0           MOV SI,AX
F81AFC  83C61A         ADD SI,001Ah
F81AFF  E431           IN AL,31h
F81B01  A804           TEST AL,04h
F81B03  7403           JZ   1B08h
F81B05  83C61A         ADD SI,001Ah
F81B08  8AC6           MOV AL,DH
F81B0A  BC101B         MOV SP,1B10h
F81B0D  E94703         JMP 1E57h
F81B10  BC161B         MOV SP,1B16h
F81B13  EB07           JMP SHORT 1B1Ch
F81B15  90             NOP
F81B16  33C0           XOR AX,AX
F81B18  8ED8           MOV DS,AX
F81B1A  FFE5           JMP BP
F81B1C  B006           MOV AL,06h                  ; --- short beep ---
F81B1E  E637           OUT 37h,AL
F81B20  33C9           XOR CX,CX
F81B22  E2FE           LOOP 1B22h
F81B24  E2FE           LOOP 1B24h
F81B26  E2FE           LOOP 1B26h
F81B28  E2FE           LOOP 1B28h
F81B2A  E2FE           LOOP 1B2Ah
F81B2C  E2FE           LOOP 1B2Ch
F81B2E  B007           MOV AL,07h
F81B30  E637           OUT 37h,AL
F81B32  FFE4           JMP SP
```

```
F81DCB  B800A0         MOV AX,0A000h               ; --- message printer: SI -> attr, ASCIIZ text, control byte ---
F81DCE  8ED8           MOV DS,AX
F81DD0  FC             CLD
F81DD1  A0E03F         MOV AL,[3FE0h]
F81DD4  B4A0           MOV AH,0A0h
F81DD6  F6E4           MUL AH
F81DD8  8BF8           MOV DI,AX
F81DDA  2EAC           CS:LODSB
F81DDC  B92800         MOV CX,28h
F81DDF  8AE0           MOV AH,AL
F81DE1  88A50020       MOV [DI+2000h],AH
F81DE5  47             INC DI
F81DE6  47             INC DI
F81DE7  E431           IN AL,31h                   ; 31h bit2 selects the text-VRAM stride (2 or 4 bytes per cell)
F81DE9  A804           TEST AL,04h
F81DEB  7402           JZ   1DEFh
F81DED  47             INC DI
F81DEE  47             INC DI
F81DEF  E2F0           LOOP 1DE1h
F81DF1  A0E03F         MOV AL,[3FE0h]
F81DF4  B4A0           MOV AH,0A0h
F81DF6  F6E4           MUL AH
F81DF8  8BF8           MOV DI,AX
F81DFA  32E4           XOR AH,AH
F81DFC  B92800         MOV CX,28h
F81DFF  2EAC           CS:LODSB
F81E01  0AC0           OR AL,AL
F81E03  7410           JZ   1E15h
F81E05  8905           MOV [DI],AX
F81E07  47             INC DI
F81E08  47             INC DI
F81E09  E431           IN AL,31h
F81E0B  A804           TEST AL,04h
F81E0D  7402           JZ   1E11h
F81E0F  47             INC DI
F81E10  47             INC DI
F81E11  E2EC           LOOP 1DFFh
F81E13  E310           JCXZ 1E25h
F81E15  C7052000       MOV WORD PTR [DI],20h
F81E19  47             INC DI
F81E1A  47             INC DI
F81E1B  E431           IN AL,31h
F81E1D  A804           TEST AL,04h
F81E1F  7402           JZ   1E23h
F81E21  47             INC DI
F81E22  47             INC DI
F81E23  E2F0           LOOP 1E15h
F81E25  FE06E03F       INC BYTE PTR [3FE0h]
F81E29  2EAC           CS:LODSB
F81E2B  8AE0           MOV AH,AL
F81E2D  F6C401         TEST AH,01h                 ; control bit0 = beep
F81E30  741B           JZ   1E4Dh
F81E32  B006           MOV AL,06h
F81E34  E637           OUT 37h,AL
F81E36  33C9           XOR CX,CX
F81E38  E2FE           LOOP 1E38h
F81E3A  E2FE           LOOP 1E3Ah
F81E3C  E2FE           LOOP 1E3Ch
F81E3E  E2FE           LOOP 1E3Eh
F81E40  E2FE           LOOP 1E40h
F81E42  E2FE           LOOP 1E42h
F81E44  F6C402         TEST AH,02h
F81E47  7504           JNZ  1E4Dh
F81E49  B007           MOV AL,07h
F81E4B  E637           OUT 37h,AL
F81E4D  F6C480         TEST AH,80h                 ; control bit7 = halt after printing
F81E50  7403           JZ   1E55h
F81E52  FA             CLI
F81E53  EBFE           JMP SHORT 1E53h
F81E55  FFE4           JMP SP
F81E57  BB881E         MOV BX,1E88h                ; --- print AL as two hex digits at DS:SI ---
F81E5A  8AE0           MOV AH,AL
F81E5C  D0E8           SHR AL,1
F81E5E  D0E8           SHR AL,1
F81E60  D0E8           SHR AL,1
F81E62  D0E8           SHR AL,1
F81E64  240F           AND AL,0Fh
F81E66  2ED7           XLAT
F81E68  8804           MOV [SI],AL
F81E6A  46             INC SI
F81E6B  46             INC SI
F81E6C  E431           IN AL,31h
F81E6E  A804           TEST AL,04h
F81E70  7402           JZ   1E74h
F81E72  46             INC SI
F81E73  46             INC SI
F81E74  8AC4           MOV AL,AH
F81E76  240F           AND AL,0Fh
F81E78  2ED7           XLAT
F81E7A  8804           MOV [SI],AL
F81E7C  46             INC SI
F81E7D  46             INC SI
F81E7E  E431           IN AL,31h
F81E80  A804           TEST AL,04h
F81E82  7402           JZ   1E86h
F81E84  46             INC SI
F81E85  46             INC SI
F81E86  FFE4           JMP SP
F81E88  3031           XOR [BX+DI],DH
F81E8A  3233           XOR DH,[BP+DI]
F81E8C  3435           XOR AL,35h
F81E8E  3637           AAA
F81E90  3839           CMP [BX+DI],BH
F81E92  41             INC CX
F81E93  42             INC DX
F81E94  43             INC BX
F81E95  44             INC SP
F81E96  45             INC BP
F81E97  46             INC SI
F81E98  B000           MOV AL,00h                  ; 0F0h := 00h then HLT  -- CPU reset
F81E9A  E6F0           OUT 0F0h,AL
F81E9C  F4             HLT
F81E9D  B007           MOV AL,07h                  ; 0F0h := 07h then HLT  -- CPU reset
F81E9F  E6F0           OUT 0F0h,AL
F81EA1  F4             HLT
F81EA2  B080           MOV AL,80h                  ; --- GRCG / EGC presence test ---
F81EA4  E67C           OUT 7Ch,AL                  ; GRCG mode := 80h (GRCG on, TDW off)
F81EA6  B033           MOV AL,33h
F81EA8  E67E           OUT 7Eh,AL                  ; tile registers: plane0=33h, plane1=55h, plane2=00h, plane3=00h
F81EAA  B055           MOV AL,55h
F81EAC  E67E           OUT 7Eh,AL
F81EAE  B000           MOV AL,00h
F81EB0  E67E           OUT 7Eh,AL
F81EB2  B000           MOV AL,00h
F81EB4  E67E           OUT 7Eh,AL
F81EB6  B04C           MOV AL,4Ch                  ; GDC FIGS 4Ch, CSRW 49h EAD=4000h (wraps to offset 0 of a 32KB plane), WDAT 20h FFFFh
F81EB8  E8A400         CALL 1F5Fh
F81EBB  B000           MOV AL,00h
F81EBD  E8AB00         CALL 1F6Bh
F81EC0  B049           MOV AL,49h
F81EC2  E89A00         CALL 1F5Fh
F81EC5  B80040         MOV AX,4000h
F81EC8  E8A000         CALL 1F6Bh
F81ECB  8AC4           MOV AL,AH
F81ECD  E89B00         CALL 1F6Bh
F81ED0  B008           MOV AL,08h
F81ED2  E89600         CALL 1F6Bh
F81ED5  B020           MOV AL,20h
F81ED7  E88500         CALL 1F5Fh
F81EDA  B0FF           MOV AL,0FFh
F81EDC  E88C00         CALL 1F6Bh
F81EDF  E88900         CALL 1F6Bh
F81EE2  B049           MOV AL,49h
F81EE4  E87800         CALL 1F5Fh
F81EE7  E89800         CALL 1F82h
F81EEA  B000           MOV AL,00h
F81EEC  E67C           OUT 7Ch,AL                  ; GRCG off
F81EEE  B800A8         MOV AX,0A800h
F81EF1  8EC0           MOV ES,AX
F81EF3  26A10000       MOV AX,ES:[0h]              ; A800:0000 must read 3333h
F81EF7  3D3333         CMP AX,3333h
F81EFA  751F           JNZ  1F1Bh
F81EFC  B800B0         MOV AX,0B000h
F81EFF  8EC0           MOV ES,AX
F81F01  26A10000       MOV AX,ES:[0h]              ; B000:0000 must read 5555h
F81F05  3D5555         CMP AX,5555h
F81F08  7511           JNZ  1F1Bh
F81F0A  E83200         CALL 1F3Fh
F81F0D  B80000         MOV AX,0h
F81F10  8EC0           MOV ES,AX
F81F12  26800E4D0540   OR BYTE PTR ES:[054Dh],40h  ; 0000:054D bit6 := 1 (GRCG/EGC present)
F81F18  EB0C           JMP SHORT 1F26h
F81F1A  90             NOP
F81F1B  B80000         MOV AX,0h
F81F1E  8EC0           MOV ES,AX
F81F20  2680264D05BF   AND BYTE PTR ES:[054Dh],0BFh
F81F26  B800A8         MOV AX,0A800h
F81F29  8EC0           MOV ES,AX
F81F2B  26C70600000000 MOV WORD PTR ES:[0000h],0h
F81F32  B800B0         MOV AX,0B000h
F81F35  8EC0           MOV ES,AX
F81F37  26C70600000000 MOV WORD PTR ES:[0000h],0h
F81F3E  C3             RET
F81F3F  B007           MOV AL,07h                  ; --- EGC probe ---
F81F41  E66A           OUT 6Ah,AL
F81F43  B005           MOV AL,05h
F81F45  E66A           OUT 6Ah,AL
F81F47  B080           MOV AL,80h
F81F49  E67C           OUT 7Ch,AL
F81F4B  BAA004         MOV DX,4A0h
F81F4E  B8F0FF         MOV AX,0FFF0h
F81F51  EF             OUT DX,AX                   ; EGC register 04A0h := FFF0h (word)
F81F52  B000           MOV AL,00h
F81F54  E67C           OUT 7Ch,AL
F81F56  B004           MOV AL,04h
F81F58  E66A           OUT 6Ah,AL
F81F5A  B006           MOV AL,06h
F81F5C  E66A           OUT 6Ah,AL
F81F5E  C3             RET
F81F5F  50             PUSH AX                     ; --- write a GDC command byte (waits for FIFO not full) ---
F81F60  E81400         CALL 1F77h
F81F63  58             POP AX
F81F64  EB00           JMP SHORT 1F66h
F81F66  EB00           JMP SHORT 1F68h
F81F68  E6A2           OUT 0A2h,AL
F81F6A  C3             RET
F81F6B  50             PUSH AX                     ; --- write a GDC parameter byte ---
F81F6C  E80800         CALL 1F77h
F81F6F  58             POP AX
F81F70  EB00           JMP SHORT 1F72h
F81F72  EB00           JMP SHORT 1F74h
F81F74  E6A0           OUT 0A0h,AL
F81F76  C3             RET
F81F77  EB00           JMP SHORT 1F79h             ; A0h bit1 = FIFO FULL
F81F79  E4A0           IN AL,0A0h
F81F7B  A802           TEST AL,02h
F81F7D  EB00           JMP SHORT 1F7Fh
F81F7F  75F6           JNZ  1F77h
F81F81  C3             RET
F81F82  EB00           JMP SHORT 1F84h             ; A0h bit2 = FIFO EMPTY
F81F84  E4A0           IN AL,0A0h
F81F86  A804           TEST AL,04h
F81F88  EB00           JMP SHORT 1F8Ah
F81F8A  74F6           JZ   1F82h
F81F8C  C3             RET
```

(`F81F8D` is a single `00h` alignment filler; `F81F8E` is the service-mode
entry, off the boot path.)


## 2. Every I/O port the ITF touches, in program order

This is the boot path with **no key held at power-on** and a cold start
(`0439h` reads 0, PPI-C reads `FFh`). Values are given where they are an
immediate or a traceable constant; `—` means a read, `?` means the value is
computed at run time and the surrounding disassembly says how.

Reads whose result is branched on are listed here too, but §3 is the section
that matters for them.

| addr | R/W | port | value | port function |
|------|-----|------|-------|---------------|
| | | | | **CPU / register self-test (F80000-F8004E): no I/O** |
| F80052 | R | `DX=0439h` | — | system control register |
| F80053 | R | `DX=0439h` | — | system control register |
| F8005A | W | `37h` | 92h | 8255 #1 control (mode / bit set-reset) |
| F80062 | W | `35h` | FFh | 8255 #1 port C (SHUT0/SHUT1, buzzer, parity enable) |
| F80067 | W | `43h` | 00h | keyboard 8251 command / status |
| F80074 | W | `43h` | 40h | keyboard 8251 command / status |
| F8007D | W | `43h` | 5Eh | keyboard 8251 command / status |
| F8007F | R | `DX=0439h` | — | system control register |
| F80084 | W | `DX=0439h` | (0439h & 02h) | 34h | system control register |
| | | | | **restart-mode dispatch** |
| F8008A | R | `35h` | — | 8255 #1 port C (SHUT0/SHUT1, buzzer, parity enable) |
| | | | | **normal cold start** |
| F800BE | W | `77h` | 70h | 8253 control |
| F800C6 | W | `73h` | 00h | 8253 counter 1 |
| F800CE | W | `73h` | 00h | 8253 counter 1 |
| | | | | **port table 1 walked by F800D3 (see 2.1)** |
| F80106 | W | `DX=7FDFh` | 93h | 386 board control |
| F80110 | W | `DX=0467h` | 00h | shadow-RAM control |
| F80116 | W | `DX=0461h` | 08h | shadow-RAM / ROM window control |
| F80117 | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F80122 | W | `DX=0037h` | 0Bh | 8255 #1 control (mode / bit set-reset) |
| F80128 | W | `DX=00F0h` | 00h | CPU reset / mode status |
| F80138 | W | `DX=043Fh` | 42h or 40h (42h bit5) | bus and window control |
| | | | | **display initialisation (the GDC block writer at F8045F and the retrace wait at F804D7 are inlined below where they are first used)** |
| F8013C | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80144 | W | `6Eh` | 00h | MODE FF3 / CRT select |
| F8014A | W | `6Eh` | 01h | MODE FF3 / CRT select |
| F80165 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80199 | W | `68h` | 01h | MODE FF1 (bit set/reset) |
| F801CD | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F801D6 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F801E5 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80203 | W | `A2h` | 0Fh | graphic GDC command |
| F80212 | W | `7Ch` | 4Fh | GRCG mode register |
| F80216 | W | `6Ah` | 81h | MODE FF2 (bit set/reset) |
| F80218 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80220 | W | `68h` | 08h | MODE FF1 (bit set/reset) |
| F80222 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F8022A | W | `70h` | 1Fh | CRT parameter (HBP) |
| F8022E | W | `72h` | 08h | CRT parameter (HFP) |
| F80232 | W | `74h` | 08h | CRT parameter (VBP) |
| F80244 | W | `70h` | 00h | CRT parameter (HBP) |
| F80248 | W | `72h` | 07h | CRT parameter (HFP) |
| F8024C | W | `74h` | 08h | CRT parameter (VBP) |
| F8025E | W | `68h` | 07h | MODE FF1 (bit set/reset) |
| F80264 | W | `68h` | 09h | MODE FF1 (bit set/reset) |
| F80266 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F8026E | W | `70h` | 1Eh | CRT parameter (HBP) |
| F80272 | W | `72h` | 11h | CRT parameter (HFP) |
| F80276 | W | `74h` | 10h | CRT parameter (VBP) |
| F80288 | W | `70h` | 00h | CRT parameter (HBP) |
| F8028C | W | `72h` | 0Fh | CRT parameter (HFP) |
| F80290 | W | `74h` | 10h | CRT parameter (VBP) |
| F8029D | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F802A5 | W | `68h` | 05h | MODE FF1 (bit set/reset) |
| F802A9 | W | `76h` | 00h | CRT parameter (VFP) |
| F802AB | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F802B3 | W | `6Ah` | 41h | MODE FF2 (bit set/reset) |
| F802B7 | W | `6Ah` | 82h | MODE FF2 (bit set/reset) |
| F802BB | W | `6Ah` | 84h | MODE FF2 (bit set/reset) |
| F802BF | W | `6Ah` | 07h | MODE FF2 (bit set/reset) |
| F802C1 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F802CD | W | `A0h` | DDh or 88h (33h bit3) | graphic GDC parameter / status |
| F802D1 | W | `A2h` | 2Ch or 32h (33h bit3) | graphic GDC command |
| F802D5 | W | `6Ah` | 06h | MODE FF2 (bit set/reset) |
| F802D9 | W | `6Ah` | 00h | MODE FF2 (bit set/reset) |
| F8030D | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F80316 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80325 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80339 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80383 | W | `6Ch` | 00h | border colour |
| F80388 | R | `60h` | — | text GDC parameter / status |
| F8038E | R | `60h` | — | text GDC parameter / status |
| F80394 | R | `60h` | — | text GDC parameter / status |
| F803A2 | R | `A0h` | — | graphic GDC parameter / status |
| F803AE | R | `A0h` | — | graphic GDC parameter / status |
| F803BA | R | `A0h` | — | graphic GDC parameter / status |
| F803C8 | W | `A2h` | 0Dh | graphic GDC command |
| F803CC | W | `62h` | 0Dh | text GDC command |
| F803D0 | R | `A0h` | — | graphic GDC parameter / status |
| F803DE | W | `A2h` | 0Ch | graphic GDC command |
| F803E2 | W | `62h` | 0Ch | text GDC command |
| F803E6 | W | `68h` | 02h | MODE FF1 (bit set/reset) |
| | | | | **port table 2 walked by F800D3 (see 2.1)** |
| F803FC | W | `6Ah` | 01h | MODE FF2 (bit set/reset) |
| F8040A | W | `A8h` | 0Fh down to 00h | palette index / digital palette |
| F8040E | W | `AAh` | from the table at F8042F | palette green |
| F80412 | W | `ACh` | from the table at F8042F | palette red |
| F80416 | W | `AEh` | from the table at F8042F | palette blue |
| F8041C | W | `6Ah` | 00h | MODE FF2 (bit set/reset) |
| F80420 | W | `68h` | 0Fh | MODE FF1 (bit set/reset) |
| | | | | **GDC block writer F8045F-F804E4, entered many times from the block above** |
| F80474 | R | `60h` | — | text GDC parameter / status |
| F80482 | R | `A0h` | — | graphic GDC parameter / status |
| F8049C | W | `62h or A2h` | byte 0 of the block = GDC command | graphic GDC command |
| F804B0 | R | `60h` | — | text GDC parameter / status |
| F804BE | R | `A0h` | — | graphic GDC parameter / status |
| F804D2 | W | `60h or A0h` | bytes 1.. of the block = GDC parameters | graphic GDC command |
| F804D7 | R | `60h` | — | text GDC parameter / status |
| F804DD | R | `60h` | — | text GDC parameter / status |
| | | | | **ROM checksum and 8253 setup** |
| F805A0 | W | `77h` | 30h | 8253 control |
| F805A8 | W | `71h` | 00h | 8253 counter 0 |
| F805B0 | W | `71h` | 00h | 8253 counter 0 |
| F805B9 | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F805C4 | W | `77h` | 76h | 8253 control |
| F805CC | W | `73h` | low byte of 03E6h or 04CDh | 8253 counter 1 |
| F805D4 | W | `73h` | high byte of 03E6h or 04CDh | 8253 counter 1 |
| F805DC | W | `77h` | B6h | 8253 control |
| | | | | **port table 3 walked by F800D3 (see 2.1)** |
| F805FE | W | `00h` | 11h | 8259 master ICW1/OCW2/OCW3 |
| F80602 | W | `02h` | 08h | 8259 master ICW2/3/4, IMR |
| F80606 | W | `02h` | 80h | 8259 master ICW2/3/4, IMR |
| F8060A | W | `02h` | 1Dh | 8259 master ICW2/3/4, IMR |
| F8060E | W | `08h` | 11h | 8259 slave  ICW1/OCW2/OCW3 |
| F80612 | W | `0Ah` | 10h | 8259 slave  ICW2/3/4, IMR |
| F80616 | W | `0Ah` | 07h | 8259 slave  ICW2/3/4, IMR |
| F8061A | W | `0Ah` | 09h | 8259 slave  ICW2/3/4, IMR |
| | | | | **keyboard 8251 primitives, entered many times** |
| F80627 | W | `43h` | 37h | keyboard 8251 command / status |
| F8063B | W | `41h` | AH = 00h / 9Dh / 7xh / 9Fh | keyboard 8251 data |
| F80644 | R | `43h` | — | keyboard 8251 command / status |
| F8064C | W | `43h` | 16h | keyboard 8251 command / status |
| F8065F | R | `43h` | — | keyboard 8251 command / status |
| F8066E | R | `41h` | — | keyboard 8251 data |
| F80679 | R | `43h` | — | keyboard 8251 command / status |
| F80689 | R | `41h` | — | keyboard 8251 data |
| | | | | **boot beep** |
| F8071E | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F80729 | W | `37h` | 06h | 8255 #1 control (mode / bit set-reset) |
| F80734 | W | `37h` | 07h | 8255 #1 control (mode / bit set-reset) |
| F80738 | W | `77h` | 76h | 8253 control |
| F80740 | W | `73h` | low byte of 03E6h or 04CDh | 8253 counter 1 |
| F80748 | W | `73h` | high byte of the same | 8253 counter 1 |
| F8074C | W | `37h` | 06h | 8255 #1 control (mode / bit set-reset) |
| F80757 | W | `37h` | 07h | 8255 #1 control (mode / bit set-reset) |
| F8075B | W | `77h` | 76h | 8253 control |
| F80763 | W | `73h` | low byte of the divisor doubled | 8253 counter 1 |
| F8076B | W | `73h` | high byte of the same | 8253 counter 1 |
| | | | | **VRAM / CG / memory-switch / base-RAM tests** |
| F8083E | W | `62h` | 0Dh | text GDC command |
| F80842 | W | `68h` | 0Fh | MODE FF1 (bit set/reset) |
| F8086F | W | `62h` | 0Dh | text GDC command |
| F80873 | W | `68h` | 0Fh | MODE FF1 (bit set/reset) |
| F8089A | R | `DX=7FDDh` | — | CPU mode (V30 / 386) |
| F808B6 | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F808F9 | W | `68h` | 0Bh | MODE FF1 (bit set/reset) |
| F8092C | W | `A1h` | CG code low byte 20h..7Fh | CG code (low) |
| F80930 | W | `A3h` | CG code high byte 56h then 57h | CG code (high) |
| F80934 | W | `A5h` | 00h | CG line select |
| F80943 | W | `A5h` | 20h | CG line select |
| F80952 | W | `A5h` | 00h | CG line select |
| F80963 | W | `A5h` | 20h | CG line select |
| F8097D | W | `68h` | 0Ah | MODE FF1 (bit set/reset) |
| F80981 | W | `6Ah` | 01h | MODE FF2 (bit set/reset) |
| F809B5 | W | `7Ch` | 00h | GRCG mode register |
| F809B7 | W | `6Ah` | 00h | MODE FF2 (bit set/reset) |
| F809B9 | W | `A6h` | 00h | draw page |
| F809BB | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F809C3 | W | `68h` | 0Dh | MODE FF1 (bit set/reset) |
| F809F8 | W | `68h` | 0Ch | MODE FF1 (bit set/reset) |
| F80A00 | W | `37h` | 08h | 8255 #1 control (mode / bit set-reset) |
| F80A12 | W | `37h` | 09h | 8255 #1 control (mode / bit set-reset) |
| F80A28 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80A42 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| | | | | **ROM shadow stub, running from RAM at 0000:0000** |
| F80A9D | W | `DX=043Dh` | 12h | ROM bank select (ITF / BIOS) |
| F80AE2 | W | `DX=043Fh` | 80h | bus and window control |
| F80AE8 | W | `DX=0461h` | 0Eh | shadow-RAM / ROM window control |
| F80B16 | W | `DX=0461h` | 0Ch | shadow-RAM / ROM window control |
| F80B17 | R | `F0h` | — | CPU reset / mode status |
| F80B22 | W | `DX=053Dh` | 40h | shadow / cache control |
| F80B3B | W | `DX=053Dh` | 00h | shadow / cache control |
| F80B41 | W | `DX=043Fh` | C2h | bus and window control |
| F80B48 | R | `DX=7FDBh` | — | system configuration |
| F80B54 | W | `DX=043Fh` | 82h | bus and window control |
| F80B5A | W | `DX=053Dh` | 02h | shadow / cache control |
| F80B64 | W | `DX=0461h` | 08h | shadow-RAM / ROM window control |
| F80B6A | W | `DX=043Dh` | 10h | ROM bank select (ITF / BIOS) |
| | | | | **bank memory, A20, 8253, 8237, 8259, IRQ0** |
| F80B8F | W | `DX=043Fh` | 22h | bus and window control |
| F80BA6 | W | `DX=043Fh` | 20h | bus and window control |
| F80BB0 | W | `DX=043Fh` | 22h | bus and window control |
| F80BBD | W | `37h` | 08h | 8255 #1 control (mode / bit set-reset) |
| F80BD1 | W | `37h` | 09h | 8255 #1 control (mode / bit set-reset) |
| F80BEF | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80C11 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80C4D | W | `DX=043Fh` | 20h | bus and window control |
| F80C73 | W | `37h` | 06h | 8255 #1 control (mode / bit set-reset) |
| F80C89 | W | `77h` | 10h, 50h, 90h | 8253 control |
| F80C91 | W | `71h, 73h, 75h` | FFh then 00h | 8253 counter 0 |
| F80C98 | W | `77h` | 00h, 40h, 80h (latch) | 8253 control |
| F80C9E | R | `71h, 73h, 75h` | — | 8253 counter 0 |
| F80CC1 | W | `37h` | 07h | 8255 #1 control (mode / bit set-reset) |
| F80CC9 | W | `1Bh` | B6h (any value; master clear ignores data) | 8237 master clear |
| F80CD7 | W | `01h,03h,05h,07h,09h,0Bh,0Dh,0Fh` | FFh then 00h | 8237 ch0 address |
| F80CDA | W | `01h..0Fh` | FFh then 00h | 8237 ch0 address |
| F80CDD | R | `01h..0Fh` | — | 8237 ch0 address |
| F80CE0 | R | `01h..0Fh` | — | 8237 ch0 address |
| F80CFD | W | `11h` | 40h | 8237 command / status |
| F80D03 | W | `02h` | 00h then FFh | 8259 master ICW2/3/4, IMR |
| F80D07 | R | `02h` | — | 8259 master ICW2/3/4, IMR |
| F80D17 | W | `0Ah` | 00h then FFh | 8259 slave  ICW2/3/4, IMR |
| F80D1B | R | `0Ah` | — | 8259 slave  ICW2/3/4, IMR |
| F80D5B | W | `71h` | 1Ah | 8253 counter 0 |
| F80D63 | W | `71h` | 00h | 8253 counter 0 |
| F80D6A | W | `02h` | FEh | 8259 master ICW2/3/4, IMR |
| F80D7F | W | `71h` | 00h | 8253 counter 0 |
| F80D85 | W | `71h` | 00h | 8253 counter 0 |
| F80D8D | W | `02h` | FFh | 8259 master ICW2/3/4, IMR |
| F80D91 | W | `00h` | 20h | 8259 master ICW1/OCW2/OCW3 |
| | | | | **memory-switch defaults and extended-memory sizing** |
| F80D94 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F80D9C | W | `68h` | 0Dh | MODE FF1 (bit set/reset) |
| F80DB8 | R | `DX=7FDBh` | — | system configuration |
| F80DD8 | W | `68h` | 0Ch | MODE FF1 (bit set/reset) |
| F80E01 | W | `37h` | 08h | 8255 #1 control (mode / bit set-reset) |
| F80E13 | W | `37h` | 09h | 8255 #1 control (mode / bit set-reset) |
| F80E29 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80E43 | R | `33h` | — | 8255 #1 port B (DIP SW 1 / status) |
| F80E9F | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F80F42 | W | `F2h` | 00h | A20 / protected-mode gate |
| F80F46 | W | `F6h` | 02h | A20 / protected-mode gate |
| F80F56 | W | `37h` | 0Eh | 8255 #1 control (mode / bit set-reset) |
| | | | | **protected-mode return paths** |
| F81265 | W | `37h` | 0Bh | 8255 #1 control (mode / bit set-reset) |
| F812B4 | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F812BD | R | `DX=7FDDh` | — | CPU mode (V30 / 386) |
| F812F2 | W | `F2h` | 00h | A20 / protected-mode gate |
| F812F6 | W | `F6h` | 02h | A20 / protected-mode gate |
| F81306 | W | `37h` | 0Eh | 8255 #1 control (mode / bit set-reset) |
| | | | | **final configuration and hand-over** |
| F817A0 | R | `DX=7FDBh` | — | system configuration |
| F817AC | W | `DX=043Fh` | 80h or 82h (7FDBh bit6) | bus and window control |
| F817AF | W | `DX=043Fh` | 20h | bus and window control |
| F817B0 | R | `F0h` | — | CPU reset / mode status |
| F817B9 | R | `DX=0CC4h` | — |  |
| F817C7 | R | `F0h` | — | CPU reset / mode status |
| F817D5 | W | `DX=053Dh` | 06h or 46h (0F0h bit5) | shadow / cache control |
| F817DD | W | `DX=0461h` | 08h | shadow-RAM / ROM window control |
| F817E3 | R | `DX=7FDDh` | — | CPU mode (V30 / 386) |
| F817EA | W | `37h` | 0Eh | 8255 #1 control (mode / bit set-reset) |
| F817FF | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F81841 | R | `42h` | — | 8255 #2 port B (hardware configuration) |
| F81871 | W | `37h` | 0Fh | 8255 #1 control (mode / bit set-reset) |
| F81879 | W | `37h` | 0Ah | 8255 #1 control (mode / bit set-reset) |
| | | | | **helpers: memory fill / verify, "MEMORY nnnKB OK", parity report, beep** |
| F819E6 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81A0F | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81A26 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81A64 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81A89 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81ACE | W | `37h` | 08h | 8255 #1 control (mode / bit set-reset) |
| F81ADE | W | `37h` | 09h | 8255 #1 control (mode / bit set-reset) |
| F81AFF | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81B1E | W | `37h` | 06h | 8255 #1 control (mode / bit set-reset) |
| F81B30 | W | `37h` | 07h | 8255 #1 control (mode / bit set-reset) |
| | | | | **helpers: message printer, hex printer, CPU reset, GRCG/EGC probe, GDC byte writers** |
| F81DE7 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81E09 | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81E1B | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81E34 | W | `37h` | 06h | 8255 #1 control (mode / bit set-reset) |
| F81E4B | W | `37h` | 07h | 8255 #1 control (mode / bit set-reset) |
| F81E6C | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81E7E | R | `31h` | — | 8255 #1 port A (DIP SW 2) |
| F81E9A | W | `F0h` | 00h | CPU reset / mode status |
| F81E9F | W | `F0h` | 07h | CPU reset / mode status |
| F81EA4 | W | `7Ch` | 80h | GRCG mode register |
| F81EA8 | W | `7Eh` | 33h | GRCG tile register |
| F81EAC | W | `7Eh` | 55h | GRCG tile register |
| F81EB0 | W | `7Eh` | 00h | GRCG tile register |
| F81EB4 | W | `7Eh` | 00h | GRCG tile register |
| F81EEC | W | `7Ch` | 00h | GRCG mode register |
| F81F41 | W | `6Ah` | 07h | MODE FF2 (bit set/reset) |
| F81F45 | W | `6Ah` | 05h | MODE FF2 (bit set/reset) |
| F81F49 | W | `7Ch` | 80h | GRCG mode register |
| F81F51 | W | `DX=04A0h` | FFF0h | EGC register |
| F81F54 | W | `7Ch` | 00h | GRCG mode register |
| F81F58 | W | `6Ah` | 04h | MODE FF2 (bit set/reset) |
| F81F5C | W | `6Ah` | 06h | MODE FF2 (bit set/reset) |
| F81F68 | W | `A2h` | GDC command byte (4Ch, 49h, 20h) | graphic GDC command |
| F81F74 | W | `A0h` | GDC parameter byte | graphic GDC parameter / status |
| F81F79 | R | `A0h` | — | graphic GDC parameter / status |
| F81F84 | R | `A0h` | — | graphic GDC parameter / status |

### 2.1 The three port-initialisation tables, as plain OUT lists

The walker at `F800D3` (§1.4) is entered three times. Decoded:

**Table 1 — `F800E5`, 13 entries, reached by falling through from `F800D0`,
resumes at `F80101`:**

    OUT 0011, 44     8237 command register
    OUT 0037, 92     8255 #1 mode set: A in, B in, C out
    OUT 0037, 07     PPI-C bit 3 := 1   (buzzer off)
    OUT 0050, 00     NMI control
    OUT 0037, 0D     PPI-C bit 6 := 1
    OUT 0046, 82     8255 #2 mode set
    OUT 0046, 0F     8255 #2 port C bit 7 := 1
    OUT 0037, 0C     PPI-C bit 6 := 0
    OUT 0037, 0F     PPI-C bit 7 := 1
    OUT 0037, 0A     PPI-C bit 5 := 0
    OUT 006A, 07     MODE FF2: reg 3 := 1
    OUT 006A, 04     MODE FF2: reg 2 := 0
    OUT 006A, 06     MODE FF2: reg 3 := 0

**Table 2 — `F803EE`, 5 entries, reached by `JMP 00D3h` from `F803EB`,
resumes at `F803FA`:**

    OUT 0068, 02     MODE FF1: reg 1 := 0
    OUT 00A8, 37     digital palette 0
    OUT 00AA, 15     digital palette 1
    OUT 00AC, 26     digital palette 2
    OUT 00AE, 04     digital palette 3

**Table 3 — `F805E6`, 10 entries, reached by `JMP 00D3h` from `F805E3`,
resumes at `F805FC`:**

    OUT 0029, 00     DMA bank-select register, channel 0
    OUT 0029, 01     ... channel 1
    OUT 0029, 02     ... channel 2
    OUT 0029, 03     ... channel 3
    OUT 001B, 00     8237 master clear
    OUT 0027, 00     DMA bank ch3 := 0
    OUT 0021, 00     DMA bank ch0 := 0
    OUT 0023, 00     DMA bank ch1 := 0
    OUT 0025, 00     DMA bank ch2 := 0
    OUT 0011, 40     8237 command register := 40h

### 2.2 Ports touched only on the ITF service path (`STOP`+`SHIFT`+`CTRL`)

Reached from `F80786` → `F81F8E`. Not on the normal boot path, listed for
completeness: `0BEh` (FDD interface mode change), `090h`/`092h`/`094h`
(640 KB FDC status/data/control), `0C8h`/`0CAh`/`0CCh` (1 MB FDC
status/data/control), and the 8237 setup at `F833DE`–`F83438`
(`009h`, `00Bh`, `00Dh`, `00Fh`, `015h`, `017h`, `019h`, `023h`, `025h`),
which ends in `FF E5  JMP BP`.

## 3. Every place the ITF polls a port and branches

Each entry says which value lets execution continue. Where a poll has no
timeout it is marked **hard**; a re-implementation that does not satisfy it
hangs the machine.

| addr | port | test | branch | what lets it continue |
|------|------|------|--------|-----------------------|
| `F80054` | `0439h` | `OR AL,AL` | `JNZ 007F` | either way is fine — `00h` means "cold start, reset the 8255/8251 first", non-zero skips that. `00h` is the safe reset value. |
| `F8008C` | `35h` | `TEST AL,80h` | `JNZ 0099` | **bit 7 must be 1**, else the ITF does `MOV SS,[0406] / MOV SP,[0404] / RETF` into whatever RAM happens to hold. Cold-start value `FFh` is correct. |
| `F8009B` | `35h` | `TEST AL,20h` | `JNZ 00BC` | **bit 5 must be 1**, else `SYSTEM SHUTDOWN` and hang at `F800BA`. |
| `F80119` | `42h` | `TEST AL,02h` | `JZ 012B` | **bit 1 must be 0**. If set: `OUT 37h,0Bh`, `OUT 0F0h,00h` (CPU reset) and `JMP $`. |
| `F8012D` | `42h` | `TEST AL,20h` | `JNZ 0133` | either — selects `043Fh := 42h` (bit set) or `40h` (bit clear). |
| `F8013E` | `33h` | `TEST AL,08h` | `JNZ 0148` | either — `06Eh := 01h` or `00h`. Also read at `F80165`, `F801D6`, `F801E5`, `F80218`, `F802C1`, `F80316`, `F80325`, `F80339`, always bit 3, always choosing between two GDC/CRT parameter sets. Bit 3 set selects the "07 90 65" SYNC timings. |
| `F80224`, `F80268` | `31h` | `TEST AL,08h` | `JZ`/`JNZ` | either — chooses the CRT parameter triple written to `70h`/`72h`/`74h`. |
| `F8029F` | `31h` | `TEST AL,04h` | `JZ 02A7` | either — bit set adds `OUT 68h,05h`. |
| `F802AD` | `42h` | `TEST AL,10h` | `JNZ 02B5` | either — bit clear adds `OUT 6Ah,41h`. |
| `F80476`, `F804B4` | `60h` | `TEST AL,04h` | `JZ` (loop) | **hard.** Text-GDC FIFO-empty. Bit 2 must eventually read 1 or the parameter writer never returns. A status port stuck at `00h` hangs here. |
| `F80484`, `F804C2` | `A0h` | `TEST AL,04h` | `JZ` (loop) | **hard.** Same for the graphic GDC. |
| `F8038A` | `60h` | `TEST AL,20h` | `JNZ 0388` | **hard.** Wait for VSYNC status *low*. |
| `F80390` | `60h` | `TEST AL,20h` | `JZ 038E` | **hard.** Then wait *high*. |
| `F80396` | `60h` | `TEST AL,20h` | `JNZ 0394` | **hard.** Then wait *low* again; the whole triple runs twice (`LOOP 0388`). Bit 5 of port `60h` must actually toggle. |
| `F803A4`, `F803B0`, `F803BC`, `F803D2` | `A0h` | `TEST AL,20h` | as above | **hard.** The same low/high/low sequence on the graphic GDC, three times, plus one more wait-for-high at `F803D0`. |
| `F804D9`, `F804DF` | `60h` | `TEST AL,20h` | `JZ`/`JNZ` | **hard.** The "wait one retrace" helper: wait for bit 5 == 0 then bit 5 == 1. Called ten times on the boot path. |
| `F80593` | (memory) | `OR DX,DX` | `JNZ 0595` | **hard.** The 32 KB ROM checksum must be zero. Silent hang. |
| `F805BB` | `42h` | `TEST AL,20h` | `JNZ 05C2` | either — PIT channel 1 divisor `03E6h` (set) or `04CDh` (clear). |
| `F80646` | `43h` | `TEST AL,01h` | `JZ 0642` | **hard.** Keyboard 8251 TxRDY. Every keyboard command send waits here with no timeout. `43h` reading `00h` hangs; `FFh` passes. |
| `F80661` | `43h` | `TEST AL,02h` | `JNZ 0669` | soft — RxRDY with a 32768-iteration timeout; timing out is a legal answer. |
| `F8067B` | `43h` | `TEST AL,02h` | `JNZ 0684` | soft — the power-on key scan, `3000h` iterations × 6. |
| `F80720` | `42h` | `TEST AL,20h` | `JNZ 0727` | either — beep divisor. |
| `F80822`, `F80828` | (memory) | `REP SCASD` / `SCASB` | `JNZ 0836` | soft — graphic VRAM at `A0000` must read back `FF/AA/55/00`; failure prints `TEXT VIDEO RAM ERROR` and continues. |
| `F8089B` | `7FDDh` | `TEST AL,04h` | `JNZ 08A8` | either — 0 = "Processor is 80386", 1 = "Processor is 70116 (V30)". Only on the information screen. |
| `F80906`, `F80918` | (memory) | via `F8092A` | `JNZ 0972` | soft — character-generator RAM test through `A1h`/`A3h`/`A5h` and the `A4000` window; failure prints `KANJI CG RAM ERROR`. |
| `F809BD` | `31h` | `TEST AL,10h` | `JZ 09FA` | either — bit set runs the memory-switch cell test at `A000:3FE2…`. |
| `F809DE` | (memory) | read/modify/verify | `JNZ 09ED` | soft — `MEMORY SWITCH ERROR`. |
| `F80A26` | CF from `F818BE` | `JC 0A58` | | soft-ish — base 128 KB must read back `01/FF/AA/55/00`; otherwise `MEMORY ERROR` then `CLI ; JMP $`. **Effectively hard.** |
| `F80A2A` | `33h` | `TEST AL,04h` | `JNZ 0A4F` | **bit 2 must read 0.** It is the parity-error latch; set means `PARITY ERROR` then `CLI ; JMP $`. |
| `F80AB2`, `F80ACD` | (memory) | `OR DX,DX` | `JZ` | **hard-ish.** With `043Dh := 12h` the system BIOS ROM must be visible at `F8000` (32 KB) and `E8000` (64 KB) and each must checksum to zero, else `ROM SUM ERROR`. |
| `F80B19` | `0F0h` | `TEST AL,20h` | `JNZ 0B45` | either — bit clear also shadows `D7000`→`97000`. |
| `F80B49` | `7FDBh` | `TEST AL,40h` | `JNZ 0B51` | either — `043Fh := 80h` (set) or `82h` (clear). |
| `F80BA7` | (memory) | `CMP [B000:0],AA55h` | `JZ 0BB3` | either — presence test for the bank-memory window opened by `043Fh := 22h`. |
| `F80BF1`, `F80C13` | `33h` | `TEST AL,04h` | `JNZ 0C23` | parity again, this time on the bank window; failure prints `EMS ERROR` and continues. |
| `F80C5F` | (memory) | `CMP [0000:0],55AAh` | `JZ 0C6B` | **hard.** A20 test: writing `F800:8000` must *not* alter `0000:0000`. Failure prints `ADDRESS 20 LINE ERROR` then `HLT`. |
| `F80CA1` | `71h`/`73h`/`75h` | `CMP AH,AL` | `JNZ 0CAD` | **hard.** 8253 latch-and-read-back on all three counters must return what was written (`FFh`, then `00h`). Failure: `TIMER ERROR` + `HLT`. |
| `F80CE3` | `01h`…`0Fh` | `CMP BX,AX` | `JNZ 0CF1` | **hard.** 8237 address/count register read-back, `FFh` then `00h`, all eight registers. Failure: `DMA ERROR` + `HLT`. |
| `F80D0B`, `F80D1F` | `02h`, `0Ah` | `CMP AH,AL` | `JNZ` | **hard.** 8259 IMR read-back on master and slave, `00h` then `FFh`. Failure: `TIMER INTERRUPT ERROR` + `HLT`. |
| `F80D4B` | `AH` | `TEST AH,0FFh` | `JZ 0D57` | **hard.** With the master IMR at `FFh` no IRQ0 may reach the CPU during 32 polls. |
| `F80D6F` | `AH` | `TEST AH,0FFh` | `JNZ 0D7D` | **hard.** After `OUT 71h` counter0 := `001Ah` and `OUT 02h,0FEh`, **IRQ0 must fire within 32 polls**. Failure: `TIMER INTERRUPT ERROR` + `HLT`. |
| `F80D96` | `31h` | `TEST AL,10h` | `JZ 0DDA` | either — bit set writes the memory-switch defaults. |
| `F80DB9` | `7FDBh` | `TEST AL,40h` | `JNZ 0DC2` | either — memory-switch byte `+0Ah` := `04h` or `03h`. |
| `F80DFA` | (memory) | `CMP DH,AL` | `JNZ 0DFF` | either — compares the measured extended-memory size against the memory-switch value at `A000:3FEA`; mismatch keeps testing, match jumps to `F80E93`. |
| `F80EA1` | `42h` | `TEST AL,02h` | `JZ 0EA8` | **bit 1 clear enters protected mode** at `F80F5E`. Bit 1 set skips straight to `F812B4`. |
| `F80EEB` | (registers) | `REP SCASW` | `JZ 0EF0` | **hard.** `LIDT`/`LGDT` then `SIDT`/`SGDT` must return the same 10 bytes for `FFFF`, `AAAA`, `5555`, `0000`. Failure → `F81263` → `PPI-C bit 5 := 1`, `OUT 0F0h,00h`, CPU reset. |
| `F812B6` | `42h` | `TEST AL,02h` | `JNZ 12C2` | bit 1 set → straight to the final configuration. |
| `F812BE` | `7FDDh` | `TEST AL,04h` | `JZ 12C5` | bit 2 clear (386 mode) → the second protected-mode entry at `F8130E`; bit 2 set → `F8174B`. |
| `F8176F`, `F81786`, `F81792` | `43h`/`41h` | keyboard reply | | soft — sends `9Fh` and looks for `FAh`, `A0h`, `80h`; a timeout just leaves `0000:0481` bit 6 clear. |
| `F817A1` | `7FDBh` | `TEST AL,40h` | `JNZ 17A9` | either — `043Fh := 80h` or `82h`. |
| `F817B2` | `0F0h` | `TEST AL,40h` | `JNZ 17C5` | either — bit clear reads `0CC4h` into `0000:0484`. |
| `F817C9` | `0F0h` | `TEST AL,20h` | `JNZ 17D0` | either — `053Dh := 06h` or `46h`. |
| `F817E4` | `7FDDh` | `TEST AL,04h` | `JZ 17FB` | **bit 2 clear (386 mode) causes a deliberate CPU reset**: `PPI-C bit 7 := 0`, `SS:SP` saved to `0000:0404/0406`, `OUT 0F0h,07h`, `HLT`. Execution must come back at `F80000`, take the `bit 7 == 0` branch at `F8008C`, and `RETF` to `F817FB`. Bit 2 set skips all of that. |
| `F81843` | `42h` | `TEST AL,02h` | `JNZ 185A` | either — bit clear runs `FNINIT`/`FNSTSW` and sets MP in CR0 if a 387 answered. |
| `F81EF7`, `F81F05` | (memory) | `CMP AX,3333h` / `5555h` | `JNZ 1F1B` | either — GRCG plane test; result only sets or clears bit 6 of `0000:054D`. |
| `F81F7F` | `A0h` | `TEST AL,02h` | `JNZ 1F77` | **hard.** Graphic-GDC FIFO-full must clear. |
| `F81F8A` | `A0h` | `TEST AL,04h` | `JZ 1F82` | **hard.** Graphic-GDC FIFO-empty must set. |

### 3.1 `F8343A` and the FDC polls (service path only)

The brief asked specifically about `F8343A`. It is reached only from
`F81F8E`, i.e. only when `STOP`+`SHIFT`+`CTRL` were held at power-on
(`AH == 91h` at `F80773`). On the ordinary boot path this code never runs.

```
F8343A  33C9           XOR CX,CX                   ; --- wait for the FDC to go not-busy ---
F8343C  E4BE           IN AL,0BEh
F8343E  A801           TEST AL,01h
F83440  740B           JZ   344Dh
F83442  E490           IN AL,90h
F83444  A810           TEST AL,10h
F83446  E0FA           LOOPNE 3442h
F83448  7538           JNZ  3482h
F8344A  F8             CLC
F8344B  FFE4           JMP SP
F8344D  E4C8           IN AL,0C8h
F8344F  A810           TEST AL,10h
F83451  E0FA           LOOPNE 344Dh
F83453  752D           JNZ  3482h
F83455  F8             CLC
F83456  FFE4           JMP SP
F83458  33C9           XOR CX,CX                   ; --- write one command byte to the FDC ---
F8345A  E4BE           IN AL,0BEh
F8345C  A801           TEST AL,01h
F8345E  7411           JZ   3471h
F83460  E490           IN AL,90h
F83462  24C0           AND AL,0C0h
F83464  3C80           CMP AL,80h
F83466  E0F8           LOOPNE 3460h
F83468  7518           JNZ  3482h
F8346A  8AC4           MOV AL,AH
F8346C  E692           OUT 92h,AL
F8346E  F8             CLC
F8346F  FFE4           JMP SP
F83471  E4C8           IN AL,0C8h
F83473  24C0           AND AL,0C0h
F83475  3C80           CMP AL,80h
F83477  E0F8           LOOPNE 3471h
F83479  7507           JNZ  3482h
F8347B  8AC4           MOV AL,AH
F8347D  E6CA           OUT 0CAh,AL
F8347F  F8             CLC
F83480  FFE4           JMP SP
F83482  F9             STC
F83483  FFE4           JMP SP
F83485  33C9           XOR CX,CX                   ; --- read one result byte from the FDC ---
F83487  E4BE           IN AL,0BEh
F83489  A801           TEST AL,01h
F8348B  740F           JZ   349Ch
F8348D  E490           IN AL,90h
F8348F  24C0           AND AL,0C0h
F83491  3CC0           CMP AL,0C0h
F83493  E0F8           LOOPNE 348Dh
F83495  75EB           JNZ  3482h
F83497  E492           IN AL,92h
F83499  F8             CLC
F8349A  FFE4           JMP SP
F8349C  E4C8           IN AL,0C8h
F8349E  24C0           AND AL,0C0h
F834A0  3CC0           CMP AL,0C0h
F834A2  E0F8           LOOPNE 349Ch
F834A4  75DC           JNZ  3482h
F834A6  E4CA           IN AL,0CAh
F834A8  F8             CLC
F834A9  FFE4           JMP SP
```

Read as three FDC primitives, each selecting between the 640 KB interface
(`90h`/`92h`) and the 1 MB interface (`C8h`/`CAh`) on **bit 0 of port `0BEh`**
(1 → 640 KB side, 0 → 1 MB side):

* **`F8343A` — wait not-busy.** `XOR CX,CX` gives 65536 tries. `TEST AL,10h`
  sets ZF when MSR bit 4 (FDC busy, `CB`) is *clear*, and `LOOPNE` continues
  while ZF == 0, i.e. **while the FDC still reports busy**. It falls out either
  when bit 4 reads 0 (then `JNZ` is not taken, `CLC`, return with CF=0 = OK) or
  when `CX` reaches 0 with bit 4 still set (`JNZ 3482` → `STC`, CF=1 = timeout).
  **To continue: MSR bit 4 must read 0 within 65536 polls.**
* **`F83458` — send a command byte.** Waits for `MSR & C0h == 80h`
  (RQM=1, DIO=0 → the FDC wants a byte from the CPU), then `OUT 92h/0CAh, AH`.
  Same 65536-try `LOOPNE`, CF=1 on timeout.
  **To continue: MSR bits 7..6 must read `10b`.**
* **`F83485` — read a result byte.** Waits for `MSR & C0h == C0h`
  (RQM=1, DIO=1), then `IN AL,92h/0CAh`. **To continue: MSR bits 7..6 must
  read `11b`.**

`F834AB`/`F834C8` are the keyboard companion: reset the 8251 with commands
`3Ah`, `32h`, `16h`, then wait up to `4000h` polls for `43h` bit 1 (RxRDY)
and require the byte read from `41h` to be **`61h`** (the keyboard self-test
reply). CF=1 otherwise.

### 3.2 The reported hang at `08383`, and the `000C` / `000D` writes

The observation is "writes ports `000C` and `000D`, then the CPU reads around
address `08383` repeatedly".

`8383h` is the **low 16 bits of `F8383`**, and `F80383` is:

```
F80381  B000           MOV AL,00h
F80383  E66C           OUT 6Ch,AL                  ; border colour register 06Ch := 00h
F80385  B90200         MOV CX,2h
F80388  E460           IN AL,60h                   ; --- text-GDC vertical-sync poll (3 edges, twice) ---
F8038A  A820           TEST AL,20h                 ; port 60h bit5 = VSYNC/VBLANK status
F8038C  75FA           JNZ  388h
F8038E  E460           IN AL,60h
F80390  A820           TEST AL,20h
F80392  74FA           JZ   38Eh
F80394  E460           IN AL,60h
F80396  A820           TEST AL,20h
F80398  75FA           JNZ  394h
F8039A  E2EC           LOOP 388h
```

The mapping is exact, not approximate: the ROM occupies `F8000`–`FFFFF`, so
`(F8000 + off) & FFFF == 8000 + off`, and `8383h` can only be ROM offset
`0383h`. `F80383` is the last instruction before the ITF starts waiting for
**bit 5 of the text-GDC status port `60h`** to go low, then high, then low —
twice over (`CX = 2`). With `60h` stuck at any constant value the CPU spins on
`F80388`–`F8038C` (if bit 5 reads 1) or `F8038E`–`F80392` (if it reads 0)
forever, and the instruction fetches sit exactly where the hardware trace put
them. No other spin loop in the image lands near `8383h`: the complete list of
self-jumps in the ROM is `8004`–`802D` and `8048` (the CPU flag/register
self-test traps), `80BA` (`SYSTEM SHUTDOWN`), `8129` (waiting for the CPU reset
it just asked for), `8595` (ROM checksum), `8A56`/`8A62` (memory error),
`9E53` (message control bit 7), and `A03E`/`A048`/`A052`/`B5C1`/`B5E0` in the
service mode. Nothing in the ROM reads a fixed RAM address around linear
`08383` in a loop either. I am confident this is the hang.

The `000C`/`000D` half I cannot reconcile cleanly, and I would rather say so
than invent a story. **This ROM never executes `OUT 0Ch` or `OUT 0Dh` on the
boot path.** The only `OUT 0Dh,AL` instructions in the whole image are at
`F8341E` and `F83424`, inside the DMA setup that is reachable only from the
service path, and there is no `OUT 0Ch,AL` anywhere. The candidates, best
first:

1. **The values `0Dh` and `0Ch`, not the ports.** At `F803C6` the ITF writes
   `0Dh` to `A2h` and then to `62h` (µPD7220 `BCTRL`, display on) and at
   `F803DC` writes `0Ch` to the same two ports (display off). Those are the
   only places in the boot path where `0Ch` and `0Dh` appear as data on
   consecutive writes — but they come *after* the `F80388` loop, so if the
   machine really stops at `8383` it never reaches them.
2. **A truncated port number.** The last port written before entering the
   loop is `6Ch` (`F80383  OUT 6Ch,AL` — the border-colour register, value
   `00h`). If the trace only captured the low nibble of the port, `6Ch` shows
   as `Ch`. Nothing on the path writes a port whose low nibble is `Dh` at that
   point, so this explains one of the two writes and not the other.
3. **The service path was entered.** If the keyboard interface returns
   plausible-looking garbage the key scan at `F80672` could in principle
   produce `AH == 91h` and divert to `F81F8E`, where `OUT 0Dh` (DMA channel 3
   address, `F8341E`/`F83424`) is genuinely executed. But `F81F8E` runs
   `OUT 0BEh`, `OUT 94h`/`0CCh`, and the FDC polls first, and it would have to
   get past `F80388` to have run at all — the observed hang address says it
   did not.

So: the `8383` hang is the GDC vertical-sync wait; the `000C`/`000D` writes
are most likely the border-colour write at `F80383` plus one more the trace
attributed to a port number, and I could not pin the second one down.

## 4. The hand-over: `OUT 043Dh, 12h`

Port `043Dh` is the ROM bank select. `10h` maps the ITF ROM at `F8000`;
`12h` maps the system BIOS ROM there instead. The ITF writes `12h` in two
different places, and only the second is the hand-over.

**(a) `F80A9D` — temporary, inside the shadow stub.** The stub copied to
`0000:0000` writes `043Dh := 12h` so that it can checksum and copy the real
BIOS ROM, and finishes with `043Dh := 10h` at `F80B6A` to map the ITF back in.
This is not the hand-over.

**(b) `F81892` — the real hand-over.** Because the write itself unmaps the
code that is executing, the ITF assembles a six-byte stub in low RAM and
jumps to it:

```
F8186F  B00F           MOV AL,0Fh
F81871  E637           OUT 37h,AL                  ; PPI-C bit7 := 1 (SHUT0)
F81873  EB00           JMP SHORT 1875h
F81875  EB00           JMP SHORT 1877h
F81877  B00A           MOV AL,0Ah
F81879  E637           OUT 37h,AL                  ; PPI-C bit5 := 0
F8187B  C706F804EEEA   MOV WORD PTR [04F8h],0EAEEh ; 0000:04F8 = EE EA  -> OUT DX,AL ; JMP FAR ...
F81881  C706FA040200   MOV WORD PTR [04FAh],2h     ; 0000:04FA = 02 00  -> offset 0002h
F81887  C706FC0480FD   MOV WORD PTR [04FCh],0FD80h ; 0000:04FC = 80 FD  -> segment FD80h
F8188D  BA3D04         MOV DX,43Dh                 ; DX = 043Dh
F81890  B012           MOV AL,12h                  ; AL = 12h
F81892  EAF8040000     JMP FAR 0h:4F8h             ; --- HAND-OVER: run the stub, which does OUT 043Dh,12h then JMP FAR FD80:0002 ---
```

`0000:04F8` ends up holding

    EE            OUT DX,AL              ; DX = 043Dh, AL = 12h
    EA 02 00 80 FD  JMP FAR FD80:0002

so the sequence is: set `DX = 043Dh` and `AL = 12h` in ROM, far-jump to
`0000:04F8`, write `12h` to `043Dh` (the ITF vanishes from `F8000` at that
instant), and far-jump into the system BIOS at **`FD80:0002`** (linear
`FD802`). Note the PPI writes immediately before: `PPI-C bit 7 := 1` and
`PPI-C bit 5 := 0`, which is exactly the combination that, on the next CPU
reset, sends `F8009B` down the `SYSTEM SHUTDOWN` branch rather than a cold
start.

**Everything that must succeed before `F81892` is reached**, in order:

1. `F80000`–`F8004E` CPU flag and register self-test — no I/O, but every step
   must produce the architecturally correct flags.
2. `F8008C` port `35h` bit 7 must read 1; `F8009B` bit 5 must read 1.
3. `F80119` port `42h` bit 1 must read 0.
4. `F8013C`–`F8042D` the whole display initialisation, including the
   **hard** GDC FIFO waits (`60h`/`A0h` bit 2) and the **hard** vertical-sync
   waits (`60h`/`A0h` bit 5).
5. `F80593` the 32 KB ROM checksum must be zero.
6. `F80646` every keyboard command send must see `43h` bit 0 (TxRDY).
7. `F80822`/`F80906`/`F809DE` VRAM, CG and memory-switch tests — these only
   print a message and carry on, so they are not blocking.
8. `F80A26`/`F80A2A` the base 128 KB must read back correctly and `33h` bit 2
   (parity) must be 0, or the ITF stops with `CLI ; JMP $`.
9. `F80AB2`/`F80ACD` with `043Dh := 12h`, the BIOS ROM at `F8000` (32 KB) and
   the extension ROM at `E8000` (64 KB) must each checksum to zero, and the
   shadow copy to `98000`/`88000` must work.
10. `F80C5F` the A20 test — `F800:8000` must not alias `0000:0000`.
11. `F80CA1` 8253 latch/read-back on all three counters.
12. `F80CE3` 8237 address/count read-back on channels 0–3.
13. `F80D0B`/`F80D1F` 8259 master and slave IMR read-back.
14. `F80D4B` no interrupt while masked, then `F80D6F` **IRQ0 must actually
    fire** once counter 0 is loaded with `001Ah` and the master IMR is `FEh`.
15. `F80EEB` the descriptor-table registers must survive `LGDT`/`SGDT` and
    `LIDT`/`SIDT`, then the protected-mode block at `38h:1064h` must return.
16. `F817E4` in 386 mode, the deliberate CPU reset must round-trip: `OUT 0F0h,07h`
    must reset the CPU, the ITF must restart at `F80000`, see `35h` bit 7 == 0,
    and `RETF` through `0000:0404`/`0406` back to `F817FB`.
17. `F81861` a final PIT setup, `F8186C` the GRCG/EGC probe (`A0h` FIFO polls,
    **hard**).

Only then does `F8187B` build the stub and `F81892` jump to it.

## 5. What a re-implementation has to provide, in the order the ITF demands it

1. **A correct 8086-compatible flag model, and 386 instructions.** The first
   79 bytes are a flag self-test that hangs on any discrepancy, and the ROM
   later needs `66`-prefixed string ops, `SHL r32,imm`, `PUSH imm16`,
   `SHL r8,imm8`, `LGDT/LIDT/SGDT/SIDT/SMSW/LMSW` and `FNINIT/FNSTSW`.
2. **Port `0439h`** readable and writable. Returning `00h` is the safe answer.
3. **8255 #1 at `31h`/`33h`/`35h`/`37h`** with a working bit-set/reset control
   port. Port C must read back what was written: after `OUT 37h,92h` and
   `OUT 35h,0FFh` the read at `F8008A` must give bit 7 = 1 and bit 5 = 1.
   Port `33h` bit 2 (parity latch) must read 0.
4. **8255 #2 at `42h`/`46h`.** `42h` bit 1 must read 0. Bits 4 and 5 only
   select variants.
5. **8253 at `71h`/`73h`/`75h`/`77h`** with real counters: the latch command
   (`00h`/`40h`/`80h`) must return what was loaded, and channel 0 must generate
   IRQ0.
6. **Twin µPD7220 at `60h`/`62h` and `A0h`/`A2h`.** This is the biggest single
   requirement and the one the observed hang is about. The status ports must
   provide, at minimum: bit 2 = FIFO empty (must become 1), bit 1 = FIFO full
   (must become 0), and **bit 5 = vertical sync/blank, which must actually
   toggle**. The command/parameter FIFO must accept the blocks listed in §1.7
   without stalling.
7. **The mode registers `68h`, `6Ah`, `6Ch`, `6Eh`, `70h`–`76h`, `7Ch`, `7Eh`**
   as write-only sinks at the very least; the GRCG (`7Ch`/`7Eh`) must really
   work if `0000:054D` bit 6 is to be set correctly, but a non-working GRCG only
   clears a flag, it does not hang.
8. **A ROM image whose 32 KB word-wise checksum is zero.**
9. **Keyboard 8251 at `41h`/`43h`.** Status bit 0 (TxRDY) must read 1 — this is
   an untimed wait and is the second most likely place to hang. Bit 1 (RxRDY)
   may stay 0 forever; every receive has a timeout.
10. **8259 pair at `00h`/`02h` and `08h`/`0Ah`** with a readable IMR and a real
    IRQ0 path from PIT channel 0.
11. **8237 at `01h`–`1Fh` plus the bank registers `21h`–`27h` and `29h`**, with
    readable 16-bit address and count registers.
12. **Bank/ROM control: `043Dh`** (`10h` = ITF, `12h` = BIOS), **`043Fh`**,
    **`0461h`**, **`0467h`**, **`053Dh`**, and a shadow-RAM region at `88000`
    and `98000` that can be written when `0461h := 0Eh` and read back after
    `0461h := 0Ch`.
13. **A system BIOS ROM behind `043Dh = 12h`**: 32 KB at `F8000` and 64 KB at
    `E8000`, each checksumming to zero, with an entry point at `FD80:0002`.
14. **A 21-bit (or wider) address bus** — `F800:8000` must not wrap onto
    `0000:0000`.
15. **At least 128 KB of base RAM** that passes the `FF/AA/55/00` pattern test,
    plus whatever extended memory is claimed by the memory-switch byte at
    `A000:3FEA`.
16. **`OUT 0F0h` must reset the CPU** and restart execution at `F800:0000` with
    the PPI port C latch preserved, because the ITF uses that as its way back
    from protected mode. It writes `07h` at `F81E9D` and `00h` at `F81E98`.
17. **`0F2h`, `0F6h`** (protected-mode/A20 gate) and **`0F0h` read** (mode
    status bits 5 and 6).
18. **`7FDBh`, `7FDDh`, `7FDFh`, `0CC4h`** as readable configuration ports.
    `7FDDh` bit 2 is the one that matters: **0 selects the 386 path**, which
    includes the protected-mode tests and the CPU-reset round trip; **1 selects
    the V30 path**, which skips both. If the reset round trip is not
    implemented, reporting `7FDDh` bit 2 = 1 is the cheap way past it — at the
    cost of the machine calling itself a V30.
19. The graphic VRAM planes at `A8000`/`B0000` (and `A0000`/`A2000` text,
    `A4000` CG window, `A000:3FE0`+ memory switches) — failures here only
    print messages.
20. Nothing at all for the FDC or the service-mode DMA setup, unless
    `STOP`+`SHIFT`+`CTRL` is to work.

## Appendix A — messages in the ROM

Each message is `attribute byte, ASCIIZ text, control byte`; control bit 0 =
beep, bit 1 = keep the buzzer on, bit 7 = `CLI ; JMP $` after printing.

| addr | attr | ctl | text |
|------|------|-----|------|
| `F81B34` | 43 | 83 | `SYSTEM SHUTDOWN` |
| `F81B46` | 43 | 83 | `ROM SUM ERROR` |
| `F81B56` | 43 | 83 | `TEXT VIDEO RAM ERROR` |
| `F81B6D` | C1 | 00 | `KANJI CG RAM ERROR` |
| `F81B82` | C1 | 00 | `MEMORY SWITCH ERROR` |
| `F81B98` | C1 | 00 | `GRAPHICS VIDEO RAM ERROR` |
| `F81BB3` | C1 | 00 | `EMS ERROR` |
| `F81BBF` | E1 | 00 | `MEMORY 000KB OK` |
| `F81BD1` | 41 | 83 | `MEMORY ERROR` |
| `F81BE0` | 41 | 83 | `PARITY ERROR   0000` |
| `F81BF6` | 41 | 83 | `ADDRESS 20 LINE ERROR` |
| `F81C0E` | C1 | 00 | `MEMORY ERROR` |
| `F81C1D` | C1 | 00 | `PARITY ERROR   0000` |
| `F81C33` | C1 | 01 | `MEMORY SIZE ERROR` |
| `F81C47` | 41 | 83 | `TIMER ERROR` |
| `F81C55` | 41 | 83 | `DMA ERROR` |
| `F81C61` | 41 | 83 | `TIMER INTERRUPT ERROR` |
| `F81C79` | 41 | 83 | `PROTECTED MODE ERROR` |
| `F81C90` | 43 | 83 | `PARITY ERROR - BASE MEMORY` |
| `F81CAD` | 43 | 83 | `PARITY ERROR - EXTENDED MEMORY` |
| `F81CCE` | 43 | 83 | `SIMM SETTING ERROR` |
| `F81CE3` | A9 | 00 | `Initial Test Firmware       (C) NEC 1988` |
| `F81D0E` | E1 | 00 | `Processor  is  80386` |
| `F81D25` | E1 | 00 | `Processor  is  70116 (V30)` |
| `F81D42` | E1 | 00 | `CPU Clock  is  20MHz` |
| `F81D59` | E1 | 00 | `CPU Clock  is  16MHz` |
| `F81D70` | E1 | 00 | `CPU Clock  is  8MHz` |
| `F81D86` | E1 | 00 | `Resolution is  Normal (640x400)` |
| `F81DA8` | E1 | 00 | `Resolution is  Hireso (1120x750)` |

## Appendix B — data regions

| range | contents |
|-------|----------|
| `F800E5`–`F80100` | port table 1 (13 entries) |
| `F803EE`–`F803F9` | port table 2 (5 entries) |
| `F8042F`–`F8045E` | analogue palette table, 16 × (G,R,B) |
| `F804E5`–`F8057E` | µPD7220 parameter blocks |
| `F805E6`–`F805FB` | port table 3 (10 entries) |
| `F80F63`–`F80FE2` | 128 bytes copied to `0000:8000` — IDT/GDT pseudo-descriptors for the first protected-mode entry |
| `F80FE3`–`F80FE8` | the descriptor prototype the loop at `F80F10`–`F80F30` expands into 256 GDT entries |
| `F80F63`–`F8125F` | this whole region also contains the protected-mode code entered at `38h:1064h`; **not disassembled** |
| `F81313`–`F8174A` | likewise for the second entry (`38h:159Dh`), including its own template at `F81416`; **not disassembled** |
| `F81B34`–`F81DCA` | messages |
| `F81E88`–`F81E97` | `"0123456789ABCDEF"` for the hex printer |
| `F8205E`–`F833DD` | 1248 × (C,H,R,N) — the format ID table for a 1.2 MB 2HD disk, 8 sectors of 1024 bytes × 2 heads × 78 tracks (service mode) |

## Appendix C — unreferenced code

`F8196F` (an NMI/parity handler that reads `33h` bit 1/2 and prints
`PARITY ERROR - BASE MEMORY` / `- EXTENDED MEMORY`) and `F8199A` (a spurious-
interrupt handler that reads the 8259 ISR through `OUT 00h,0Bh` / `IN AL,00h`
and issues the right EOI) are complete and correct routines that nothing in
this image installs. They are presumably installed by the system BIOS after
the hand-over, or are left over from a shared source tree.
