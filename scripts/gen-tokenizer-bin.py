#!/usr/bin/env python3
"""把 HuggingFace 的 tokenizer.json 转成 iOS 端用的紧凑二进制 tools/tokenizer.bin。

为什么不直接读 JSON：tokenizer.json 有 6.37 MB，nlohmann::json 解析它会在手机上
产生 100 MB 量级的峰值内存；转成「长度前缀 + 原始字节」的二进制后只剩 3~4 MB，
C++ 侧一次性读进 buffer，所有字符串用 string_view 指进这块内存，零拷贝。

布局（小端）：
  magic       6s   b"DSBPE1"
  version     u16
  vocabCount  u32
  mergeCount  u32
  addedCount  u32
  catCount[5] u32   # N / L / M / P / S 各类的区间数
  --- 以下按顺序紧密排列 ---
  cats   : 每类 catCount[c] 个 (u32 start, u32 end)   # 闭区间
  vocab  : vocabCount 个 (u32 len, bytes)             # 下标即 id（0..n-1 连续）
  merges : mergeCount 个 (u32 lenA, A, u32 lenB, B)   # 下标即 rank
  added  : addedCount 个 (u32 id, u32 len, bytes)

用法：python scripts/gen-tokenizer-bin.py <tokenizer.json> <输出 bin>

源文件 tokenizer.json 不在本仓库（6.37 MB，属于 Web 版的 vendor 资产），复现时用兄弟仓库里的那份：
  ../deepseek-chatbox/.build/green/DeepSeekChatBox/public/vendor/tokenizer/tokenizer.json
生成结果 tools/tokenizer.bin 是提交进仓库的，CI 不重跑本脚本，所以改了词表要手动重生成并提交。
"""
import json
import struct
import sys
import unicodedata

CATS = ["N", "L", "M", "P", "S"]


def cat_ranges(prefix):
    """扫全部码点，返回该 Unicode 大类下的闭区间列表（已合并相邻）。"""
    out = []
    start = None
    for cp in range(0x110000):
        hit = unicodedata.category(chr(cp)).startswith(prefix)
        if hit:
            if start is None:
                start = cp
        elif start is not None:
            out.append((start, cp - 1))
            start = None
    if start is not None:
        out.append((start, 0x10FFFF))
    return out


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as f:
        t = json.load(f)

    vocab = t["model"]["vocab"]
    merges = t["model"]["merges"]
    added = t.get("added_tokens") or []

    # id 必须连续，才能用「下标即 id」
    n = len(vocab)
    by_id = [None] * n
    for tok, i in vocab.items():
        if not (0 <= i < n):
            raise SystemExit(f"vocab id 越界: {tok!r} -> {i}")
        by_id[i] = tok
    if any(x is None for x in by_id):
        raise SystemExit("vocab id 不连续，无法用下标当 id")

    cats = [cat_ranges(p) for p in CATS]

    out = bytearray()
    out += b"DSBPE1"
    out += struct.pack("<H", 1)
    out += struct.pack("<I", n)
    out += struct.pack("<I", len(merges))
    out += struct.pack("<I", len(added))
    out += struct.pack("<5I", *[len(c) for c in cats])

    for c in cats:
        for a, b in c:
            out += struct.pack("<II", a, b)

    for tok in by_id:
        b = tok.encode("utf-8")
        out += struct.pack("<I", len(b)) + b

    for m in merges:
        parts = m if isinstance(m, list) else str(m).split(" ")
        if len(parts) != 2:
            raise SystemExit(f"merge 格式异常: {m!r}")
        a = parts[0].encode("utf-8")
        b = parts[1].encode("utf-8")
        out += struct.pack("<I", len(a)) + a + struct.pack("<I", len(b)) + b

    for a in added:
        s = a["content"].encode("utf-8")
        out += struct.pack("<II", a["id"], len(s)) + s

    with open(dst, "wb") as f:
        f.write(out)

    print(f"vocab={n} merges={len(merges)} added={len(added)} "
          f"cats={[len(c) for c in cats]} -> {len(out)} bytes ({len(out)/1048576:.2f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
