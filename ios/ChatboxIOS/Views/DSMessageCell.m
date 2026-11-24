//
//  DSMessageCell.m
//  ChatboxIOS
//
//  两种形态，对齐官方：
//  - 用户消息：右对齐淡蓝气泡（--bubble），圆角 18，内边距 10/14，最大宽 78%
//  - 助手消息：无气泡背景，全宽左对齐；思考块左侧 2px 竖线 + 可折叠正文
//  结构参官方类的 Fragment 思路（ThinkFragmentView / AgentFragmentsView）：
//  一条回答内的「思考 → 工具 → 正文」按顺序竖向排布，不使用左右分栏。
//

#import "DSMessageCell.h"
#import "DSTheme.h"
#import "DSStrings.h"

@interface DSMessageCell ()
// 用户气泡
@property (nonatomic, strong) UIView *userBubble;
@property (nonatomic, strong) UILabel *userLabel;
// 助手列
@property (nonatomic, strong) UIStackView *assistStack;
@property (nonatomic, strong) UIView *thinkBox;
@property (nonatomic, strong) UIView *thinkBar;
@property (nonatomic, strong) UIButton *thinkHead;
@property (nonatomic, strong) UILabel *thinkBody;
@property (nonatomic, strong) UILabel *contentLabel;
@property (nonatomic, strong) UILabel *toolLabel;
@property (nonatomic, strong) UIStackView *footerStack;
@property (nonatomic, strong) UILabel *usageLabel;
@property (nonatomic, strong) UIButton *btnCopy;
@property (nonatomic, strong) UIButton *regenButton;
// 状态
@property (nonatomic, strong, readwrite, nullable) NSDictionary *message;
@property (nonatomic, assign) BOOL thinkExpanded;
@end

@implementation DSMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    [self buildUserViews];
    [self buildAssistViews];
    [self activateBaseConstraints];
  }
  return self;
}

#pragma mark - 构建

- (void)buildUserViews {
  _userBubble = [[UIView alloc] init];
  _userBubble.translatesAutoresizingMaskIntoConstraints = NO;
  _userBubble.backgroundColor = [DSTheme userBubble];
  _userBubble.layer.cornerRadius = [DSTheme userBubbleRadius];
  _userBubble.layer.cornerCurve = kCACornerCurveContinuous;
  [self.contentView addSubview:_userBubble];

  _userLabel = [[UILabel alloc] init];
  _userLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _userLabel.numberOfLines = 0;
  _userLabel.textColor = [DSTheme labelPrimary];
  [_userBubble addSubview:_userLabel];

  UIEdgeInsets ins = [DSTheme userBubbleInsets];
  [NSLayoutConstraint activateConstraints:@[
    [_userLabel.topAnchor constraintEqualToAnchor:_userBubble.topAnchor constant:ins.top],
    [_userLabel.bottomAnchor constraintEqualToAnchor:_userBubble.bottomAnchor constant:-ins.bottom],
    [_userLabel.leadingAnchor constraintEqualToAnchor:_userBubble.leadingAnchor constant:ins.left],
    [_userLabel.trailingAnchor constraintEqualToAnchor:_userBubble.trailingAnchor constant:-ins.right],
  ]];
}

- (void)buildAssistViews {
  _assistStack = [[UIStackView alloc] init];
  _assistStack.translatesAutoresizingMaskIntoConstraints = NO;
  _assistStack.axis = UILayoutConstraintAxisVertical;
  _assistStack.spacing = 10;
  _assistStack.alignment = UIStackViewAlignmentFill;
  [self.contentView addSubview:_assistStack];

  // 思考块：左侧竖线 + 头部 + 正文
  _thinkBox = [[UIView alloc] init];
  _thinkBox.translatesAutoresizingMaskIntoConstraints = NO;

  _thinkBar = [[UIView alloc] init];
  _thinkBar.translatesAutoresizingMaskIntoConstraints = NO;
  _thinkBar.backgroundColor = [DSTheme borderL3];
  [_thinkBox addSubview:_thinkBar];

  _thinkHead = [UIButton buttonWithType:UIButtonTypeSystem];
  _thinkHead.translatesAutoresizingMaskIntoConstraints = NO;
  _thinkHead.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  _thinkHead.titleLabel.font = [DSTheme thinkHeadFont];
  [_thinkHead setTitle:DSStrThinking forState:UIControlStateNormal];
  [_thinkHead setTitleColor:[DSTheme labelSecondary] forState:UIControlStateNormal];
  [_thinkHead addTarget:self action:@selector(toggleThink) forControlEvents:UIControlEventTouchUpInside];

  _thinkBody = [[UILabel alloc] init];
  _thinkBody.translatesAutoresizingMaskIntoConstraints = NO;
  _thinkBody.numberOfLines = 0;

  UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:@[_thinkHead, _thinkBody]];
  inner.translatesAutoresizingMaskIntoConstraints = NO;
  inner.axis = UILayoutConstraintAxisVertical;
  inner.spacing = 4;
  inner.alignment = UIStackViewAlignmentFill;
  [_thinkBox addSubview:inner];

  [NSLayoutConstraint activateConstraints:@[
    [_thinkBar.leadingAnchor constraintEqualToAnchor:_thinkBox.leadingAnchor],
    [_thinkBar.topAnchor constraintEqualToAnchor:_thinkBox.topAnchor],
    [_thinkBar.bottomAnchor constraintEqualToAnchor:_thinkBox.bottomAnchor],
    [_thinkBar.widthAnchor constraintEqualToConstant:[DSTheme thinkBarWidth]],
    [inner.leadingAnchor constraintEqualToAnchor:_thinkBox.leadingAnchor constant:[DSTheme thinkBarGap]],
    [inner.trailingAnchor constraintEqualToAnchor:_thinkBox.trailingAnchor],
    [inner.topAnchor constraintEqualToAnchor:_thinkBox.topAnchor],
    [inner.bottomAnchor constraintEqualToAnchor:_thinkBox.bottomAnchor],
  ]];

  // 正文
  _contentLabel = [[UILabel alloc] init];
  _contentLabel.numberOfLines = 0;

  // 工具摘要（暂时用单行文字；Fragment 卡片化留待后续）
  _toolLabel = [[UILabel alloc] init];
  _toolLabel.numberOfLines = 0;
  _toolLabel.font = [DSTheme thinkFont];
  _toolLabel.textColor = [DSTheme labelSecondary];

  // 底栏：用量 + 操作
  _usageLabel = [[UILabel alloc] init];
  _usageLabel.font = [DSTheme usageFont];
  _usageLabel.textColor = [DSTheme labelCaption];

  _btnCopy = [self footerButtonWithTitle:DSStrCopy action:@selector(onCopyTapped)];
  _regenButton = [self footerButtonWithTitle:DSStrRegenerate action:@selector(regenTapped)];

  UIView *spacer = [[UIView alloc] init];
  [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow
                            forAxis:UILayoutConstraintAxisHorizontal];

  _footerStack = [[UIStackView alloc] initWithArrangedSubviews:@[_usageLabel, spacer, _btnCopy, _regenButton]];
  _footerStack.axis = UILayoutConstraintAxisHorizontal;
  _footerStack.spacing = 12;
  _footerStack.alignment = UIStackViewAlignmentCenter;

  [_assistStack addArrangedSubview:_thinkBox];
  [_assistStack addArrangedSubview:_toolLabel];
  [_assistStack addArrangedSubview:_contentLabel];
  [_assistStack addArrangedSubview:_footerStack];
}

- (UIButton *)footerButtonWithTitle:(NSString *)title action:(SEL)action {
  UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
  b.translatesAutoresizingMaskIntoConstraints = NO;
  b.titleLabel.font = [DSTheme usageFont];
  [b setTitle:title forState:UIControlStateNormal];
  [b setTitleColor:[DSTheme labelTertiary] forState:UIControlStateNormal];
  [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  return b;
}

- (void)activateBaseConstraints {
  UIView *cv = self.contentView;
  CGFloat pad = [DSTheme messageListPadding];

  [NSLayoutConstraint activateConstraints:@[
    // 用户气泡
    [_userBubble.topAnchor constraintEqualToAnchor:cv.topAnchor constant:6],
    [_userBubble.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-6],
    [_userBubble.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
    [_userBubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor constant:pad],
    [_userBubble.widthAnchor constraintLessThanOrEqualToAnchor:cv.widthAnchor multiplier:[DSTheme userBubbleMaxWidth]],

    // 助手列
    [_assistStack.topAnchor constraintEqualToAnchor:cv.topAnchor constant:6],
    [_assistStack.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-6],
    [_assistStack.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
    [_assistStack.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
  ]];
}

#pragma mark - 配置

- (void)configure:(NSDictionary *)message {
  _message = message;
  BOOL isUser = [(message[@"role"] ?: @"") isEqualToString:@"user"];

  _userBubble.hidden = !isUser;
  _assistStack.hidden = isUser;

  if (isUser) {
    [self configureUser:message];
  } else {
    [self configureAssistant:message];
  }
}

- (void)configureUser:(NSDictionary *)m {
  _userLabel.attributedText = [DSTheme bodyText:m[@"content"] ?: @""
                                          color:[DSTheme labelPrimary]];
}

- (void)configureAssistant:(NSDictionary *)m {
  NSString *reasoning = m[@"reasoning"] ?: @"";
  NSString *content = m[@"content"] ?: @"";
  BOOL streaming = [m[@"streaming"] boolValue];

  // 思考块
  if (reasoning.length > 0) {
    _thinkBox.hidden = NO;
    _thinkBody.attributedText = [DSTheme thinkText:reasoning color:[DSTheme labelTertiary]];
    // 流式中始终展开；结束后按折叠状态（默认折叠，对齐 thinkingAutoFold 的默认行为）
    BOOL expand = streaming ? YES : self.thinkExpanded;
    _thinkBody.hidden = !expand;
  } else {
    _thinkBox.hidden = YES;
  }

  // 工具调用摘要
  NSArray *tools = m[@"toolNames"];
  if ([tools isKindOfClass:NSArray.class] && tools.count > 0) {
    _toolLabel.hidden = NO;
    _toolLabel.text = [NSString stringWithFormat:@"%@ · %lu",
                       DSStrToolSearchResult, (unsigned long)tools.count];
  } else {
    _toolLabel.hidden = YES;
    _toolLabel.text = nil;
  }

  // 正文
  if (content.length > 0) {
    _contentLabel.hidden = NO;
    _contentLabel.attributedText = [DSTheme bodyText:content color:[DSTheme labelPrimary]];
  } else {
    _contentLabel.hidden = YES;
    _contentLabel.attributedText = nil;
  }

  // 用量与操作
  NSNumber *p = m[@"prompt_tokens"], *c = m[@"completion_tokens"];
  if ((p || c) && !streaming) {
    _usageLabel.hidden = NO;
    _usageLabel.text = [NSString stringWithFormat:@"↑%@ ↓%@", p ?: @0, c ?: @0];
  } else {
    _usageLabel.hidden = YES;
    _usageLabel.text = nil;
  }
  _btnCopy.hidden = streaming || content.length == 0;
  // 「再试一次」需要「替换指定消息」的服务端能力，当前 core 尚未提供，
  // 先隐藏按钮而不是给一个会追加重复消息的假功能。
  _regenButton.hidden = YES;
  _footerStack.hidden = _usageLabel.hidden && _btnCopy.hidden;
}

#pragma mark - 交互

- (void)setThinkExpanded:(BOOL)expanded {
  _thinkExpanded = expanded;
  _thinkBody.hidden = !expanded;
}

- (void)toggleThink {
  [self setThinkExpanded:!self.thinkExpanded];
  // 高度变化后让所在表格刷新本行
  UITableView *tv = [self containingTableView];
  [tv beginUpdates];
  [tv endUpdates];
}

- (UITableView *)containingTableView {
  UIView *v = self.superview;
  while (v && ![v isKindOfClass:UITableView.class]) v = v.superview;
  return [v isKindOfClass:UITableView.class] ? (UITableView *)v : nil;
}

- (void)onCopyTapped {
  NSString *text = self.message[@"content"] ?: @"";
  if (text.length == 0) return;
  UIPasteboard.generalPasteboard.string = text;
  if ([self.delegate respondsToSelector:@selector(messageCellDidCopy:)]) {
    [self.delegate messageCellDidCopy:self];
  }
}

- (void)regenTapped {
  if ([self.delegate respondsToSelector:@selector(messageCellDidTapRegenerate:)]) {
    [self.delegate messageCellDidTapRegenerate:self];
  }
}

- (void)prepareForReuse {
  [super prepareForReuse];
  _message = nil;
  _thinkExpanded = NO;
  _userBubble.hidden = YES;
  _assistStack.hidden = YES;
}

@end
