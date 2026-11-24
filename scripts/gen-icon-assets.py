#!/usr/bin/env python3
"""把 Resources/OfficialIcons/*.svg 打成一张 C 表，生成 DSIconAssets.h/.m。

图标来源：官方 iOS 包 `Assets.car` 里的 `ISTC` rendition。每个 SVG 的载荷是
LZVN（`bvxn`）压缩的，解开后就是官方图标的原始矢量源码，坐标与官方一致。
生成物只有字符串表，运行期由 DSSVGIcon 解析成 UIBezierPath，不引入第三方渲染器。

用法：
    python3 scripts/gen-icon-assets.py          # 重新生成
    python3 scripts/gen-icon-assets.py --check  # 只校验生成物是否最新（CI 用）
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'ios', 'ChatboxIOS', 'Resources', 'OfficialIcons')
OUT_H = os.path.join(ROOT, 'ios', 'ChatboxIOS', 'Supporting', 'DSIconAssets.h')
OUT_M = os.path.join(ROOT, 'ios', 'ChatboxIOS', 'Supporting', 'DSIconAssets.m')

HEADER = '''//
//  DSIconAssets.h
//  ChatboxIOS
//
//  官方图标矢量表。**本文件由 scripts/gen-icon-assets.py 生成，勿手改。**
//
//  每个条目是官方 App `Assets.car` 里对应 `ISTC` rendition 解出来的原始 SVG
//  源码（LZVN 解压后原样保留），因此图形、线宽、颜色都与官方逐字节一致。
//  运行期交给 DSSVGIcon 解析并渲染，不依赖任何 SVG 库。
//

#ifndef DSIconAssets_h
#define DSIconAssets_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  const char *key;  // 资源名（文件名去掉 .svg，全小写）
  const char *svg;  // 原始 SVG 源码（单行）
} DSIconAssetEntry;

extern const DSIconAssetEntry kDSIconAssetEntries[];
extern const size_t kDSIconAssetCount;

/// 按 key 取 SVG 源码；没有则返回 NULL。
const char *DSIconAssetSource(const char *key);

#ifdef __cplusplus
}
#endif

#endif /* DSIconAssets_h */
'''

FOOTER_TMPL = '''const char *DSIconAssetSource(const char *key) {
  if (key == NULL) return NULL;
  for (size_t i = 0; i < kDSIconAssetCount; i++) {
    const char *k = kDSIconAssetEntries[i].key;
    const char *a = key;
    while (*k && *k == *a) { k++; a++; }
    if (*k == '\\0' && *a == '\\0') return kDSIconAssetEntries[i].svg;
  }
  return NULL;
}
'''


def c_string(text: str) -> str:
    """转成 C 字符串字面量：换行压平，引号与反斜杠转义。"""
    text = text.replace('\r\n', '\n').replace('\n', ' ')
    text = re.sub(r'\s{2,}', ' ', text).strip()
    text = text.replace('\\', '\\\\').replace('"', '\\"')
    return '"' + text + '"'


def build() -> str:
    names = sorted(n for n in os.listdir(SRC) if n.endswith('.svg'))
    rows = []
    for n in names:
        key = n[:-4]
        with open(os.path.join(SRC, n), encoding='utf-8') as f:
            rows.append((key, f.read()))
    lines = [
        '//',
        '//  DSIconAssets.m',
        '//  ChatboxIOS',
        '//',
        '//  **本文件由 scripts/gen-icon-assets.py 生成，勿手改。**',
        '//  共 %d 个官方图标，源码取自官方包 Assets.car 的 ISTC rendition。' % len(rows),
        '//',
        '',
        '#import "DSIconAssets.h"',
        '',
        'const DSIconAssetEntry kDSIconAssetEntries[] = {',
    ]
    for key, svg in rows:
        lines.append('    {"%s",\n     %s},' % (key, c_string(svg)))
    lines.append('};')
    lines.append('')
    lines.append('const size_t kDSIconAssetCount = '
                 'sizeof(kDSIconAssetEntries) / sizeof(kDSIconAssetEntries[0]);')
    lines.append('')
    lines.append(FOOTER_TMPL)
    return '\n'.join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true', help='只校验生成物是否最新')
    args = ap.parse_args()

    if not os.path.isdir(SRC):
        print('找不到图标目录：%s' % SRC, file=sys.stderr)
        return 2

    body = build()
    if args.check:
        stale = []
        if not os.path.exists(OUT_H) or open(OUT_H, encoding='utf-8').read() != HEADER:
            stale.append(os.path.basename(OUT_H))
        if not os.path.exists(OUT_M) or open(OUT_M, encoding='utf-8').read() != body:
            stale.append(os.path.basename(OUT_M))
        if stale:
            print('生成物不是最新：%s（跑 scripts/gen-icon-assets.py）' % ', '.join(stale),
                  file=sys.stderr)
            return 1
        print('图标表已是最新')
        return 0

    with open(OUT_H, 'w', encoding='utf-8', newline='\n') as f:
        f.write(HEADER)
    with open(OUT_M, 'w', encoding='utf-8', newline='\n') as f:
        f.write(body)
    print('生成 %d 个图标 → %s / %s'
          % (body.count('{"'), os.path.basename(OUT_H), os.path.basename(OUT_M)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
