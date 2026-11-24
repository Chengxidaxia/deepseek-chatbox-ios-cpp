//
//  DSFragmentView.m
//  ChatboxIOS
//
//  尺寸全部取自 Web 端设计令牌（app.css 的 .tool-card / .think / .method）：
//  圆角 14、描边 1、头部内边距 10×12、字号 13、图标 16、间距 8。
//

#import "DSFragmentView.h"
#import "DSTheme.h"
#import "DSStrings.h"
#import "DSIcon.h"
#import <objc/runtime.h>

#pragma mark - 工具卡片

@interface DSToolCardView ()
@property (nonatomic, copy) NSString *toolName;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy, nullable) NSString *subtitle;   // query / url / 表达式
@property (nonatomic, assign) DSToolStatus status;
@property (nonatomic, strong) UIStackView *root;
@property (nonatomic, strong) UIControl *head;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong) UIView *pulseDot;
@property (nonatomic, strong) UITextView *resultView;
@property (nonatomic, assign, readwrite) BOOL expanded;
@end

@implementation DSToolCardView

- (instancetype)initWithToolName:(NSString *)name arguments:(NSDictionary *)args {
  if ((self = [super initWithFrame:CGRectZero])) {
    _toolName = [name copy] ?: @"";
    _kind = DSStrToolKind(_toolName);
    _subtitle = [self subtitleFromArgs:args];
    _status = DSToolStatusRunning;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self buildUI];
    [self refreshHead];
  }
  return self;
}

/// 从参数里挑一个最能说明「在做什么」的字段做副标题
- (nullable NSString *)subtitleFromArgs:(NSDictionary *)args {
  if (![args isKindOfClass:NSDictionary.class]) return nil;
  static NSArray<NSString *> *keys;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    keys = @[@"query", @"url", @"expr", @"pattern", @"text", @"name", @"input", @"q", @"keyword"];
  });
  for (NSString *k in keys) {
    id v = args[k];
    if ([v isKindOfClass:NSString.class] && [v length]) return v;
  }
  // 再退一步：任意字符串参数
  for (NSString *k in args) {
    id v = args[k];
    if ([v isKindOfClass:NSString.class] && [v length] && [v length] < 200) return v;
  }
  return nil;
}

- (void)buildUI {
  self.backgroundColor = [DSTheme toolCardBG];
  self.layer.cornerRadius = 14;
  self.layer.cornerCurve = kCACornerCurveContinuous;
  self.layer.borderWidth = 1;
  self.layer.borderColor = [DSTheme borderL2].CGColor;
  self.clipsToBounds = YES;

  _icon = [[UIImageView alloc] init];
  _icon.translatesAutoresizingMaskIntoConstraints = NO;
  _icon.contentMode = UIViewContentModeCenter;
  _icon.tintColor = [DSTheme labelSecondary];
  [_icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  _titleLabel = [[UILabel alloc] init];
  _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  _titleLabel.textColor = [DSTheme labelSecondary];
  [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                               forAxis:UILayoutConstraintAxisHorizontal];

  _subLabel = [[UILabel alloc] init];
  _subLabel.font = [UIFont systemFontOfSize:13];
  _subLabel.textColor = [DSTheme labelCaption];
  _subLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

  _statusLabel = [[UILabel alloc] init];
  _statusLabel.font = [UIFont systemFontOfSize:13];
  _statusLabel.textColor = [DSTheme labelCaption];

  _pulseDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 6)];
  _pulseDot.translatesAutoresizingMaskIntoConstraints = NO;
  _pulseDot.backgroundColor = [DSTheme brand];
  _pulseDot.layer.cornerRadius = 3;
  _pulseDot.hidden = YES;

  _chevron = [[UIImageView alloc] init];
  _chevron.translatesAutoresizingMaskIntoConstraints = NO;
  _chevron.image = [DSIcon image:DSIconChevronDown size:14];
  _chevron.tintColor = [DSTheme labelCaption];
  _chevron.contentMode = UIViewContentModeCenter;
  [_chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIView *headRow = [[UIView alloc] init];
  UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:
      @[_icon, _titleLabel, _subLabel, _pulseDot, _statusLabel, _chevron]];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.axis = UILayoutConstraintAxisHorizontal;
  row.alignment = UIStackViewAlignmentCenter;
  row.spacing = 8;
  [headRow addSubview:row];
  [NSLayoutConstraint activateConstraints:@[
    [row.leadingAnchor constraintEqualToAnchor:headRow.leadingAnchor constant:12],
    [row.trailingAnchor constraintEqualToAnchor:headRow.trailingAnchor constant:-12],
    [row.topAnchor constraintEqualToAnchor:headRow.topAnchor constant:10],
    [row.bottomAnchor constraintEqualToAnchor:headRow.bottomAnchor constant:-10],
    [_icon.widthAnchor constraintEqualToConstant:16],
    [_icon.heightAnchor constraintEqualToConstant:16],
    [_pulseDot.widthAnchor constraintEqualToConstant:6],
    [_pulseDot.heightAnchor constraintEqualToConstant:6],
    [_chevron.widthAnchor constraintEqualToConstant:14],
    [_chevron.heightAnchor constraintEqualToConstant:14],
  ]];
  // 副标题吃掉剩余空间，其余不拉伸
  [_subLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  _head = [[UIControl alloc] init];
  _head.translatesAutoresizingMaskIntoConstraints = NO;
  [_head addSubview:headRow];
  [NSLayoutConstraint activateConstraints:@[
    [headRow.leadingAnchor constraintEqualToAnchor:_head.leadingAnchor],
    [headRow.trailingAnchor constraintEqualToAnchor:_head.trailingAnchor],
    [headRow.topAnchor constraintEqualToAnchor:_head.topAnchor],
    [headRow.bottomAnchor constraintEqualToAnchor:_head.bottomAnchor],
  ]];
  [_head addTarget:self action:@selector(toggleExpanded) forControlEvents:UIControlEventTouchUpInside];

  _resultView = [[UITextView alloc] init];
  _resultView.translatesAutoresizingMaskIntoConstraints = NO;
  _resultView.editable = NO;
  _resultView.scrollEnabled = YES;
  _resultView.backgroundColor = UIColor.clearColor;
  _resultView.textContainerInset = UIEdgeInsetsMake(2, 0, 2, 0);
  _resultView.textContainer.lineFragmentPadding = 0;
  _resultView.font = [UIFont systemFontOfSize:12.5];
  _resultView.textColor = [DSTheme labelSecondary];
  _resultView.hidden = YES;

  _root = [[UIStackView alloc] initWithArrangedSubviews:@[_head, _resultView]];
  _root.translatesAutoresizingMaskIntoConstraints = NO;
  _root.axis = UILayoutConstraintAxisVertical;
  _root.spacing = 0;
  [self addSubview:_root];

  [NSLayoutConstraint activateConstraints:@[
    [_root.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [_root.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [_root.topAnchor constraintEqualToAnchor:self.topAnchor],
    [_root.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    // 结果区限高 260，超出内部滚动（对齐 Web 的 max-height）
    [_resultView.heightAnchor constraintLessThanOrEqualToConstant:260],
    [_resultView.heightAnchor constraintGreaterThanOrEqualToConstant:36],
  ]];
  // 结果区内边距用容器实现，便于保持 12 的左右对齐
  _resultView.textContainerInset = UIEdgeInsetsMake(2, 12, 8, 12);
}

- (void)refreshHead {
  DSIconName iname = DSIconGlobe;
  if ([_kind isEqualToString:@"open"]) iname = DSIconDoc;
  else if ([_kind isEqualToString:@"find"]) iname = DSIconSearch;
  else if (![_kind isEqualToString:@"search"]) iname = DSIconLightning;
  _icon.image = [DSIcon image:iname size:16];

  NSString *label = DSStrToolLabel(_toolName);
  NSString *sub = _subtitle.length ? [NSString stringWithFormat:@"· %@", _subtitle] : @"";

  if (_status == DSToolStatusRunning) {
    _pulseDot.hidden = NO;
    [self startPulse];
    if ([_kind isEqualToString:@"search"]) {
      _titleLabel.text = _subtitle.length ? [NSString stringWithFormat:DSStrToolSearchQuery, _subtitle] : DSStrSearching;
      _subLabel.text = @"";
    } else if ([_kind isEqualToString:@"open"]) {
      _titleLabel.text = [NSString stringWithFormat:@"%@ %@", DSStrBrowsing, _subtitle ?: @""];
      _subLabel.text = @"";
    } else if ([_kind isEqualToString:@"find"]) {
      _titleLabel.text = _subtitle.length ? [NSString stringWithFormat:DSStrToolFindWip, _subtitle] : DSStrToolCalls;
      _subLabel.text = @"";
    } else {
      _titleLabel.text = [NSString stringWithFormat:@"%@%@", label, DSStrGenerating];
      _subLabel.text = sub;
    }
    _statusLabel.text = @"";
    _statusLabel.textColor = [DSTheme labelCaption];
  } else {
    _pulseDot.hidden = YES;
    [self stopPulse];
    if (_status == DSToolStatusFailed) {
      if ([_kind isEqualToString:@"search"]) _titleLabel.text = DSStrSearchFailed;
      else if ([_kind isEqualToString:@"open"]) _titleLabel.text = DSStrBrowseFailed;
      else if ([_kind isEqualToString:@"find"]) _titleLabel.text = DSStrFindFailed;
      else _titleLabel.text = [NSString stringWithFormat:@"%@ %@", label, @"失败"];
      _subLabel.text = @"";
      _statusLabel.text = @"";
      _titleLabel.textColor = [DSTheme danger];
    } else {
      _titleLabel.textColor = [DSTheme labelSecondary];
      if ([_kind isEqualToString:@"search"]) {
        _titleLabel.text = _subtitle.length ? [NSString stringWithFormat:DSStrToolSearchDone, _subtitle] : DSStrSearched;
        _subLabel.text = @"";
      } else if ([_kind isEqualToString:@"open"]) {
        _titleLabel.text = [NSString stringWithFormat:@"%@ %@", DSStrSearched, _subtitle ?: @""];
        _subLabel.text = @"";
      } else if ([_kind isEqualToString:@"find"]) {
        _titleLabel.text = _subtitle.length ? [NSString stringWithFormat:DSStrToolFindDone, _subtitle] : label;
        _subLabel.text = @"";
      } else {
        _titleLabel.text = label;
        _subLabel.text = sub;
      }
      _statusLabel.text = @"";
    }
  }
  _chevron.image = [DSIcon image:_expanded ? DSIconChevronDown : DSIconChevronRight size:14];
}

- (void)startPulse {
  if ([_pulseDot.layer animationForKey:@"pulse"]) return;
  CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
  a.fromValue = @0.25;
  a.toValue = @1.0;
  a.duration = 0.55;
  a.autoreverses = YES;
  a.repeatCount = HUGE_VALF;
  a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  [_pulseDot.layer addAnimation:a forKey:@"pulse"];
}

- (void)stopPulse { [_pulseDot.layer removeAllAnimations]; }

- (void)applyStatus:(DSToolStatus)status text:(NSString *)text milliseconds:(NSInteger)ms {
  _status = status;
  if (text.length) {
    _resultView.text = text;
    // 结果有内容才允许展开
    _resultView.hidden = !_expanded;
  }
  [self refreshHead];
  if (ms > 0 && status != DSToolStatusRunning) {
    _statusLabel.text = ms >= 1000
        ? [NSString stringWithFormat:@"%ld.%lds", (long)(ms / 1000), (long)((ms % 1000) / 100)]
        : [NSString stringWithFormat:@"%ldms", (long)ms];
    _statusLabel.textColor = [DSTheme labelCaption];
  }
}

- (void)toggleExpanded {
  if (_resultView.text.length == 0) return;
  _expanded = !_expanded;
  _resultView.hidden = !_expanded;
  _chevron.image = [DSIcon image:_expanded ? DSIconChevronDown : DSIconChevronRight size:14];
  if (self.onLayoutChange) self.onLayoutChange();
}

@end

#pragma mark - 分支切换

@interface DSBranchBar ()
@property (nonatomic, strong) UIButton *prev;
@property (nonatomic, strong) UIButton *next;
@property (nonatomic, strong) UILabel *label;
@end

@implementation DSBranchBar

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setContentHuggingPriority:UILayoutPriorityDefaultHigh
                            forAxis:UILayoutConstraintAxisHorizontal];
    _prev = [self arrowButton:DSIconChevronLeft];
    _next = [self arrowButton:DSIconChevronRight];
    _label = [[UILabel alloc] init];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [UIFont systemFontOfSize:12];
    _label.textColor = [DSTheme labelTertiary];
    _label.textAlignment = NSTextAlignmentCenter;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_prev, _label, _next]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 2;
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
      [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [row.topAnchor constraintEqualToAnchor:self.topAnchor],
      [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [row.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
      [_prev.widthAnchor constraintEqualToConstant:24],
      [_prev.heightAnchor constraintEqualToConstant:24],
      [_next.widthAnchor constraintEqualToConstant:24],
      [_next.heightAnchor constraintEqualToConstant:24],
    ]];
  }
  return self;
}

- (UIButton *)arrowButton:(DSIconName)icon {
  UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
  b.translatesAutoresizingMaskIntoConstraints = NO;
  [b setImage:[DSIcon image:icon size:14] forState:UIControlStateNormal];
  b.tintColor = [DSTheme labelTertiary];
  return b;
}

- (void)setIndex:(NSInteger)index total:(NSInteger)total {
  _label.text = [NSString stringWithFormat:DSStrBranchSwitcher, (int)(index + 1), (int)total];
  _prev.enabled = index > 0;
  _next.enabled = index + 1 < total;
  _prev.alpha = _prev.enabled ? 1 : 0.35;
  _next.alpha = _next.enabled ? 1 : 0.35;
  [_prev removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
  [_next removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
  [_prev addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
  [_next addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
}

- (void)prevTapped { if (_prev.enabled && self.onPrev) self.onPrev(); }
- (void)nextTapped { if (_next.enabled && self.onNext) self.onNext(); }

@end

#pragma mark - 引用来源

@interface DSCitationListView ()
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation DSCitationListView

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _stack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 2;
    [self addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
      [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
      [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
  }
  return self;
}

- (void)setCitations:(NSArray<NSDictionary *> *)items {
  for (UIView *v in _stack.arrangedSubviews) {
    [_stack removeArrangedSubview:v];
    [v removeFromSuperview];
  }
  if (items.count == 0) { self.hidden = YES; return; }
  self.hidden = NO;

  UILabel *head = [[UILabel alloc] init];
  head.text = DSStrSources;
  head.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  head.textColor = [DSTheme labelTertiary];
  [_stack addArrangedSubview:head];

  NSInteger i = 1;
  for (NSDictionary *it in items) {
    if (![it isKindOfClass:NSDictionary.class]) continue;
    NSString *title = it[@"title"] ?: it[@"url"] ?: @"";
    NSString *urlStr = it[@"url"] ?: @"";
    NSString *site = it[@"site_name"] ?: @"";
    if (title.length == 0 && urlStr.length == 0) continue;

    UIControl *row = [[UIControl alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *idx = [[UILabel alloc] init];
    idx.translatesAutoresizingMaskIntoConstraints = NO;
    idx.text = [NSString stringWithFormat:@"%ld", (long)i];
    idx.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    idx.textColor = [DSTheme labelTertiary];
    idx.textAlignment = NSTextAlignmentCenter;
    idx.backgroundColor = [DSTheme bgHover];
    idx.layer.cornerRadius = 4;
    idx.layer.masksToBounds = YES;

    UILabel *t = [[UILabel alloc] init];
    t.numberOfLines = 2;
    t.font = [UIFont systemFontOfSize:13];
    t.textColor = [DSTheme labelSecondary];
    t.text = title;

    UILabel *u = [[UILabel alloc] init];
    u.font = [UIFont systemFontOfSize:11];
    u.textColor = [DSTheme labelTertiary];
    u.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *host = urlStr;
    NSURL *parsed = urlStr.length ? [NSURL URLWithString:urlStr] : nil;
    if (parsed.host.length) host = site.length ? [NSString stringWithFormat:@"%@ · %@", site, parsed.host] : parsed.host;
    u.text = host;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[t, u]];
    col.translatesAutoresizingMaskIntoConstraints = NO;
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 1;

    [row addSubview:idx];
    [row addSubview:col];
    [NSLayoutConstraint activateConstraints:@[
      [idx.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:2],
      [idx.topAnchor constraintEqualToAnchor:row.topAnchor constant:5],
      [idx.widthAnchor constraintEqualToConstant:16],
      [idx.heightAnchor constraintEqualToConstant:16],
      [col.leadingAnchor constraintEqualToAnchor:idx.trailingAnchor constant:8],
      [col.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-2],
      [col.topAnchor constraintEqualToAnchor:row.topAnchor constant:4],
      [col.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-4],
    ]];

    if (parsed) {
      objc_setAssociatedObject(row, "ds.citation.url", parsed, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    [_stack addArrangedSubview:row];
    i++;
  }
}

- (void)rowTapped:(UIControl *)sender {
  NSURL *url = objc_getAssociatedObject(sender, "ds.citation.url");
  if (url && self.onOpenURL) self.onOpenURL(url);
}

@end

#pragma mark - 联网搜索卡片

@interface DSSearchResultCardView ()
@property (nonatomic, strong) UIControl *head;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *queryLabel;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong) UIStackView *body;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, strong) NSArray<NSDictionary *> *sources;
@end

@implementation DSSearchResultCardView

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [DSTheme toolCardBG];
    self.layer.cornerRadius = 14;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [DSTheme borderL2].CGColor;
    self.clipsToBounds = YES;

    _icon = [[UIImageView alloc] init];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.image = [DSIcon image:DSIconGlobe size:16];
    _icon.tintColor = [DSTheme labelSecondary];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _titleLabel.textColor = [DSTheme labelSecondary];
    _titleLabel.text = DSStrSearching;

    _queryLabel = [[UILabel alloc] init];
    _queryLabel.font = [UIFont systemFontOfSize:13];
    _queryLabel.textColor = [DSTheme labelCaption];
    _queryLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_queryLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _chevron = [[UIImageView alloc] init];
    _chevron.translatesAutoresizingMaskIntoConstraints = NO;
    _chevron.image = [DSIcon image:DSIconChevronRight size:14];
    _chevron.tintColor = [DSTheme labelCaption];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:
        @[_icon, _titleLabel, _queryLabel, _chevron]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;

    _head = [[UIControl alloc] init];
    _head.translatesAutoresizingMaskIntoConstraints = NO;
    [_head addSubview:row];
    [_head addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

    _body = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    _body.axis = UILayoutConstraintAxisVertical;
    _body.spacing = 6;
    _body.hidden = YES;

    UIStackView *root = [[UIStackView alloc] initWithArrangedSubviews:@[_head, _body]];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.axis = UILayoutConstraintAxisVertical;
    [self addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
      [root.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [root.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [root.topAnchor constraintEqualToAnchor:self.topAnchor],
      [root.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [row.leadingAnchor constraintEqualToAnchor:_head.leadingAnchor constant:12],
      [row.trailingAnchor constraintEqualToAnchor:_head.trailingAnchor constant:-12],
      [row.topAnchor constraintEqualToAnchor:_head.topAnchor constant:10],
      [row.bottomAnchor constraintEqualToAnchor:_head.bottomAnchor constant:-10],
      [_icon.widthAnchor constraintEqualToConstant:16],
      [_icon.heightAnchor constraintEqualToConstant:16],
      [_chevron.widthAnchor constraintEqualToConstant:14],
      [_chevron.heightAnchor constraintEqualToConstant:14],
      // body 左右留白 12，底部由内部条目自带的留白撑开
      [_body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
      [_body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
    ]];
  }
  return self;
}

- (void)applyServerToolCalls:(NSArray<NSDictionary *> *)calls {
  NSMutableArray<NSString *> *queries = [NSMutableArray array];
  NSMutableArray<NSDictionary *> *sources = [NSMutableArray array];
  BOOL running = NO, failed = NO, sawCall = NO;

  for (NSDictionary *c in calls) {
    if (![c isKindOfClass:NSDictionary.class]) continue;
    sawCall = YES;
    NSDictionary *action = [c[@"action"] isKindOfClass:NSDictionary.class] ? c[@"action"] : nil;
    id qs = action[@"queries"];
    if ([qs isKindOfClass:NSArray.class]) {
      for (id q in qs) if ([q isKindOfClass:NSString.class] && [q length]) [queries addObject:q];
    } else if ([action[@"query"] isKindOfClass:NSString.class]) {
      [queries addObject:action[@"query"]];
    }
    id st = c[@"status"];
    if ([st isKindOfClass:NSString.class]) {
      if ([st isEqualToString:@"searching"] || [st isEqualToString:@"running"]) running = YES;
      if ([st isEqualToString:@"failed"]) failed = YES;
    }
    id srcs = c[@"sources"];
    if ([srcs isKindOfClass:NSArray.class]) {
      for (id s in srcs) if ([s isKindOfClass:NSDictionary.class]) [sources addObject:s];
    }
    NSDictionary *page = [c[@"page"] isKindOfClass:NSDictionary.class] ? c[@"page"] : nil;
    if (page) [sources addObject:page];
  }

  _sources = sources;
  _queryLabel.text = queries.count ? [NSString stringWithFormat:@"· %@", [queries componentsJoinedByString:@" · "]] : @"";

  if (!sawCall || running) {
    _titleLabel.text = DSStrSearching;
    _titleLabel.textColor = [DSTheme labelSecondary];
  } else if (failed && sources.count == 0) {
    _titleLabel.text = DSStrSearchFailed;
    _titleLabel.textColor = [DSTheme danger];
  } else if (sources.count) {
    _titleLabel.text = [NSString stringWithFormat:DSStrMergeSearchCount, (int)sources.count];
    _titleLabel.textColor = [DSTheme labelSecondary];
  } else {
    _titleLabel.text = DSStrToolSearchEmpty;
    _titleLabel.textColor = [DSTheme labelTertiary];
  }

  [self rebuildSources];
  if (self.onLayoutChange) self.onLayoutChange();
}

- (void)rebuildSources {
  for (UIView *v in _body.arrangedSubviews) {
    [_body removeArrangedSubview:v];
    [v removeFromSuperview];
  }
  NSInteger i = 1;
  for (NSDictionary *s in _sources) {
    NSString *title = [s[@"title"] isKindOfClass:NSString.class] ? s[@"title"] : @"";
    NSString *urlStr = [s[@"url"] isKindOfClass:NSString.class] ? s[@"url"] : @"";
    NSString *snippet = [s[@"snippet"] isKindOfClass:NSString.class] ? s[@"snippet"]
                        : ([s[@"description"] isKindOfClass:NSString.class] ? s[@"description"] : @"");
    if (title.length == 0 && urlStr.length == 0) continue;

    UIControl *row = [[UIControl alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *idx = [[UILabel alloc] init];
    idx.translatesAutoresizingMaskIntoConstraints = NO;
    idx.text = [NSString stringWithFormat:@"%ld", (long)i];
    idx.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    idx.textColor = [DSTheme labelTertiary];
    idx.textAlignment = NSTextAlignmentCenter;
    idx.backgroundColor = [DSTheme bgHover];
    idx.layer.cornerRadius = 4;
    idx.layer.masksToBounds = YES;

    UILabel *t = [[UILabel alloc] init];
    t.numberOfLines = 2;
    t.font = [UIFont systemFontOfSize:13];
    t.textColor = [DSTheme labelSecondary];
    t.text = title.length ? title : urlStr;

    UILabel *sn = [[UILabel alloc] init];
    sn.numberOfLines = 2;
    sn.font = [UIFont systemFontOfSize:11.5];
    sn.textColor = [DSTheme labelTertiary];
    sn.text = snippet;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[t, sn]];
    col.translatesAutoresizingMaskIntoConstraints = NO;
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 2;

    [row addSubview:idx];
    [row addSubview:col];
    [NSLayoutConstraint activateConstraints:@[
      [idx.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
      [idx.topAnchor constraintEqualToAnchor:row.topAnchor constant:4],
      [idx.widthAnchor constraintEqualToConstant:16],
      [idx.heightAnchor constraintEqualToConstant:16],
      [col.leadingAnchor constraintEqualToAnchor:idx.trailingAnchor constant:8],
      [col.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
      [col.topAnchor constraintEqualToAnchor:row.topAnchor constant:3],
      [col.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-3],
    ]];

    NSURL *parsed = urlStr.length ? [NSURL URLWithString:urlStr] : nil;
    if (parsed) {
      objc_setAssociatedObject(row, "ds.source.url", parsed, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    [_body addArrangedSubview:row];
    i++;
  }
  _body.hidden = !_expanded || _body.arrangedSubviews.count == 0;
  _chevron.image = [DSIcon image:(_expanded && _body.arrangedSubviews.count) ? DSIconChevronDown
                                                                : DSIconChevronRight size:14];
}

- (void)toggle {
  if (_body.arrangedSubviews.count == 0) return;
  _expanded = !_expanded;
  _body.hidden = !_expanded;
  _chevron.image = [DSIcon image:_expanded ? DSIconChevronDown : DSIconChevronRight size:14];
  if (self.onLayoutChange) self.onLayoutChange();
}

- (void)rowTapped:(UIControl *)sender {
  NSURL *url = objc_getAssociatedObject(sender, "ds.source.url");
  if (url && self.onOpenURL) self.onOpenURL(url);
}

@end

