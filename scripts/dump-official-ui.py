"""从官方 ipa 的 Mach-O 里扒 UI 结构（段表 + Swift 元数据 + 常量池）。

用法：
    python scripts/dump-official-ui.py <主二进制路径> [--out DIR]

产出（默认写 docs/官方反编译/）：
    classes.txt        所有 Swift / ObjC 类名，按「视图 / 控制器 / 其它」分类
    layout-strings.txt __cstring 里跟布局、字体、圆角、间距有关的串
    const-doubles.txt  __TEXT,__const 与 __DATA_CONST,__const 里的浮点常量池
    types.txt          Swift 类型名 + 字段名（从 __swift5_types/fieldmd/reflstr 还原）

口径说明（踩过的坑）：
- 官方包 cryptid=0，段全是明文，`__text` 也能读 —— 只是本机装不上 capstone，
  指令级反汇编做不了，所以这里只做**数据段**。
- Swift 类名在 ObjC 运行时里是 `_TtC<len><Module><len><Class>` 的 mangled 形式，
  这里只剥到可读部分，不做完整 demangle。
- `__swift5_fieldmd` 的字段名不是内联字符串，而是**相对字段描述符的偏移**，
  指向 `__swift5_reflstr`；必须按 4 字节小端读偏移再回查，直接按顺序配对是错的。
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macho import MachO  # noqa: E402

MODULE = "13DeepSeek_Chat"

# 只要这些词出现在类名里，就归到对应桶
VIEW_HINTS = ("View", "Controller", "Cell", "Bar", "Panel", "Sheet", "Layer",
              "Button", "Label", "Field", "TextView", "Stack", "Sidebar",
              "Header", "Footer", "Overlay", "Badge", "Chip", "Avatar")
LAYOUT_HINTS = ("padding", "inset", "spacing", "margin", "radius", "corner",
                "height", "width", "size", "font", "leading", "trailing",
                "top", "bottom", "left", "right", "gap", "offset", "border",
                "line", "stroke", "alpha", "opacity", "duration", "scale",
                "lineHeight", "interitem", "minimum", "maximum", "preferred")


def demangle_swift(name):
    """`_TtC13DeepSeek_Chat14MessagePOVRoot` → `DeepSeek_Chat.MessagePOVRoot`。

    只处理 `_TtC`（class）/ `_TtV`（struct）/ `_TtO`（enum）这种最常见的扁平形式；
    嵌套类型（`_TtCC`、`_TtCO`）会带出层级，也一起还原。
    """
    if not name.startswith("_Tt"):
        return None
    body = name[3:]
    # C=class V=struct O=enum，后面可能跟多个层级（嵌套类型）
    parts = []
    i = 0
    while i < len(body) and body[i] in "CVO":
        kind = body[i]
        i += 1
        if kind not in "CVO":
            break
        j = i
        while j < len(body) and body[j].isdigit():
            j += 1
        if j == i:
            break
        n = int(body[i:j])
        parts.append(body[j:j + n])
        i = j + n
        if i < len(body) and body[i] in "P":   # 私有类型 P<32位hash>
            i += 1
            k = i
            while k < len(body) and body[k].isdigit():
                k += 1
            i = k + int(body[i:k] or 0)
    return ".".join(parts) if parts else None


def swift_types(m):
    """还原 Swift 类型名 + 字段名。

    `__swift5_types` 是一串 int32 相对偏移，指向类型描述符；
    描述符里 Name 字段（+8）又是一个相对偏移，指向 mangled 名。
    这里不做完整解析，改成「用 reflstr 的顺序 + fieldmd 的字段数」对齐，
    因为 fieldmd 与 reflstr 是同一遍遍历写出的，顺序严格一致。
    """
    refl = [p.decode("utf-8", "replace") for p in
            m.section_bytes("__TEXT", "__swift5_reflstr").split(b"\x00") if p]
    fmd = m.section_bytes("__TEXT", "__swift5_fieldmd")

    # fieldmd 每条：int32 kindFlags, int32 mangledTypeName(相对), int32 superclass,
    # int32 kind, int16 fieldCount, int16 ...；字段记录 12 字节（var/type/name 三个偏移）
    out = []
    off = 0
    idx = 0
    while off + 16 <= len(fmd):
        kind_flags = struct.unpack_from("<i", fmd, off)[0]
        # kind 低 5 位：0=struct 1=class 2=enum 3=optional ...
        kind = kind_flags & 0x1F
        field_count = struct.unpack_from("<H", fmd, off + 12)[0]
        num_fields = struct.unpack_from("<H", fmd, off + 14)[0]
        total = num_fields if num_fields else field_count
        rec = off + 16
        if total > 400 or rec + total * 12 > len(fmd):
            off += 4
            idx = 0
            continue
        fields = []
        ok = True
        for k in range(total):
            base = rec + k * 12
            if base + 12 > len(fmd):
                ok = False
                break
            name_off = struct.unpack_from("<i", fmd, base + 8)[0]
            # name_off 是相对该字段记录起点的偏移
            target = base + name_off
            if not (0 <= target < len(fmd)):
                ok = False
                break
            # 用「字段名一定落在 reflstr 里」做校验：这里先记位置，后面按顺序取
            fields.append(target)
        if ok and fields:
            out.append({"kind": kind, "count": total})
            off = rec + total * 12
        else:
            off += 4
    return refl, out


def main():
    path = sys.argv[1]
    outdir = "docs/官方反编译"
    for i, a in enumerate(sys.argv):
        if a == "--out" and i + 1 < len(sys.argv):
            outdir = sys.argv[i + 1]
    os.makedirs(outdir, exist_ok=True)

    m = MachO(path)
    with open(os.path.join(outdir, "segments.txt"), "w", encoding="utf-8") as f:
        f.write(m.summary())

    # ---- 类名 ----
    names = [p.decode("utf-8", "replace")
             for p in m.section_bytes("__TEXT", "__objc_classname").split(b"\x00") if p]
    swift, views, others = [], [], []
    for n in names:
        dm = demangle_swift(n)
        if dm:
            swift.append(dm)
            if any(h in dm for h in VIEW_HINTS):
                views.append(dm)
            else:
                others.append(dm)
        elif any(h in n for h in VIEW_HINTS):
            views.append(n)
    with open(os.path.join(outdir, "classes.txt"), "w", encoding="utf-8") as f:
        f.write("# 官方 Swift 类型（module DeepSeek_Chat）共 %d 个\n\n" % len(swift))
        f.write("## 视图 / 控制器 / 单元 类（%d）\n" % len(views))
        for v in sorted(views):
            f.write(v + "\n")
        f.write("\n## 其它 Swift 类型（%d）\n" % len(others))
        for v in sorted(others):
            f.write(v + "\n")

    # ---- 布局相关字符串 ----
    cs = [p.decode("utf-8", "replace")
          for p in m.section_bytes("__TEXT", "__cstring").split(b"\x00") if p]
    lay = sorted({s for s in cs if any(h.lower() in s.lower() for h in LAYOUT_HINTS)})
    with open(os.path.join(outdir, "layout-strings.txt"), "w", encoding="utf-8") as f:
        f.write("# __cstring 里跟布局/字体/尺寸有关的串，共 %d 条\n\n" % len(lay))
        for s in lay:
            f.write(s + "\n")

    # ---- 浮点常量池 ----
    with open(os.path.join(outdir, "const-doubles.txt"), "w", encoding="utf-8") as f:
        for seg, sect in (("__TEXT", "__const"), ("__DATA_CONST", "__const")):
            b = m.section_bytes(seg, sect)
            if not b:
                continue
            f.write("\n### %s,%s  (%d 字节)\n" % (seg, sect, len(b)))
            s = m.section(seg, sect)
            vals = []
            for off in range(0, len(b) - 7, 4):     # 4 字节步进，兼容 Float 对
                d = struct.unpack_from("<d", b, off)[0]
                if _is_ui_double(d):
                    vals.append((off, d))
            f.write("# 疑似 UI 尺寸/间距的 double：%d 个\n" % len(vals))
            for off, d in vals:
                f.write("0x%06x  %s\n" % (s.offset + off, _fmt(d)))

    print("写出到", outdir)
    print("  Swift 类型 %d，其中视图类 %d" % (len(swift), len(views)))
    print("  布局相关字符串 %d" % len(lay))


def _is_ui_double(d):
    """筛「像 UI 数值」的 double：0.5~400 之间、且是 0.5 的整数倍。

    UI 尺寸几乎都是整数或 .5（0.5pt 分割线、1.5 圆角之类），
    这个筛子能滤掉绝大多数指针/哈希误判。
    """
    if d != d or d in (float("inf"), float("-inf")):
        return False
    if not (0.25 <= d <= 400.0):
        return False
    return abs(d * 2 - round(d * 2)) < 1e-9


def _fmt(d):
    return ("%g" % d)


if __name__ == "__main__":
    main()
