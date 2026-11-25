//
//  DSIconButton.m
//  ChatboxIOS
//

#import "DSIconButton.h"

@implementation DSIconButton

+ (instancetype)buttonWithIcon:(UIImage *)icon tint:(UIColor *)tint {
  // 不走 `[UIButton buttonWithType:]`：工厂方法在某些系统版本上返回的是 UIButton
  // 本身而不是子类，那就拿不到 setHighlighted: 里的动画。
  DSIconButton *b = [[DSIconButton alloc] initWithFrame:CGRectZero];
  b.translatesAutoresizingMaskIntoConstraints = NO;
  [b setImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
      forState:UIControlStateNormal];
  b.tintColor = tint ?: UIColor.labelColor;
  return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;
  _pressedScale = 0.9;
  _pressedAlpha = 0.6;
  return self;
}

- (void)setHighlighted:(BOOL)highlighted {
  [super setHighlighted:highlighted];

  CGFloat scale = highlighted ? self.pressedScale : 1.0;
  CGFloat alpha = highlighted ? self.pressedAlpha : 1.0;

  // 按下要快（90ms，让人确认「点到了」），回弹要慢一点、带弹簧，才不像机械跳变。
  // BeginFromCurrentState 很关键：连点的时候从上一次动画的中间状态接上，
  // 否则会先跳回 1.0 再缩，看着像闪了一下。
  [UIView animateWithDuration:highlighted ? 0.09 : 0.30
                        delay:0
       usingSpringWithDamping:highlighted ? 1.0 : 0.55
        initialSpringVelocity:0
                      options:UIViewAnimationOptionAllowUserInteraction |
                              UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    self.transform = CGAffineTransformMakeScale(scale, scale);
    self.alpha = alpha;
  } completion:nil];
}

@end
