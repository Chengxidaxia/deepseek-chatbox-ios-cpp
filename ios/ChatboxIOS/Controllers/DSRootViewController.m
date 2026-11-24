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

@interface DSRootViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, copy, nullable) NSString *initialConvId;
@property (nonatomic, strong, nullable) DSChatViewController *chat;
@property (nonatomic, strong) DSConversationListController *sidebar;
@property (nonatomic, strong) UIView *dim;
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

  // ---- 抽屉（先建，保证 z 序在聊天页之上）----
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

  _dim = [[UIView alloc] init];
  _dim.translatesAutoresizingMaskIntoConstraints = NO;
  _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
  _dim.alpha = 0;
  _dim.hidden = YES;
  [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                   action:@selector(closeSidebar)]];
  [self.view addSubview:_dim];

  CGFloat drawerWidth = MIN(320.0, UIScreen.mainScreen.bounds.size.width * 0.84);
  _drawerLeading = [_drawer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                        constant:-drawerWidth];

  [NSLayoutConstraint activateConstraints:@[
    [_drawer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_drawer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [_drawer.widthAnchor constraintEqualToConstant:drawerWidth],
    _drawerLeading,

    [_sidebar.view.topAnchor constraintEqualToAnchor:_drawer.topAnchor],
    [_sidebar.view.bottomAnchor constraintEqualToAnchor:_drawer.bottomAnchor],
    [_sidebar.view.leadingAnchor constraintEqualToAnchor:_drawer.leadingAnchor],
    [_sidebar.view.trailingAnchor constraintEqualToAnchor:_drawer.trailingAnchor],

    [_dim.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_dim.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [_dim.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_dim.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
  ]];

  // 聊天页：抽屉打开时右滑手势由抽屉自己吃掉，其余交给聊天页
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
  [self.view insertSubview:vc.view atIndex:0];   // 垫在最底层，遮罩和抽屉在上面
  [NSLayoutConstraint activateConstraints:@[
    [vc.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [vc.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [vc.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [vc.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
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

- (void)openSidebar {
  if (_sidebarOpen) return;
  _sidebarOpen = YES;
  _dim.hidden = NO;
  [self.view layoutIfNeeded];
  _drawerLeading.constant = 0;
  [UIView animateWithDuration:0.28
                        delay:0
       usingSpringWithDamping:0.92
        initialSpringVelocity:0
                      options:UIViewAnimationOptionCurveEaseOut
                   animations:^{
                     self.dim.alpha = 1;
                     [self.view layoutIfNeeded];
                   }
                   completion:nil];
}

- (void)closeSidebar {
  if (!_sidebarOpen) return;
  _sidebarOpen = NO;
  _drawerLeading.constant = -[self drawerWidth];
  [UIView animateWithDuration:0.24
                   animations:^{
                     self.dim.alpha = 0;
                     [self.view layoutIfNeeded];
                   }
                   completion:^(BOOL finished) {
                     self.dim.hidden = YES;
                   }];
}

/// 左缘右滑打开、抽屉上左滑关闭
- (void)handlePan:(UIPanGestureRecognizer *)g {
  CGPoint t = [g translationInView:self.view];
  if (g.state == UIGestureRecognizerStateBegan) {
    [self.view layoutIfNeeded];
  }
  CGFloat width = [self drawerWidth];
  if (!_sidebarOpen) {
    // 只有从屏幕左缘起手才跟手，避免和消息区的横向手势打架
    if (t.x <= 0) return;
    _dim.hidden = NO;
    _drawerLeading.constant = MIN(0, -width + t.x);
    _dim.alpha = MAX(0, MIN(1, t.x / width));
  } else {
    _drawerLeading.constant = MAX(-width, MIN(0, t.x));
    _dim.alpha = MAX(0, 1 + MIN(0, t.x) / width);
  }
  [self.view layoutIfNeeded];

  if (g.state == UIGestureRecognizerStateEnded ||
      g.state == UIGestureRecognizerStateCancelled) {
    CGFloat progress = 1 + _drawerLeading.constant / width;  // 0 关 → 1 开
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
