"""从 `__text` 里统计「哪些 double 常量被代码真正引用」，反推官方布局数值。

为什么这么干：官方 UI 是 UIKit + FlexLayout（flexbox），间距/圆角/高度写成
`flex.padding(16)` 这种 CGFloat 字面量。能编成立即数（1/2/4/8/16/32）的用
`FMOV`，编不成的（20/22/44/13/17 这些，恰恰是最有布局意义的）一律进常量池，
用 `LDR Dt, label` 读出来。所以**扫 `LDR Dt, label` 就等于在数「这个数被用了多少次」**。

本机装不上 capstone（pip 被拦），所以只实现需要的那一条指令格式：

    LDR (literal), 64-bit FP:  0x5C000000 | (imm19 << 5) | Rt
    目标地址 = 本条指令地址 + (sign_extend(imm19) << 2)

扫完把目标落在 `__const` 里的读成 double，按引用次数排序 —— 次数高的就是
官方的高频布局常量。这比「猜 44pt 顶栏」靠谱得多。

局限（写在前面，别自欺）：拿不到「哪个视图用了哪个数」。要归因得知道函数边界，
那需要完整的反汇编与符号恢复，超出本工具范围。
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macho import MachO  # noqa: E402

LDR_D_LITERAL_MASK = 0xFF000000
# LDR (literal) 的位布局是  opc[31:30] | 011[29:27] | V[26] | 00[25:24] | imm19 | Rt
# （不是 [28:24]=01100，我前面两次都按那个记，掩码全错）。
# 取 64 位浮点：opc=11、V=0 → 11 011 0 00 = 0xD8。
# 顺带对照：LDR Xt = 01 011 0 00 = 0x58（公认值，用它验算这条规则是对的）。
# 错的两次：0x5C（opc=01,V=1，无效组合）、0xC6（位段整体错位），命中全落在 __text 里。
LDR_D_LITERAL_OPC = 0xD8000000


def scan(m):
    """扫 `__text`，用简易寄存器追踪把 `LDR Dt,[Xn,#imm]` 归因到具体常量地址。

    Swift 取浮点常量不走 `LDR (literal)`（我试过，命中 0 处），而是：
        adrp x8, page@PAGE
        add  x8, x8, page@PAGEOFF
        ldr  d0, [x8, #off]
    所以要认三种指令、并在寄存器里跟着走：

        ADRP  Rd, page      : 1 immlo[30:29] 10000 immhi[23:5] Rd
        ADD   Rd, Rn, #imm  : 1001 0001 sh imm12 Rn Rd      （64 位，sh 为 LSL#12）
        LDR   Dt, [Xn,#imm] : size=11 V=1 opc=01 → 0xFD400000

    追踪是**线性扫描、不建控制流图**，所以遇到函数序言就清表，避免跨函数串味。
    对「统计常量被用了几次」这个目的足够；不要拿它当反汇编器用。
    """
    text = m.section("__TEXT", "__text")
    code = m.section_bytes("__TEXT", "__text")
    base_addr = text.addr

    segs = []
    for seg in m.segments:
        if seg.filesize:
            segs.append((seg.vmaddr, seg.vmaddr + seg.filesize, seg.fileoff, seg.name))

    def vm_to_off(vm):
        for lo, hi, off, name in segs:
            if lo <= vm < hi:
                return off + (vm - lo)
        return None

    hits = {}
    regs = {}
    stats = {"adrp": 0, "add": 0, "ldr": 0, "prologue": 0}

    for i in range(0, len(code) - 3, 4):
        insn = struct.unpack_from("<I", code, i)[0]
        vm = base_addr + i

        # 函数序言 stp x29, x30, [sp, #-N]! —— 清表，别让上一个函数的 adrp 漏过来
        if (insn & 0xFFC00000) == 0xA9800000 and ((insn >> 5) & 0x1F) == 31 and (insn & 0x1F) == 29:
            regs.clear()
            stats["prologue"] += 1
            continue

        if (insn & 0x9F000000) == 0x90000000:              # ADRP
            rd = insn & 0x1F
            imm = (((insn >> 5) & 0x7FFFF) << 2) | ((insn >> 29) & 3)
            if imm & (1 << 20):
                imm -= (1 << 21)
            regs[rd] = (vm & ~0xFFF) + (imm << 12)
            stats["adrp"] += 1
            continue

        if (insn & 0xFF800000) == 0x91000000:              # ADD (imm) 64 位
            rd = insn & 0x1F
            rn = (insn >> 5) & 0x1F
            sh = (insn >> 22) & 1
            imm12 = (insn >> 10) & 0xFFF
            base = regs.get(rn)
            if base is not None:
                regs[rd] = base + ((imm12 << 12) if sh else imm12)
            else:
                regs.pop(rd, None)
            stats["add"] += 1
            continue

        if (insn & 0xFFC00000) == 0xFD400000:              # LDR Dt, [Xn, #imm]
            rn = (insn >> 5) & 0x1F
            imm12 = (insn >> 10) & 0xFFF
            base = regs.get(rn)
            if base is not None:
                off = vm_to_off(base + imm12 * 8)
                if off is not None:
                    hits[off] = hits.get(off, 0) + 1
                    stats["ldr"] += 1
            continue

        # 其它指令可能写 Rd，保守起见不追踪（宁可漏，不可错）
        rd = insn & 0x1F
        if (insn >> 31) & 1 and ((insn >> 26) & 0x1F) not in (0x05, 0x0D, 0x0F, 0x11):
            regs.pop(rd, None)

    return hits, stats


def classify(m, off):
    """文件偏移落在哪个段/节。"""
    for s in m.sections:
        if s.size and s.offset <= off < s.offset + s.size:
            return "%s,%s" % (s.segname, s.sectname)
    return "?"


def main():
    path = sys.argv[1]
    outdir = "docs/官方反编译"
    os.makedirs(outdir, exist_ok=True)
    m = MachO(path)

    hits, stats = scan(m)
    print("指令统计：adrp=%d add=%d 序言=%d 命中 LDR D=%d" % (
        stats["adrp"], stats["add"], stats["prologue"], stats["ldr"]))
    print("涉及 %d 个不同常量地址" % len(hits))

    rows = []
    for off, cnt in hits.items():
        sect = classify(m, off)
        raw = m.data[off:off + 8]
        if len(raw) < 8:
            continue
        d = struct.unpack("<d", raw)[0]
        f = struct.unpack("<f", raw[:4])[0]
        rows.append((cnt, off, sect, d, f))

    # 按「像不像 UI 数值」分组
    def ui_like(d):
        if d != d or d in (float("inf"), float("-inf")):
            return False
        return 0.25 <= d <= 600.0 and abs(d * 2 - round(d * 2)) < 1e-9

    ui = [r for r in rows if ui_like(r[3])]
    ui.sort(key=lambda r: (-r[0], r[3]))

    with open(os.path.join(outdir, "const-usage.txt"), "w", encoding="utf-8") as f:
        f.write("# __text 里 `LDR Dt, label` 的引用统计\n")
        f.write("# 列：引用次数  值  所在节  文件偏移\n")
        f.write("# 说明：次数越高越可能是官方的高频布局常量。\n\n")
        f.write("## 像 UI 数值的（%d 个地址，共 %d 次引用）\n\n" % (len(ui), sum(r[0] for r in ui)))
        for cnt, off, sect, d, _ in ui:
            f.write("%5d  %8g  %-22s 0x%06x\n" % (cnt, d, sect, off))

        f.write("\n## 其它（非 UI 数值，供排查误判）\n\n")
        for cnt, off, sect, d, fv in sorted(rows, key=lambda r: -r[0])[:200]:
            if ui_like(d):
                continue
            f.write("%5d  d=%-24r f=%-16r %-22s 0x%06x\n" % (cnt, d, fv, sect, off))

    # 控制台直接给前 40 个高频值，方便当场判断
    print("\n引用最多的 UI 数值：")
    for cnt, off, sect, d, _ in ui[:40]:
        print("  %4d 次  %8g  %s" % (cnt, d, sect))


if __name__ == "__main__":
    main()
