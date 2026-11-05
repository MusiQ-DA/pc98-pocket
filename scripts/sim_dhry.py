#!/usr/bin/env python3
"""sim_dhry.py -- build the Dhrystone-kernel replay images (scripts/sim_dhry.sh).

CPUBENCH 0.980's benchmark routine (sim/z86_tests/dhry_kernel.hex, the
1C28h bytes CPUBENCH copies to a 64 KB boundary and far-calls) is placed at
2000:0000 with its loop count patched to N, under a stub at 9000:0000 that
points INT 20h and INT FFh (tb_z86_loop's and tb_mem_perf's IRQ vectors) at
a counting IRET, sets up a stack, enables interrupts, far-calls the kernel,
then CLI / HLT at 9002Bh (tb_mem_perf stops on the CLI: a halted
z86 reports that PC).

    sim_dhry.py <outdir> <loops> [expect.hex]

Writes <outdir>/dhry.mem (1 MB, tb_z86_loop +mem), dhry.img (640 KB,
tb_mem_perf +img), dhry.prog (the stub, tb_z86_loop +prog at 90000), and --
given the expected kernel bytes 20000-21AFF after the run -- dhry.ref (the
image with them in place, tb_mem_perf +imgref).
"""
import os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KERNEL = os.path.join(HERE, '..', 'sim', 'z86_tests', 'dhry_kernel.hex')
LO, HI = 0x20000, 0x21B00          # the kernel's code+data, not its stack
LOOP_IMM = 0x153                   # cmp di,7530h -> cmp di,N
STOP = 0x9002C


def kernel(n):
    k = bytearray(int(l, 16) for l in open(KERNEL) if l.strip() and not l.startswith('//'))
    assert len(k) == 0x1C28 and k[LOOP_IMM:LOOP_IMM + 2] == b'\x30\x75'
    k[LOOP_IMM:LOOP_IMM + 2] = struct.pack('<H', n)
    return bytes(k)


def stub():
    irq = 0x2D
    s = bytes([0xFA, 0x31, 0xC0, 0x8E, 0xD8])                       # cli; xor ax,ax; mov ds,ax
    s += b'\xC7\x06\x80\x00' + struct.pack('<H', irq)               # [0080] = irq_h
    s += b'\xC7\x06\x82\x00\x00\x90'                                # [0082] = 9000
    s += b'\xC7\x06\xFC\x03' + struct.pack('<H', irq)               # [03FC] = irq_h
    s += b'\xC7\x06\xFE\x03\x00\x90'                                # [03FE] = 9000
    s += b'\xB8\x00\x80\x8E\xD0\xBC\xF0\xFF'                        # ss = 8000, sp = FFF0
    s += b'\xFB'                                                    # sti
    s += b'\x9A\x00\x00\x00\x20'                                    # call 2000:0000
    assert len(s) == STOP - 0x90000 - 1
    s += b'\xFA\xF4'                                                # cli; hlt  (9002C)
    assert len(s) == irq
    s += b'\x2E\xFF\x06\xF0\x06\xCF'                                # inc word [cs:06F0]; iret
    return s


def image(n):
    m = bytearray(b'\x90' * 0x100000)
    m[0:0x400] = bytes(0x400)
    k = kernel(n)
    m[LO:LO + len(k)] = k
    s = stub()
    m[0x90000:0x90000 + len(s)] = s
    return m


def hexf(path, data):
    with open(path, 'w') as f:
        f.write(''.join(f'{b:02x}\n' for b in data))


if __name__ == '__main__':
    out, n = sys.argv[1], int(sys.argv[2])
    os.makedirs(out, exist_ok=True)
    m = image(n)
    hexf(os.path.join(out, 'dhry.mem'), m)
    hexf(os.path.join(out, 'dhry.img'), m[:0xA0000])
    p = bytearray(b'\xF4' * 4096); s = stub(); p[:len(s)] = s
    hexf(os.path.join(out, 'dhry.prog'), p)
    if len(sys.argv) > 3:
        e = bytes(int(l, 16) for l in open(sys.argv[3]) if l.strip() and not l.startswith('//'))
        assert len(e) == HI - LO
        r = bytearray(m[:0xA0000]); r[LO:HI] = e
        hexf(os.path.join(out, 'dhry.ref'), r)
