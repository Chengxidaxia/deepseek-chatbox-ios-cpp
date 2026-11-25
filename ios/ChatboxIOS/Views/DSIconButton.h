//
//  DSIconButton.h
//  ChatboxIOS
//
//  顶栏 / 工具条上的纯图标按钮。
//
//  为什么不用 `UIButton buttonWithType:UIButtonTypeSystem`：系统按钮的按下反馈
//  只是把 tint 压到 30% 透明，**图标本身不动**。顶栏底色和图标颜色本来就接近，
//  这个变化在手机上几乎看不出来 —— 用户会以为没点到，然后反复戳。
//
//  官方按钮按下去是整体缩小 + 回弹，这里照做：按下 90ms 收到 0.9，松手用弹簧回到 1.0。
//  用 transform 而不是改约束，动画期间不影响布局。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSIconButton : UIButton

/// 按下时的缩放比例，默认 0.9。设 1.0 表示只做透明度变化。
@property (nonatomic, assign) CGFloat pressedScale;
/// 按下时的不透明度，默认 0.6。
@property (nonatomic, assign) CGFloat pressedAlpha;

/// 纯图标按钮。图标按模板色渲染，颜色取 `tint`。
+ (instancetype)buttonWithIcon:(nullable UIImage *)icon tint:(nullable UIColor *)tint;

@end

NS_ASSUME_NONNULL_END
