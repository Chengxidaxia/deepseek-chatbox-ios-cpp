//
//  DSVoiceOverlay.h
//  ChatboxIOS
//
//  按住说话的遮罩，对齐官方 VoiceInputMaskView + SpectrumView：
//  半透明底 + 居中毛玻璃卡片（波形 + 提示 + 计时），上滑进入「松开取消」态。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSVoiceOverlay : UIView

- (void)showInView:(UIView *)host;
/// level: 0..1；canceling: 手指已上滑到取消区
- (void)updateLevel:(CGFloat)level duration:(NSTimeInterval)duration canceling:(BOOL)canceling;
/// 识别中：换成「识别中...」并锁住波形
- (void)showRecognizing;
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
