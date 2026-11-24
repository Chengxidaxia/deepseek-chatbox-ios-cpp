//
//  DSVoiceOverlay.m
//  ChatboxIOS
//

#import "DSVoiceOverlay.h"
#import "DSTheme.h"
#import "DSStrings.h"
#import "DSIcon.h"

@interface DSVoiceOverlay ()
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) NSMutableArray<UIView *> *bars;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *barHeights;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UILabel *timer;
@property (nonatomic, strong) UIImageView *micIcon;
@property (nonatomic, assign) BOOL canceling;
@end

@implementation DSVoiceOverlay

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [[DSTheme labelPrimary] colorWithAlphaComponent:0.18];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
    _card = [[UIVisualEffectView alloc] initWithEffect:blur];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.layer.cornerRadius = 20;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.clipsToBounds = YES;
    [self addSubview:_card];

    _micIcon = [[UIImageView alloc] init];
    _micIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _micIcon.image = [DSIcon image:DSIconMic size:22];
    _micIcon.tintColor = [DSTheme labelSecondary];
    _micIcon.contentMode = UIViewContentModeCenter;
    [_card.contentView addSubview:_micIcon];

    // 波形：24 根竖条，高度随音量起伏
    _bars = [NSMutableArray array];
    _barHeights = [NSMutableArray array];
    UIStackView *wave = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    wave.translatesAutoresizingMaskIntoConstraints = NO;
    wave.axis = UILayoutConstraintAxisHorizontal;
    wave.alignment = UIStackViewAlignmentCenter;
    wave.spacing = 3;
    wave.distribution = UIStackViewDistributionEqualSpacing;
    for (NSInteger i = 0; i < 24; i++) {
      UIView *b = [[UIView alloc] init];
      b.translatesAutoresizingMaskIntoConstraints = NO;
      b.backgroundColor = [DSTheme labelTertiary];
      b.layer.cornerRadius = 1.5;
      [b.widthAnchor constraintEqualToConstant:3].active = YES;
      NSLayoutConstraint *h = [b.heightAnchor constraintEqualToConstant:4];
      h.active = YES;
      [wave addArrangedSubview:b];
      [_bars addObject:b];
      [_barHeights addObject:h];
    }
    [_card.contentView addSubview:wave];

    _hint = [[UILabel alloc] init];
    _hint.translatesAutoresizingMaskIntoConstraints = NO;
    _hint.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _hint.textColor = [DSTheme labelSecondary];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.text = DSStrReleaseToSend;
    [_card.contentView addSubview:_hint];

    _timer = [[UILabel alloc] init];
    _timer.translatesAutoresizingMaskIntoConstraints = NO;
    _timer.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    _timer.textColor = [DSTheme labelTertiary];
    _timer.textAlignment = NSTextAlignmentCenter;
    _timer.text = @"00:00";
    [_card.contentView addSubview:_timer];

    [NSLayoutConstraint activateConstraints:@[
      [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-20],
      [_card.widthAnchor constraintEqualToConstant:260],

      [_micIcon.centerXAnchor constraintEqualToAnchor:_card.contentView.centerXAnchor],
      [_micIcon.topAnchor constraintEqualToAnchor:_card.contentView.topAnchor constant:20],
      [_micIcon.widthAnchor constraintEqualToConstant:24],
      [_micIcon.heightAnchor constraintEqualToConstant:24],

      [wave.centerXAnchor constraintEqualToAnchor:_card.contentView.centerXAnchor],
      [wave.topAnchor constraintEqualToAnchor:_micIcon.bottomAnchor constant:14],
      [wave.heightAnchor constraintEqualToConstant:36],

      [_hint.centerXAnchor constraintEqualToAnchor:_card.contentView.centerXAnchor],
      [_hint.topAnchor constraintEqualToAnchor:wave.bottomAnchor constant:14],
      [_hint.leadingAnchor constraintGreaterThanOrEqualToAnchor:_card.contentView.leadingAnchor constant:16],

      [_timer.centerXAnchor constraintEqualToAnchor:_card.contentView.centerXAnchor],
      [_timer.topAnchor constraintEqualToAnchor:_hint.bottomAnchor constant:4],
      [_timer.bottomAnchor constraintEqualToAnchor:_card.contentView.bottomAnchor constant:-16],
    ]];

    self.hidden = YES;
    self.alpha = 0;
  }
  return self;
}

- (void)showInView:(UIView *)host {
  if (self.superview != host) {
    [self removeFromSuperview];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:self];
    [NSLayoutConstraint activateConstraints:@[
      [self.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
      [self.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
      [self.topAnchor constraintEqualToAnchor:host.topAnchor],
      [self.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
  }
  self.hidden = NO;
  [UIView animateWithDuration:0.16 animations:^{ self.alpha = 1; }];
}

- (void)updateLevel:(CGFloat)level duration:(NSTimeInterval)duration canceling:(BOOL)canceling {
  if (canceling != _canceling) {
    _canceling = canceling;
    _hint.text = canceling ? DSStrSlideUpToCancel : DSStrReleaseToSend;
    _hint.textColor = canceling ? [DSTheme danger] : [DSTheme labelSecondary];
    _micIcon.tintColor = canceling ? [DSTheme danger] : [DSTheme labelSecondary];
  }
  NSInteger sec = (NSInteger)duration;
  _timer.text = [NSString stringWithFormat:@"%02ld:%02ld", (long)(sec / 60), (long)(sec % 60)];

  // 中间高、两端低的包络，让波形看起来像频谱而不是一团方块
  CGFloat n = (CGFloat)self.bars.count;
  for (NSInteger i = 0; i < (NSInteger)self.bars.count; i++) {
    CGFloat center = 1.0 - fabs((CGFloat)i - n / 2.0) / (n / 2.0);   // 0..1
    CGFloat env = 0.35 + 0.65 * center;
    CGFloat jitter = 0.25 + 0.75 * ((CGFloat)((i * 37) % 11) / 10.0);
    CGFloat h = 4 + level * 30 * env * jitter;
    if (canceling) h *= 0.4;
    self.barHeights[(NSUInteger)i].constant = MAX(4, h);
  }
  [UIView animateWithDuration:0.06 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{ [self layoutIfNeeded]; } completion:nil];
}

- (void)showRecognizing {
  _hint.text = DSStrRecognizing;
  _hint.textColor = [DSTheme labelSecondary];
  for (NSLayoutConstraint *h in self.barHeights) h.constant = 4;
  [UIView animateWithDuration:0.2 animations:^{ [self layoutIfNeeded]; }];
}

- (void)dismiss {
  [UIView animateWithDuration:0.14 animations:^{
    self.alpha = 0;
  } completion:^(BOOL done) {
    self.hidden = YES;
    [self removeFromSuperview];
  }];
}

@end
