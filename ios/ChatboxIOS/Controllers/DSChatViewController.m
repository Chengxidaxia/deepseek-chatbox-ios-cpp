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
#import "DSConversationListController.h"
#import "DSMessageCell.h"
#import "DSTurn.h"
#import "DSFragmentView.h"
#import "DSAttachmentPanel.h"
#import "DSVoiceRecorder.h"
#import "DSVoiceOverlay.h"
#import "DSTheme.h"
#import "DSStrings.h"
#import "DSIcon.h"
#import "DSTopBarView.h"
#import "DSButton.h"

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
@property (nonatomic, strong) DSButton *thinkChip;
@property (nonatomic, strong) DSButton *searchChip;
/// 官方顶栏（自绘，不是 UINavigationBar）：☰ / 模型名⌄ / ＋
@property (nonatomic, strong) DSTopBarView *topBar;
// 模型 id → 展示名（来自 /models，取不到就用 id 本身）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *modelNames;
@property (nonatomic, strong) NSArray<NSDictionary *> *modelList;
@property (nonatomic, strong) DSAttachmentStrip *attachStrip;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIButton *micButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) NSLayoutConstraint *composerBottom;
@property (nonatomic, strong) NSLayoutConstraint *attachStripHeight;
@property (nonatomic, strong) NSLayoutConstraint *inputHeight;
/// 空态欢迎页（没有消息时盖在表格上）
@property (nonatomic, strong) UIView *welcomeView;

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

  [self buildTopBar];      // 顶栏先建，下面的表格要贴它的底边
  [self buildTableView];
  [self buildWelcome];
  [self buildComposer];
  [self loadModelList];    // 异步取模型名，只影响顶栏的显示，不阻塞进入会话
  [self refreshEmptyState];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:)
      name:UIKeyboardWillChangeFrameNotification object:nil];
  [self scrollToBottomAnimated:NO];
}

/// 官方顶栏是自绘的（`chat/top_bar/*`），不走 UINavigationBar：
/// 左 ☰ 开会话抽屉、中间模型选择、右 ＋ 新对话。
- (void)buildTopBar {
  DSTopBarView *bar = [[DSTopBarView alloc] initWithFrame:CGRectZero];
  [self.view addSubview:bar];
  _topBar = bar;

  __weak __typeof(self) ws = self;
  bar.onMenu = ^{
    if (ws.onMenuTap) ws.onMenuTap();
  };
  bar.onModel = ^{ [ws modelTapped]; };
  bar.onNewChat = ^{ [ws newChatHere]; };

  [NSLayoutConstraint activateConstraints:@[
    [bar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [bar.heightAnchor constraintEqualToConstant:DSTopBarView.preferredHeight],
  ]];
  [self refreshChips];   // 先把当前模型名填上，等 /models 回来再刷新成展示名
}

/// ☰：回到会话列表。直接 push 进来的会话可能不是从列表来的，那就把列表 push 上去。
- (void)openSessionList {
  if (self.onMenuTap) { self.onMenuTap(); return; }
  UINavigationController *nav = self.navigationController;
  if (!nav) return;
  for (UIViewController *vc in nav.viewControllers.reverseObjectEnumerator) {
    if ([vc isKindOfClass:DSConversationListController.class]) {
      [nav popToViewController:vc animated:YES];
      return;
    }
  }
  [nav pushViewController:[[DSConversationListController alloc] init] animated:YES];
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

/// 空态：没有消息时盖住消息区（官方新对话页的形态）
- (void)buildWelcome {
  UIView *v = [[UIView alloc] init];
  v.translatesAutoresizingMaskIntoConstraints = NO;
  v.backgroundColor = [DSTheme bgBase];
  v.hidden = YES;
  [self.view addSubview:v];
  _welcomeView = v;

  // 文案全部取自官方 2.7.1：welcomeMessageTitleUnified=今天有什么可以帮到你？
  // welcomeMessageDescription=我可以帮你搜索、答疑、写作…（见 DSStrings.h）
  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = DSStrWelcomeTitle;
  title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
  title.textColor = [DSTheme labelPrimary];
  title.textAlignment = NSTextAlignmentCenter;
  title.numberOfLines = 0;

  UILabel *tip = [[UILabel alloc] init];
  tip.translatesAutoresizingMaskIntoConstraints = NO;
  tip.text = DSStrWelcomeDesc;
  tip.font = [UIFont systemFontOfSize:15];
  tip.textColor = [DSTheme labelSecondary];
  tip.textAlignment = NSTextAlignmentCenter;
  tip.numberOfLines = 0;

  [v addSubview:title];
  [v addSubview:tip];

  [NSLayoutConstraint activateConstraints:@[
    [v.leadingAnchor constraintEqualToAnchor:self.tableView.leadingAnchor],
    [v.trailingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor],
    [v.topAnchor constraintEqualToAnchor:self.tableView.topAnchor],
    [v.bottomAnchor constraintEqualToAnchor:self.tableView.bottomAnchor],
    [title.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
    [title.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-24],
    [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:v.leadingAnchor constant:24],
    [tip.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
    [tip.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:32],
    [tip.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-32],
  ]];
}

- (void)refreshEmptyState {
  self.welcomeView.hidden = self.turns.count > 0;
}

- (void)buildComposer {
  // 官方输入区**没有毛玻璃、也没有分割线**：就是页面底色，输入框本身是一块浅灰圆角。
  // 之前用 UIBlurEffectStyleSystemChromeMaterial + hairline，是最明显的「不像」来源。
  _composer = [[UIVisualEffectView alloc] initWithEffect:nil];
  _composer.translatesAutoresizingMaskIntoConstraints = NO;
  _composer.backgroundColor = [DSTheme bgBase];
  [self.view addSubview:_composer];

  UIView *hairline = [[UIView alloc] init];
  hairline.translatesAutoresizingMaskIntoConstraints = NO;
  hairline.backgroundColor = UIColor.clearColor;
  hairline.hidden = YES;   // 保留视图，约束块里还要用
  [_composer.contentView addSubview:hairline];

  // ---- 开关 chips：深度思考 / 智能搜索 ----
  // 文案取自官方 2.7.1：messageR1Button=深度思考、messageSearchButton=智能搜索；
  // 官方底部工具条的资源名是 chat/bottom_bar/{deep_think,searching,add,voice,send,stop}，
  // 模型选择不在底部，而在顶栏（chat/top_bar/modelChoose），所以这里不再放模型 chip。
  // 图标用官方的：深度思考 = toggle_think.json 的双菱形环，智能搜索 = toggle_search.json 的地球
  _thinkChip = [self chipButtonWithTitle:DSStrDeepThink icon:DSIconThink action:@selector(toggleThinking)];
  _searchChip = [self chipButtonWithTitle:DSStrSmartSearch icon:DSIconGlobe action:@selector(toggleSearch)];

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

  // ---- 输入容器 ----
  // 官方 InputAreaView 是「一个圆角框里上下两行」：正文在上，工具行在下（左 chips、右按钮），
  // 不是「chips 在外面、输入框是个细条」。这里照这个结构重排。
  UIView *box = [[UIView alloc] init];
  box.translatesAutoresizingMaskIntoConstraints = NO;
  box.backgroundColor = [DSTheme bgHover];   // 官方是浅灰填充，没有描边
  box.layer.cornerRadius = 22;
  box.layer.cornerCurve = kCACornerCurveContinuous;

  _input = [[UITextView alloc] init];
  _input.translatesAutoresizingMaskIntoConstraints = NO;
  _input.font = [UIFont systemFontOfSize:16];
  _input.textColor = [DSTheme labelPrimary];
  _input.backgroundColor = UIColor.clearColor;
  _input.scrollEnabled = NO;                 // 高度由 sizeThatFits 撑，超过上限再开滚动
  _input.textContainerInset = UIEdgeInsetsMake(6, 4, 6, 4);
  _input.textContainer.lineFragmentPadding = 0;
  _input.delegate = self;
  [box addSubview:_input];

  _placeholder = [[UILabel alloc] init];
  _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
  _placeholder.text = DSStrInputPlaceholder;
  _placeholder.font = [UIFont systemFontOfSize:16];
  _placeholder.textColor = [DSTheme labelTertiary];
  _placeholder.userInteractionEnabled = NO;
  [box addSubview:_placeholder];

  // ---- 工具行右侧：附件 / 语音 / 发送 ----
  // 官方 ActionAreaView 里是 UploadButton / VoiceInputButton / SendButton 三个独立类，
  // 但样式全来自 DSButton。这里同样走 DSButton，尺寸 30（官方输入条按钮实测约 30）。
  DSButtonConfig *attachCfg = [DSButtonConfig style:DSButtonStylePlain icon:DSIconPlus title:nil];
  attachCfg.iconSize = DSIconPointSizeAction;          // 20
  attachCfg.minSize = CGSizeMake(30, 30);
  attachCfg.hPadding = 0;
  attachCfg.vPadding = 0;
  attachCfg.cornerRadius = 0;
  _attachButton = [DSButton buttonWithConfig:attachCfg];
  [_attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];

  DSButtonConfig *micCfg = [DSButtonConfig style:DSButtonStylePlain icon:DSIconMic title:nil];
  micCfg.iconSize = DSIconPointSizeAction;
  micCfg.minSize = CGSizeMake(30, 30);
  micCfg.hPadding = 0;
  micCfg.vPadding = 0;
  micCfg.cornerRadius = 0;
  _micButton = [DSButton buttonWithConfig:micCfg];
  UILongPressGestureRecognizer *press =
      [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(micPressed:)];
  press.minimumPressDuration = 0.12;
  [_micButton addGestureRecognizer:press];

  DSButtonConfig *sendCfg = [DSButtonConfig style:DSButtonStyleFilled icon:DSIconSend title:nil];
  sendCfg.iconSize = DSIconPointSizeInline;
  sendCfg.minSize = CGSizeMake(30, 30);
  sendCfg.hPadding = 0;
  sendCfg.vPadding = 0;
  sendCfg.cornerRadius = 15;
  _sendButton = [DSButton buttonWithConfig:sendCfg];
  _sendButton.enabled = NO;      // applyConfig 会把 alpha 压到 0.4
  [_sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];

  DSButtonConfig *stopCfg = [DSButtonConfig style:DSButtonStyleFilled icon:DSIconStop title:nil];
  stopCfg.iconSize = DSIconPointSizeInline;
  stopCfg.minSize = CGSizeMake(30, 30);
  stopCfg.hPadding = 0;
  stopCfg.vPadding = 0;
  stopCfg.cornerRadius = 15;
  stopCfg.background = [DSTheme labelPrimary];   // 停止是深色实心，和发送的蓝色区分开
  _stopButton = [DSButton buttonWithConfig:stopCfg];
  _stopButton.hidden = YES;
  [_stopButton addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];

  UIView *spacer = [[UIView alloc] init];
  [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [spacer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                          forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *tools = [[UIStackView alloc] initWithArrangedSubviews:
      @[_thinkChip, _searchChip, spacer, _attachButton, _micButton, _sendButton, _stopButton]];
  tools.translatesAutoresizingMaskIntoConstraints = NO;
  tools.axis = UILayoutConstraintAxisHorizontal;
  tools.alignment = UIStackViewAlignmentCenter;
  tools.spacing = 6;
  [box addSubview:tools];

  [_composer.contentView addSubview:box];

  _composerBottom = [_composer.bottomAnchor
      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
  _attachStripHeight = [_attachStrip.heightAnchor constraintEqualToConstant:0];
  _inputHeight = [_input.heightAnchor constraintEqualToConstant:32];

  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:_topBar.bottomAnchor],
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

    [_attachStrip.leadingAnchor constraintEqualToAnchor:_composer.contentView.leadingAnchor constant:16],
    [_attachStrip.trailingAnchor constraintEqualToAnchor:_composer.contentView.trailingAnchor constant:-16],
    [_attachStrip.topAnchor constraintEqualToAnchor:_composer.contentView.topAnchor constant:6],
    _attachStripHeight,

    // 输入容器：左右各 12，底部留 8（贴安全区）
    [box.leadingAnchor constraintEqualToAnchor:_composer.contentView.leadingAnchor constant:12],
    [box.trailingAnchor constraintEqualToAnchor:_composer.contentView.trailingAnchor constant:-12],
    [box.topAnchor constraintEqualToAnchor:_attachStrip.bottomAnchor constant:6],
    [box.bottomAnchor constraintEqualToAnchor:_composer.contentView.bottomAnchor constant:-8],

    [_input.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8],
    [_input.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8],
    [_input.topAnchor constraintEqualToAnchor:box.topAnchor constant:6],
    _inputHeight,

    [_placeholder.leadingAnchor constraintEqualToAnchor:_input.leadingAnchor constant:4],
    [_placeholder.topAnchor constraintEqualToAnchor:_input.topAnchor constant:6],

    [tools.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:6],
    [tools.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-6],
    [tools.topAnchor constraintEqualToAnchor:_input.bottomAnchor constant:2],
    [tools.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-6],
    [tools.heightAnchor constraintEqualToConstant:30],

    [_attachButton.widthAnchor constraintEqualToConstant:30],
    [_attachButton.heightAnchor constraintEqualToConstant:30],
    [_micButton.widthAnchor constraintEqualToConstant:30],
    [_micButton.heightAnchor constraintEqualToConstant:30],
    [_sendButton.widthAnchor constraintEqualToConstant:30],
    [_sendButton.heightAnchor constraintEqualToConstant:30],
    [_stopButton.widthAnchor constraintEqualToConstant:30],
    [_stopButton.heightAnchor constraintEqualToConstant:30],
  ]];

  [self refreshChips];
  [self updateSendState];
}

/// chips 是「输入框内的小胶囊」：未选中浅灰填充，选中品牌色淡底 + 品牌色字（官方同款）
/// 尺寸按官方量：图标 16×16（官方 Assets 里 toggle 系列就是 16 画布）、胶囊高 30
///
/// 走 DSButton 而不是手写 UIButton：官方全站按钮同源（`DSButton` + 五个 Config），
/// 选中/禁用/深浅色切换都由配置统一驱动。手写的话每加一处按钮就要重抄一遍配色，
/// 迟早不一致 —— 这正是之前「看着不像官方」的根因。
- (DSButton *)chipButtonWithTitle:(NSString *)title icon:(DSIconName)icon action:(SEL)action {
  DSButtonConfig *c = [DSButtonConfig style:DSButtonStyleTinted icon:icon title:title];
  c.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  c.iconSize = DSIconPointSizeInline;   // 16
  c.cornerRadius = 15;
  c.hPadding = 10;
  c.vPadding = 0;
  c.iconTitleGap = 4;
  c.minSize = CGSizeMake(0, 30);       // 高度锁 30，宽度由内容撑
  DSButton *b = [DSButton buttonWithConfig:c];
  [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [b.heightAnchor constraintEqualToConstant:30].active = YES;
  return b;
}

- (void)applyChipStyles {
  NSDictionary *s = [[DSBoxService shared] settings];
  BOOL thinking = [s[@"thinking"] boolValue];
  BOOL search = [s[@"search"] boolValue];

  [self styleChip:_thinkChip on:thinking];
  [self styleChip:_searchChip on:search];
}

/// 选中态交给 DSButton 的 config（selectedTint / selectedBackground），
/// 这里只负责把状态传下去 —— 配色不要再在这儿写第二遍。
- (void)styleChip:(DSButton *)chip on:(BOOL)on {
  if (!chip) return;
  chip.selected = on;   // setSelected 里会自动 applyConfig
}

- (void)refreshChips {
  NSDictionary *s = [[DSBoxService shared] settings];
  NSString *model = s[@"model"] ?: @"deepseek-flash";
  // 官方 2.7.1 已经取消「快速/专家/识图」三档，顶栏直接显示当前模型的展示名，
  // 点开是真实模型列表（/models，取不到就用 id 本身）。
  NSString *title = self.modelNames[model] ?: model;
  self.topBar.modelTitle = title;
  [self applyChipStyles];
}

/// 拉一次模型列表，缓存 id→展示名，顺便把 chip 标题刷新成真实模型名
- (void)loadModelList {
  __weak __typeof(self) ws = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *err = nil;
    NSArray<NSDictionary *> *models = [[DSBoxService shared] listModelsWithError:&err];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!models.count) return;
      NSMutableDictionary *names = [NSMutableDictionary dictionary];
      for (NSDictionary *m in models) {
        if (![m isKindOfClass:NSDictionary.class]) continue;
        NSString *mid = [m[@"id"] isKindOfClass:NSString.class] ? m[@"id"] : nil;
        if (!mid.length) continue;
        NSString *name = [m[@"name"] isKindOfClass:NSString.class] && [m[@"name"] length] ? m[@"name"] : mid;
        names[mid] = name;
      }
      ws.modelList = models;
      ws.modelNames = names;
      [ws refreshChips];
    });
  });
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
  for (NSMutableDictionary *r in self.streamRounds) {
    r[@"streaming"] = @NO;
    // 中途停止/出错时思考还没结束，也要把计时封口，否则停在「正在思考」
    if (r[@"thinkStart"] && !r[@"thinkEnd"]) {
      r[@"thinkEnd"] = @([[NSDate date] timeIntervalSince1970]);
    }
  }
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
  // 先按新值上色，不等回读 —— 万一落盘失败，按钮至少给到点击反馈，
  // 再由 verifyChipState 把「存不进去」打到日志里。
  [self styleChip:_thinkChip on:v];
  [self verifyChipState];
}

- (void)toggleSearch {
  NSDictionary *s = [[DSBoxService shared] settings];
  BOOL v = ![s[@"search"] boolValue];
  [[DSBoxService shared] saveSettingsPatch:@{@"search": @(v), @"readUrl": @(v)}];
  [self styleChip:_searchChip on:v];
  [self verifyChipState];
}

/// 回读校验。之前这里出过一个很隐蔽的 bug：ObjC 桥接把 `@(YES)` 当成数字发成 1，
/// C++ 侧 `j.value<bool>()` 抛 type_error.302，`saveSettings` 整体失败并被 catch 掉，
/// 于是「开关点了没反应」且毫无提示。现在存不进去会留下这条日志。
- (void)verifyChipState {
  NSDictionary *s = [[DSBoxService shared] settings];
  BOOL thinking = [s[@"thinking"] boolValue];
  BOOL search = [s[@"search"] boolValue];
  if (thinking != _thinkChip.selected || search != _searchChip.selected) {
    NSLog(@"[chip] 状态未落盘：thinking=%d(期望 %d) search=%d(期望 %d)",
          thinking, _thinkChip.selected, search, _searchChip.selected);
  }
}

- (void)modelTapped {
  NSDictionary *s = [[DSBoxService shared] settings];
  NSString *cur = s[@"model"] ?: @"deepseek-flash";

  // 已经拉过就直接弹；没拉过就先去取（取不到会用内置兜底，不会空着）
  if (self.modelList.count) { [self presentModelSheetWithList:self.modelList current:cur]; return; }
  __weak __typeof(self) ws = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *err = nil;
    NSArray<NSDictionary *> *models = [[DSBoxService shared] listModelsWithError:&err];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (models.count) {
        NSMutableDictionary *names = [NSMutableDictionary dictionary];
        for (NSDictionary *m in models) {
          NSString *mid = [m[@"id"] isKindOfClass:NSString.class] ? m[@"id"] : nil;
          if (!mid.length) continue;
          names[mid] = ([m[@"name"] isKindOfClass:NSString.class] && [m[@"name"] length]) ? m[@"name"] : mid;
        }
        ws.modelList = models;
        ws.modelNames = names;
        [ws presentModelSheetWithList:models current:cur];
      } else {
        [ws toast:@"取不到模型列表，请检查网络或 API Key"];
      }
    });
  });
}

- (void)presentModelSheetWithList:(NSArray<NSDictionary *> *)models current:(NSString *)cur {
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:DSStrModelSwitch
      message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  __weak __typeof(self) ws = self;
  for (NSDictionary *m in models) {
    if (![m isKindOfClass:NSDictionary.class]) continue;
    NSString *mid = [m[@"id"] isKindOfClass:NSString.class] ? m[@"id"] : nil;
    if (!mid.length) continue;
    NSString *name = ([m[@"name"] isKindOfClass:NSString.class] && [m[@"name"] length]) ? m[@"name"] : mid;
    BOOL on = [cur isEqualToString:mid];
    NSString *title = on ? [NSString stringWithFormat:@"✓ %@", name] : name;

    [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
      [[DSBoxService shared] saveSettingsPatch:@{@"model": mid}];
      [ws refreshChips];
    }]];
  }
  [sheet addAction:[UIAlertAction actionWithTitle:DSStrCancel style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.sourceView = self.topBar.modelButton;
  sheet.popoverPresentationController.sourceRect = self.topBar.modelButton.bounds;
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
        // 官方 ASR 单次上限 120 秒，到点自动收尾并开始识别（否则接口直接 400）
        if (rec.duration >= 120.0) {
          [t invalidate];
          ws.voiceTimer = nil;
          NSString *path = [rec finish];
          ws.recorder = nil;
          if (path.length) {
            [ws.voiceOverlay showRecognizing];
            [ws transcribeVoiceAtPath:path];
          } else {
            [ws.voiceOverlay dismiss];
          }
        }
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
      if (!self.recorder) break;  // 已在 120 秒上限处自动收尾，避免把「识别中」浮层关掉
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
  if (self.onNewChat) { self.onNewChat(); return; }
  NSDictionary *conv = [[DSBoxService shared] createConversation];
  DSChatViewController *vc = [[DSChatViewController alloc] initWithConversationId:conv[@"id"]];
  [self.navigationController pushViewController:vc animated:YES];
}

- (NSString *)conversationId { return self.convId; }

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
  [self updateSendState];
  [self resizeInputIfNeeded];
}

/// 输入框跟着内容长高（官方最多约 5 行，超过就内部滚动）
- (void)resizeInputIfNeeded {
  static const CGFloat kMaxHeight = 120;
  static const CGFloat kMinHeight = 32;
  CGFloat width = self.input.bounds.size.width;
  if (width <= 0) return;
  CGSize fit = [self.input sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
  CGFloat h = MIN(MAX(fit.height, kMinHeight), kMaxHeight);
  BOOL scroll = fit.height > kMaxHeight;
  if (h > self.inputHeight.constant - 0.5 && h < self.inputHeight.constant + 0.5 &&
      self.input.scrollEnabled == scroll) {
    return;
  }

  self.inputHeight.constant = h;
  self.input.scrollEnabled = scroll;
  [UIView animateWithDuration:0.12 animations:^{
    [self.view layoutIfNeeded];
  } completion:^(BOOL done) {
    [self scrollToBottomAnimated:NO];
  }];
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
      // 官方思考头部是「已思考（用时 N 秒）」：第一个正文增量到达就算思考结束
      if (cur && cur[@"thinkStart"] && !cur[@"thinkEnd"]) {
        cur[@"thinkEnd"] = @([[NSDate date] timeIntervalSince1970]);
      }
      [self appendText:text to:cur key:@"content"];
      break;
    case DSBoxStreamEventReasoning:
      if (cur && !cur[@"thinkStart"]) {
        cur[@"thinkStart"] = @([[NSDate date] timeIntervalSince1970]);
      }
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
        // 注意：服务端下发的是单个对象，但不同版本/网关可能包成数组，
        // 直接 ev[@"type"] 会对 NSArray 发 objectForKeyedSubscript: 崩掉，这里统一按 id 取。
        id rawEv = data[@"event"];
        NSArray *evList = nil;
        if ([rawEv isKindOfClass:NSDictionary.class]) evList = @[rawEv];
        else if ([rawEv isKindOfClass:NSArray.class]) evList = rawEv;

        for (id item in evList) {
          if (![item isKindOfClass:NSDictionary.class]) continue;
          NSDictionary *ev = item;
          NSString *kind = [ev[@"type"] isKindOfClass:NSString.class] ? ev[@"type"] : @"";
          NSDictionary *call = [ev[@"call"] isKindOfClass:NSDictionary.class] ? ev[@"call"] : nil;
          if (!call || !([kind isEqualToString:@"call_started"] || [kind isEqualToString:@"call_completed"])) continue;

          NSMutableArray *arr = [cur[@"server_tool_calls"] isKindOfClass:NSArray.class]
              ? [cur[@"server_tool_calls"] mutableCopy] : [NSMutableArray array];
          NSInteger exist = -1;
          for (NSInteger i = 0; i < (NSInteger)arr.count; i++) {
            NSDictionary *old = [arr[(NSUInteger)i] isKindOfClass:NSDictionary.class] ? arr[(NSUInteger)i] : nil;
            if (old && [old[@"id"] isEqual:call[@"id"]]) { exist = i; break; }
          }
          if (exist >= 0) arr[(NSUInteger)exist] = call;
          else [arr addObject:call];
          cur[@"server_tool_calls"] = arr;
        }
        [self refreshStreamRow];
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
      // 服务端定稿里没有本地记的思考计时，这里带过去，否则「已思考（用时 N 秒）」会丢
      if (cur) {
        if (cur[@"thinkStart"]) merged[@"thinkStart"] = cur[@"thinkStart"];
        if (cur[@"thinkEnd"]) merged[@"thinkEnd"] = cur[@"thinkEnd"];
      }
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
  [self refreshEmptyState];
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

  // 官方限制：用过 deepseek_web_search / deepseek_read_url 的回复不能续写（会返回 400）
  NSDictionary *st = [[DSBoxService shared] settings];
  if ([st[@"search"] boolValue] || [st[@"readUrl"] boolValue]) {
    [self toast:@"联网工具开启时无法续写，请先关闭「智能搜索」"];
    return;
  }

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
