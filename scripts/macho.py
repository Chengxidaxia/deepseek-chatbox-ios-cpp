"""最小可用的 Mach-O 解析器（只做我们需要的部分，不引 lief）。

存在的理由：本机是 Windows，没有 otool / nm 能认 Mach-O；而官方的布局常量
全在 `__TEXT,__const` 与 Swift 元数据段里，必须自己扒。

已验证口径：
- 只处理 thin 64 位小端（MH_MAGIC_64 = 0xfeedfacf），官方包就是这种；
  fat 包先自己挑 arm64 分片再传进来。
- 段/节的 `offset` 是**文件偏移**，直接拿去 seek 就能读。
- `LC_ENCRYPTION_INFO_64`(0x2C) 给出 FairPlay 的 cryptoff/cryptsize：
  该区间内的字节是密文，反编译无意义；区间外（含 __cstring / __const /
  __swift5_*）仍是明文，这是能继续往下扒的前提。
"""

import struct

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_ENCRYPTION_INFO_64 = 0x2C
LC_SYMTAB = 0x2
LC_DYLD_INFO_ONLY = 0x80000022


class Section:
    __slots__ = ("segname", "sectname", "addr", "size", "offset", "align", "flags")

    def __init__(self, segname, sectname, addr, size, offset, align, flags):
        self.segname = segname
        self.sectname = sectname
        self.addr = addr
        self.size = size
        self.offset = offset
        self.align = align
        self.flags = flags

    def __repr__(self):
        return "<%s,%s off=0x%x size=0x%x>" % (
            self.segname, self.sectname, self.offset, self.size)


class Segment:
    __slots__ = ("name", "vmaddr", "vmsize", "fileoff", "filesize", "sections", "maxprot", "initprot")

    def __init__(self, name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot):
        self.name = name
        self.vmaddr = vmaddr
        self.vmsize = vmsize
        self.fileoff = fileoff
        self.filesize = filesize
        self.maxprot = maxprot
        self.initprot = initprot
        self.sections = []

    def __repr__(self):
        return "<seg %s off=0x%x size=0x%x sects=%d>" % (
            self.name, self.fileoff, self.filesize, len(self.sections))


class MachO:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as f:
            self.data = f.read()
        self.segments = []
        self.sections = []
        self.cputype = None
        self.cpusubtype = None
        self.filetype = None
        self.cryptid = 0
        self.cryptoff = 0
        self.cryptsize = 0
        self.symtab = None
        self._parse()

    # ---------- 解析 ----------

    def _parse(self):
        d = self.data
        magic = struct.unpack_from("<I", d, 0)[0]
        if magic != MH_MAGIC_64:
            raise ValueError("不是 thin 64 位小端 Mach-O：0x%08x" % magic)
        self.cputype, self.cpusubtype, self.filetype, ncmds, sizeofcmds, _, _ = \
            struct.unpack_from("<iiIIIII", d, 4)

        off = 32
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", d, off)
            if cmdsize < 8:
                break
            if cmd == LC_SEGMENT_64:
                self._parse_segment(off)
            elif cmd == LC_ENCRYPTION_INFO_64:
                self.cryptoff, self.cryptsize, self.cryptid = struct.unpack_from("<IIi", d, off + 8)
            elif cmd == LC_SYMTAB:
                symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", d, off + 8)
                self.symtab = (symoff, nsyms, stroff, strsize)
            off += cmdsize

    def _parse_segment(self, off):
        d = self.data
        segname = _cstr(d[off + 8:off + 24])
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", d, off + 24)
        maxprot, initprot, nsects = struct.unpack_from("<iii", d, off + 56)
        seg = Segment(segname, vmaddr, vmsize, fileoff, filesize, maxprot, initprot)
        self.segments.append(seg)
        soff = off + 72
        for _ in range(nsects):
            sectname = _cstr(d[soff:soff + 16])
            sseg = _cstr(d[soff + 16:soff + 32])
            addr, size = struct.unpack_from("<QQ", d, soff + 32)
            offset, align, reloff, nreloc, flags = struct.unpack_from("<IIIII", d, soff + 48)
            s = Section(sseg, sectname, addr, size, offset, align, flags)
            seg.sections.append(s)
            self.sections.append(s)
            soff += 80

    # ---------- 查询 ----------

    def section(self, segname, sectname):
        for s in self.sections:
            if s.segname == segname and s.sectname == sectname:
                return s
        return None

    def section_bytes(self, segname, sectname):
        s = self.section(segname, sectname)
        if s is None or s.size == 0:
            return b""
        return self.data[s.offset:s.offset + s.size]

    def is_encrypted(self, offset, size=1):
        """文件偏移 offset 起的 size 字节是否落在 FairPlay 密文区间内。"""
        if self.cryptid == 0:
            return False
        return not (offset + size <= self.cryptoff or offset >= self.cryptoff + self.cryptsize)

    def summary(self):
        lines = [
            "cputype   %d (arm64=%d)" % (self.cputype, 0x0100000C),
            "filetype  %d" % self.filetype,
            "cryptid   %d  cryptoff=0x%x cryptsize=0x%x (%.1f MB)" % (
                self.cryptid, self.cryptoff, self.cryptsize, self.cryptsize / 1048576.0),
        ]
        for seg in self.segments:
            flag = " [加密]" if self.cryptid and self.is_encrypted(seg.fileoff, seg.filesize) else ""
            lines.append("%-16s off=0x%-8x size=0x%-8x sects=%d%s" % (
                seg.name, seg.fileoff, seg.filesize, len(seg.sections), flag))
            for s in seg.sections:
                enc = " *密文" if self.is_encrypted(s.offset, s.size) else ""
                lines.append("    %-18s off=0x%-8x size=0x%-8x%s" % (
                    s.sectname, s.offset, s.size, enc))
        return "\n".join(lines)


def _cstr(b):
    i = b.find(b"\x00")
    return (b[:i] if i >= 0 else b).decode("utf-8", "replace")


if __name__ == "__main__":
    import sys
    m = MachO(sys.argv[1])
    print(m.summary())
