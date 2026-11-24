//
//  DSBackToBottomButton.h
//  ChatboxIOS
//
//  对齐官方 `MessageViewController.BackToBottomButton`。
//  用户上滑离开底部后浮现在输入区上方，点一下回到底部。
//
//  官方那枚图标没有出现在我们提取的 182 个 SVG 里（最接近的 `arrow_collapse`
//  是上下双箭头，用于折叠思考区，不是回到底部），所以这里用官方的
//  `ic_chevron_down_outline_20` 素材 —— 至少形状语言和描边粗细是官方的。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSBackToBottomButton : UIControl

/// 点击回调（UIControl 的 touchUpInside 也能用，这个只是省一次 addTarget）
@property (nonatomic, copy, nullable) void (^onTap)(void);

/// 带出现/消失动画的显隐。直接设 hidden 的话没有过渡，很突兀。
- (void)setVisible:(BOOL)visible animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
