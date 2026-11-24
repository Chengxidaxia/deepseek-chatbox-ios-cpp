//
//  DSMessageCell.m
//  ChatboxIOS
//
//  两种形态：
//  - 用户消息：右对齐淡蓝气泡（--bubble），圆角 18、内边距 10/14、最大宽 78%
//  - 助手消息：无气泡、全宽左对齐，按官方 Fragment 顺序竖向排列：
//      思考（2px 竖线，可折叠）→ 该轮工具卡片 → 引用 → 正文 → 用量/分支/操作
//    一条回答可能有多轮（工具调用往返），每轮的思考与工具各归各位，不合并成一组。
//

#import "DSMessageCell.h"
#import "DSTheme.h"
#import "DSStrings.h"
#import "DSIcon.h"
#import "DSTurn.h"
#import "DSFragmentView.h"
#import "DSBoxService.h"
#import <objc/runtime.h>

@interface DSMessageCell ()
// 用户
@property (nonatomic, strong) UIView *userBubble;
@property (nonatomic, strong) UILabel *userLabel;
@property (nonatomic, strong) UIStackView *userAttach;
@property (nonatomic, strong) UIStackView *userFoot;
@property (nonatomic, strong) DSBranchBar *userBranchBar;
@property (nonatomic, strong) UIButton *btnUserCopy;
// 助手
@property (nonatomic, strong) UIStackView *assistStack;
@property (nonatomic, strong) UIStackView *fragStack;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIStackView *footerStack;
@property (nonatomic, strong) UILabel *usageLabel;
@property (nonatomic, strong) DSBranchBar *assistBranchBar;
@property (nonatomic, strong) UIButton *btnCopy;
@property (nonatomic, strong) UIButton *btnRegen;
@property (nonatomic, strong) UIButton *btnContinue;
// 状态
@property (nonatomic, strong, readwrite, nullable) DSTurn *turn;
@property (nonatomic, copy) NSString *signature;
/// key -> 视图，用于流式增量更新（避免每帧重建整条消息）
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *fragIndex;
/// 已展开的思考块（按轮序号）
@property (nonatomic, strong) NSMutableSet<NSNumber *> *thinkExpanded;
/// 用户侧 / 助手侧各一条底部约束，按 turn 类型互斥启用（否则隐藏的一侧仍会撑高行）
@property (nonatomic, strong) NSLayoutConstraint *userBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *assistBottomConstraint;
@end

@implementation DSMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    _fragIndex = [NSMutableDictionary dictionary];
    _thinkExpanded = [NSMutableSet set];
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

  // 气泡内：附件缩略图（图片 / 文件 chip）在上，正文在下
  _userAttach = [[UIStackView alloc] initWithArrangedSubviews:@[]];
  _userAttach.translatesAutoresizingMaskIntoConstraints = NO;
  _userAttach.axis = UILayoutConstraintAxisHorizontal;
  _userAttach.spacing = 6;
  _userAttach.alignment = UIStackViewAlignmentTop;

  UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[_userAttach, _userLabel]];
  col.translatesAutoresizingMaskIntoConstraints = NO;
  col.axis = UILayoutConstraintAxisVertical;
  col.spacing = 6;
  [_userBubble addSubview:col];

  UIEdgeInsets ins = [DSTheme userBubbleInsets];
  [NSLayoutConstraint activateConstraints:@[
    [col.topAnchor constraintEqualToAnchor:_userBubble.topAnchor constant:ins.top],
    [col.bottomAnchor constraintEqualToAnchor:_userBubble.bottomAnchor constant:-ins.bottom],
    [col.leadingAnchor constraintEqualToAnchor:_userBubble.leadingAnchor constant:ins.left],
    [col.trailingAnchor constraintEqualToAnchor:_userBubble.trailingAnchor constant:-ins.right],
  ]];

  // 气泡下方：分支切换 + 复制（右对齐，对齐官方 UserMessageOperationBar）
  _btnUserCopy = [self footerButtonWithTitle:DSStrCopy action:@selector(onCopyTapped)];
  _userBranchBar = [[DSBranchBar alloc] initWithFrame:CGRectZero];
  UIView *spacer = [[UIView alloc] init];
  [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  _userFoot = [[UIStackView alloc] initWithArrangedSubviews:@[_userBranchBar, spacer, _btnUserCopy]];
  _userFoot.translatesAutoresizingMaskIntoConstraints = NO;
  _userFoot.axis = UILayoutConstraintAxisHorizontal;
  _userFoot.alignment = UIStackViewAlignmentCenter;
  _userFoot.spacing = 8;
  [self.contentView addSubview:_userFoot];
}

- (void)buildAssistViews {
  _assistStack = [[UIStackView alloc] init];
  _assistStack.translatesAutoresizingMaskIntoConstraints = NO;
  _assistStack.axis = UILayoutConstraintAxisVertical;
  _assistStack.spacing = 10;
  _assistStack.alignment = UIStackViewAlignmentFill;
  [self.contentView addSubview:_assistStack];

  _fragStack = [[UIStackView alloc] init];
  _fragStack.translatesAutoresizingMaskIntoConstraints = NO;
  _fragStack.axis = UILayoutConstraintAxisVertical;
  _fragStack.spacing = 10;
  _fragStack.alignment = UIStackViewAlignmentFill;

  _statusLabel = [[UILabel alloc] init];
  _statusLabel.numberOfLines = 0;
  _statusLabel.font = [DSTheme captionFont];
  _statusLabel.textColor = [DSTheme labelTertiary];

  _usageLabel = [[UILabel alloc] init];
  _usageLabel.font = [DSTheme usageFont];
  _usageLabel.textColor = [DSTheme labelCaption];

  _assistBranchBar = [[DSBranchBar alloc] initWithFrame:CGRectZero];
  _btnCopy = [self footerButtonWithTitle:DSStrCopy action:@selector(onCopyTapped)];
  _btnRegen = [self footerButtonWithTitle:DSStrRegenerate action:@selector(regenTapped)];
  _btnContinue = [self footerButtonWithTitle:DSStrContinue action:@selector(continueTapped)];

  UIView *spacer = [[UIView alloc] init];
  [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  _footerStack = [[UIStackView alloc] initWithArrangedSubviews:
      @[_assistBranchBar, _usageLabel, spacer, _btnContinue, _btnCopy, _btnRegen]];
  _footerStack.axis = UILayoutConstraintAxisHorizontal;
  _footerStack.spacing = 12;
  _footerStack.alignment = UIStackViewAlignmentCenter;

  [_assistStack addArrangedSubview:_fragStack];
  [_assistStack addArrangedSubview:_statusLabel];
  [_assistStack addArrangedSubview:_footerStack];
}

- (UIButton *)footerButtonWithTitle:(NSString *)title action:(SEL)action {
  UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
  b.translatesAutoresizingMaskIntoConstraints = NO;
  b.titleLabel.font = [DSTheme usageFont];
  [b setTitle:title forState:UIControlStateNormal];
  [b setTitleColor:[DSTheme labelTertiary] forState:UIControlStateNormal];
  [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  return b;
}

- (void)activateBaseConstraints {
  UIView *cv = self.contentView;
  CGFloat pad = [DSTheme messageListPadding];

  _userBottomConstraint = [_userFoot.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-6];
  _assistBottomConstraint = [_assistStack.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-6];

  [NSLayoutConstraint activateConstraints:@[
    // 用户气泡
    [_userBubble.topAnchor constraintEqualToAnchor:cv.topAnchor constant:6],
    [_userBubble.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
    [_userBubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor constant:pad],
    [_userBubble.widthAnchor constraintLessThanOrEqualToAnchor:cv.widthAnchor multiplier:[DSTheme userBubbleMaxWidth]],

    [_userFoot.topAnchor constraintEqualToAnchor:_userBubble.bottomAnchor constant:4],
    [_userFoot.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
    [_userFoot.leadingAnchor constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor constant:pad],

    // 助手列
    [_assistStack.topAnchor constraintEqualToAnchor:cv.topAnchor constant:6],
    [_assistStack.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
    [_assistStack.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
  ]];
  // 默认按助手形态排布；configure 时按 turn 类型切换
  _assistBottomConstraint.active = YES;
  _userBottomConstraint.active = NO;
}

#pragma mark - 配置

- (void)configureWithTurn:(DSTurn *)turn {
  _turn = turn;
  BOOL isUser = (turn.role == DSTurnRoleUser);

  _userBubble.hidden = !isUser;
  _userFoot.hidden = !isUser;
  _assistStack.hidden = isUser;
  _userBottomConstraint.active = isUser;
  _assistBottomConstraint.active = !isUser;

  if (isUser) {
    // 用户行不保留上一条助手内容，避免隐藏视图继续撑高
    [self clearFragments];
    _signature = nil;
    [self renderUser:(DSTurn *)turn];
    return;
  }
  _userLabel.attributedText = nil;

  NSString *sig = [self signatureForTurn:turn];
  if (_fragIndex.count && [sig isEqualToString:_signature]) {
    [self updateAssistantTexts:turn];
    return;
  }
  _signature = sig;
  [self rebuildAssistant:turn];
}

- (NSString *)signatureForTurn:(DSTurn *)t {
  NSMutableString *s = [NSMutableString string];
  [s appendFormat:@"r%lu", (unsigned long)t.rounds.count];
  for (NSDictionary *r in t.rounds) {
    NSArray *calls = [r[@"tool_calls"] isKindOfClass:NSArray.class] ? r[@"tool_calls"] : @[];
    [s appendFormat:@"|c%lu", (unsigned long)calls.count];
  }
  [s appendFormat:@"|s%lu|n%lu|b%ld/%ld", (unsigned long)t.serverCalls.count,
                  (unsigned long)t.citations.count, (long)t.branchIndex, (long)t.branchTotal];
  return s;
}

- (void)renderUser:(DSTurn *)t {
  NSDictionary *m = t.anchor;
  _userLabel.attributedText = [DSTheme bodyText:m[@"content"] ?: @"" color:[DSTheme labelPrimary]];
  [self renderUserAttachments:m[@"attachments"]];

  if (t.branchTotal > 1) {
    _userBranchBar.hidden = NO;
    [_userBranchBar setIndex:t.branchIndex total:t.branchTotal];
    __weak __typeof(self) ws = self;
    _userBranchBar.onPrev = ^{
      if ([ws.delegate respondsToSelector:@selector(messageCell:didSwitchBranch:)])
        [ws.delegate messageCell:ws didSwitchBranch:-1];
    };
    _userBranchBar.onNext = ^{
      if ([ws.delegate respondsToSelector:@selector(messageCell:didSwitchBranch:)])
        [ws.delegate messageCell:ws didSwitchBranch:1];
    };
  } else {
    _userBranchBar.hidden = YES;
  }
  _btnUserCopy.hidden = [(NSString *)(m[@"content"] ?: @"") length] == 0;
}

/// 用户气泡里的附件预览：图片显示缩略图，其它显示文件名 chip
- (void)renderUserAttachments:(NSArray *)atts {
  for (UIView *v in _userAttach.arrangedSubviews) {
    [_userAttach removeArrangedSubview:v];
    [v removeFromSuperview];
  }
  if (![atts isKindOfClass:NSArray.class] || atts.count == 0) {
    _userAttach.hidden = YES;
    return;
  }
  _userAttach.hidden = NO;

  for (NSDictionary *a in atts) {
    if (![a isKindOfClass:NSDictionary.class]) continue;
    NSString *kind = [a[@"kind"] isKindOfClass:NSString.class] ? a[@"kind"] : @"file";
    NSString *name = [a[@"name"] isKindOfClass:NSString.class] ? a[@"name"] : @"附件";

    if ([kind isEqualToString:@"image"]) {
      UIImage *img = [self imageForAttachment:a];
      UIImageView *iv = [[UIImageView alloc] initWithImage:img];
      iv.translatesAutoresizingMaskIntoConstraints = NO;
      iv.contentMode = UIViewContentModeScaleAspectFill;
      iv.clipsToBounds = YES;
      iv.backgroundColor = [DSTheme bgHover];
      iv.layer.cornerRadius = 12;
      iv.layer.cornerCurve = kCACornerCurveContinuous;
      [NSLayoutConstraint activateConstraints:@[
        [iv.widthAnchor constraintEqualToConstant:124],
        [iv.heightAnchor constraintEqualToConstant:124],
      ]];
      [_userAttach addArrangedSubview:iv];
    } else {
      UIView *chip = [[UIView alloc] init];
      chip.translatesAutoresizingMaskIntoConstraints = NO;
      chip.backgroundColor = [DSTheme bgBase];
      chip.layer.cornerRadius = 10;
      chip.layer.borderWidth = 1;
      chip.layer.borderColor = [DSTheme borderL2].CGColor;

      UIImageView *icon = [[UIImageView alloc] init];
      icon.translatesAutoresizingMaskIntoConstraints = NO;
      icon.image = [DSIcon image:DSIconFile size:14];
      icon.tintColor = [DSTheme labelTertiary];
      [chip addSubview:icon];

      UILabel *label = [[UILabel alloc] init];
      label.translatesAutoresizingMaskIntoConstraints = NO;
      label.font = [UIFont systemFontOfSize:12];
      label.textColor = [DSTheme labelSecondary];
      label.text = name;
      label.lineBreakMode = NSLineBreakByTruncatingMiddle;
      [chip addSubview:label];

      [NSLayoutConstraint activateConstraints:@[
        [chip.heightAnchor constraintEqualToConstant:30],
        [icon.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:8],
        [icon.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:14],
        [icon.heightAnchor constraintEqualToConstant:14],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-10],
        [label.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
      ]];
      [_userAttach addArrangedSubview:chip];
    }
  }
}

- (nullable UIImage *)imageForAttachment:(NSDictionary *)a {
  NSString *dataUrl = [a[@"dataUrl"] isKindOfClass:NSString.class] ? a[@"dataUrl"] : @"";
  if ([dataUrl hasPrefix:@"data:image/"] && [dataUrl containsString:@","]) {
    NSString *b64 = [dataUrl componentsSeparatedByString:@","].lastObject;
    NSData *d = [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (d.length) return [UIImage imageWithData:d];
  }
  NSString *attId = [a[@"id"] isKindOfClass:NSString.class] ? a[@"id"] : @"";
  if (attId.length) {
    NSData *d = [[DSBoxService shared] attachmentDataWithId:attId];
    if (d.length) return [UIImage imageWithData:d];
  }
  return nil;
}

#pragma mark - 助手重建

- (void)clearFragments {
  for (UIView *v in _fragStack.arrangedSubviews) {
    [_fragStack removeArrangedSubview:v];
    [v removeFromSuperview];
  }
  [_fragIndex removeAllObjects];
}

- (void)rebuildAssistant:(DSTurn *)t {
  [self clearFragments];

  __weak __typeof(self) ws = self;
  void (^layoutChanged)(void) = ^{
    [ws notifyHeightChanged];
  };

  // ---- 按发生顺序铺 Fragment ----
  [t.rounds enumerateObjectsUsingBlock:^(NSDictionary *round, NSUInteger i, BOOL *stop) {
    NSString *reasoning = [round[@"reasoning"] isKindOfClass:NSString.class] ? round[@"reasoning"] : @"";
    if (reasoning.length) {
      UIView *box = [self thinkBoxForRound:round index:i layoutChanged:layoutChanged];
      [self->_fragStack addArrangedSubview:box];
    }

    // 本地工具调用（每轮各自成卡片，按调用顺序；同一轮多个调用依次列出）
    NSArray *calls = [round[@"tool_calls"] isKindOfClass:NSArray.class] ? round[@"tool_calls"] : @[];
    [calls enumerateObjectsUsingBlock:^(NSDictionary *call, NSUInteger j, BOOL *stop2) {
      NSString *name = [call[@"name"] isKindOfClass:NSString.class] ? call[@"name"] : @"";
      if (name.length == 0) return;
      NSString *argsStr = [call[@"arguments"] isKindOfClass:NSString.class] ? call[@"arguments"] : @"";
      NSDictionary *args = [self jsonObjectFromString:argsStr];
      DSToolCardView *card = [[DSToolCardView alloc] initWithToolName:name arguments:args];
      card.onLayoutChange = layoutChanged;

      NSString *cid = [call[@"id"] isKindOfClass:NSString.class] ? call[@"id"] : @"";
      NSDictionary *result = cid.length ? t.toolResults[cid] : nil;
      if (result) {
        BOOL ok = [result[@"toolOk"] isKindOfClass:NSNumber.class] ? [result[@"toolOk"] boolValue] : YES;
        NSString *text = [result[@"content"] isKindOfClass:NSString.class] ? result[@"content"] : @"";
        NSInteger ms = [result[@"toolMs"] isKindOfClass:NSNumber.class] ? [result[@"toolMs"] integerValue] : 0;
        [card applyStatus:ok ? DSToolStatusOK : DSToolStatusFailed text:text milliseconds:ms];
      }
      NSString *key = [NSString stringWithFormat:@"tool:%lu:%lu", (unsigned long)i, (unsigned long)j];
      self.fragIndex[key] = card;
      [self->_fragStack addArrangedSubview:card];
    }];

    // 服务端联网搜索卡片（该轮下发过 server_tool_calls，或整条里有合并结果时挂一张）
    BOOL hasServer = [round[@"server_tool_calls"] isKindOfClass:NSArray.class]
                     && [round[@"server_tool_calls"] count] > 0;
    if (hasServer) {
      DSSearchResultCardView *sc = [[DSSearchResultCardView alloc] initWithFrame:CGRectZero];
      sc.onLayoutChange = layoutChanged;
      __weak __typeof(self) ws2 = self;
      sc.onOpenURL = ^(NSURL *url) {
        if ([ws2.delegate respondsToSelector:@selector(messageCell:didTapURL:)])
          [ws2.delegate messageCell:ws2 didTapURL:url];
      };
      [sc applyServerToolCalls:t.serverCalls];
      self.fragIndex[[NSString stringWithFormat:@"search:%lu", (unsigned long)i]] = sc;
      [self->_fragStack addArrangedSubview:sc];
    }

    // 正文
    NSString *content = [round[@"content"] isKindOfClass:NSString.class] ? round[@"content"] : @"";
    if (content.length) {
      UILabel *l = [[UILabel alloc] init];
      l.numberOfLines = 0;
      l.attributedText = [DSTheme bodyText:content color:[DSTheme labelPrimary]];
      self.fragIndex[[NSString stringWithFormat:@"content:%lu", (unsigned long)i]] = l;
      [self->_fragStack addArrangedSubview:l];
    }
  }];

  // 引用来源（整条回答一份，放在正文之后）
  if (t.citations.count) {
    DSCitationListView *cites = [[DSCitationListView alloc] initWithFrame:CGRectZero];
    __weak __typeof(self) ws3 = self;
    cites.onOpenURL = ^(NSURL *url) {
      if ([ws3.delegate respondsToSelector:@selector(messageCell:didTapURL:)])
        [ws3.delegate messageCell:ws3 didTapURL:url];
    };
    [cites setCitations:t.citations];
    _fragIndex[@"cites"] = cites;
    [_fragStack addArrangedSubview:cites];
  }

  [self updateAssistantTexts:t];

  // ---- 底部：状态 / 用量 / 分支 / 操作 ----
  _statusLabel.text = t.statusNote;
  _statusLabel.hidden = t.statusNote.length == 0;

  NSString *usage = [self usageTextForTurn:t];
  _usageLabel.text = usage;
  _usageLabel.hidden = usage.length == 0;

  BOOL hasBranch = t.branchTotal > 1;
  _assistBranchBar.hidden = !hasBranch;
  if (hasBranch) {
    [_assistBranchBar setIndex:t.branchIndex total:t.branchTotal];
    __weak __typeof(self) wsb = self;
    _assistBranchBar.onPrev = ^{
      if ([wsb.delegate respondsToSelector:@selector(messageCell:didSwitchBranch:)])
        [wsb.delegate messageCell:wsb didSwitchBranch:-1];
    };
    _assistBranchBar.onNext = ^{
      if ([wsb.delegate respondsToSelector:@selector(messageCell:didSwitchBranch:)])
        [wsb.delegate messageCell:wsb didSwitchBranch:1];
    };
  }

  NSDictionary *tail = t.tailRound;
  NSString *tailContent = [tail[@"content"] isKindOfClass:NSString.class] ? tail[@"content"] : @"";
  _btnCopy.hidden = t.streaming || tailContent.length == 0;
  _btnRegen.hidden = t.streaming || t.rounds.count == 0;
  // 续写只在最后一条回答上出现（控制器按行号置 showContinue）
  _btnContinue.hidden = !self.showContinue || t.streaming || tailContent.length == 0;
  BOOL footerEmpty = _usageLabel.hidden && _btnCopy.hidden && _btnRegen.hidden && _btnContinue.hidden && !hasBranch;
  _footerStack.hidden = footerEmpty;
}

/// 结构没变时只刷文字/状态，避免流式每帧重建整条消息
- (void)updateAssistantTexts:(DSTurn *)t {
  [t.rounds enumerateObjectsUsingBlock:^(NSDictionary *round, NSUInteger i, BOOL *stop) {
    NSString *reasoning = [round[@"reasoning"] isKindOfClass:NSString.class] ? round[@"reasoning"] : @"";
    UIView *box = self.fragIndex[[NSString stringWithFormat:@"think:%lu", (unsigned long)i]];
    if (box) {
      UILabel *body = (UILabel *)[box viewWithTag:0x7A11];
      if (body) {
        body.attributedText = [DSTheme thinkText:reasoning color:[DSTheme labelTertiary]];
        body.hidden = reasoning.length == 0;
      }
      UIButton *head = (UIButton *)[box viewWithTag:0x7A12];
      if (head) {
        BOOL streaming = t.streaming && i == t.rounds.count - 1;
        [head setTitle:streaming ? DSStrThinking : DSStrThinkingDone forState:UIControlStateNormal];
      }
    }
    UILabel *content = (UILabel *)self.fragIndex[[NSString stringWithFormat:@"content:%lu", (unsigned long)i]];
    if (content) {
      NSString *text = [round[@"content"] isKindOfClass:NSString.class] ? round[@"content"] : @"";
      content.attributedText = [DSTheme bodyText:text color:[DSTheme labelPrimary]];
    }
    NSArray *calls = [round[@"tool_calls"] isKindOfClass:NSArray.class] ? round[@"tool_calls"] : @[];
    [calls enumerateObjectsUsingBlock:^(NSDictionary *call, NSUInteger j, BOOL *stop2) {
      DSToolCardView *card = (DSToolCardView *)self.fragIndex[
          [NSString stringWithFormat:@"tool:%lu:%lu", (unsigned long)i, (unsigned long)j]];
      if (!card) return;
      NSString *cid = [call[@"id"] isKindOfClass:NSString.class] ? call[@"id"] : @"";
      NSDictionary *result = cid.length ? t.toolResults[cid] : nil;
      if (result) {
        BOOL ok = [result[@"toolOk"] isKindOfClass:NSNumber.class] ? [result[@"toolOk"] boolValue] : YES;
        NSString *text = [result[@"content"] isKindOfClass:NSString.class] ? result[@"content"] : @"";
        NSInteger ms = [result[@"toolMs"] isKindOfClass:NSNumber.class] ? [result[@"toolMs"] integerValue] : 0;
        [card applyStatus:ok ? DSToolStatusOK : DSToolStatusFailed text:text milliseconds:ms];
      }
    }];
  }];

  NSString *usage = [self usageTextForTurn:t];
  _usageLabel.text = usage;
  _usageLabel.hidden = usage.length == 0;

  NSDictionary *tail = t.tailRound;
  NSString *tailContent = [tail[@"content"] isKindOfClass:NSString.class] ? tail[@"content"] : @"";
  _btnCopy.hidden = t.streaming || tailContent.length == 0;
  _statusLabel.text = t.statusNote;
  _statusLabel.hidden = t.statusNote.length == 0;
}

/// 整条回答只显示一行合并用量（与 Web 版一致）
- (NSString *)usageTextForTurn:(DSTurn *)t {
  long long p = 0, c = 0;
  BOOL any = NO;
  for (NSDictionary *r in t.rounds) {
    id pp = r[@"prompt_tokens"], cc = r[@"completion_tokens"];
    if (pp) { p += [pp longLongValue]; any = YES; }
    if (cc) { c += [cc longLongValue]; any = YES; }
  }
  if (!any) return @"";
  return [NSString stringWithFormat:@"↑%lld ↓%lld", p, c];
}

#pragma mark - 思考块

- (UIView *)thinkBoxForRound:(NSDictionary *)round
                       index:(NSUInteger)index
                layoutChanged:(void (^)(void))layoutChanged {
  UIView *box = [[UIView alloc] init];
  box.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *bar = [[UIView alloc] init];
  bar.translatesAutoresizingMaskIntoConstraints = NO;
  bar.backgroundColor = [DSTheme borderL3];
  [box addSubview:bar];

  UIButton *head = [UIButton buttonWithType:UIButtonTypeSystem];
  head.translatesAutoresizingMaskIntoConstraints = NO;
  head.tag = 0x7A12;
  head.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  head.titleLabel.font = [DSTheme thinkHeadFont];
  [head setTitleColor:[DSTheme labelSecondary] forState:UIControlStateNormal];
  BOOL streaming = (index == self.turn.rounds.count - 1) && self.turn.streaming;
  [head setTitle:streaming ? DSStrThinking : DSStrThinkingDone forState:UIControlStateNormal];

  UILabel *body = [[UILabel alloc] init];
  body.translatesAutoresizingMaskIntoConstraints = NO;
  body.tag = 0x7A11;
  body.numberOfLines = 0;
  NSString *reasoning = [round[@"reasoning"] isKindOfClass:NSString.class] ? round[@"reasoning"] : @"";
  body.attributedText = [DSTheme thinkText:reasoning color:[DSTheme labelTertiary]];

  // 流式中默认展开；结束后默认折叠（对齐 thinkingAutoFold 默认行为），用户点开过则保持
  BOOL expanded = streaming || [self.thinkExpanded containsObject:@(index)];
  body.hidden = !expanded;

  __weak __typeof(self) ws = self;
  head.accessibilityHint = [NSString stringWithFormat:@"%lu", (unsigned long)index];
  [head addTarget:self action:@selector(thinkHeadTapped:) forControlEvents:UIControlEventTouchUpInside];
  objc_setAssociatedObject(head, "ds.think.index", @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(head, "ds.think.body", body, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(head, "ds.think.layout", layoutChanged, OBJC_ASSOCIATION_COPY_NONATOMIC);
  (void)ws;

  UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:@[head, body]];
  inner.translatesAutoresizingMaskIntoConstraints = NO;
  inner.axis = UILayoutConstraintAxisVertical;
  inner.spacing = 4;
  inner.alignment = UIStackViewAlignmentFill;
  [box addSubview:inner];

  [NSLayoutConstraint activateConstraints:@[
    [bar.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
    [bar.topAnchor constraintEqualToAnchor:box.topAnchor],
    [bar.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
    [bar.widthAnchor constraintEqualToConstant:[DSTheme thinkBarWidth]],
    [inner.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:[DSTheme thinkBarGap]],
    [inner.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
    [inner.topAnchor constraintEqualToAnchor:box.topAnchor constant:2],
    [inner.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-2],
  ]];

  self.fragIndex[[NSString stringWithFormat:@"think:%lu", (unsigned long)index]] = box;
  self.fragIndex[[NSString stringWithFormat:@"think:%lu:body", (unsigned long)index]] = body;
  return box;
}

- (void)thinkHeadTapped:(UIButton *)sender {
  NSNumber *idx = objc_getAssociatedObject(sender, "ds.think.index");
  UILabel *body = objc_getAssociatedObject(sender, "ds.think.body");
  void (^layoutChanged)(void) = objc_getAssociatedObject(sender, "ds.think.layout");
  if (!idx || !body) return;
  BOOL nowHidden = !body.hidden;
  body.hidden = nowHidden;
  if (nowHidden) [self.thinkExpanded removeObject:idx];
  else [self.thinkExpanded addObject:idx];
  if (layoutChanged) layoutChanged();
}

#pragma mark - 布局变化

- (void)notifyHeightChanged {
  UITableView *tv = [self containingTableView];
  if (!tv) return;
  [UIView performWithoutAnimation:^{
    [tv beginUpdates];
    [tv endUpdates];
  }];
}

- (UITableView *)containingTableView {
  UIView *v = self.superview;
  while (v && ![v isKindOfClass:UITableView.class]) v = v.superview;
  return [v isKindOfClass:UITableView.class] ? (UITableView *)v : nil;
}

#pragma mark - 交互

- (void)onCopyTapped {
  NSString *text = nil;
  if (self.turn.role == DSTurnRoleUser) {
    text = self.turn.anchor[@"content"] ?: @"";
  } else {
    NSDictionary *tail = self.turn.tailRound;
    text = [tail[@"content"] isKindOfClass:NSString.class] ? tail[@"content"] : @"";
  }
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

- (void)continueTapped {
  if ([self.delegate respondsToSelector:@selector(messageCellDidTapContinue:)]) {
    [self.delegate messageCellDidTapContinue:self];
  }
}

- (NSDictionary *)jsonObjectFromString:(NSString *)s {
  if (s.length == 0) return @{};
  NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
  id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
  return [obj isKindOfClass:NSDictionary.class] ? obj : @{};
}

- (void)prepareForReuse {
  [super prepareForReuse];
  _turn = nil;
  _signature = nil;
  [_thinkExpanded removeAllObjects];
  [self clearFragments];
  _userBubble.hidden = YES;
  _userFoot.hidden = YES;
  _assistStack.hidden = YES;
}

@end
