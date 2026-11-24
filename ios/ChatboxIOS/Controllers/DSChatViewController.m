//
//  DSChatViewController.m
//  ChatboxIOS
//
//  输入区对齐官方 InputAreaView：毛玻璃底 + 开关 chips（深度思考 / 联网 / 模型）
//  + 「+」附件 + 圆角输入框 + 按住说话 + 圆形发送钮。
//  消息按官方 Fragment 顺序渲染（见 DSMessageCell / DSTurn）。
//

#import "DSChatViewController.h"
#import "DSBoxService.h"
#import "DSMessageCell.h"
#import "DSTurn.h"
#import "DSFragmentView.h"
#import "DSAttachmentPanel.h"
#import "DSVoiceRecorder.h"
#import "DSVoiceOverlay.h"
#import "DSTheme.h"
#import "DSStrings.h"
#import "DSIcon.h"

#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AVFoundation/AVFoundation.h>

@interface DSChatViewController () <UITableViewDataSource, UITableViewDelegate,
    UITextViewDelegate, DSBoxChatDelegate, DSMessageCellDelegate,
    PHPickerViewControllerDelegate, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate, UIDocumentPickerDelegate>

@property (nonatomic, copy) NSString *convId;

// 数据
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *rawMessages;
@property (nonatomic, strong) NSArray<DSTurn *> *turns;
@property (nonatomic, assign) BOOL streaming;

// 流式中的落点
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *streamRounds;
@property (nonatomic, assign) NSInteger streamTurnStart;   // 本次生成在 rawMessages 里的起点

// 继续生成（续写）：把某条回答的正文当前缀让模型接着写
@property (nonatomic, assign) NSInteger continueTargetIdx;  // 目标消息下标，-1 表示不在续写
@property (nonatomic, copy, nullable) NSString *continuePrefixText;
@property (nonatomic, copy, nullable) NSString *pendingContinuePrefix;  // 解锁后要接着发的前缀

// 视图
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIVisualEffectView *composer;
@property (nonatomic, strong) UIScrollView *chipsScroll;
@property (nonatomic, strong) UIButton *thinkChip;
@property (nonatomic, strong) UIButton *searchChip;
@property (nonatomic, strong) UIButton *modelChip;
@property (nonatomic, strong) DSAttachmentStrip *attachStrip;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIButton *micButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) NSLayoutConstraint *composerBottom;
@property (nonatomic, strong) NSLayoutConstraint *attachStripHeight;

// 附件 / 语音
@property (nonatomic, strong) NSMutableArray<DSAttachmentItem *> *pending;
@property (nonatomic, strong) DSVoiceRecorder *recorder;
@property (nonatomic, strong) DSVoiceOverlay *voiceOverlay;
@property (nonatomic, strong) NSTimer *voiceTimer;
@property (nonatomic, assign) BOOL voiceCanceling;
@property (nonatomic, assign) CGPoint voiceStartPoint;
@property (nonatomic, assign) NSTimeInterval lastPaint;

@end

@implementation DSChatViewController

- (instancetype)initWithConversationId:(NSString *)convId {
  if ((self = [super init])) {
    _convId = [convId copy];
    _rawMessages = [NSMutableArray array];
    _pending = [NSMutableArray array];
    _streamRounds = [NSMutableArray array];
    _continueTargetIdx = -1;
    [self reloadMessagesFromStore];
  }
  return self;
}

- (void)reloadMessagesFromStore {
  NSArray *msgs = [[DSBoxService shared] messagesOfConversation:self.convId];
  [self.rawMessages removeAllObjects];
  for (NSDictionary *m in msgs) [self.rawMessages addObject:[m mutableCopy]];
  self.turns = [DSTurn turnsFromMessages:self.rawMessages];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  NSDictionary *conv = [[DSBoxService shared] conversationWithId:self.convId];
  self.title = [conv[@"title"] length] ? conv[@"title"] : DSStrNewChatTitle;
  self.view.backgroundColor = [DSTheme bgBase];
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

  [self buildTableView];
  [self buildComposer];

  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithImage:[DSIcon image:DSIconPlus size:20]
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(newChatHere)];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:)
      name:UIKeyboardWillChangeFrameNotification object:nil];
  [self scrollToBottomAnimated:NO];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  if (!previousTraitCollection) return;
  if (previousTraitCollection.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  // 主题切换后重刷，让自绘描边/毛玻璃跟着变
  [self applyChipStyles];
  [self.tableView reloadData];
}

#pragma mark - 视图

- (void)buildTableView {
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 120;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.backgroundColor = [DSTheme bgBase];
  self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
  self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 8, 0);
  [self.tableView registerClass:DSMessageCell.class forCellReuseIdentifier:@"turn"];
  [self.view addSubview:self.tableView];
}

- (void)buildComposer {
  UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
  _composer = [[UIVisualEffectView alloc] initWithEffect:blur];
  _composer.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:_composer];

  UIView *hairline = [[UIView alloc] init];
  hairline.translatesAutoresizingMaskIntoConstraints = NO;
  hairline.backgroundColor = [DSTheme borderL2];
  [_composer.contentView addSubview:hairline];

  // ---- 上方开关条：深度思考 / 联网搜索 / 模型 ----
  _thinkChip = [self chipButtonWithTitle:DSStrDeepThink icon:DSIconBrain action:@selector(toggleThinking)];
  _searchChip = [self chipButtonWithTitle:@"联网搜索" icon:DSIconSearch action:@selector(toggleSearch)];
  _modelChip = [self chipButtonWithTitle:DSStrModelDefault icon:DSIconLightning action:@selector(modelTapped)];

  UIStackView *chips = [[UIStackView alloc] initWithArrangedSubviews:@[_thinkChip, _searchChip, _modelChip]];
  chips.translatesAutoresizingMaskIntoConstraints = NO;
  chips.axis = UILayoutConstraintAxisHorizontal;
  chips.spacing = 8;

  _chipsScroll = [[UIScrollView alloc] init];
  _chipsScroll.translatesAutoresizingMaskIntoConstraints = NO;
  _chipsScroll.showsHorizontalScrollIndicator = NO;
  [_chipsScroll addSubview:chips];
  [_composer.contentView addSubview:_chipsScroll];

  // ---- 附件条 ----
  _attachStrip = [[DSAttachmentStrip alloc] initWithFrame:CGRectZero];
  __weak __typeof(self) ws = self;
  _attachStrip.onRemove = ^(NSUInteger index) {
    if (index < ws.pending.count) {
      [ws.pending removeObjectAtIndex:index];
      [ws refreshAttachments];
    }
  };
  [_composer.contentView addSubview:_attachStrip];

  // ---- 附件按钮 ----
  _attachButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _attachButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_attachButton setImage:[DSIcon image:DSIconPlus size:22] forState:UIControlStateNormal];
  _attachButton.tintColor = [DSTheme labelSecondary];
  _attachButton.layer.cornerRadius = 16;
  [_attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];

  // ---- 输入框 ----
  UIView *field = [[UIView alloc] init];
  field.translatesAutoresizingMaskIntoConstraints = NO;
  field.backgroundColor = [DSTheme bgLayer1];
  field.layer.cornerRadius = 20;
  field.layer.cornerCurve = kCACornerCurveContinuous;
  field.layer.borderWidth = 1;
  field.layer.borderColor = [DSTheme borderL2].CGColor;
  field.tag = 0x5E1D;

  _input = [[UITextView alloc] init];
  _input.translatesAutoresizingMaskIntoConstraints = NO;
  _input.font = [UIFont systemFontOfSize:16];
  _input.textColor = [DSTheme labelPrimary];
  _input.backgroundColor = UIColor.clearColor;
  _input.scrollEnabled = YES;
  _input.textContainerInset = UIEdgeInsetsMake(9, 10, 9, 10);
  _input.textContainer.lineFragmentPadding = 0;
  _input.delegate = self;
  [field addSubview:_input];

  _placeholder = [[UILabel alloc] init];
  _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
  _placeholder.text = DSStrInputPlaceholder;
  _placeholder.font = [UIFont systemFontOfSize:16];
  _placeholder.textColor = [DSTheme labelTertiary];
  _placeholder.userInteractionEnabled = NO;
  [field addSubview:_placeholder];

  // ---- 按住说话 ----
  _micButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _micButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_micButton setImage:[DSIcon image:DSIconMic size:22] forState:UIControlStateNormal];
  _micButton.tintColor = [DSTheme labelSecondary];
  UILongPressGestureRecognizer *press =
      [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(micPressed:)];
  press.minimumPressDuration = 0.12;
  [_micButton addGestureRecognizer:press];

  // ---- 发送 / 停止 ----
  _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_sendButton setImage:[DSIcon image:DSIconSend size:18] forState:UIControlStateNormal];
  _sendButton.tintColor = UIColor.whiteColor;
  _sendButton.backgroundColor = [DSTheme brand];
  _sendButton.layer.cornerRadius = 16;
  _sendButton.layer.cornerCurve = kCACornerCurveContinuous;
  _sendButton.enabled = NO;
  _sendButton.alpha = 0.4;
  [_sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];

  _stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_stopButton setImage:[DSIcon image:DSIconStop size:16] forState:UIControlStateNormal];
  _stopButton.tintColor = UIColor.whiteColor;
  _stopButton.backgroundColor = [DSTheme labelPrimary];
  _stopButton.layer.cornerRadius = 16;
  _stopButton.layer.cornerCurve = kCACornerCurveContinuous;
  _stopButton.hidden = YES;
  [_stopButton addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];

  [_composer.contentView addSubview:_attachButton];
  [_composer.contentView addSubview:field];
  [_composer.contentView addSubview:_micButton];
  [_composer.contentView addSubview:_sendButton];
  [_composer.contentView addSubview:_stopButton];

  _composerBottom = [_composer.bottomAnchor
      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
  _attachStripHeight = [_attachStrip.heightAnchor constraintEqualToConstant:0];

  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:_composer.topAnchor],

    [_composer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_composer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    _composerBottom,

    [hairline.leadingAnchor constraintEqualToAnchor:_composer.contentView.leadingAnchor],
    [hairline.trailingAnchor constraintEqualToAnchor:_composer.contentView.trailingAnchor],
    [hairline.topAnchor constraintEqualToAnchor:_composer.contentView.topAnchor],
    [hairline.heightAnchor constraintEqualToConstant:0.5],

    [_chipsScroll.leadingAnchor constraintEqualToAnchor:_composer.contentView.leadingAnchor constant:12],
    [_chipsScroll.trailingAnchor constraintEqualToAnchor:_composer.contentView.trailingAnchor constant:-12],
    [_chipsScroll.topAnchor constraintEqualToAnchor:_composer.contentView.topAnchor constant:8],
    [_chipsScroll.heightAnchor constraintEqualToConstant:30],
    [chips.leadingAnchor constraintEqualToAnchor:_chipsScroll.contentLayoutGuide.leadingAnchor],
    [chips.trailingAnchor constraintEqualToAnchor:_chipsScroll.contentLayoutGuide.trailingAnchor],
    [chips.topAnchor constraintEqualToAnchor:_chipsScroll.contentLayoutGuide.topAnchor],
    [chips.bottomAnchor constraintEqualToAnchor:_chipsScroll.contentLayoutGuide.bottomAnchor],
    [chips.heightAnchor constraintEqualToAnchor:_chipsScroll.frameLayoutGuide.heightAnchor],

    [_attachStrip.leadingAnchor constraintEqualToAnchor:_composer.contentView.leadingAnchor constant:14],
    [_attachStrip.trailingAnchor constraintEqualToAnchor:_composer.contentView.trailingAnchor constant:-14],
    [_attachStrip.topAnchor constraintEqualToAnchor:_chipsScroll.bottomAnchor constant:6],
    _attachStripHeight,

    [_attachButton.leadingAnchor constraintEqualToAnchor:_composer.contentView.leadingAnchor constant:8],
    [_attachButton.topAnchor constraintEqualToAnchor:_attachStrip.bottomAnchor constant:6],
    [_attachButton.widthAnchor constraintEqualToConstant:32],
    [_attachButton.heightAnchor constraintEqualToConstant:32],

    [field.topAnchor constraintEqualToAnchor:_attachStrip.bottomAnchor constant:6],
    [field.leadingAnchor constraintEqualToAnchor:_attachButton.trailingAnchor constant:2],
    [field.trailingAnchor constraintEqualToAnchor:_micButton.leadingAnchor constant:-6],
    [field.bottomAnchor constraintEqualToAnchor:_composer.contentView.bottomAnchor constant:-8],
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:38],
    [field.heightAnchor constraintLessThanOrEqualToConstant:132],

    [_input.leadingAnchor constraintEqualToAnchor:field.leadingAnchor constant:4],
    [_input.trailingAnchor constraintEqualToAnchor:field.trailingAnchor constant:-4],
    [_input.topAnchor constraintEqualToAnchor:field.topAnchor constant:1],
    [_input.bottomAnchor constraintEqualToAnchor:field.bottomAnchor constant:-1],

    [_placeholder.leadingAnchor constraintEqualToAnchor:_input.leadingAnchor constant:10],
    [_placeholder.topAnchor constraintEqualToAnchor:_input.topAnchor constant:9],

    [_micButton.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-2],
    [_micButton.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
    [_micButton.widthAnchor constraintEqualToConstant:30],
    [_micButton.heightAnchor constraintEqualToConstant:30],

    [_sendButton.trailingAnchor constraintEqualToAnchor:_composer.contentView.trailingAnchor constant:-12],
    [_sendButton.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
    [_sendButton.widthAnchor constraintEqualToConstant:32],
    [_sendButton.heightAnchor constraintEqualToConstant:32],
    [_stopButton.centerXAnchor constraintEqualToAnchor:_sendButton.centerXAnchor],
    [_stopButton.centerYAnchor constraintEqualToAnchor:_sendButton.centerYAnchor],
    [_stopButton.widthAnchor constraintEqualToConstant:32],
    [_stopButton.heightAnchor constraintEqualToConstant:32],
  ]];

  [self refreshChips];
  [self updateSendState];
}

- (UIButton *)chipButtonWithTitle:(NSString *)title icon:(DSIconName)icon action:(SEL)action {
  UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
  b.translatesAutoresizingMaskIntoConstraints = NO;
  b.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
  [b setTitle:title forState:UIControlStateNormal];
  [b setImage:[DSIcon image:icon size:14] forState:UIControlStateNormal];
  b.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
  b.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
  b.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
  b.layer.cornerRadius = 15;
  b.layer.borderWidth = 1;
  b.layer.cornerCurve = kCACornerCurveContinuous;
  [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [b.heightAnchor constraintEqualToConstant:30].active = YES;
  [b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  return b;
}

- (void)applyChipStyles {
  NSDictionary *s = [[DSBoxService shared] settings];
  BOOL thinking = [s[@"thinking"] boolValue];
  BOOL search = [s[@"search"] boolValue];

  [self styleChip:_thinkChip on:thinking];
  [self styleChip:_searchChip on:search];
  [self styleChip:_modelChip on:NO];
}

- (void)styleChip:(UIButton *)chip on:(BOOL)on {
  if (on) {
    chip.backgroundColor = [[DSTheme brand] colorWithAlphaComponent:0.12];
    chip.layer.borderColor = [[DSTheme brand] colorWithAlphaComponent:0.45].CGColor;
    [chip setTitleColor:[DSTheme brand] forState:UIControlStateNormal];
    chip.tintColor = [DSTheme brand];
  } else {
    chip.backgroundColor = [DSTheme bgHover];
    chip.layer.borderColor = [DSTheme borderL2].CGColor;
    [chip setTitleColor:[DSTheme labelSecondary] forState:UIControlStateNormal];
    chip.tintColor = [DSTheme labelSecondary];
  }
}

- (void)refreshChips {
  NSDictionary *s = [[DSBoxService shared] settings];
  NSString *model = s[@"model"] ?: @"deepseek-flash";
  DSIconName icon = DSIconLightning;
  NSString *name = DSStrModelDefault;
  if ([model containsString:@"reasoner"] || [model containsString:@"expert"]) {
    icon = DSIconBrain;
    name = DSStrModelExpert;
  } else if ([model containsString:@"vision"] || [model containsString:@"image"]) {
    icon = DSIconPhoto;
    name = DSStrModelVision;
  }
  [_modelChip setTitle:name forState:UIControlStateNormal];
  [_modelChip setImage:[DSIcon image:icon size:14] forState:UIControlStateNormal];
  [self applyChipStyles];
}

#pragma mark - 键盘

- (void)keyboardWillChange:(NSNotification *)n {
  CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGRect local = [self.view convertRect:end fromView:nil];
  CGFloat overlap = MAX(0, self.view.bounds.size.height - local.origin.y);
  CGFloat inset = MAX(0, overlap - self.view.safeAreaInsets.bottom);
  self.composerBottom.constant = -inset;

  NSTimeInterval d = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
  [UIView animateWithDuration:d animations:^{
    [self.view layoutIfNeeded];
    [self scrollToBottomAnimated:NO];
  }];
}

#pragma mark - 发送 / 停止

- (void)send {
  NSString *text = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if ((text.length == 0 && self.pending.count == 0) || self.streaming) return;

  NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:
      @{@"role": @"user", @"content": text.length ? text : @" "}];
  if (self.pending.count) m[@"attachments"] = [self attachmentsPayload];

  NSDictionary *saved = [[DSBoxService shared] appendMessage:m toConversation:self.convId];
  [self.rawMessages addObject:[saved mutableCopy]];

  self.input.text = @"";
  [self.pending removeAllObjects];
  [self refreshAttachments];
  [self updateSendState];
  [self rebuildTurnsAndReload];
  [self scrollToBottomAnimated:YES];

  if (![[DSBoxService shared] isUnlocked]) {
    [self promptUnlockThenStart];
    return;
  }
  [self startStream];
}

/// 把待发附件转成消息附件（图片存库带 attId，文本把原文塞 dataUrl 供 API 内联）
- (NSArray<NSDictionary *> *)attachmentsPayload {
  NSMutableArray *out = [NSMutableArray array];
  for (DSAttachmentItem *it in self.pending) {
    NSString *attId = [[DSBoxService shared] putAttachmentData:it.data filename:it.name mime:it.mime] ?: @"";
    NSMutableDictionary *d = [@{
      @"id": attId, @"name": it.name, @"mime": it.mime, @"kind": it.kind, @"size": @(it.size),
    } mutableCopy];
    if ([it.kind isEqualToString:@"text"] && it.data) {
      NSString *body = [[NSString alloc] initWithData:it.data encoding:NSUTF8StringEncoding];
      if (body.length) d[@"dataUrl"] = [NSString stringWithFormat:@"%@\n```\n%@\n```", it.name, body];
    }
    [out addObject:d];
  }
  return out;
}

- (void)promptUnlockThenStart {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:DSStrAPIKey
      message:@"输入 PIN 以解锁本机加密保存的 Key" preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.placeholder = @"PIN";
    tf.secureTextEntry = YES;
    tf.keyboardType = UIKeyboardTypeNumberPad;
  }];
  [a addAction:[UIAlertAction actionWithTitle:DSStrCancel style:UIAlertActionStyleCancel handler:nil]];
  __weak __typeof(self) ws = self;
  [a addAction:[UIAlertAction actionWithTitle:DSStrConfirm style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *act) {
    NSError *err = nil;
    BOOL ok = [[DSBoxService shared] unlockWithPin:a.textFields.firstObject.text error:&err];
    if (ok) {
      if (ws.pendingContinuePrefix.length) {
        NSString *prefix = ws.pendingContinuePrefix;
        ws.pendingContinuePrefix = nil;
        [ws startStreamWithContinuePrefix:prefix];
      } else {
        [ws startStream];
      }
    }
    else [ws showError:err.localizedDescription];
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)startStream {
  [self startStreamWithContinuePrefix:nil];
}

/// prefix 非空表示续写：core 会把该前缀作为 assistant 前缀发给模型，只返回新增内容
- (void)startStreamWithContinuePrefix:(nullable NSString *)prefix {
  self.streaming = YES;
  [self.streamRounds removeAllObjects];
  self.streamTurnStart = (NSInteger)self.rawMessages.count;
  [self updateSendState];
  [self rebuildTurnsAndReload];
  [self scrollToBottomAnimated:YES];

  NSError *err = nil;
  BOOL ok = prefix.length
      ? [[DSBoxService shared] streamChatWithConversation:self.convId
                                          continuePrefix:prefix
                                                delegate:self
                                                   error:&err]
      : [[DSBoxService shared] streamChatWithConversation:self.convId delegate:self error:&err];
  if (!ok) [self finishWithError:err];
}

- (void)stop {
  [[DSBoxService shared] stopStream];
}

- (void)updateSendState {
  BOOL hasText = self.input.text.length > 0 || self.pending.count > 0;
  self.placeholder.hidden = self.input.text.length > 0;
  self.sendButton.hidden = self.streaming;
  self.stopButton.hidden = !self.streaming;
  self.sendButton.enabled = hasText && !self.streaming;
  self.sendButton.alpha = self.sendButton.enabled ? 1.0 : 0.4;
  self.micButton.hidden = self.streaming || hasText;
}

- (void)finishWithError:(NSError *)error {
  self.streaming = NO;
  for (NSMutableDictionary *r in self.streamRounds) r[@"streaming"] = @NO;
  NSMutableArray *rounds = self.streamRounds;
  self.streamRounds = [NSMutableArray array];
  self.continueTargetIdx = -1;
  self.continuePrefixText = nil;
  self.pendingContinuePrefix = nil;

  // 统一落盘：本次回答写进分支候选，再用内存中的完整消息覆盖，避免半截历史
  [self dropEmptyTrailingRound];
  [self commitLastSegment];
  [self persistAll];
  [self updateSendState];
  [self rebuildTurnsAndReload];

  if (error) {
    [self showError:error.localizedDescription];
    return;
  }
  // 本轮没有任何输出：给一条提示，避免用户看到空气泡
  if (rounds.count == 0) {
    DSTurn *last = self.turns.lastObject;
    if (last && last.role == DSTurnRoleAssistant) {
      last.statusNote = DSStrStopped;
      [self.tableView reloadData];
    }
  }
}

- (void)persistAll {
  // 去掉只用于渲染的临时字段
  NSMutableArray *clean = [NSMutableArray array];
  for (NSDictionary *m in self.rawMessages) {
    NSMutableDictionary *c = [m mutableCopy];
    [c removeObjectForKey:@"streaming"];
    [clean addObject:c];
  }
  [[DSBoxService shared] replaceMessages:clean inConversation:self.convId];
}

/// 出错或中断时，末尾可能留下一条彻底空的 assistant 占位，落盘前丢掉
- (void)dropEmptyTrailingRound {
  while (self.rawMessages.count) {
    NSDictionary *m = self.rawMessages.lastObject;
    if (![m[@"role"] isEqualToString:@"assistant"]) break;
    NSString *c = [m[@"content"] isKindOfClass:NSString.class] ? m[@"content"] : @"";
    NSString *r = [m[@"reasoning"] isKindOfClass:NSString.class] ? m[@"reasoning"] : @"";
    NSArray *tc = [m[@"tool_calls"] isKindOfClass:NSArray.class] ? m[@"tool_calls"] : @[];
    NSArray *st = [m[@"server_tool_calls"] isKindOfClass:NSArray.class] ? m[@"server_tool_calls"] : @[];
    if (c.length || r.length || tc.count || st.count) break;
    [self.rawMessages removeLastObject];
  }
}

#pragma mark - 输入区交互

- (void)toggleThinking {
  NSDictionary *s = [[DSBoxService shared] settings];
  BOOL v = ![s[@"thinking"] boolValue];
  [[DSBoxService shared] saveSettingsPatch:@{@"thinking": @(v)}];
  [self refreshChips];
}

- (void)toggleSearch {
  NSDictionary *s = [[DSBoxService shared] settings];
  BOOL v = ![s[@"search"] boolValue];
  [[DSBoxService shared] saveSettingsPatch:@{@"search": @(v), @"readUrl": @(v)}];
  [self refreshChips];
}

- (void)modelTapped {
  NSDictionary *s = [[DSBoxService shared] settings];
  NSString *cur = s[@"model"] ?: @"deepseek-flash";
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:DSStrModelSwitch
      message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  NSArray<NSArray<NSString *> *> *models = @[
    @[DSStrModelDefault, @"deepseek-flash", DSStrModelDefaultDesc],
    @[DSStrModelExpert, @"deepseek-reasoner", DSStrModelExpertDesc],
    @[DSStrModelVision, @"deepseek-vision", DSStrModelVisionDesc],
  ];
  __weak __typeof(self) ws = self;
  for (NSArray<NSString *> *m in models) {
    NSString *title = [cur isEqualToString:m[1]] ? [NSString stringWithFormat:@"✓ %@", m[0]] : m[0];
    [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
      [[DSBoxService shared] saveSettingsPatch:@{@"model": m[1]}];
      [ws refreshChips];
    }]];
  }
  [sheet addAction:[UIAlertAction actionWithTitle:DSStrCancel style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.sourceView = self.modelChip;
  sheet.popoverPresentationController.sourceRect = self.modelChip.bounds;
  [self presentViewController:sheet animated:YES completion:nil];
}

- (void)attachTapped {
  __weak __typeof(self) ws = self;
  DSAttachmentPanel *panel = [DSAttachmentPanel panelWithHandler:^(DSAttachSource source) {
    switch (source) {
      case DSAttachSourceAlbum: [ws pickFromAlbum]; break;
      case DSAttachSourceCamera: [ws pickFromCamera]; break;
      case DSAttachSourceFile: [ws pickFile]; break;
    }
  }];
  [self presentViewController:panel animated:YES completion:nil];
}

- (void)pickFromAlbum {
  PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
  cfg.filter = PHPickerFilter.imagesFilter;
  cfg.selectionLimit = 4;
  PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
  p.delegate = self;
  [self presentViewController:p animated:YES completion:nil];
}

- (void)pickFromCamera {
  if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
    [self showError:@"当前设备没有可用的相机"];
    return;
  }
  UIImagePickerController *p = [[UIImagePickerController alloc] init];
  p.sourceType = UIImagePickerControllerSourceTypeCamera;
  p.delegate = self;
  [self presentViewController:p animated:YES completion:nil];
}

- (void)pickFile {
  UIDocumentPickerViewController *p =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem]
                                                                  asCopy:YES];
  p.delegate = self;
  p.allowsMultipleSelection = YES;
  [self presentViewController:p animated:YES completion:nil];
}

- (void)refreshAttachments {
  [self.attachStrip setItems:self.pending];
  self.attachStripHeight.constant = self.pending.count ? 44 : 0;
  [self updateSendState];
  [UIView animateWithDuration:0.18 animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)addAttachmentData:(NSData *)data name:(NSString *)name mime:(NSString *)mime {
  if (!data.length) return;
  // 单个附件限 8MB，避免写库过大
  if (data.length > 8 * 1024 * 1024) {
    [self showError:[NSString stringWithFormat:@"%@ 超过 8MB，未添加", name]];
    return;
  }
  [self.pending addObject:[DSAttachmentItem itemWithData:data name:name mime:mime]];
  [self refreshAttachments];
}

#pragma mark - PHPicker / Camera / Document

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  [picker dismissViewControllerAnimated:YES completion:nil];
  for (PHPickerResult *r in results) {
    NSItemProvider *provider = r.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier]) continue;
    __weak __typeof(self) ws = self;
    [provider loadDataRepresentationForTypeIdentifier:UTTypeImage.identifier
                                    completionHandler:^(NSData *data, NSError *error) {
      if (!data) return;
      UIImage *img = [UIImage imageWithData:data];
      NSData *jpeg = img ? UIImageJPEGRepresentation(img, 0.82) : data;
      dispatch_async(dispatch_get_main_queue(), ^{
        [ws addAttachmentData:jpeg ?: data name:@"图片.jpg" mime:@"image/jpeg"];
      });
    }];
  }
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info {
  [picker dismissViewControllerAnimated:YES completion:nil];
  UIImage *img = info[UIImagePickerControllerOriginalImage];
  NSData *jpeg = img ? UIImageJPEGRepresentation(img, 0.82) : nil;
  [self addAttachmentData:jpeg name:@"照片.jpg" mime:@"image/jpeg"];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  for (NSURL *url in urls) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) continue;
    NSString *mime = @"application/octet-stream";
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"txt"] || [ext isEqualToString:@"md"]) mime = @"text/plain";
    else if ([ext isEqualToString:@"json"]) mime = @"application/json";
    else if ([ext isEqualToString:@"csv"]) mime = @"text/csv";
    else if ([ext isEqualToString:@"pdf"]) mime = @"application/pdf";
    else if ([ext isEqualToString:@"png"]) mime = @"image/png";
    else if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) mime = @"image/jpeg";
    [self addAttachmentData:data name:url.lastPathComponent mime:mime];
  }
}

#pragma mark - 按住说话

- (void)micPressed:(UILongPressGestureRecognizer *)g {
  if (self.streaming) return;
  CGPoint p = [g locationInView:self.view];
  switch (g.state) {
    case UIGestureRecognizerStateBegan: {
      self.recorder = [[DSVoiceRecorder alloc] init];
      NSError *err = nil;
      if (![self.recorder startWithError:&err]) {
        [self showError:err.localizedDescription ?: @"无法录音"];
        self.recorder = nil;
        return;
      }
      self.voiceCanceling = NO;
      self.voiceStartPoint = p;
      if (!self.voiceOverlay) self.voiceOverlay = [[DSVoiceOverlay alloc] initWithFrame:CGRectZero];
      [self.voiceOverlay showInView:self.view];
      __weak __typeof(self) ws = self;
      self.voiceTimer = [NSTimer scheduledTimerWithTimeInterval:0.06 repeats:YES block:^(NSTimer *t) {
        DSVoiceRecorder *rec = ws.recorder;
        if (!rec || !rec.isRecording) return;
        [ws.voiceOverlay updateLevel:rec.level duration:rec.duration canceling:ws.voiceCanceling];
      }];
      break;
    }
    case UIGestureRecognizerStateChanged: {
      // 上滑超过 60pt 判定为取消
      BOOL cancel = (self.voiceStartPoint.y - p.y) > 60;
      if (cancel != self.voiceCanceling) self.voiceCanceling = cancel;
      break;
    }
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed: {
      [self.voiceTimer invalidate];
      self.voiceTimer = nil;
      BOOL cancel = self.voiceCanceling || g.state != UIGestureRecognizerStateEnded;
      NSString *path = cancel ? nil : [self.recorder finish];
      if (cancel) [self.recorder cancel];
      self.recorder = nil;
      if (path.length) {
        [self.voiceOverlay showRecognizing];
        [self transcribeVoiceAtPath:path];
      } else {
        [self.voiceOverlay dismiss];
      }
      break;
    }
    default: break;
  }
}

- (void)transcribeVoiceAtPath:(NSString *)path {
  __weak __typeof(self) ws = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *err = nil;
    NSString *text = [[DSBoxService shared] transcribeFile:path filename:@"voice.wav" error:&err];
    dispatch_async(dispatch_get_main_queue(), ^{
      [ws.voiceOverlay dismiss];
      ws.voiceOverlay = nil;
      if (text.length) {
        NSString *cur = ws.input.text ?: @"";
        ws.input.text = cur.length ? [cur stringByAppendingString:text] : text;
        [ws textViewDidChange:ws.input];
      } else if (err) {
        [ws showError:err.localizedDescription ?: @"语音识别失败"];
      }
    });
  });
}

#pragma mark - 新对话

- (void)newChatHere {
  NSDictionary *conv = [[DSBoxService shared] createConversation];
  DSChatViewController *vc = [[DSChatViewController alloc] initWithConversationId:conv[@"id"]];
  [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
  [self updateSendState];
}

#pragma mark - DSBoxChatDelegate（已切主线程）

- (void)dsboxDidReceiveEvent:(DSBoxStreamEventType)type
                        text:(NSString *)text
                        data:(NSDictionary *)data {
  NSMutableDictionary *cur = self.streamRounds.lastObject;

  switch (type) {
    case DSBoxStreamEventRound: {
      // 续写第一轮：不新建气泡，直接复用被续写的那条消息（新内容追加到原正文后面）
      if (self.continueTargetIdx >= 0 &&
          (NSInteger)self.rawMessages.count == self.continueTargetIdx + 1) {
        NSMutableDictionary *m = self.rawMessages[(NSUInteger)self.continueTargetIdx];
        m[@"streaming"] = @YES;
        [self.streamRounds addObject:m];
        [self rebuildTurnsAndReload];
        [self scrollToBottomAnimated:YES];
        break;
      }
      // 新一轮：新建一条 assistant 占位（官方 Fragment 序列里每轮各自成段）
      NSMutableDictionary *m = [@{
        @"id": [[NSUUID UUID] UUIDString], @"role": @"assistant", @"content": @"",
        @"reasoning": @"", @"streaming": @YES,
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
      } mutableCopy];
      [self.rawMessages addObject:m];
      [self.streamRounds addObject:m];
      [self rebuildTurnsAndReload];
      [self scrollToBottomAnimated:YES];
      break;
    }
    case DSBoxStreamEventContent:
      [self appendText:text to:cur key:@"content"];
      break;
    case DSBoxStreamEventReasoning:
      [self appendText:text to:cur key:@"reasoning"];
      break;
    case DSBoxStreamEventUsage:
      if (cur) {
        if (data[@"prompt_tokens"]) cur[@"prompt_tokens"] = data[@"prompt_tokens"];
        if (data[@"completion_tokens"]) cur[@"completion_tokens"] = data[@"completion_tokens"];
        [self refreshStreamRow];
      }
      break;
    case DSBoxStreamEventServerTool: {
      if (!cur) break;
      if (data[@"calls"]) {
        cur[@"server_tool_calls"] = data[@"calls"];
        [self refreshStreamRow];
      } else if (data[@"event"]) {
        // call_started / call_completed：合并进该轮的 server_tool_calls
        NSDictionary *ev = data[@"event"];
        NSString *kind = ev[@"type"] ?: @"";
        NSDictionary *call = [ev[@"call"] isKindOfClass:NSDictionary.class] ? ev[@"call"] : nil;
        if (call && ([kind isEqualToString:@"call_started"] || [kind isEqualToString:@"call_completed"])) {
          NSMutableArray *arr = [cur[@"server_tool_calls"] isKindOfClass:NSArray.class]
              ? [cur[@"server_tool_calls"] mutableCopy] : [NSMutableArray array];
          NSInteger exist = -1;
          for (NSInteger i = 0; i < (NSInteger)arr.count; i++) {
            if ([arr[(NSUInteger)i][@"id"] isEqual:call[@"id"]]) { exist = i; break; }
          }
          if (exist >= 0) arr[(NSUInteger)exist] = call;
          else [arr addObject:call];
          cur[@"server_tool_calls"] = arr;
          [self refreshStreamRow];
        }
      }
      break;
    }
    case DSBoxStreamEventAnnotations:
      if (cur && [data[@"annotations"] isKindOfClass:NSArray.class]) {
        cur[@"annotations"] = data[@"annotations"];
        [self rebuildTurnsAndReload];
      }
      break;
    case DSBoxStreamEventRoundEnd: {
      // 服务端定稿：内容/工具调用/用量以它为准，替换本地占位
      NSDictionary *final = data;
      if (![final isKindOfClass:NSDictionary.class]) break;
      NSMutableDictionary *merged = [final mutableCopy];
      merged[@"streaming"] = @NO;
      // 续写：服务端只回新增内容，正文要拼回原前缀，id 也保持原值（分支快照按 id 引用）
      if (cur && self.continueTargetIdx >= 0 &&
          [self.rawMessages indexOfObjectIdenticalTo:cur] == (NSUInteger)self.continueTargetIdx) {
        NSString *add = [merged[@"content"] isKindOfClass:NSString.class] ? merged[@"content"] : @"";
        merged[@"content"] = [(self.continuePrefixText ?: @"") stringByAppendingString:add];
        if (cur[@"id"]) merged[@"id"] = cur[@"id"];
      }
      if (cur) {
        NSUInteger idx = [self.rawMessages indexOfObjectIdenticalTo:cur];
        if (idx != NSNotFound) self.rawMessages[idx] = merged;
        NSUInteger ridx = [self.streamRounds indexOfObjectIdenticalTo:cur];
        if (ridx != NSNotFound) self.streamRounds[ridx] = merged;
      } else {
        [self.rawMessages addObject:merged];
        [self.streamRounds addObject:merged];
      }
      [self rebuildTurnsAndReload];
      [self scrollToBottomAnimated:YES];
      break;
    }
    case DSBoxStreamEventToolStart: {
      // 卡片已随 tool_calls 出现（running 态），这里只需滚到底
      [self scrollToBottomAnimated:YES];
      break;
    }
    case DSBoxStreamEventToolEnd: {
      NSMutableDictionary *tool = [@{
        @"id": data[@"messageId"] ?: [[NSUUID UUID] UUIDString],
        @"role": @"tool",
        @"tool_call_id": data[@"id"] ?: @"",
        @"name": data[@"name"] ?: @"",
        @"content": data[@"text"] ?: @"",
        @"toolOk": data[@"ok"] ?: @YES,
        @"toolMs": data[@"ms"] ?: @0,
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
      } mutableCopy];
      [self.rawMessages addObject:tool];
      [self rebuildTurnsAndReload];
      [self scrollToBottomAnimated:NO];
      break;
    }
    case DSBoxStreamEventTitle:
      if (text.length) self.title = text;
      break;
    case DSBoxStreamEventRefusal:
      if (cur && text.length) cur[@"refusal"] = text;
      break;
    case DSBoxStreamEventError:
      if (text.length) [self showError:text];
      break;
    default:
      break;
  }
}

- (void)appendText:(NSString *)text to:(NSMutableDictionary *)m key:(NSString *)key {
  if (text.length == 0 || !m) return;
  NSString *old = [m[key] isKindOfClass:NSString.class] ? m[key] : @"";
  m[key] = [old stringByAppendingString:text];
  [self refreshStreamRow];
}

/// 流式高频路径：只重载最后一行，避免整表重建（对齐 Web 版 70ms 节流）
- (void)refreshStreamRow {
  NSTimeInterval now = [NSDate date].timeIntervalSince1970;
  if (now - _lastPaint < 0.07) return;
  _lastPaint = now;
  self.turns = [DSTurn turnsFromMessages:self.rawMessages];
  NSInteger rows = (NSInteger)self.turns.count;
  if (rows == 0) return;
  NSIndexPath *ip = [NSIndexPath indexPathForRow:rows - 1 inSection:0];
  [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
  [self scrollToBottomAnimated:NO];
}

- (void)rebuildTurnsAndReload {
  self.turns = [DSTurn turnsFromMessages:self.rawMessages];
  [self.tableView reloadData];
}

- (void)dsboxDidFinishWithError:(NSError *)error {
  [self finishWithError:error];
}

#pragma mark - 分支 / 再试一次

- (void)messageCellDidTapRegenerate:(DSMessageCell *)cell {
  DSTurn *turn = cell.turn;
  if (!turn || turn.role != DSTurnRoleAssistant || self.streaming) return;

  NSInteger userIdx = [self userIndexForTurn:turn];
  if (userIdx < 0) return;

  // 旧回答存为一条候选，新回答占下一个候选位（官方分支切换器据此显示「第 n 条 / 共 m 条」）
  [self commitSegmentForUserIndex:userIdx];
  NSMutableDictionary *user = self.rawMessages[(NSUInteger)userIdx];
  NSMutableArray *branches = [user[@"branches"] isKindOfClass:NSArray.class]
      ? [user[@"branches"] mutableCopy] : [NSMutableArray array];
  if (branches.count == 0) [branches addObject:@{}];
  [branches addObject:@{}];
  user[@"branches"] = branches;
  user[@"branchIndex"] = @(branches.count - 1);

  // 截断到该提问之后，重新生成（与 Web 版「从这一点重答」一致）
  while ((NSInteger)self.rawMessages.count > userIdx + 1) [self.rawMessages removeLastObject];
  [self persistAll];
  [self rebuildTurnsAndReload];
  [self startStream];
}

/// 「继续生成」：以该条回答的正文为前缀续写，新内容拼回同一条消息（对齐 Web 版 continueGeneration）
- (void)messageCellDidTapContinue:(DSMessageCell *)cell {
  DSTurn *turn = cell.turn;
  if (!turn || turn.role != DSTurnRoleAssistant || self.streaming) return;

  NSDictionary *tail = turn.tailRound;
  if (!tail) return;
  NSString *content = [tail[@"content"] isKindOfClass:NSString.class] ? tail[@"content"] : @"";
  if (content.length == 0) return;

  // rawMessages 泛型是 NSMutableDictionary，turn 里拿到的是 NSDictionary，用 id 抹平类型
  NSUInteger idx = [self.rawMessages indexOfObjectIdenticalTo:(id)tail];
  if (idx == NSNotFound) return;
  // 只允许续写最后一条回答：中间轮次续写会和后面的消息打架
  if ((NSInteger)idx + 1 != (NSInteger)self.rawMessages.count) {
    [self toast:@"只能对最后一条回答继续生成"];
    return;
  }

  self.continueTargetIdx = (NSInteger)idx;
  self.continuePrefixText = content;

  if (![[DSBoxService shared] isUnlocked]) {
    self.pendingContinuePrefix = content;
    [self promptUnlockThenStart];
    return;
  }
  [self startStreamWithContinuePrefix:content];
}

- (void)messageCell:(DSMessageCell *)cell didSwitchBranch:(NSInteger)delta {
  if (self.streaming) return;
  NSInteger userIdx = [self userIndexForTurn:cell.turn];
  if (userIdx < 0) return;

  NSMutableDictionary *user = self.rawMessages[(NSUInteger)userIdx];
  NSMutableArray *branches = [user[@"branches"] isKindOfClass:NSArray.class]
      ? [user[@"branches"] mutableCopy] : [NSMutableArray array];
  if (branches.count < 2) return;

  NSInteger cur = [user[@"branchIndex"] isKindOfClass:NSNumber.class] ? [user[@"branchIndex"] integerValue] : 0;
  [self commitSegmentForUserIndex:userIdx];

  NSInteger next = cur + delta;
  if (next < 0 || next >= (NSInteger)branches.count) return;

  // 用目标候选替换「该提问之后」的消息段
  while ((NSInteger)self.rawMessages.count > userIdx + 1) [self.rawMessages removeLastObject];
  NSDictionary *target = branches[(NSUInteger)next];
  NSArray *msgs = [target[@"messages"] isKindOfClass:NSArray.class] ? target[@"messages"] : @[];
  for (NSDictionary *m in msgs) [self.rawMessages addObject:[m mutableCopy]];
  user[@"branchIndex"] = @(next);
  user[@"branches"] = branches;

  [self persistAll];
  [self rebuildTurnsAndReload];
  [self scrollToBottomAnimated:NO];
}

/// 定位 turn 所属的 user 消息（助手 turn 取 anchor 之前最近的一条 user）
- (NSInteger)userIndexForTurn:(DSTurn *)turn {
  NSString *anchorId = [turn.anchor[@"id"] isKindOfClass:NSString.class] ? turn.anchor[@"id"] : nil;
  NSInteger anchorIdx = -1;
  if (anchorId.length) {
    for (NSInteger i = 0; i < (NSInteger)self.rawMessages.count; i++) {
      if ([self.rawMessages[(NSUInteger)i][@"id"] isEqual:anchorId]) { anchorIdx = i; break; }
    }
  }
  if (anchorIdx < 0) anchorIdx = (NSInteger)self.rawMessages.count - 1;
  for (NSInteger i = anchorIdx; i >= 0; i--) {
    if ([self.rawMessages[(NSUInteger)i][@"role"] isEqualToString:@"user"]) return i;
  }
  return -1;
}

/// 把「该提问之后生成的消息段」写入对应的候选槽
- (void)commitSegmentForUserIndex:(NSInteger)userIdx {
  if (userIdx < 0 || userIdx >= (NSInteger)self.rawMessages.count) return;
  NSMutableDictionary *user = self.rawMessages[(NSUInteger)userIdx];
  NSMutableArray *seg = [NSMutableArray array];
  for (NSInteger i = userIdx + 1; i < (NSInteger)self.rawMessages.count; i++) {
    NSMutableDictionary *m = [self.rawMessages[(NSUInteger)i] mutableCopy];
    [m removeObjectForKey:@"streaming"];
    [seg addObject:m];
  }
  if (seg.count == 0) return;

  NSMutableArray *branches = [user[@"branches"] isKindOfClass:NSArray.class]
      ? [user[@"branches"] mutableCopy] : [NSMutableArray array];
  NSInteger cur = [user[@"branchIndex"] isKindOfClass:NSNumber.class] ? [user[@"branchIndex"] integerValue] : 0;
  NSDictionary *snap = @{@"messages": seg};
  if (cur >= 0 && cur < (NSInteger)branches.count) branches[(NSUInteger)cur] = snap;
  else {
    while ((NSInteger)branches.count < cur) [branches addObject:@{}];
    [branches addObject:snap];
  }
  user[@"branches"] = branches;
  if (![user[@"branchIndex"] isKindOfClass:NSNumber.class]) user[@"branchIndex"] = @0;
}

/// 生成结束时把本次回答写进候选槽，让切换器能回看
- (void)commitLastSegment {
  for (NSInteger i = (NSInteger)self.rawMessages.count - 1; i >= 0; i--) {
    if ([self.rawMessages[(NSUInteger)i][@"role"] isEqualToString:@"user"]) {
      [self commitSegmentForUserIndex:i];
      return;
    }
  }
}

#pragma mark - DSMessageCellDelegate

- (void)messageCellDidCopy:(DSMessageCell *)cell {
  [self toast:DSStrCopied];
}

- (void)messageCell:(DSMessageCell *)cell didTapURL:(NSURL *)url {
  if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.turns.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  DSMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"turn" forIndexPath:indexPath];
  cell.delegate = self;
  // 「继续生成」只出现在最后一条回答上
  cell.showContinue = (indexPath.row == (NSInteger)self.turns.count - 1);
  [cell configureWithTurn:self.turns[(NSUInteger)indexPath.row]];
  return cell;
}

- (void)scrollToBottomAnimated:(BOOL)animated {
  if (self.turns.count == 0) return;
  NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)self.turns.count - 1 inSection:0];
  [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - 提示

- (void)toast:(NSString *)text {
  UIWindow *win = self.view.window;
  if (!win) return;
  UILabel *toast = [[UILabel alloc] init];
  toast.text = text;
  toast.font = [UIFont systemFontOfSize:13];
  toast.textColor = UIColor.whiteColor;
  toast.backgroundColor = [[DSTheme labelPrimary] colorWithAlphaComponent:0.9];
  toast.textAlignment = NSTextAlignmentCenter;
  toast.layer.cornerRadius = 8;
  toast.layer.masksToBounds = YES;
  [toast sizeToFit];
  CGRect f = toast.frame;
  toast.frame = CGRectMake(0, 0, f.size.width + 28, 34);
  toast.center = CGPointMake(win.center.x, win.bounds.size.height - 140);
  [win addSubview:toast];
  [UIView animateWithDuration:0.25 delay:1.1 options:0 animations:^{
    toast.alpha = 0;
  } completion:^(BOOL done) {
    [toast removeFromSuperview];
  }];
}

- (void)showError:(NSString *)msg {
  if (msg.length == 0) return;
  UIAlertController *a = [UIAlertController alertControllerWithTitle:msg
      message:nil preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:DSStrOK style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:a animated:YES completion:nil];
}

@end
