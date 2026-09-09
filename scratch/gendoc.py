#!/usr/bin/env python3
import io, sys
src = open('/Users/hiroya/repo/pc98-pocket/scratch/dis8086.py').read().replace('\nmain()\n','\n')
g={'__name__':'d8'}; exec(compile(src,'dis8086.py','exec'), g)
Dis=g['Dis']
rom=open('/Users/hiroya/.pc98roms/itf.rom','rb').read()
d=Dis(rom,0)

C = {}
def c(a,t): C[a]=t

def dis(a,b):
    out=[]
    pc=a
    while pc<b:
        n,t,info=d.decode(pc)
        raw=''.join('%02X'%x for x in rom[pc:n])
        line='F8%04X  %-14s %-28s'%(pc,raw,t)
        cm=C.get(pc)
        out.append((line.rstrip() if not cm else line+'; '+cm))
        pc=n
    return '\n'.join(out)

def data(a,b,per=16):
    out=[]
    for i in range(a,b,per):
        out.append('F8%04X  %s'%(i,' '.join('%02X'%x for x in rom[i:min(i+per,b)])))
    return '\n'.join(out)

# ---------------- annotations ----------------
for a,t in [
 (0x0000,'interrupts off for the whole ITF'),
 (0x0001,'D5h = SF,ZF,AF,PF,CF all set'),
 (0x0003,'load AH into FLAGS'),
 (0x0004,'each J** $-2 is a self-test trap: wrong flag => hang here forever'),
 (0x000C,'CF=0'),
 (0x000D,'AF is still 1, so AAS must SET CF'),
 (0x0014,'1*2 => no overflow'),
 (0x0018,'AH=0 -> SAHF clears SF,ZF,AF,PF,CF'),
 (0x0023,'CF=1'),
 (0x0024,'AF is now 0, so AAS must CLEAR CF'),
 (0x002B,'7Fh*20h=0FE0h => OF set'),
 (0x002F,'register/segment-register walking-bit test starts here'),
 (0x0046,'DI must equal AX after the chain of moves'),
 (0x004A,'next pattern: FFFF, AAAA, 5555, 0000'),
 (0x004D,'CF=0 while patterns remain'),
 (0x004F,'--- 0439h: system control register ---'),
 (0x0052,'dummy read then real read'),
 (0x0054,'0439h == 0 -> cold start, do the full PPI/PIT reset'),
 (0x0056,'0439h != 0 -> skip to 007F'),
 (0x0058,'8255 #1 control: mode set 92h (A=in, B=in, C=out)'),
 (0x0062,'PPI port C := FFh (all output bits high, incl. SHUT0/SHUT1)'),
 (0x0067,'keyboard 8251 command register: 3x 00h = force async idle'),
 (0x0074,'8251 internal reset'),
 (0x007D,'8251 mode byte 5Eh (async, 8N1, x16)'),
 (0x007F,'re-read 0439h'),
 (0x0080,'keep bit1'),
 (0x0082,'set bits 2,4,5'),
 (0x0084,'0439h := (old & 02h) | 34h'),
 (0x008A,'--- restart-mode dispatch: PPI port C ---'),
 (0x008C,'bit7 (SHUT0). 0 => "return from reset" path'),
 (0x0090,'restore SS:SP from 0000:0404/0406 and RETF -- the PC-98 shutdown-return'),
 (0x0099,'bit5. 1 => normal cold start at 00BC'),
 (0x009D,'bit5 == 0 => SYSTEM SHUTDOWN message path'),
 (0x00A0,'display init, returns to 00A3 via JMP BP'),
 (0x00A3,'wait for text-GDC FIFO, returns to 00A9 via JMP SP'),
 (0x00AB,'GDC command 0Dh = BCTRL, display ON (text GDC)'),
 (0x00AF,'MODE FF1: reg7 := 1'),
 (0x00B1,'message "SYSTEM SHUTDOWN"'),
 (0x00BA,'hang'),
 (0x00BC,'--- normal cold start ---'),
 (0x00BE,'8253 control: 70h = counter1, LSB+MSB, mode 0, binary'),
 (0x00C6,'counter1 low := 00'),
 (0x00CE,'counter1 high := 00 (count 65536, mode 0 = one-shot, never reloads)'),
 (0x00D0,'--- port-initialisation table walker ---'),
 (0x00D6,'first word: AL->CL = entry count, AH->DH = high byte of every port'),
 (0x00DC,'each entry: AL = data byte, AH -> DL = low byte of port'),
 (0x00E0,'DX = DH:DL = the 16-bit port'),
 (0x00E3,'SI now points past the table -> continue at 0101h'),
 (0x0101,'7FDFh := 93h (386 board control)'),
 (0x010B,'0467h := 00h'),
 (0x0111,'0461h := 08h (shadow/window control: ROM through, RAM write-protected)'),
 (0x0117,'--- printer 8255 port B = hardware configuration ---'),
 (0x0119,'bit1 must be 0'),
 (0x011D,'bit1 set: PPI-C bit5 := 1 ...'),
 (0x0123,'... then write 0F0h = CPU RESET, and wait for it'),
 (0x012B,'BL = 42h'),
 (0x012D,'42h bit5 (clock group)'),
 (0x0131,'bit5 clear -> BL = 40h'),
 (0x0133,'043Fh := 42h or 40h'),
 (0x0139,'return address for the whole display-init block'),
 (0x013C,'--- display initialisation ---'),
 (0x013E,'DIP SW (port 33h) bit3 = display timing / 24k-31k'),
 (0x0144,'06Eh := 00h'),
 (0x014A,'06Eh := 01h'),
 (0x014C,'GDC block 04E5 (RESET), AH=40h: text GDC, no FIFO wait'),
 (0x0157,'GDC block 04E7 (6Fh VSYNC master), text GDC'),
 (0x0165,'33h bit3 again: pick SYNC parameter block'),
 (0x0176,'GDC block 04FD (47h PITCH,50h)'),
 (0x0181,'GDC block 0500 (46h ZOOM,00)'),
 (0x018C,'GDC block 0503 (70h PRAM 0-15)'),
 (0x0199,'MODE FF1: reg0 := 1'),
 (0x01A1,'wait 2 x text-GDC vertical sync (04D7)'),
 (0x01CD,'42h bit3'),
 (0x01D6,'33h bit3'),
 (0x0203,'graphic GDC command port := 0Fh (SYNC, DE=1)'),
 (0x0212,'GRCG mode register := 4Fh'),
 (0x0216,'MODE FF2 := 81h'),
 (0x0218,'33h bit3'),
 (0x0220,'MODE FF1: reg4 := 0'),
 (0x0222,'DIP SW (port 31h) bit3'),
 (0x022A,'CRT parameter registers 70h/72h/74h'),
 (0x029D,'31h bit2'),
 (0x02A5,'MODE FF1: reg2 := 1'),
 (0x02A9,'076h := 00h'),
 (0x02AB,'42h bit4'),
 (0x02B3,'MODE FF2 := 41h'),
 (0x02C1,'33h bit3 -> graphic GDC SYNC extra parameters'),
 (0x02CD,'graphic GDC parameter port'),
 (0x02D1,'graphic GDC command port'),
 (0x0383,'border colour register 06Ch := 00h'),
 (0x0388,'--- text-GDC vertical-sync poll (3 edges, twice) ---'),
 (0x038A,'port 60h bit5 = VSYNC/VBLANK status'),
 (0x03A2,'--- graphic-GDC vertical-sync poll (3 edges) ---'),
 (0x03C6,'0Dh = BCTRL display ON, to both GDCs'),
 (0x03D0,'wait for graphic-GDC VSYNC once more'),
 (0x03DC,'0Ch = BCTRL display OFF, to both GDCs'),
 (0x03E6,'MODE FF1: reg1 := 0'),
 (0x03E8,'run the second port table at 03EE'),
 (0x03FC,'MODE FF2 := 01h (analogue palette access)'),
 (0x0404,'palette index = -CL & 0Fh'),
 (0x040A,'palette index register'),
 (0x040E,'green / red / blue components from the table at 042F'),
 (0x041C,'MODE FF2 := 00h'),
 (0x0420,'MODE FF1: reg7 := 1'),
 (0x0427,'A000:3FE0 = text-screen line counter used by the message printer'),
 (0x042D,'return to 057Fh (or 00A3h on the shutdown path)'),
 (0x045F,'--- GDC parameter-block writer.  BX -> block, AH bit7: 0=text 1=graphic, bit6: skip FIFO wait ---'),
 (0x0474,'text GDC status port 60h bit2 = FIFO EMPTY'),
 (0x0482,'graphic GDC status port A0h bit2 = FIFO EMPTY'),
 (0x048E,'CL = byte count'),
 (0x049C,'first byte -> command port (62h / A2h)'),
 (0x049D,'DX -= 2 -> parameter port (60h / A0h)'),
 (0x04A4,'re-check FIFO every 16 bytes'),
 (0x04D5,'return'),
 (0x04D7,'--- wait one text-GDC vertical retrace ---'),
 (0x04D9,'port 60h bit5: wait low, then wait high'),
 (0x057F,'--- 32 KB ROM checksum ---'),
 (0x058C,'sum even bytes into DL and odd bytes into DH'),
 (0x0593,'DX must be 0000'),
 (0x0595,'silent hang -- the display is not usable yet'),
 (0x059E,'--- 8253 PIT setup ---'),
 (0x05A0,'control 30h = counter0, LSB+MSB, mode 0'),
 (0x05A8,'counter0 := 0000'),
 (0x05B9,'42h bit5 selects the PIT input clock constant'),
 (0x05C4,'control 76h = counter1, LSB+MSB, mode 3'),
 (0x05CC,'counter1 := 03E6h (bit5 set) or 04CDh (bit5 clear)'),
 (0x05DC,'control B6h = counter2, LSB+MSB, mode 3'),
 (0x05E0,'run the third port table at 05E6'),
 (0x05FC,'--- 8259 master: ICW1 11h, ICW2 08h, ICW3 80h, ICW4 1Dh ---'),
 (0x060E,'--- 8259 slave: ICW1 11h, ICW2 10h, ICW3 07h, ICW4 09h ---'),
 (0x0621,'--- keyboard: send command byte AH ---'),
 (0x0627,'8251 command 37h (TxEN,DTR,RxE,ER,RTS)'),
 (0x063B,'data out'),
 (0x0644,'status bit0 = TxRDY: wait until the byte has left'),
 (0x064C,'8251 command 16h (RxE,ER,RTS)'),
 (0x0655,'--- keyboard: wait for a byte, ~32768 polls ---'),
 (0x065F,'status bit1 = RxRDY'),
 (0x0667,'timeout: return with ZF=1'),
 (0x066E,'read the byte'),
 (0x0672,'--- collect up to 6 keys held at power-on ---'),
 (0x0679,'RxRDY'),
 (0x0681,'nothing pressed -> AH stays 0'),
 (0x0689,'make code'),
 (0x068B,'60h -> AH bit7'),
 (0x0694,'70h (SHIFT) -> bit0'),
 (0x069D,'74h (CTRL)  -> bit4'),
 (0x06A6,'73h (GRPH)  -> bit3'),
 (0x06AF,'72h (KANA)  -> bit2'),
 (0x06B8,'71h (CAPS)  -> bit1'),
 (0x06C7,'keyboard command 9Dh, up to 4 tries, expect FAh (ACK)'),
 (0x06D5,'FAh = ACK'),
 (0x06E5,'A000:3FF6 memory-switch byte -> keyboard command 7xh'),
 (0x0714,'--- STOP-key dispatch ---'),
 (0x0716,'AH bit7 = scan code 60h was held'),
 (0x0719,'held -> skip the beep and every RAM/VRAM test'),
 (0x071E,'42h bit5 -> beep divisor'),
 (0x0729,'PPI-C bit3 := 0  (buzzer ON, active low)'),
 (0x0734,'PPI-C bit3 := 1  (buzzer OFF)'),
 (0x0738,'counter1 mode 3, divisor DX then DX*2 -- the two-tone boot beep'),
 (0x076D,'go on to the VRAM tests'),
 (0x0770,'mask off KANA and CAPS'),
 (0x0773,'STOP+SHIFT+CTRL exactly -> ITF service mode'),
 (0x077A,'0F2h := 00h, 0F6h := 02h'),
 (0x0785,'0567h := B0h'),
 (0x0786,'--- entry to the floppy/ITF service mode (off the normal path) ---'),
 (0x0789,'STOP held: clear the BIOS work area and skip all tests'),
 (0x07E2,'053Dh := 02h'),
 (0x07E8,'0461h := 08h'),
 (0x07EC,'--- graphic VRAM clear and pattern test (A0000) ---'),
 (0x0822,'mismatch -> TEXT VIDEO RAM ERROR'),
 (0x082D,'patterns FF, AA, 55, 00'),
 (0x083E,'display on so the message can be seen'),
 (0x084D,'fill text VRAM with 0020h and the attribute plane with 00E1h'),
 (0x0877,'AH==1Eh (CTRL+GRPH+KANA+CAPS) -> print the machine information screen'),
 (0x0897,'7FDDh bit2: 0 = 80386 mode, 1 = 70116 (V30) mode'),
 (0x08B6,'42h bit5: 0 = 20MHz, 1 = 16MHz'),
 (0x08F7,'MODE FF1: reg5 := 1 (character-generator RAM access on)'),
 (0x092A,'CG code low / high / line select'),
 (0x0972,'KANJI CG RAM ERROR'),
 (0x097D,'MODE FF1: reg5 := 0'),
 (0x097F,'MODE FF2 := 01h'),
 (0x09B5,'GRCG off, MODE FF2 := 00h, draw page := 0'),
 (0x09BB,'31h bit4'),
 (0x09C1,'MODE FF1: reg6 := 1 (memory-switch area writable)'),
 (0x09D2,'read/modify/verify the memory-switch cells A000:3FE2,3FE6,...'),
 (0x09ED,'MEMORY SWITCH ERROR'),
 (0x09F6,'MODE FF1: reg6 := 0'),
 (0x0A00,'PPI-C bit4 := 0 (parity check off while filling)'),
 (0x0A07,'fill 128 KB at segment BX with EAX'),
 (0x0A12,'PPI-C bit4 := 1 (parity check on)'),
 (0x0A23,'verify 128 KB'),
 (0x0A28,'33h bit2 = parity error latch'),
 (0x0A4F,'parity error report, then CLI/JMP $'),
 (0x0A58,'memory error report, then CLI/JMP $'),
 (0x0A79,'0000:0402 := shift/ctrl/graph flags'),
 (0x0A88,'copy 200h bytes of stub from CS:0A96 to 0000:0000'),
 (0x0A91,'and run it from RAM'),
 (0x0A96,'--- ROM shadow stub, executes at 0000:0000 ---'),
 (0x0A9D,'043Dh := 12h  -- ITF ROM out, system BIOS ROM in'),
 (0x0AA4,'checksum F8000-FFFFF'),
 (0x0AC1,'checksum E8000-F7FFF'),
 (0x0AD6,'first pass?'),
 (0x0AE2,'043Fh := 80h'),
 (0x0AE8,'0461h := 0Eh (shadow RAM writable)'),
 (0x0AFB,'F8000-FFFFF -> 98000'),
 (0x0B0E,'E8000-F7FFF -> 88000'),
 (0x0B16,'0461h := 0Ch'),
 (0x0B17,'0F0h bit5'),
 (0x0B22,'053Dh := 40h'),
 (0x0B34,'D7000 -> 97000'),
 (0x0B41,'043Fh := C2h'),
 (0x0B48,'7FDBh bit6'),
 (0x0B54,'043Fh := 80h or 82h'),
 (0x0B5A,'053Dh := 02h'),
 (0x0B5C,'second pass: re-verify with the shadow active'),
 (0x0B64,'0461h := 08h'),
 (0x0B6A,'043Dh := 10h  -- ITF ROM back in'),
 (0x0B6B,'back into ROM'),
 (0x0B70,'CF set by the stub => ROM SUM ERROR'),
 (0x0B8F,'043Fh := 22h (window in)'),
 (0x0BA6,'043Fh := 20h (window out)'),
 (0x0BA7,'B000:0 must have kept AA55h -> bank memory present'),
 (0x0BBD,'PPI-C bit4 := 0'),
 (0x0BC6,'fill/verify the 64 KB bank window'),
 (0x0BEF,'parity'),
 (0x0C23,'EMS ERROR'),
 (0x0C4D,'043Fh := 20h'),
 (0x0C52,'--- A20 test: write F800:8000 (linear 100000h) ---'),
 (0x0C59,'0000:0000 must NOT have changed'),
 (0x0C61,'ADDRESS 20 LINE ERROR, then HLT'),
 (0x0C73,'PPI-C bit3 := 0'),
 (0x0C87,'--- 8253 read-back test on counters 0,1,2 ---'),
 (0x0C89,'control: 10h/50h/90h = counter n, LSB only, mode 0'),
 (0x0C98,'control: 00h/40h/80h = latch counter n'),
 (0x0CA3,'TIMER ERROR, then HLT'),
 (0x0CC6,'re-run the PIT setup'),
 (0x0CC9,'01Bh: DMA master clear'),
 (0x0CD7,'--- 8237 register read-back on 01,03,05,07,09,0B,0D,0F ---'),
 (0x0CF1,'DMA ERROR, then HLT'),
 (0x0CFD,'DMA command register := 40h'),
 (0x0D03,'--- 8259 IMR read-back, master 02h and slave 0Ah ---'),
 (0x0D0D,'TIMER INTERRUPT ERROR, then HLT'),
 (0x0D38,'IRQ0 vector 0000:0020 := F800:0D89'),
 (0x0D47,'IMR is still FFh: no interrupt may arrive'),
 (0x0D59,'counter0 := 001Ah'),
 (0x0D6A,'master IMR := FEh -- unmask IRQ0'),
 (0x0D6C,'--- IRQ0 must now fire within 32 polls ---'),
 (0x0D73,'TIMER INTERRUPT ERROR, then HLT'),
 (0x0D89,'IRQ0 handler: AH=FF, mask everything again, EOI'),
 (0x0D94,'31h bit4'),
 (0x0D9C,'MODE FF1: reg6 := 1'),
 (0x0DB8,'7FDBh bit6'),
 (0x0DD8,'MODE FF1: reg6 := 0'),
 (0x0DE3,'"MEMORY 000KB OK" then size the extended memory from segment 2000h up'),
 (0x0E01,'PPI-C bit4 := 0 / 1 around each 128 KB block'),
 (0x0E9F,'42h bit1: 1 -> skip the protected-mode test'),
 (0x0EC6,'LIDT/LGDT/SIDT/SGDT walking-bit test of the descriptor registers'),
 (0x0F42,'0F2h := 00h, 0F6h := 02h  (A20 / protected-mode gate)'),
 (0x0F54,'PPI-C bit7 := 0  -- arm the shutdown-return path'),
 (0x0F5B,'enter protected mode'),
 (0x0F5E,'unresolved: protected-mode code, selector 38h offset 1064h'),
 (0x1263,'PROTECTED MODE ERROR path: PPI-C bit5 := 1 then 0F0h := 00h (CPU reset)'),
 (0x12B4,'42h bit1'),
 (0x12BD,'7FDDh bit2 (V30 mode)'),
 (0x12C2,'-> final configuration'),
 (0x130E,'unresolved: second protected-mode entry, selector 38h offset 159Dh'),
 (0x174B,'--- final configuration and hand-over ---'),
 (0x1759,'keyboard: send 00h'),
 (0x1761,'keyboard: send 9Fh (read ID), expect FAh then A0h then 80h'),
 (0x1798,'0000:0481 bit6 := 1 (new-type keyboard)'),
 (0x17A0,'7FDBh bit6'),
 (0x17AC,'043Fh := 80h or 82h, then 20h'),
 (0x17B0,'0F0h bit6'),
 (0x17B9,'0CC4h bits0-1 -> 0000:0484'),
 (0x17C7,'0F0h bit5'),
 (0x17D5,'053Dh := 06h or 46h'),
 (0x17DD,'0461h := 08h'),
 (0x17E3,'7FDDh bit2: in 386 mode ...'),
 (0x17EA,'PPI-C bit7 := 0'),
 (0x17F0,'... save SS:SP at 0000:0404/0406 ...'),
 (0x17F8,'... and reset the CPU; execution resumes at 17FB through 0000:0404'),
 (0x17FF,'42h -> 0000:0500 machine-type byte'),
 (0x1841,'42h bit1 clear -> probe for a 387'),
 (0x1847,'FNINIT / FNSTSW AX'),
 (0x1850,'set MP in CR0 if a coprocessor answered'),
 (0x1861,'re-run the PIT setup one last time'),
 (0x186C,'GRCG / EGC presence test'),
 (0x1871,'PPI-C bit7 := 1 (SHUT0)'),
 (0x1879,'PPI-C bit5 := 0'),
 (0x187B,'--- build the 6-byte hand-over stub in RAM at 0000:04F8 ---'),
 (0x187B,'0000:04F8 = EE EA  -> OUT DX,AL ; JMP FAR ...'),
 (0x1881,'0000:04FA = 02 00  -> offset 0002h'),
 (0x1887,'0000:04FC = 80 FD  -> segment FD80h'),
 (0x188D,'DX = 043Dh'),
 (0x1890,'AL = 12h'),
 (0x1892,'--- HAND-OVER: run the stub, which does OUT 043Dh,12h then JMP FAR FD80:0002 ---'),
 (0x1897,'--- fill 2 x 64 KB at segment BX with EAX ---'),
 (0x18BE,'--- verify 2 x 64 KB at segment BX against EAX; CF=1 on mismatch ---'),
 (0x19BF,'--- print "MEMORY nnnKB OK" ---'),
 (0x1ACC,'--- parity-error report ---'),
 (0x1B1C,'--- short beep ---'),
 (0x1DCB,'--- message printer: SI -> attr, ASCIIZ text, control byte ---'),
 (0x1DE7,'31h bit2 selects the text-VRAM stride (2 or 4 bytes per cell)'),
 (0x1E2D,'control bit0 = beep'),
 (0x1E4D,'control bit7 = halt after printing'),
 (0x1E57,'--- print AL as two hex digits at DS:SI ---'),
 (0x1E98,'0F0h := 00h then HLT  -- CPU reset'),
 (0x1E9D,'0F0h := 07h then HLT  -- CPU reset'),
 (0x1EA2,'--- GRCG / EGC presence test ---'),
 (0x1EA4,'GRCG mode := 80h (GRCG on, TDW off)'),
 (0x1EA8,'tile registers: plane0=33h, plane1=55h, plane2=00h, plane3=00h'),
 (0x1EB6,'GDC FIGS 4Ch, CSRW 49h EAD=4000h (wraps to offset 0 of a 32KB plane), WDAT 20h FFFFh'),
 (0x1EEC,'GRCG off'),
 (0x1EF3,'A800:0000 must read 3333h'),
 (0x1F01,'B000:0000 must read 5555h'),
 (0x1F12,'0000:054D bit6 := 1 (GRCG/EGC present)'),
 (0x1F3F,'--- EGC probe ---'),
 (0x1F51,'EGC register 04A0h := FFF0h (word)'),
 (0x1F5F,'--- write a GDC command byte (waits for FIFO not full) ---'),
 (0x1F6B,'--- write a GDC parameter byte ---'),
 (0x1F77,'A0h bit1 = FIFO FULL'),
 (0x1F82,'A0h bit2 = FIFO EMPTY'),
 (0x1F8E,'--- ITF service mode (STOP+SHIFT+CTRL) ---'),
 (0x33DE,'--- 8237 setup for the floppy transfer (service mode only) ---'),
 (0x343A,'--- wait for the FDC to go not-busy ---'),
 (0x3458,'--- write one command byte to the FDC ---'),
 (0x3485,'--- read one result byte from the FDC ---'),
 (0x34AB,'--- reset the keyboard 8251 ---'),
 (0x34C8,'--- wait for the keyboard self-test reply 61h ---'),
]:
    c(a,t)

def tbl(a):
    w = rom[a] | (rom[a+1] << 8); i = a + 2
    cnt = w & 0xFF; hi = w >> 8
    ents = []
    for _ in range(cnt):
        ww = rom[i] | (rom[i+1] << 8)
        ents.append((i, (hi << 8) | (ww >> 8), ww & 0xFF)); i += 2
    return cnt, hi, ents, i

def tbltext(a):
    cnt, hi, ents, end = tbl(a)
    L = ['first word at F8%04X = %04X -> count %d, port high byte %02X, table body F8%04X..F8%04X, walker resumes at F8%04X'
         % (a, rom[a] | (rom[a+1] << 8), cnt, hi, a+2, end-1, end), '']
    for ea, p, v in ents:
        L.append('    F8%04X:  OUT %04X, %02X' % (ea, p, v))
    return '\n'.join(L)

def blockdump(a):
    n = rom[a]; b = list(rom[a+1:a+1+n])
    return 'F8%04X  count=%2d  cmd=%02X  params=%s' % (a, n, b[0], ' '.join('%02X' % x for x in b[1:]) or '-')

out = io.StringIO()
W = out.write

import re
IOPORTS = {
 0x00:'8259 master ICW1/OCW2/OCW3', 0x02:'8259 master ICW2/3/4, IMR',
 0x08:'8259 slave  ICW1/OCW2/OCW3', 0x0A:'8259 slave  ICW2/3/4, IMR',
 0x01:'8237 ch0 address', 0x03:'8237 ch0 count', 0x05:'8237 ch1 address', 0x07:'8237 ch1 count',
 0x09:'8237 ch2 address', 0x0B:'8237 ch2 count', 0x0D:'8237 ch3 address', 0x0F:'8237 ch3 count',
 0x11:'8237 command / status', 0x13:'8237 request', 0x15:'8237 single mask', 0x17:'8237 mode',
 0x19:'8237 clear byte-pointer FF', 0x1B:'8237 master clear', 0x1D:'8237 clear mask', 0x1F:'8237 all mask',
 0x21:'DMA bank ch0', 0x23:'DMA bank ch1', 0x25:'DMA bank ch2', 0x27:'DMA bank ch3',
 0x29:'DMA bank select / extension',
 0x31:'8255 #1 port A (DIP SW 2)', 0x33:'8255 #1 port B (DIP SW 1 / status)',
 0x35:'8255 #1 port C (SHUT0/SHUT1, buzzer, parity enable)', 0x37:'8255 #1 control (mode / bit set-reset)',
 0x40:'8255 #2 port A (printer data)', 0x42:'8255 #2 port B (hardware configuration)',
 0x44:'8255 #2 port C', 0x46:'8255 #2 control',
 0x41:'keyboard 8251 data', 0x43:'keyboard 8251 command / status',
 0x50:'NMI / interrupt control', 0x52:'NMI control',
 0x60:'text GDC parameter / status', 0x62:'text GDC command',
 0x64:'text VSYNC interrupt reset', 0x68:'MODE FF1 (bit set/reset)', 0x6A:'MODE FF2 (bit set/reset)',
 0x6C:'border colour', 0x6E:'MODE FF3 / CRT select',
 0x70:'CRT parameter (HBP)', 0x72:'CRT parameter (HFP)', 0x74:'CRT parameter (VBP)', 0x76:'CRT parameter (VFP)',
 0x71:'8253 counter 0', 0x73:'8253 counter 1', 0x75:'8253 counter 2', 0x77:'8253 control',
 0x7C:'GRCG mode register', 0x7E:'GRCG tile register',
 0x90:'FDC (640K i/f) main status', 0x92:'FDC (640K i/f) data', 0x94:'FDC (640K i/f) control',
 0xA0:'graphic GDC parameter / status', 0xA1:'CG code (low)', 0xA2:'graphic GDC command',
 0xA3:'CG code (high)', 0xA4:'display page', 0xA5:'CG line select', 0xA6:'draw page',
 0xA8:'palette index / digital palette', 0xA9:'CG data',
 0xAA:'palette green', 0xAC:'palette red', 0xAE:'palette blue',
 0xBE:'FDD interface mode change', 0xC8:'FDC (1MB i/f) main status', 0xCA:'FDC (1MB i/f) data',
 0xCC:'FDC (1MB i/f) control',
 0xF0:'CPU reset / mode status', 0xF2:'A20 / protected-mode gate', 0xF6:'A20 / protected-mode gate',
 0x0439:'system control register', 0x043B:'', 0x043D:'ROM bank select (ITF / BIOS)',
 0x043F:'bus and window control', 0x0461:'shadow-RAM / ROM window control', 0x0467:'shadow-RAM control',
 0x04A0:'EGC register', 0x053D:'shadow / cache control', 0x0567:'', 0x0CC4:'', 
 0x7FDB:'system configuration', 0x7FDD:'CPU mode (V30 / 386)', 0x7FDF:'386 board control',
}

def ioscan(a, b, label=None):
    rows = []
    al = ah = ax = dx = None
    pc = a
    while pc < b:
        n, t, info = d.decode(pc)
        m = re.match(r'^MOV AL,([0-9A-F]+)h$', t)
        if m: al = int(m.group(1), 16)
        m = re.match(r'^MOV AH,([0-9A-F]+)h$', t)
        if m: ah = int(m.group(1), 16)
        m = re.match(r'^MOV AX,([0-9A-F]+)h$', t)
        if m: ax = int(m.group(1), 16); al = ax & 0xFF; ah = ax >> 8
        m = re.match(r'^MOV DX,([0-9A-F]+)h$', t)
        if m: dx = int(m.group(1), 16)
        if t == 'MOV AL,AH': al = ah
        elif t.startswith('MOV AL,') or t.startswith('XOR AL') or t.startswith('AND AL') \
             or t.startswith('OR AL') or t.startswith('SUB AL') or t.startswith('ADD AL'):
            if not re.match(r'^MOV AL,[0-9A-F]+h$', t): al = None
        elif re.match(r'^(XOR|AND|OR|ADD|SUB|MOV) AX,', t) and not re.match(r'^MOV AX,[0-9A-F]+h$', t):
            al = ah = None
        elif t.startswith('IN AL') or t.startswith('IN AX'):
            al = ah = None
        if 'io' in info:
            d0, port, wide = info['io']
            pname = ('DX=%04Xh' % dx) if port == 'DX' and dx is not None else \
                    ('DX=?' if port == 'DX' else '%02Xh' % port)
            pnum = dx if port == 'DX' else port
            if d0 == 'IN':
                rows.append((pc, 'R', pnum, pname, '', t))
                al = ah = None
            else:
                if wide:
                    v = '%04Xh' % ax if ax is not None else '?'
                else:
                    v = '%02Xh' % al if al is not None else '?'
                rows.append((pc, 'W', pnum, pname, v, t))
        pc = n
    return rows

OV = {
 0x0084: (None, '(0439h & 02h) | 34h'),
 0x0138: (None, '42h or 40h (42h bit5)'),
 0x02CD: (None, 'DDh or 88h (33h bit3)'),
 0x02D1: (None, '2Ch or 32h (33h bit3)'),
 0x040A: (None, '0Fh down to 00h'),
 0x040E: (None, 'from the table at F8042F'),
 0x0412: (None, 'from the table at F8042F'),
 0x0416: (None, 'from the table at F8042F'),
 0x049C: ('62h or A2h', 'byte 0 of the block = GDC command'),
 0x04D2: ('60h or A0h', 'bytes 1.. of the block = GDC parameters'),
 0x05CC: (None, 'low byte of 03E6h or 04CDh'),
 0x05D4: (None, 'high byte of 03E6h or 04CDh'),
 0x063B: (None, 'AH = 00h / 9Dh / 7xh / 9Fh'),
 0x0740: (None, 'low byte of 03E6h or 04CDh'),
 0x0748: (None, 'high byte of the same'),
 0x0763: (None, 'low byte of the divisor doubled'),
 0x076B: (None, 'high byte of the same'),
 0x092C: (None, 'CG code low byte 20h..7Fh'),
 0x0930: (None, 'CG code high byte 56h then 57h'),
 0x0C89: (None, '10h, 50h, 90h'),
 0x0C91: ('71h, 73h, 75h', 'FFh then 00h'),
 0x0C98: (None, '00h, 40h, 80h (latch)'),
 0x0C9E: ('71h, 73h, 75h', None),
 0x0CC9: (None, 'B6h (any value; master clear ignores data)'),
 0x0CD7: ('01h,03h,05h,07h,09h,0Bh,0Dh,0Fh', 'FFh then 00h'),
 0x0CDA: ('01h..0Fh', 'FFh then 00h'),
 0x0CDD: ('01h..0Fh', None),
 0x0CE0: ('01h..0Fh', None),
 0x0D03: (None, '00h then FFh'),
 0x0D17: (None, '00h then FFh'),
 0x0D63: (None, '00h'),
 0x0D7F: (None, '00h'),
 0x0D85: (None, '00h'),
 0x0F42: (None, '00h'),
 0x12F2: (None, '00h'),
 0x17AC: (None, '80h or 82h (7FDBh bit6)'),
 0x17D5: (None, '06h or 46h (0F0h bit5)'),
 0x1F68: (None, 'GDC command byte (4Ch, 49h, 20h)'),
 0x1F74: (None, 'GDC parameter byte'),
}

def iotable(ranges):
    L = ['| addr | R/W | port | value | port function |',
         '|------|-----|------|-------|---------------|']
    for r in ranges:
        if isinstance(r, str):
            L.append('| | | | | **%s** |' % r)
            continue
        a, b = r
        for pc, rw, pnum, pname, v, t in ioscan(a, b):
            fn = IOPORTS.get(pnum, '') if pnum is not None else ''
            if pc in OV:
                op, ov = OV[pc]
                if op: pname = op
                if ov: v = ov
            L.append('| F8%04X | %s | `%s` | %s | %s |' % (pc, rw, pname, v or '—', fn))
    return '\n'.join(L)

MAIN_IO = [
 'CPU / register self-test (F80000-F8004E): no I/O',
 (0x004F, 0x0085),
 'restart-mode dispatch',
 (0x0085, 0x008E),
 'normal cold start',
 (0x00BC, 0x00D0),
 'port table 1 walked by F800D3 (see 2.1)',
 (0x0101, 0x013C),
 'display initialisation (the GDC block writer at F8045F and the retrace wait at F804D7 are inlined below where they are first used)',
 (0x013C, 0x03EE),
 'port table 2 walked by F800D3 (see 2.1)',
 (0x03FA, 0x042F),
 'GDC block writer F8045F-F804E4, entered many times from the block above',
 (0x045F, 0x04E5),
 'ROM checksum and 8253 setup',
 (0x057F, 0x05E0),
 'port table 3 walked by F800D3 (see 2.1)',
 (0x05FC, 0x0621),
 'keyboard 8251 primitives, entered many times',
 (0x0621, 0x0714),
 'boot beep',
 (0x0714, 0x076F),
 'VRAM / CG / memory-switch / base-RAM tests',
 (0x07EC, 0x0A96),
 'ROM shadow stub, running from RAM at 0000:0000',
 (0x0A96, 0x0B70),
 'bank memory, A20, 8253, 8237, 8259, IRQ0',
 (0x0B70, 0x0D94),
 'memory-switch defaults and extended-memory sizing',
 (0x0D94, 0x0F63),
 'protected-mode return paths',
 (0x1263, 0x126C),
 (0x12B4, 0x1313),
 'final configuration and hand-over',
 (0x174B, 0x1897),
 'helpers: memory fill / verify, "MEMORY nnnKB OK", parity report, beep',
 (0x1897, 0x18F1),
 (0x19BF, 0x1B34),
 'helpers: message printer, hex printer, CPU reset, GRCG/EGC probe, GDC byte writers',
 (0x1DCB, 0x1F8D),
]

def msgs():
    L = ['| addr | attr | ctl | text |', '|------|------|-----|------|']
    a = 0x1B34
    while a < 0x1DCB:
        e = rom.index(b'\0', a + 1)
        if e + 1 >= 0x1DCB: break
        L.append('| `F8%04X` | %02X | %02X | `%s` |' % (a, rom[a], rom[e+1], rom[a+1:e].decode('latin1')))
        a = e + 2
    return '\n'.join(L)

BLOCKS = [0x4E5,0x4E7,0x4E9,0x4F3,0x4FD,0x500,0x503,0x515,0x51A,0x51F,0x524,0x529,
          0x52B,0x52D,0x537,0x541,0x544,0x547,0x54A,0x54D,0x55F,0x569,0x56B,0x575]

def expand(text):
    def rep(m):
        k = m.group(1)
        if k == 'iotable': return iotable(MAIN_IO)
        if k == 'msgs': return msgs()
        if k == 'blocks': return '\n'.join(blockdump(x) for x in BLOCKS)
        kind, rng = k.split(':')
        a, b = [int(x, 16) for x in rng.split('-')] if '-' in rng else (int(rng, 16), None)
        if kind == 'dis': return dis(a, b)
        if kind == 'data': return data(a, b)
        if kind == 'tbl': return tbltext(a)
        raise SystemExit('bad key ' + k)
    return re.sub(r'\{\{([^}]+)\}\}', rep, text)

body = open('/Users/hiroya/repo/pc98-pocket/scratch/body.md').read() + \
       open('/Users/hiroya/repo/pc98-pocket/scratch/body2.md').read()
open('/Users/hiroya/repo/pc98-pocket/docs/PC98_ITF_TRACE.md','w').write(expand(body))
print('written', len(expand(body)), 'bytes')
