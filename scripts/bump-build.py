#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""累计编译计数器。

口径（重要）：**只要发起过一次编译，就算一次构建** —— 本机 cmake / g++ 编译、ctest、
云编译（GitHub Actions 每次 run）都 +1，成功失败都算。跟「发版构建号」是两件事：

  build        发版构建号，写进 tag（vX.Y.Z.buildN）与 Info.plist 的 CFBundleVersion，
               只在发版时 +1，不要跟着日常编译乱涨
  totalBuilds  累计编译次数，每次编译 +1，这是「构建了多少次」的答案

用法：
    python scripts/bump-build.py --show
    python scripts/bump-build.py --source local --note "cmake --build 全量"
    python scripts/bump-build.py --source test  --note "ctest 三套件"
    python scripts/bump-build.py --source ci --ref 45351591405 --result failed
    python scripts/bump-build.py --release --note "v1.12.6"     # 发版：build 也 +1
    python scripts/bump-build.py --source ci --dry-run          # 只算不写（CI 里回写前预演）
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, 'build-count.json')
KEEP = 40  # history 只留最近 40 条，避免文件无限膨胀


def load() -> dict:
    if not os.path.exists(PATH):
        return {'build': 0, 'totalBuilds': 0, 'since': now(), 'meaning': {}, 'history': []}
    with open(PATH, encoding='utf-8') as f:
        return json.load(f)


def now() -> str:
    return time.strftime('%Y-%m-%d %H:%M %z')


def save(d: dict) -> None:
    tmp = PATH + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(tmp, PATH)


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--source', default='local', choices=['local', 'test', 'ci'],
                    help='构建来源：local=本机编译，test=跑测试，ci=云编译')
    ap.add_argument('--result', default='success', choices=['success', 'failed'],
                    help='本次构建结果（失败也要计数）')
    ap.add_argument('--ref', default='', help='CI run id / commit sha 等外部标识')
    ap.add_argument('--note', default='', help='一句话说明这次编译在做什么')
    ap.add_argument('--release', action='store_true', help='发版：同时把 build 号 +1')
    ap.add_argument('--dry-run', action='store_true', help='只算不写')
    ap.add_argument('--show', action='store_true', help='只打印当前计数')
    a = ap.parse_args()

    d = load()
    if a.show:
        print(f"totalBuilds={d.get('totalBuilds', 0)}  build={d.get('build', 0)}  since={d.get('since', '-')}")
        for h in d.get('history', [])[-5:]:
            print(f"  #{h['n']:<4} {h['at']}  {h['source']:<5} {h['result']:<7} {h.get('note','')}")
        return 0

    n = int(d.get('totalBuilds', 0)) + 1
    if a.release:
        d['build'] = int(d.get('build', 0)) + 1

    entry = {'n': n, 'at': now(), 'source': a.source, 'result': a.result, 'ref': a.ref, 'note': a.note}
    hist = d.setdefault('history', [])
    hist.append(entry)
    if len(hist) > KEEP:
        del hist[:len(hist) - KEEP]
    d['totalBuilds'] = n

    tag = ' [dry-run]' if a.dry_run else ''
    print(f"第 {n} 次编译（build={d.get('build', 0)}）{tag}")
    if not a.dry_run:
        save(d)
    return 0


if __name__ == '__main__':
    sys.exit(main())
