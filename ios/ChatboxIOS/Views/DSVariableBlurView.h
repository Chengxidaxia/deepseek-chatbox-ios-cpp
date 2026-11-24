//
//  DSVariableBlurView.h
//  ChatboxIOS
//
//  对齐官方 `VariableBlurView`（它下面还挂着 `ExclusionState` 和 `BackdropSegmentView`）。
//  用途是消息列表与顶栏 / 输入区交界处的「内容渐隐」：滚动内容接近边缘时淡出，
//  而不是被一条硬边切掉。
//
//  为什么不是简单的渐变遮罩：官方那个类叫 VariableBlur，是真的在模糊。
//  这里用 `UIVisualEffectView` + `CAGradientLayer` 当 mask —— 模糊强度沿边缘线性衰减，
//  视觉上就是「越靠边越糊、越透明」，和纯色渐变叠一层是不一样的观感。
//
//  注意：这**不是**给输入框加毛玻璃。官方输入框本身是纯色浅灰圆角，
//  渐隐只发生在容器与列表的交界处。两者别搞混。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DSVariableBlurEdge) {
  /// 贴在顶栏下方：上边不透明，下边渐隐
  DSVariableBlurEdgeTop = 0,
  /// 贴在输入区上方：上边渐隐，下边不透明
  DSVariableBlurEdgeBottom,
};

@interface DSVariableBlurView : UIView

- (instancetype)initWithEdge:(DSVariableBlurEdge)edge;

/// 渐隐带高度，默认 28。
@property (nonatomic, assign) CGFloat fadeHeight;

/// 0~1，整体不透明度。滚动到两端时可以淡出这条带子，避免「明明没内容还糊一层」。
@property (nonatomic, assign) CGFloat strength;

/// 是否需要真的模糊。关掉就只剩淡出（纯 alpha 渐变），性能更好但层次弱。
@property (nonatomic, assign) BOOL blurEnabled;

@end

NS_ASSUME_NONNULL_END
