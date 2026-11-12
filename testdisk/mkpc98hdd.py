#!/usr/bin/env python3
"""mkpc98hdd.py -- lay out a bootable PC-98 hard-disk image (FreeDOS(98) or
the user's own NEC MS-DOS 5/6) for the core's SCSI Hard Disk slot.

The disk is the shape the core's SCSI option ROM (fpga/scsi_rom.asm) and the
PC-98 DOSes expect:

  LBA 0        PC-98 IPL ("IPL1" at +4, 55AA at +0FEh and +1FEh). The ROM loads
               LBA 0-1 (1024 bytes) to 1FC0:0000 and far-calls it with
               DISK_BOOT [0584h] = A0h.
  LBA 1        PC-98 partition table: 16 x 32-byte entries; entry 0 is the DOS
               partition, mid A1h (bootable | DOS) / sid A1h (active | FAT16),
               IPL / start / end as {sector, head, cylinder}, zero-based.
  cyl 1 ...    the DOS partition: FAT16, 512-byte logical sectors, its PBR =
               the FreeDOS(98) FAT16 HD loader with this BPB and the fd98
               extension fields (sysPartStart, sysPhysicalBPS,
               sysRootDirStart, ...) filled in, as SYS.COM would.

The IPL is sava/LP-Project's btnpart MBR (public domain): it reads the
partition table riding along at +200h, loads the active entry's IPL sector to
1F80:0000 with INT 1Bh AH=06h (CHS, DA/UA A0h) and jumps there with SI = the
entry's offset (200h + 32 x index). The PBR is the FreeDOS(98) FAT16 HD loader
(GPL-2.0, nec98/boot/boot.asm of github.com/lpproj/fdkernel): it finds a file
in the root by its 11-byte name (offset 1F3h), follows its FAT chain reading
by LBA (INT 1Bh AH=06h, DA/UA & 7Fh = 20h for SCSI), loads it to 0060:0000
and jumps there with SI handed back -- the NEC DOS 5+ hand-off, so with the
name patched to "IO      SYS" the same loader starts NEC MS-DOS 5/6's IO.SYS
(--system msdos), which reads the boot partition from SI.

IPL, PBR, KERNEL.SYS / COMMAND.COM / COUNTRY.SYS / \\FDOS are read out of the
FreeDOS(98) release disk FD98_HD_250M.hdi (fd98_hd_250m_20220123.zip, the
github.com/lpproj/fdkernel test-20220120-cherrypick release).

The filesystem is written here, not with mtools: short names are cp932
(Shift_JIS, kana/kanji kept, only ASCII a-z upper-cased) and names that are
not valid 8.3 get a NAME~N alias plus VFAT long-name entries, which DOS
ignores. mtools' cp932 short names drop characters (a "注意.TXT" became "注").

Containers, one body: --nhd (T98-Next, any geometry), --vhd (Virtual98 .hdd,
any geometry; np2kai mounts .hdd as SCSI), --hdn (flat; np21w's fixed 8 heads
x 25 sectors geometry, np2kai mounts it as SCSI too). The core takes all three
(firmware/scsi_service.c scsi_probe).
"""
import argparse
import datetime
import os
import shutil
import struct
import sys
import zipfile

SECTOR = 512
SKIP = {".DS_Store", "@eaDir", "Thumbs.db", ".AppleDouble", "#recycle",
        ".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems",
        "desktop.ini"}
SHORT_BAD = set(b' "*+,./:;<=>?[\\]|')


# --------------------------------------------------------------------------
# FAT16 reader (for the release disk)
# --------------------------------------------------------------------------
class FatReader:
    def __init__(self, f, base):
        self.f, self.base, self.bps = f, base, SECTOR
        b = self.sec(0)
        (self.bps, self.spc, self.res, self.nfat, self.nroot, _, _, self.fsz
         ) = struct.unpack_from("<HBHBHHBH", b, 11)
        self.root = self.res + self.nfat * self.fsz
        self.data = self.root + self.nroot * 32 // self.bps
        self.fat = self.read(self.res, self.fsz)

    def read(self, lsec, n):
        self.f.seek(self.base + lsec * self.bps)
        return self.f.read(n * self.bps)

    def sec(self, n):
        return self.read(n, 1)

    def chain(self, c):
        while 2 <= c < 0xFFF8:
            yield c
            c = struct.unpack_from("<H", self.fat, c * 2)[0]

    def clusters(self, c):
        return b"".join(self.read(self.data + (x - 2) * self.spc, self.spc)
                        for x in self.chain(c))

    def entries(self, raw):
        for i in range(0, len(raw), 32):
            e = raw[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x08:
                continue
            base, ext = e[:8].rstrip(b" "), e[8:11].rstrip(b" ")
            name = (base + (b"." + ext if ext else b"")).decode("cp932")
            if name in (".", ".."):
                continue
            yield name, e

    def lookup(self, path):
        raw = self.read(self.root, self.nroot * 32 // self.bps)
        e = None
        for part in path.upper().split("/"):
            e = dict(self.entries(raw))[part]
            if e[11] & 0x10:
                raw = self.clusters(struct.unpack_from("<H", e, 26)[0])
        return e

    def file(self, path):
        e = self.lookup(path)
        size = struct.unpack_from("<I", e, 28)[0]
        return self.clusters(struct.unpack_from("<H", e, 26)[0])[:size]

    def extract(self, path, dest):
        """Copy a directory tree out to DEST (mtimes from the entries)."""
        e = self.lookup(path)
        self._extract(self.clusters(struct.unpack_from("<H", e, 26)[0]), dest)
        os.utime(dest, (dos_time(e), dos_time(e)))

    def _extract(self, raw, dest):
        os.makedirs(dest, exist_ok=True)
        for name, e in self.entries(raw):
            p = os.path.join(dest, name)
            first = struct.unpack_from("<H", e, 26)[0]
            if e[11] & 0x10:
                self._extract(self.clusters(first), p)
            else:
                size = struct.unpack_from("<I", e, 28)[0]
                open(p, "wb").write(self.clusters(first)[:size])
            os.utime(p, (dos_time(e), dos_time(e)))


def dos_time(e):
    t, d = struct.unpack_from("<HH", e, 22)
    dt = datetime.datetime(1980 + (d >> 9), max(1, (d >> 5) & 15), max(1, d & 31),
                           t >> 11, (t >> 5) & 63, (t & 31) * 2)
    return dt.timestamp()


def lift_fd98(zpath, tmp):
    """IPL, PBR and the FreeDOS(98) system files out of FD98_HD_250M.hdi."""
    with zipfile.ZipFile(zpath) as z:
        name = [n for n in z.namelist() if n.lower().endswith(".hdi")][0]
        hdi = os.path.join(tmp, "fd98.hdi")
        with z.open(name) as src, open(hdi, "wb") as dst:
            shutil.copyfileobj(src, dst)
    sysd = os.path.join(tmp, "fd98sys")
    with open(hdi, "rb") as f:
        hdr = struct.unpack("<8I", f.read(32))
        hsize, ssize, spt, heads = hdr[2], hdr[4], hdr[5], hdr[6]
        assert ssize == SECTOR, "fd98 disk is not 512-byte"
        f.seek(hsize)
        ipl = f.read(SECTOR)
        pt = f.read(SECTOR)
        s, h, c = pt[8], pt[9], struct.unpack_from("<H", pt, 10)[0]
        part = hsize + ((c * heads + h) * spt + s) * SECTOR
        f.seek(part)
        pbr = f.read(SECTOR)
        assert ipl[4:8] == b"IPL1" and ipl[0xFE:0x100] == b"\x55\xAA", "IPL?"
        assert pbr[3:11] == b"FreeDOS " and pbr[0x36:0x3E] == b"FAT16   " \
            and pbr[0x1F3:0x1FE] == b"KERNEL  SYS", "PBR?"
        fr = FatReader(f, part)
        os.makedirs(sysd)
        for fn in ("KERNEL.SYS", "COMMAND.COM", "COUNTRY.SYS"):
            p = os.path.join(sysd, fn)
            open(p, "wb").write(fr.file(fn))
            os.utime(p, (dos_time(fr.lookup(fn)),) * 2)
        fr.extract("FDOS", os.path.join(sysd, "FDOS"))
    os.remove(hdi)
    return ipl, pbr, sysd


# --------------------------------------------------------------------------
# FAT16 writer
# --------------------------------------------------------------------------
def upper_ascii(s):
    return "".join(chr(ord(c) - 32) if "a" <= c <= "z" else c for c in s)


def short83(name):
    """11-byte cp932 short name if NAME is a valid DOS 8.3 name, else None."""
    if name in (".", "..") or name.startswith("."):
        return None
    up = upper_ascii(name)
    base, dot, ext = up.rpartition(".") if "." in up else (up, "", "")
    if "." in base:
        return None
    try:
        b, x = base.encode("cp932"), ext.encode("cp932")
    except UnicodeEncodeError:
        return None
    if not (1 <= len(b) <= 8 and len(x) <= 3):
        return None
    if any(ch in SHORT_BAD or ch < 0x20 for ch in sjis_single_bytes(b + x)):
        return None
    out = b.ljust(8, b" ") + x.ljust(3, b" ")
    if out[0] == 0xE5:
        out = b"\x05" + out[1:]
    return out


def sjis_single_bytes(b):
    """The bytes of B that are single-byte characters (lead/trail skipped)."""
    i, out = 0, []
    while i < len(b):
        c = b[i]
        if 0x81 <= c <= 0x9F or 0xE0 <= c <= 0xFC:
            i += 2
        else:
            out.append(c)
            i += 1
    return out


def sjis_trunc(s, n):
    """cp932 bytes of S (unencodable/invalid chars as '_'), at most N bytes,
    never splitting a double-byte character."""
    out = b""
    for ch in upper_ascii(s):
        try:
            b = ch.encode("cp932")
        except UnicodeEncodeError:
            b = b"_"
        if len(b) == 1 and (b[0] in SHORT_BAD or b[0] < 0x20):
            if ch in " .":
                continue                      # Windows drops these
            b = b"_"
        if len(out) + len(b) > n:
            break
        out += b
    return out


def alias83(name, taken):
    base, dot, ext = name.rpartition(".")
    if not dot or not base:
        base, ext = name, ""
    b, x = sjis_trunc(base.lstrip("."), 8), sjis_trunc(ext, 3)
    for n in range(1, 100000):
        tail = b"~%d" % n
        stem = b
        while len(stem) + len(tail) > 8:
            stem = sjis_trunc(stem.decode("cp932"), len(stem) - 1)
        cand = (stem + tail).ljust(8, b" ") + x.ljust(3, b" ")
        if cand not in taken:
            return cand
    raise SystemExit("no alias for " + name)


def lfn_entries(long, short):
    csum = 0
    for c in short:
        csum = (((csum & 1) << 7) + (csum >> 1) + c) & 0xFF
    u = long.encode("utf-16-le")
    units = [u[i:i + 2] for i in range(0, len(u), 2)]
    if len(units) % 13:
        units.append(b"\0\0")
    while len(units) % 13:
        units.append(b"\xff\xff")
    n = len(units) // 13
    out = []
    for seq in range(n, 0, -1):
        part = units[(seq - 1) * 13: seq * 13]
        e = bytearray(32)
        e[0] = seq | (0x40 if seq == n else 0)
        e[1:11] = b"".join(part[0:5])
        e[11], e[12], e[13] = 0x0F, 0, csum
        e[14:26] = b"".join(part[5:11])
        e[28:32] = b"".join(part[11:13])
        out.append(bytes(e))
    return out


def stamp(ts):
    t = datetime.datetime.fromtimestamp(ts)
    if t.year < 1980:
        t = datetime.datetime(1980, 1, 1)
    return ((t.hour << 11) | (t.minute << 5) | (t.second // 2),
            ((t.year - 1980) << 9) | (t.month << 5) | t.day)


class Node:
    def __init__(self, name, short, is_dir, src=None, data=None, mtime=0, attr=0x20):
        self.name, self.short, self.is_dir = name, short, is_dir
        self.src, self.data, self.mtime, self.attr = src, data, mtime, attr
        self.children = []          # dirs: [Node]
        self.lfn = None
        self.first = 0
        self.size = 0

    def payload(self):
        if self.data is not None:
            return self.data
        with open(self.src, "rb") as f:
            return f.read()


class Fat16:
    def __init__(self, nsect, root_entries=512):
        self.nsect = nsect
        self.root_secs = root_entries * 32 // SECTOR
        for spc in (1, 2, 4, 8, 16, 32, 64):
            fat = 1
            while True:
                clusters = (nsect - 1 - 2 * fat - self.root_secs) // spc
                need = -(-(clusters + 2) * 2 // SECTOR)
                if need <= fat:
                    break
                fat = need
            if 4085 < clusters < 65525:
                break
        else:
            raise SystemExit("partition size does not fit FAT16")
        self.spc, self.res, self.fat_secs, self.clusters = spc, 1, fat, clusters
        self.root_start = self.res + 2 * fat
        self.data_start = self.root_start + self.root_secs
        self.root = Node("", b"", True)
        self.next = 2
        self.fat = [0] * (clusters + 2)
        self.fat[0], self.fat[1] = 0xFFF8, 0xFFFF
        self.out = None
        self.nfiles = self.ndirs = 0
        self.lfns = []

    # -- tree building ----------------------------------------------------
    def find(self, d, name):
        for c in d.children:
            if c.name.upper() == name.upper():
                return c
        return None

    def add(self, d, name, node):
        if self.find(d, name):
            raise SystemExit("duplicate %r" % name)
        taken = {c.short for c in d.children}
        s = short83(name)
        if s is None or s in taken:
            s = alias83(name, taken)
            node.lfn = name
            self.lfns.append(name)
        node.name, node.short = name, s
        d.children.append(node)
        return node

    def mkdir(self, d, name, mtime=0):
        n = self.find(d, name)
        return n if n else self.add(d, name, Node(name, None, True, mtime=mtime))

    def add_tree(self, src, d, first=()):
        """SRC's contents into directory node D (FIRST names go in first)."""
        names = sorted(os.listdir(src), key=lambda n: (n.upper() not in first,
                                                       first.index(n.upper()) if n.upper() in first else 0,
                                                       n.upper()))
        for n in names:
            if n in SKIP or n.startswith("._"):
                continue
            p = os.path.join(src, n)
            st = os.lstat(p)
            if os.path.isdir(p):
                sub = self.mkdir(d, n, st.st_mtime)
                sub.mtime = st.st_mtime
                self.add_tree(p, sub)
            elif os.path.isfile(p):
                self.add(d, n, Node(n, None, False, src=p, mtime=st.st_mtime))

    # -- layout -------------------------------------------------------------
    def alloc(self, nbytes):
        cs = max(1, -(-nbytes // (self.spc * SECTOR)))
        first = self.next
        if first + cs > self.clusters + 2:
            raise SystemExit("disk full")
        for i in range(cs):
            self.fat[first + i] = first + i + 1 if i < cs - 1 else 0xFFFF
        self.next += cs
        return first

    def write_cluster_data(self, first, data):
        off = self.base + (self.data_start + (first - 2) * self.spc) * SECTOR
        self.out.seek(off)
        self.out.write(data)

    def entry(self, node):
        e = bytearray(32)
        e[0:11] = node.short
        e[11] = 0x10 if node.is_dir else node.attr
        t, d = stamp(node.mtime or 0)
        struct.pack_into("<HHHHHHHI", e, 14, t, d, d, 0, t, d, node.first,
                         0 if node.is_dir else node.size)
        return bytes(e)

    def dir_bytes(self, d, parent_first, is_root):
        raw = []
        if not is_root:
            dot = Node(".", b".          ", True, mtime=d.mtime); dot.first = d.first
            dd = Node("..", b"..         ", True, mtime=d.mtime); dd.first = parent_first
            raw += [self.entry(dot), self.entry(dd)]
        for c in d.children:
            if c.lfn:
                raw += lfn_entries(c.lfn, c.short)
            raw.append(self.entry(c))
        return b"".join(raw)

    def nentries(self, d):
        n = 0 if d is self.root else 2
        for c in d.children:
            n += 1 + (-(-len(c.lfn.encode("utf-16-le")) // 26) if c.lfn else 0)
        return n

    def place(self, d):
        """Allocate files (in order) then subdirs, depth first."""
        for c in d.children:
            if not c.is_dir:
                data = c.payload()
                c.size = len(data)
                if c.size:
                    c.first = self.alloc(c.size)
                    self.write_cluster_data(c.first, data)
                self.nfiles += 1
        for c in d.children:
            if c.is_dir:
                c.first = self.alloc(self.nentries(c) * 32 + 32)
                self.ndirs += 1
                self.place(c)

    def write_dirs(self, d, parent_first):
        for c in d.children:
            if c.is_dir:
                raw = self.dir_bytes(c, parent_first, False)
                self.write_cluster_data(c.first, raw)
                self.write_dirs(c, c.first)

    def write(self, out, base):
        self.out, self.base = out, base
        if self.nentries(self.root) > self.root_secs * SECTOR // 32:
            raise SystemExit("root directory full")
        self.place(self.root)
        self.write_dirs(self.root, 0)
        out.seek(base + self.root_start * SECTOR)
        out.write(self.dir_bytes(self.root, 0, True))
        fat = struct.pack("<%dH" % len(self.fat), *self.fat)
        for i in range(2):
            out.seek(base + (self.res + i * self.fat_secs) * SECTOR)
            out.write(fat)


# --------------------------------------------------------------------------
def build(args):
    import tempfile
    tmp = tempfile.mkdtemp(prefix="mkpc98hdd.")
    try:
        ipl, pbr0, sysd = lift_fd98(args.fd98_zip, tmp)
        C, H, S = args.cyls, args.heads, args.spt
        assert 1 <= H <= 15, "the -55 BIOS keeps heads in 4 bits"
        assert 1 <= S <= 255 and 2 <= C <= 0xFFFF
        total = C * H * S
        plba = H * S                          # partition = cylinder 1 ..
        psect = (C - 1) * H * S
        fs = Fat16(psect)

        # --- LBA 1: partition table ----------------------------------------
        pt = bytearray(SECTOR)
        e = bytearray(32)
        e[0] = 0xA1                           # mid: bootable | DOS
        e[1] = 0xA1                           # sid: active | FAT16 (DOS 5+)
        struct.pack_into("<BBH", e, 4, 0, 0, 1)            # IPL   s,h,c
        struct.pack_into("<BBH", e, 8, 0, 0, 1)            # start s,h,c
        struct.pack_into("<BBH", e, 12, S - 1, H - 1, C - 1)  # end
        e[16:32] = args.part_name.encode("cp932")[:16].ljust(16, b" ")
        pt[0:32] = e

        # --- PBR -------------------------------------------------------------
        pbr = bytearray(pbr0)
        struct.pack_into("<HBHBHHBHHHII", pbr, 0x0B,
                         SECTOR, fs.spc, fs.res, 2, fs.root_secs * SECTOR // 32,
                         psect if psect < 0x10000 else 0, 0xF8, fs.fat_secs,
                         S, H, plba, psect if psect >= 0x10000 else 0)
        pbr[0x24], pbr[0x25], pbr[0x26] = 0x80, 0, 0x29
        struct.pack_into("<I", pbr, 0x27, args.serial)
        pbr[0x2B:0x36] = args.label.encode("ascii")[:11].ljust(11, b" ")
        pbr[0x36:0x3E] = b"FAT16   "
        struct.pack_into("<IHHBIHIIHH", pbr, 0x3E,
                         plba,                # sysPartStart
                         0,                   # sysDataOffset (NEC IO.SYS)
                         SECTOR,              # sysPhysicalBPS
                         0,
                         fs.root_start,       # sysRootDirStart
                         fs.root_secs,        # sysRootDirSecs
                         fs.res,              # sysFatStart
                         fs.data_start,       # sysDataStart
                         0, 0x0060)           # load address 0060:0000
        boot = b"KERNEL  SYS" if args.system == "freedos" else b"IO      SYS"
        pbr[0x1F3:0x1FE] = boot
        assert pbr[0x1FE:0x200] == b"\x55\xAA"

        # --- files -------------------------------------------------------------
        root = fs.root
        if args.system == "freedos":
            for fn in ("KERNEL.SYS", "COMMAND.COM", "COUNTRY.SYS"):
                p = os.path.join(sysd, fn)
                fs.add(root, fn, Node(fn, None, False, src=p,
                                      mtime=os.stat(p).st_mtime))
            fdos = fs.mkdir(root, "FDOS", os.stat(os.path.join(sysd, "FDOS")).st_mtime)
            fs.add_tree(os.path.join(sysd, "FDOS"), fdos)
        renames = dict(r.split("=", 1) for r in args.rename)
        for spec in args.tree:                # DIR=NAME, or DIR=/ for the root
            src, dest = spec.split("=", 1)
            if dest == "/":
                first = ("IO.SYS", "MSDOS.SYS", "COMMAND.COM") \
                    if args.system == "msdos" else ()
                fs.add_tree(src, root, first)
            else:
                d = fs.mkdir(root, dest, os.stat(src).st_mtime)
                fs.add_tree(src, d)
        for old, new in renames.items():
            n = fs.find(root, old)
            if n is None:
                raise SystemExit("--rename: no %s in the root" % old)
            root.children.remove(n)
            fs.add(root, new, n)
        for spec in args.text:                # NAME=FILE, CRLF line ends
            name, src = spec.split("=", 1)
            data = open(src, "rb").read().replace(b"\r\n", b"\n")
            data = data.replace(b"\n", b"\r\n")
            old = fs.find(root, name)
            if old:
                raise SystemExit("--text %s would overwrite the tree's own "
                                 "(--rename it first)" % name)
            fs.add(root, name, Node(name, None, False, data=data,
                                    mtime=os.stat(src).st_mtime))
        if args.system == "msdos":
            for fn in ("IO.SYS", "MSDOS.SYS"):
                n = fs.find(root, fn)
                if n is None or root.children.index(n) > 1:
                    raise SystemExit("msdos: %s must be in the tree's root" % fn)
                n.attr = 0x27                 # read-only | hidden | system
        if fs.lfns:
            print("long names kept as VFAT entries (DOS sees ~N aliases): %d"
                  % len(fs.lfns))

        body = os.path.join(tmp, "body.img")
        with open(body, "wb") as f:
            f.truncate(total * SECTOR)
            f.seek(0); f.write(ipl)
            f.seek(SECTOR); f.write(pt)
            f.seek(plba * SECTOR); f.write(pbr)
            fs.write(f, plba * SECTOR)

        used = (fs.next - 2) * fs.spc * SECTOR
        print("partition: LBA %d + %d sectors, FAT16 %d sec/cluster, %d clusters,"
              " FAT %d sectors; %d files, %d dirs, %.1f MB used, %.1f MB free"
              % (plba, psect, fs.spc, fs.clusters, fs.fat_secs, fs.nfiles,
                 fs.ndirs, used / 1e6,
                 (fs.clusters - (fs.next - 2)) * fs.spc * SECTOR / 1e6))

        # --- containers ------------------------------------------------------
        def emit(path, hdr):
            with open(path, "wb") as o, open(body, "rb") as i:
                o.write(hdr)
                shutil.copyfileobj(i, o, 1 << 20)
            print("%s: C/H/S %d/%d/%d x 512 = %d bytes + %d-byte header"
                  % (path, C, H, S, total * SECTOR, len(hdr)))
        if args.nhd:
            hdr = bytearray(512)
            hdr[0:15] = b"T98HDDIMAGE.R0\0"
            hdr[0x10:0x10 + 32] = args.comment.encode("ascii")[:31].ljust(32, b"\0")
            struct.pack_into("<IIHHH", hdr, 0x110, 512, C, H, S, SECTOR)
            emit(args.nhd, bytes(hdr))
        if args.vhd:
            hdr = bytearray(220)
            hdr[0:8] = b"VHD1.00\0"
            hdr[8:8 + 128] = args.comment.encode("ascii")[:127].ljust(128, b"\0")
            struct.pack_into("<HHBBHI", hdr, 0x8C, total * SECTOR >> 20, SECTOR,
                             S, H, C, total)
            emit(args.vhd, bytes(hdr))
        if args.hdn:
            assert (H, S) == (8, 25), ".hdn is np21w's flat 8 x 25 geometry"
            emit(args.hdn, b"")
    finally:
        shutil.rmtree(tmp)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fd98-zip", required=True,
                    help="fd98_hd_250m_20220123.zip (lpproj/fdkernel release)")
    ap.add_argument("--system", choices=("freedos", "msdos"), default="freedos",
                    help="freedos: KERNEL.SYS etc. from the release disk; "
                         "msdos: boot the tree's own IO.SYS / MSDOS.SYS")
    ap.add_argument("--cyls", type=int, required=True)
    ap.add_argument("--heads", type=int, default=8)
    ap.add_argument("--spt", type=int, default=25)
    ap.add_argument("--nhd", help="write a T98-Next .nhd here")
    ap.add_argument("--vhd", help="write a Virtual98 .hdd here")
    ap.add_argument("--hdn", help="write a flat .hdn (8 x 25 only) here")
    ap.add_argument("--tree", action="append", default=[],
                    help="DIR=NAME: DIR's contents into \\NAME; DIR=/ into the root")
    ap.add_argument("--rename", action="append", default=[],
                    help="OLD=NEW: rename a root file from the tree")
    ap.add_argument("--text", action="append", default=[],
                    help="NAME=FILE: a text file for the root, CRLF line ends")
    ap.add_argument("--part-name", default="FreeDOS(98)")
    ap.add_argument("--label", default="NO NAME")
    ap.add_argument("--comment", default="PC-98 Pocket SCSI disk")
    ap.add_argument("--serial", type=lambda s: int(s, 0), default=0x19951006)
    args = ap.parse_args()
    if not (args.nhd or args.hdn or args.vhd):
        ap.error("need --nhd, --vhd and/or --hdn")
    build(args)


if __name__ == "__main__":
    main()
