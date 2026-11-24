#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""累计编译计数器（构建号 = 编译次数）。

口径（重要）：**只要发起过一次编译，就算一次构建** —— 本机 cmake / g++ 编译、ctest、
云编译（GitHub Actions 每次 run）都算，成功失败都算。

## 为什么不再用一个数字

以前 `build-count.json` 里只有一个 `build`，本机和 CI 各自读出来 +1 再写回。
两边同时推进时，git 合并只能二选一：**两次编译只留下一次，号被吃掉**。
用户要的是「本机算一次、云端算一次，那就是两次」，所以改成**只追加事件**：

    build-count.json     base（1~110 那段的汇总数，之后不再变）+ 口径说明 + 冻结的旧明细
    build-events.jsonl   一次编译一行，只追加、不修改；.gitattributes 里 merge=union

`build = base + build-events.jsonl 的行数`。合并时 union 会把两边的行都留下，
所以本机 1 行 + 云端 1 行 = 号 +2，不会再互相覆盖，也不会再产生冲突。

## 用法

    python scripts/bump-build.py --show                  # 看当前号 + 最近几条
    python scripts/bump-build.py --next                  # 只算下一次的号，不写（CI 取号用）
    python scripts/bump-build.py --source local --note "cmake --build"
    python scripts/bump-build.py --source test  --note "ctest 三套件"
    python scripts/bump-build.py --source ci --ref 45373523603 --result failed
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = os.path.join(ROOT, 'build-count.json')
EVENTS = os.path.join(ROOT, 'build-events.jsonl')
KEEP_SHOW = 6


def now() -> str:
    # 固定用 +0800：CI runner 是 UTC，本地是 +0800，混着记会看不懂先后顺序
    t = time.gmtime(time.time() + 8 * 3600)
    return time.strftime('%Y-%m-%d %H:%M', t) + ' +0800'


def load_meta() -> dict:
    if not os.path.exists(META):
        return {'base': 0, 'since': now(), 'meaning': {}}
    with open(META, encoding='utf-8') as f:
        d = json.load(f)
    # 兼容更早的格式：曾经把总数写在 build / totalBuilds 里，没有事件文件
    if 'base' not in d:
        legacy = int(d.get('totalBuilds', d.get('build', 0)) or 0)
        d['base'] = legacy
    return d


def read_events() -> list:
    if not os.path.exists(EVENTS):
        return []
    out = []
    with open(EVENTS, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                # 一行坏了不影响整体计数（比如手工编辑残留），跳过并提示
                print(f"警告：build-events.jsonl 有一行不是合法 JSON，已跳过：{line[:60]}",
                      file=sys.stderr)
    return out


def current(meta: dict, events: list) -> int:
    return int(meta.get('base', 0)) + len(events)


def append_event(entry: dict) -> None:
    # 追加一行，不动已有内容 —— 这是能被 union 合并的前提
    with open(EVENTS, 'a', encoding='utf-8') as f:
        f.write(json.dumps(entry, ensure_ascii=False, separators=(',', ':')) + '\n')


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--source', default='local', choices=['local', 'test', 'ci'],
                    help='构建来源：local=本机编译，test=跑测试，ci=云编译')
    ap.add_argument('--result', default='success', choices=['success', 'failed'],
                    help='本次构建结果（失败也要计数）')
    ap.add_argument('--ref', default='', help='CI run id / commit sha 等外部标识')
    ap.add_argument('--note', default='', help='一句话说明这次编译在做什么')
    ap.add_argument('--dry-run', action='store_true', help='只算不写')
    ap.add_argument('--next', action='store_true', help='打印下一次的号，不写（CI 分配号用）')
    ap.add_argument('--show', action='store_true', help='只打印当前计数')
    a = ap.parse_args()

    meta = load_meta()
    events = read_events()
    cur = current(meta, events)

    if a.next:
        print(cur + 1)
        return 0

    if a.show:
        print(f"build={cur}  base={meta.get('base', 0)}  events={len(events)}  since={meta.get('since', '-')}")
        for e in events[-KEEP_SHOW:]:
            print(f"  #{e.get('n', '?'):<5} {e.get('at', '')}  {e.get('source', ''):<5} "
                  f"{e.get('result', ''):<7} {e.get('note', '')}")
        return 0

    n = cur + 1
    entry = {'n': n, 'at': now(), 'source': a.source, 'result': a.result,
             'ref': a.ref, 'note': a.note}
    tag = ' [dry-run]' if a.dry_run else ''
    print(f"第 {n} 次编译（build={n}）{tag}")
    if not a.dry_run:
        append_event(entry)
    return 0


if __name__ == '__main__':
    sys.exit(main())
