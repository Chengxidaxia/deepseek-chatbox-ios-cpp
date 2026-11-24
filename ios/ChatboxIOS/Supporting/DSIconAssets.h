//
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
