//
//  DSToggleButtonGroup.m
//  ChatboxIOS
//

#import "DSToggleButtonGroup.h"
#import "DSButton.h"

@interface DSToggleButtonGroup ()
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, copy, readwrite) NSArray<DSButton *> *buttons;
@end

@implementation DSToggleButtonGroup

- (instancetype)initWithButtons:(NSArray<DSButton *> *)buttons {
  self = [super initWithFrame:CGRectZero];
  if (!self) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.backgroundColor = UIColor.clearColor;
  _buttons = [buttons copy];
  _spacing = 6.0;

  // 用 UIStackView 而不是手写约束：组内按钮宽度由各自 intrinsicContentSize 决定
  // （chips 的宽度跟着文案走），stack 的 distribution 天然处理这件事。
  _stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
  _stack.translatesAutoresizingMaskIntoConstraints = NO;
  _stack.axis = UILayoutConstraintAxisHorizontal;
  _stack.alignment = UIStackViewAlignmentCenter;
  _stack.spacing = _spacing;
  [self addSubview:_stack];

  [NSLayoutConstraint activateConstraints:@[
    [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
    [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
  ]];
  return self;
}

- (void)setSpacing:(CGFloat)spacing {
  _spacing = spacing;
  self.stack.spacing = spacing;
}

/// 宽度完全由内容撑，不要在工具条里被拉长 —— 开关组左边不该留空白。
- (CGSize)intrinsicContentSize {
  return CGSizeMake(UIViewNoIntrinsicMetric, 30.0);
}

@end
