//
//  DSIcon.h
//  ChatboxIOS
//
//  线性图标。官方 App 用内嵌 SVG（20×20，描边 1.6，圆角端点），
//  Assets.car 里的位图在 Windows 上解不开，因此这里按官方 SVG 的
//  几何特征用 UIBezierPath 重绘：统一 20×20 视口、1.6pt 描边、圆头圆角。
//  这样不用 SF Symbols，跨 iOS 版本描边粗细一致，也便于动画（见 DSIconAnimator）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DSIconName) {
  DSIconGlobe = 0,     // 联网搜索 / 浏览
  DSIconDoc,           // 页内查找 / 文件
  DSIconChevronDown,
  DSIconChevronLeft,
  DSIconChevronRight,
  DSIconCopy,
  DSIconRefresh,
  DSIconPlus,
  DSIconMic,
  DSIconCamera,
  DSIconPhoto,
  DSIconFile,
  DSIconSend,
  DSIconStop,
  DSIconSpeaker,
  DSIconCheck,
  DSIconClose,
  DSIconLightning,     // 快速模式
  DSIconBrain,         // 专家模式
  DSIconSearch,        // 联网搜索开关
  DSIconMenu,          // 顶栏三横线（打开会话列表）
};

@interface DSIcon : NSObject

/// 线条图标（模板图，用 tintColor 上色）
+ (UIImage *)image:(DSIconName)name size:(CGFloat)size;

/// 线条图标，指定颜色与线宽
+ (UIImage *)image:(DSIconName)name
              size:(CGFloat)size
             color:(UIColor *)color
         lineWidth:(CGFloat)lineWidth;

@end

NS_ASSUME_NONNULL_END
