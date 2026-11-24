//
//  DSOperationView.m
//  ChatboxIOS
//

#import "DSOperationView.h"
#import "DSIcon.h"
#import "DSTheme.h"

@interface DSOperationView ()
@property (nonatomic, assign) DSOperationKind kind;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
/// 三个跳动的小点，用来表达「还在跑」—— 官方这种胶囊里都有活性指示
@property (nonatomic, strong) NSArray<UIView *> *dots;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSTimeInterval startedAt;
@property (nonatomic, assign) BOOL running;
@end

@implementation DSOperationView

- (instancetype)initWithKind:(DSOperationKind)kind {
  self = [super initWithFrame:CGRectZero];
  if (!self) return nil;
  _kind = kind;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.backgroundColor = [[DSTheme brand] colorWithAlphaComponent:0.10];
  self.layer.cornerRadius = 15;
  self.layer.cornerCurve = kCACornerCurveContinuous;
  self.hidden = YES;
  self.userInteractionEnabled = NO;   // 纯指示，不抢输入区的点击

  _icon = [[UIImageView alloc] init];
  _icon.translatesAutoresizingMaskIntoConstraints = NO;
  _icon.image = [[DSIcon image:(kind == DSOperationKindSearch ? DSIconGlobe : DSIconThink)
                          size:DSIconPointSizeInline]
      imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
  _icon.tintColor = [DSTheme brand];
  [self addSubview:_icon];

  _label = [[UILabel alloc] init];
  _label.translatesAutoresizingMaskIntoConstraints = NO;
  _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  _label.textColor = [DSTheme brand];
  _label.text = [self defaultText];
  [self addSubview:_label];

  NSMutableArray<UIView *> *dots = [NSMutableArray array];
  for (NSInteger i = 0; i < 3; i++) {
    UIView *d = [[UIView alloc] init];
    d.translatesAutoresizingMaskIntoConstraints = NO;
    d.backgroundColor = [DSTheme brand];
    d.layer.cornerRadius = 1.5;
    [self addSubview:d];
    [dots addObject:d];
  }
  _dots = dots;

  NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray array];
  [cs addObjectsFromArray:@[
    [self.heightAnchor constraintEqualToConstant:30],
    [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
    [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_icon.widthAnchor constraintEqualToConstant:16],
    [_icon.heightAnchor constraintEqualToConstant:16],
    [_label.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:5],
    [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
  ]];
  UIView *prev = _label;
  for (NSInteger i = 0; i < 3; i++) {
    UIView *d = dots[i];
    [cs addObjectsFromArray:@[
      [d.widthAnchor constraintEqualToConstant:3],
      [d.heightAnchor constraintEqualToConstant:3],
      [d.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [d.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor
                                     constant:(i == 0 ? 4 : 2)],
    ]];
    prev = d;
  }
  [cs addObject:[self.trailingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:10]];
  [NSLayoutConstraint activateConstraints:cs];

  return self;
}

- (NSString *)defaultText {
  return self.kind == DSOperationKindSearch ? @"正在搜索" : @"正在深度思考";
}

- (void)setText:(NSString *)text {
  _text = [text copy];
  self.label.text = text.length ? text : [self defaultText];
}

#pragma mark - 运行

- (void)start {
  if (self.running) return;
  self.running = YES;
  self.startedAt = [NSDate date].timeIntervalSince1970;
  self.hidden = NO;
  self.alpha = 0.0;
  [UIView animateWithDuration:0.18 animations:^{ self.alpha = 1.0; }];
  [self startDotAnimation];

  // 计时只用来算「用时 N 秒」，1 秒一跳足够，不用 CADisplayLink。
  __weak __typeof(self) ws = self;
  self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                               repeats:YES
                                                 block:^(NSTimer *t) {
    [ws tick];
  }];
}

- (NSTimeInterval)stop {
  if (!self.running) return -1;
  self.running = NO;
  [self.timer invalidate];
  self.timer = nil;
  [self stopDotAnimation];
  NSTimeInterval elapsed = [NSDate date].timeIntervalSince1970 - self.startedAt;
  [UIView animateWithDuration:0.18
                   animations:^{ self.alpha = 0.0; }
                   completion:^(BOOL finished) { self.hidden = YES; }];
  return elapsed;
}

/// 每秒把「正在…」补上用时，让用户知道它没卡住。
- (void)tick {
  if (!self.running) return;
  NSInteger secs = (NSInteger)([NSDate date].timeIntervalSince1970 - self.startedAt);
  if (secs < 2) return;      // 头两秒不加，否则一闪一闪很吵
  NSString *base = self.kind == DSOperationKindSearch ? @"正在搜索" : @"正在深度思考";
  // 如果外部设过带内容的文案（例如「正在搜索 3 个网页」），保留前缀只追加用时
  NSString *prefix = self.text.length ? self.text : base;
  // 去掉上一次追加的「（N 秒）」
  NSRange r = [prefix rangeOfString:@"（" options:NSBackwardsSearch];
  if (r.location != NSNotFound) prefix = [prefix substringToIndex:r.location];
  self.label.text = [NSString stringWithFormat:@"%@（%ld 秒）", prefix, (long)secs];
}

#pragma mark - 小点动画

- (void)startDotAnimation {
  for (NSInteger i = 0; i < (NSInteger)self.dots.count; i++) {
    UIView *d = self.dots[i];
    // 用 CAKeyframeAnimation 做「依次抬起」的波浪，比三个独立 CABasicAnimation 稳
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    a.values = @[@0.0, @-2.5, @0.0, @0.0];
    a.keyTimes = @[@0.0, @0.25, @0.5, @1.0];
    a.duration = 1.2;
    a.repeatCount = HUGE_VALF;
    a.beginTime = CACurrentMediaTime() + i * 0.15;   // 依次错开
    [d.layer addAnimation:a forKey:@"wave"];
  }
}

- (void)stopDotAnimation {
  for (UIView *d in self.dots) [d.layer removeAnimationForKey:@"wave"];
}

- (void)dealloc {
  [_timer invalidate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
  [super traitCollectionDidChange:previous];
  if (!previous) return;
  if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  self.backgroundColor = [[DSTheme brand] colorWithAlphaComponent:0.10];
  self.icon.tintColor = [DSTheme brand];
  self.label.textColor = [DSTheme brand];
  for (UIView *d in self.dots) d.backgroundColor = [DSTheme brand];
}

@end
