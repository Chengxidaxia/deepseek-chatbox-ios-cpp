//
//  DSRootViewController.m
//  ChatboxIOS
//

#import "DSRootViewController.h"
#import "DSChatViewController.h"
#import "DSConversationListController.h"
#import "DSSettingsViewController.h"
#import "DSBoxService.h"
#import "DSTheme.h"
#import "DSIcon.h"

/// 抽屉打开时主页面缩到多大。官方是 SidebarViewController 里的 MainDecorationView 干这事，
/// 配套还有个 CornerReferenceView 专门算转角曲率 —— 说明它确实是「主视图缩成圆角卡片」。
/// 0.94 是照着 iOS 原生侧栏（以及官方观感）调的：再小就显脏，再大看不出层次。
static const CGFloat kDSContentShrink = 0.94;
static const CGFloat kDSContentCorner = 12.0;

@interface DSRootViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, copy, nullable) NSString *initialConvId;
@property (nonatomic, strong, nullable) DSChatViewController *chat;
@property (nonatomic, strong) DSConversationListController *sidebar;
/// 遮罩：垫在最底层。主视图不缩小时被完全盖住，缩小时才从四周露出来。
@property (nonatomic, strong) UIView *dim;
/// 主内容容器。抽屉打开时整体缩放 + 圆角，对应官方的 MainDecorationView。
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) UIView *drawer;
@property (nonatomic, strong) NSLayoutConstraint *drawerLeading;
@property (nonatomic, assign) BOOL sidebarOpen;
@end

@implementation DSRootViewController

- (instancetype)initWithConversationId:(NSString *)convId {
  self = [super initWithNibName:nil bundle:nil];
  if (!self) return nil;
  _initialConvId = [convId copy];
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [DSTheme bgBase];

  // 层次（从下往上）：
  //   0 dim     —— 主视图缩小后露出来的暗背景，也是「点空白关闭」的接收者
  //   1 content —— 主内容（聊天页），抽屉打开时缩放 + 圆角
  //   2 drawer  —— 会话抽屉，永远在最上面
  //
  // 之前是 chat < dim < drawer，dim 压在聊天页上 —— 主视图会整体变暗，
  // 官方是主视图保持亮、只有露出来的背景暗，所以 dim 必须垫到最底下。
  _dim = [[UIView alloc] init];
  _dim.translatesAutoresizingMaskIntoConstraints = NO;
  _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
  [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                   action:@selector(closeSidebar)]];
  [self.view addSubview:_dim];

  _content = [[UIView alloc] init];
  _content.translatesAutoresizingMaskIntoConstraints = NO;
  _content.backgroundColor = [DSTheme bgBase];
  _content.layer.masksToBounds = YES;      // 圆角要裁子视图
  _content.layer.cornerCurve = kCACornerCurveContinuous;
  [self.view addSubview:_content];

  _drawer = [[UIView alloc] init];
  _drawer.translatesAutoresizingMaskIntoConstraints = NO;
  _drawer.backgroundColor = [DSTheme bgBase];
  _drawer.layer.shadowColor = UIColor.blackColor.CGColor;
  _drawer.layer.shadowOpacity = 0.12;
  _drawer.layer.shadowRadius = 16;
  _drawer.layer.shadowOffset = CGSizeMake(2, 0);
  [self.view addSubview:_drawer];

  _sidebar = [[DSConversationListController alloc] init];
  _sidebar.drawerMode = YES;
  __weak __typeof(self) ws = self;
  _sidebar.onSelectConversation = ^(NSString *convId) {
    [ws showConversation:convId];
    [ws closeSidebar];
  };
  _sidebar.onNewChat = ^{
    [ws startNewChat];
    [ws closeSidebar];
  };
  _sidebar.onOpenSettings = ^{ [ws presentSettings]; };
  [self addChildViewController:_sidebar];
  _sidebar.view.translatesAutoresizingMaskIntoConstraints = NO;
  [_drawer addSubview:_sidebar.view];
  [_sidebar didMoveToParentViewController:self];

  CGFloat drawerWidth = MIN(320.0, UIScreen.mainScreen.bounds.size.width * 0.84);
  _drawerLeading = [_drawer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                        constant:-drawerWidth];

  [NSLayoutConstraint activateConstraints:@[
    [_dim.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_dim.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [_dim.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_dim.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

    [_content.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [_content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

    [_drawer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_drawer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [_drawer.widthAnchor constraintEqualToConstant:drawerWidth],
    _drawerLeading,

    [_sidebar.view.topAnchor constraintEqualToAnchor:_drawer.topAnchor],
    [_sidebar.view.bottomAnchor constraintEqualToAnchor:_drawer.bottomAnchor],
    [_sidebar.view.leadingAnchor constraintEqualToAnchor:_drawer.leadingAnchor],
    [_sidebar.view.trailingAnchor constraintEqualToAnchor:_drawer.trailingAnchor],
  ]];

  [self showConversation:[self resolvedInitialConversationId]];

  UIPanGestureRecognizer *pan =
      [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
  pan.delegate = self;
  [self.view addGestureRecognizer:pan];
}

- (NSString *)resolvedInitialConversationId {
  if (_initialConvId.length) return _initialConvId;
  NSDictionary *ui = [[DSBoxService shared] uiState];
  NSString *active = ui[@"activeId"];
  if ([active isKindOfClass:NSString.class] && active.length) {
    if ([[DSBoxService shared] conversationWithId:active]) return active;
  }
  NSArray *all = [[DSBoxService shared] allConversations];
  if (all.count) {
    NSString *cid = all.firstObject[@"id"];
    if ([cid isKindOfClass:NSString.class] && cid.length) return cid;
  }
  NSDictionary *conv = [[DSBoxService shared] createConversation];
  NSString *cid = conv[@"id"];
  return [cid isKindOfClass:NSString.class] ? cid : @"";
}

#pragma mark - 切换会话

- (void)showConversation:(NSString *)convId {
  if (!convId.length) return;
  if (_chat && [_chat.conversationId isEqualToString:convId]) return;

  if (_chat) {
    [_chat willMoveToParentViewController:nil];
    [_chat.view removeFromSuperview];
    [_chat removeFromParentViewController];
    _chat = nil;
  }

  DSChatViewController *vc = [[DSChatViewController alloc] initWithConversationId:convId];
  __weak __typeof(self) ws = self;
  vc.onMenuTap = ^{ [ws openSidebar]; };
  vc.onNewChat = ^{ [ws startNewChat]; };
  [self addChildViewController:vc];
  vc.view.translatesAutoresizingMaskIntoConstraints = NO;
  [_content addSubview:vc.view];       // 进主内容容器，这样抽屉打开时跟着一起缩放
  [NSLayoutConstraint activateConstraints:@[
    [vc.view.topAnchor constraintEqualToAnchor:_content.topAnchor],
    [vc.view.bottomAnchor constraintEqualToAnchor:_content.bottomAnchor],
    [vc.view.leadingAnchor constraintEqualToAnchor:_content.leadingAnchor],
    [vc.view.trailingAnchor constraintEqualToAnchor:_content.trailingAnchor],
  ]];
  [vc didMoveToParentViewController:self];
  _chat = vc;

  [[DSBoxService shared] saveUIPatch:@{@"activeId": convId}];
}

- (void)startNewChat {
  NSDictionary *conv = [[DSBoxService shared] createConversation];
  NSString *cid = conv[@"id"];
  if ([cid isKindOfClass:NSString.class] && cid.length) [self showConversation:cid];
}

- (void)presentSettings {
  DSSettingsViewController *vc = [[DSSettingsViewController alloc] init];
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
  nav.modalPresentationStyle = UIModalPresentationPageSheet;
  if (@available(iOS 15.0, *)) {
    // 与官方一致：顶栏与页面同色、无分割线、无投影
    UINavigationBarAppearance *app = [UINavigationBarAppearance new];
    [app configureWithOpaqueBackground];
    app.backgroundColor = [DSTheme bgBase];
    app.shadowColor = UIColor.clearColor;
    app.titleTextAttributes = @{NSForegroundColorAttributeName: [DSTheme labelPrimary]};
    nav.navigationBar.standardAppearance = app;
    nav.navigationBar.scrollEdgeAppearance = app;
    nav.navigationBar.compactAppearance = app;
  }
  [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 抽屉

- (CGFloat)drawerWidth {
  return MIN(320.0, self.view.bounds.size.width * 0.84);
}

/// 主视图的「缩成卡片」变换。
///
/// 用 transform 而不是改约束：transform 不动 layout，聊天页里的滚动位置、
/// 输入框高度、键盘避让全都保持不变；改约束会把整棵树重排一遍，还容易和
/// 键盘通知打架。代价是缩放时文字会轻微重采样，0.94 这个幅度看不出来。
- (void)setContentShrunk:(BOOL)shrunk animated:(BOOL)animated duration:(NSTimeInterval)duration {
  void (^apply)(void) = ^{
    self.content.transform = shrunk
        ? CGAffineTransformMakeScale(kDSContentShrink, kDSContentShrink)
        : CGAffineTransformIdentity;
    self.content.layer.cornerRadius = shrunk ? kDSContentCorner : 0;
  };
  if (!animated) {
    apply();
    return;
  }
  [UIView animateWithDuration:duration
                        delay:0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                   animations:apply
                   completion:nil];
}

- (void)openSidebar {
  if (_sidebarOpen) return;
  _sidebarOpen = YES;
  [self.view layoutIfNeeded];
  _drawerLeading.constant = 0;
  [self setContentShrunk:YES animated:YES duration:0.32];
  [UIView animateWithDuration:0.32
                        delay:0
       usingSpringWithDamping:0.92
        initialSpringVelocity:0
                      options:UIViewAnimationOptionCurveEaseOut
                   animations:^{ [self.view layoutIfNeeded]; }
                   completion:nil];
}

- (void)closeSidebar {
  if (!_sidebarOpen) return;
  _sidebarOpen = NO;
  _drawerLeading.constant = -[self drawerWidth];
  [self setContentShrunk:NO animated:YES duration:0.26];
  [UIView animateWithDuration:0.26
                   animations:^{ [self.view layoutIfNeeded]; }
                   completion:nil];
}

/// 左缘右滑打开、抽屉上左滑关闭
- (void)handlePan:(UIPanGestureRecognizer *)g {
  CGPoint t = [g translationInView:self.view];
  if (g.state == UIGestureRecognizerStateBegan) {
    [self.view layoutIfNeeded];
  }
  CGFloat width = [self drawerWidth];
  if (!_sidebarOpen) {
    // 只有从屏幕左缘起手才跟手（由 gestureRecognizerShouldBegin 拦），这里只管跟手位移。
    // 左滑把 t.x 拉成负数时夹到 -width，也就是「关到底」，不要冲出去。
    _drawerLeading.constant = MAX(-width, MIN(0, -width + t.x));
  } else {
    _drawerLeading.constant = MAX(-width, MIN(0, t.x));
  }
  // 跟手时主视图同步缩放，手感才连得上（不然松手才突然一缩，很假）
  CGFloat progress = 1 + _drawerLeading.constant / width;   // 0 关 → 1 开
  CGFloat s = 1 - (1 - kDSContentShrink) * progress;
  _content.transform = CGAffineTransformMakeScale(s, s);
  _content.layer.cornerRadius = kDSContentCorner * progress;
  [self.view layoutIfNeeded];

  if (g.state == UIGestureRecognizerStateEnded ||
      g.state == UIGestureRecognizerStateCancelled) {
    BOOL velocityOpens = [g velocityInView:self.view].x > 300;
    BOOL velocityCloses = [g velocityInView:self.view].x < -300;
    if (!_sidebarOpen) {
      if (progress > 0.4 || velocityOpens) [self openSidebar]; else [self closeSidebar];
    } else {
      if (progress < 0.6 || velocityCloses) [self closeSidebar]; else [self openSidebar];
    }
  }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
  if (![g isKindOfClass:UIPanGestureRecognizer.class]) return YES;
  CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self.view];
  if (fabs(v.x) <= fabs(v.y)) return NO;            // 只认横向
  CGPoint p = [g locationInView:self.view];
  if (!_sidebarOpen) return p.x < 24;               // 关着时只认左缘
  return YES;
}

@end
