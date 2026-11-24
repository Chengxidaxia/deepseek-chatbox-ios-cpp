//
//  DSVariableBlurView.m
//  ChatboxIOS
//

#import "DSVariableBlurView.h"
#import "DSTheme.h"

@interface DSVariableBlurView ()
@property (nonatomic, assign) DSVariableBlurEdge edge;
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) CAGradientLayer *maskLayer;
@end

@implementation DSVariableBlurView

- (instancetype)initWithEdge:(DSVariableBlurEdge)edge {
  self = [super initWithFrame:CGRectZero];
  if (!self) return nil;
  _edge = edge;
  _fadeHeight = 28.0;
  _strength = 1.0;
  _blurEnabled = YES;

  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.userInteractionEnabled = NO;   // 只是装饰，不能吃掉列表的点击
  self.backgroundColor = UIColor.clearColor;

  // 超薄材质：比 systemChromeMaterial 轻，压在滚动内容上不会有「一块灰板」的感觉。
  _blur = [[UIVisualEffectView alloc]
      initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
  _blur.translatesAutoresizingMaskIntoConstraints = NO;
  _blur.userInteractionEnabled = NO;
  [self addSubview:_blur];
  [NSLayoutConstraint activateConstraints:@[
    [_blur.topAnchor constraintEqualToAnchor:self.topAnchor],
    [_blur.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [_blur.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [_blur.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
  ]];

  // mask 用黑→透明：黑色不透明处显示，透明处隐藏。
  _maskLayer = [CAGradientLayer layer];
  _maskLayer.startPoint = CGPointMake(0.5, 0.0);
  _maskLayer.endPoint = CGPointMake(0.5, 1.0);
  self.layer.mask = _maskLayer;

  [self applyGradient];
  return self;
}

- (void)setFadeHeight:(CGFloat)fadeHeight {
  _fadeHeight = fadeHeight;
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout];
}

- (void)setStrength:(CGFloat)strength {
  _strength = MAX(0.0, MIN(1.0, strength));
  self.alpha = _strength;
}

- (void)setBlurEnabled:(BOOL)blurEnabled {
  _blurEnabled = blurEnabled;
  _blur.hidden = !blurEnabled;
}

/// 渐变颜色只在初始化/切主题时设一次；方向由 edge 决定，不随 frame 变。
- (void)applyGradient {
  UIColor *solid = [UIColor blackColor];          // mask 里「黑」= 完全显示
  UIColor *clear = [UIColor clearColor];          // 「透明」= 完全隐藏
  UIColor *mid = [UIColor colorWithWhite:0 alpha:0.55];

  // 中段留一档 0.55：只做两端插值的话，渐变中段的不透明度偏低，
  // 压在文字上会显得「糊得不够」，像一块脏印子。
  if (self.edge == DSVariableBlurEdgeTop) {
    // 上不透明（贴着顶栏），下渐隐
    _maskLayer.colors = @[(id)solid.CGColor, (id)mid.CGColor, (id)clear.CGColor];
  } else {
    // 上渐隐，下不透明（贴着输入区）
    _maskLayer.colors = @[(id)clear.CGColor, (id)mid.CGColor, (id)solid.CGColor];
  }
  _maskLayer.locations = @[@0.0, @0.45, @1.0];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  // CAGradientLayer 不是自动布局的，必须手动跟 frame。
  // 而且这里要禁掉隐式动画，否则滚动时每次 layout 都会看到 mask 在「爬」。
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _maskLayer.frame = self.bounds;
  [CATransaction commit];
}

- (CGSize)intrinsicContentSize {
  return CGSizeMake(UIViewNoIntrinsicMetric, self.fadeHeight);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
  [super traitCollectionDidChange:previous];
  if (!previous) return;
  if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  [self applyGradient];   // 颜色是 CGColor，不跟着 dynamic color 自动变
}

@end
