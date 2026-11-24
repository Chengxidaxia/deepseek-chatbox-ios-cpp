//
//  DSSVGIcon.h
//  ChatboxIOS
//
//  官方图标的矢量渲染。图标源码来自官方包 `Assets.car` 的 `ISTC` rendition
//  （LZVN 解压后是原始 SVG），见 DSIconAssets.h。这里自带一个够用的 SVG 解析器，
//  把 path/rect/circle/ellipse/line 转成 CGPath 直接画，不引入 SVGKit 之类的库。
//
//  支持范围（按官方图标实际用到的子集）：
//    · path 的 M/L/H/V/C/S/Q/T/A/Z 与全部相对命令
//    · rect（含 rx/ry）、circle、ellipse、line
//    · fill / stroke / stroke-width / stroke-linecap / stroke-linejoin / fill-rule / opacity
//    · transform 的 translate/scale/rotate/matrix
//    · `url(#...)` 形式的渐变引用降级成纯色（官方只有 Loading 用到，纯色足够）
//  不支持的（clip-path、mask、filter、text）直接忽略——官方图标里没用到。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSSVGIcon : NSObject

/// 按资源名渲染，保留 SVG 里自带颜色（官方配色）。
+ (nullable UIImage *)imageNamed:(NSString *)key size:(CGFloat)size;

/// 按资源名渲染，并把所有非 none 的填充/描边换成 tint（用于选中态、按钮着色）。
+ (nullable UIImage *)imageNamed:(NSString *)key size:(CGFloat)size tint:(nullable UIColor *)tint;

/// 直接渲染一段 SVG 源码（测试用）。
+ (nullable UIImage *)imageWithSVG:(NSString *)svg size:(CGFloat)size tint:(nullable UIColor *)tint;

/// 把一段 SVG 的 path 数据转成 CGPath（已按 viewBox 缩放到 size，调用方负责释放）。
+ (nullable CGPathRef)newPathFromData:(NSString *)d CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
