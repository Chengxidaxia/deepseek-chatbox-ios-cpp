//
//  DSBackToBottomButton.m
//  ChatboxIOS
//

#import "DSBackToBottomButton.h"
#import "DSIcon.h"
#import "DSTheme.h"

/// 36 是官方这类悬浮小钮的常见尺寸；触控区另外补到 44（见 pointInside:）。
static const CGFloat kDSSize = 36.0;

@interface DSBackToBottomButton ()
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, assign) BOOL visible;
@end

@implementation DSBackToBottomButton

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;

  self.backgroundColor = [DSTheme bgLayer1];
  self.layer.cornerRadius = kDSSize / 2.0;
  self.layer.cornerCurve = kCACornerCurveContinuous;
  self.layer.borderWidth = 1.0;
  self.layer.borderColor = [DSTheme borderL2].CGColor;

  // 悬浮在内容上，没有阴影会「贴」在文字里分不清层级。
  self.layer.shadowColor = UIColor.blackColor.CGColor;
  self.layer.shadowOpacity = 0.10;
  self.layer.shadowRadius = 8;
  self.layer.shadowOffset = CGSizeMake(0, 2);

  _icon = [[UIImageView alloc] init];
  _icon.translatesAutoresizingMaskIntoConstraints = NO;
  _icon.image = [[DSIcon image:DSIconChevronDown size:DSIconPointSizeAction]
      imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
  _icon.tintColor = [DSTheme labelSecondary];
  _icon.userInteractionEnabled = NO;
  [self addSubview:_icon];

  [NSLayoutConstraint activateConstraints:@[
    [self.widthAnchor constraintEqualToConstant:kDSSize],
    [self.heightAnchor constraintEqualToConstant:kDSSize],
    [_icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
  ]];

  [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

  // 初始隐藏：alpha 0 且不接收点击
  self.alpha = 0.0;
  self.hidden = YES;
  self.visible = NO;
  self.accessibilityLabel = @"回到底部";
  return self;
}

- (void)tapped {
  if (self.onTap) self.onTap();
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
  if (_visible == visible) return;
  _visible = visible;
  if (visible) self.hidden = NO;

  void (^apply)(void) = ^{
    self.alpha = visible ? 1.0 : 0.0;
    // 出现时带一点上浮，消失时缩回去 —— 纯淡入淡出会显得「贴纸」
    self.transform = visible ? CGAffineTransformIdentity
                             : CGAffineTransformMakeTranslation(0, 8);
  };

  if (!animated) {
    apply();
    self.hidden = !visible;
    return;
  }
  [UIView animateWithDuration:0.22
                        delay:0
                      options:UIViewAnimationOptionCurveEaseOut
                   animations:apply
                   completion:^(BOOL finished) {
                     if (!visible) self.hidden = YES;
                   }];
}

/// 视觉尺寸 36，但触控区补到 44（Apple 下限，官方那个 44 也是这个意思）。
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  CGFloat pad = (44.0 - kDSSize) / 2.0;
  CGRect hit = CGRectInset(self.bounds, -pad, -pad);
  return CGRectContainsPoint(hit, point);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
  [super traitCollectionDidChange:previous];
  if (!previous) return;
  if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  // borderColor 是 CGColor，不跟 dynamic color 走，切主题要重设
  self.layer.borderColor = [DSTheme borderL2].CGColor;
  self.icon.tintColor = [DSTheme labelSecondary];
}

@end
