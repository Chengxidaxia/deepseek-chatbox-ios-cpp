//
//  DSButton.h
//  ChatboxIOS
//
//  对齐官方 `DSButton`。反编译官方主二进制，`DSButton` 下面挂着五个配置结构：
//      DSButton.ImageConfig / TitleConfig / BorderConfig / IconTitleConfig /
//      ScaledImageConfig，外加一个 ConfigurationUpdateHandler。
//  也就是说官方**全站按钮同源**，样式靠配置组合，而不是每个地方手写一遍。
//
//  我们之前各处 `[UIButton buttonWithType:]` 再零散设 imageEdgeInsets / cornerRadius，
//  这才是「看着不像官方」的深层原因 —— 不是某个数值差 2pt，是**没有统一来源**。
//
//  为什么不用 `UIButtonConfiguration`：它接管 title/image 布局，iconTitleGap 这种
//  细粒度间距只能靠 `imagePadding` 近似，且和 `contentInsets` 叠加后难以预测。
//  这里自己放 UIImageView + UILabel，layoutSubviews 里算，间距完全可控，
//  也顺手避开了 imageEdgeInsets / titleEdgeInsets / contentEdgeInsets 的弃用警告。
//

#import <UIKit/UIKit.h>
#import "DSIcon.h"

NS_ASSUME_NONNULL_BEGIN

/// 按钮语义。官方的样式集合收敛成这几种，其余靠 config 覆盖。
typedef NS_ENUM(NSInteger, DSButtonStyle) {
  /// 纯图标，无背景（顶栏 ☰ / ＋）
  DSButtonStylePlain = 0,
  /// 浅底胶囊（输入区 chip 未选中、次要操作）
  DSButtonStyleTinted,
  /// 实心（发送按钮）
  DSButtonStyleFilled,
  /// 描边（次强调）
  DSButtonStyleOutline,
};

@interface DSButtonConfig : NSObject <NSCopying>

@property (nonatomic, assign) DSButtonStyle style;
@property (nonatomic, assign) DSIconName icon;
@property (nonatomic, assign) CGFloat iconSize;      // 默认按 style 取 20
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, strong, nullable) UIFont *font;

@property (nonatomic, strong, nullable) UIColor *tint;          // 图标/文字色
@property (nonatomic, strong, nullable) UIColor *background;    // 覆盖 style 给的底色
@property (nonatomic, strong, nullable) UIColor *selectedTint;
@property (nonatomic, strong, nullable) UIColor *selectedBackground;

@property (nonatomic, assign) CGFloat cornerRadius;   // 默认胶囊：高度/2
@property (nonatomic, assign) CGFloat borderWidth;
@property (nonatomic, strong, nullable) UIColor *borderColor;

@property (nonatomic, assign) CGFloat hPadding;       // 左右内边距
@property (nonatomic, assign) CGFloat vPadding;       // 上下内边距
@property (nonatomic, assign) CGFloat iconTitleGap;   // 图标与文字间距
@property (nonatomic, assign) CGSize minSize;         // 最小点击区（默认 44×44）

/// 按语义给一套默认值（官方各处的实际取值都在这张表里）。
+ (instancetype)style:(DSButtonStyle)style icon:(DSIconName)icon title:(nullable NSString *)title;

@end

@interface DSButton : UIButton

+ (instancetype)buttonWithConfig:(DSButtonConfig *)config;

/// 换配置会重新应用样式，不会重建视图。
@property (nonatomic, copy) DSButtonConfig *config;

/// 选中态走 config 里的 selectedTint / selectedBackground。
/// （UIButton 自带 selected 属性，这里只重写样式应用。）
- (void)applyConfig;

@end

NS_ASSUME_NONNULL_END
