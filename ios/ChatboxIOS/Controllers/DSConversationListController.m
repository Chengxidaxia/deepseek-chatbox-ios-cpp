//
//  DSConversationListController.m
//  ChatboxIOS
//
//  对齐官方会话列表：`SessionListCollectionView` 的分组结构
//  （置顶 / 今天 / 昨天 / 7 天内 / 30 天内 / 更早），空态给标题 + 说明 +
//  「开启新对话」入口（对应 SessionListEmptyView）。
//
//  为什么从 UITableView 换成 UICollectionView：官方就是 collection view，
//  而且分区头要**吸顶**。UITableView 的 plain 样式也能吸顶，但单元格只能吃
//  系统那套 subtitle 布局；换成 collection view + compositional layout 之后，
//  单元格完全自绘，分区头也能独立控制。
//

#import "DSConversationListController.h"
#import "DSBoxService.h"
#import "DSChatViewController.h"
#import "DSSettingsViewController.h"
#import "DSTheme.h"
#import "DSStrings.h"
#import "DSIcon.h"
#import "DSButton.h"
#import "DSSessionCell.h"

static NSString *const kCellID = @"session";
static NSString *const kHeaderID = @"sessionHeader";

@interface DSConversationListController () <UICollectionViewDataSource, UICollectionViewDelegate,
    UISearchResultsUpdating>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;    // 全量
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered; // 过滤后
@property (nonatomic, strong) NSArray<NSDictionary *> *sections; // {title, items}
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyTitle;
@property (nonatomic, strong) UILabel *emptyDesc;
// 抽屉模式自带的四段：开启新对话 / 搜索 / 列表 / 设置
@property (nonatomic, strong) UIView *drawerHeader;
@property (nonatomic, strong) UIView *drawerFooter;
@property (nonatomic, strong) UITextField *searchField;
@end

@implementation DSConversationListController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [DSTheme bgBase];

  if (self.drawerMode) {
    // 官方会话列表是**抽屉**（SidebarViewController 里的 SessionListViewController），
    // 没有导航栏：自己带「开启新对话 / 搜索 / 列表 / 设置」四段。
    [self buildDrawerHeader];
    [self buildDrawerFooter];
  } else {
    [self setupNavigationMode];
  }

  [self buildCollectionView];
  [self buildEmptyView];
  [self reload];
}

/// 独立页模式（老路径）：导航栏 + 系统搜索控制器
- (void)setupNavigationMode {
  self.title = @"DeepSeek Chatbox";
  self.navigationItem.leftBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:DSStrSettings
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(openSettings)];
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                    target:self
                                                    action:@selector(newChat)];

  self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
  self.search.searchResultsUpdater = self;
  self.search.obscuresBackgroundDuringPresentation = NO;
  self.search.searchBar.placeholder = DSStrSearchHint;
  self.navigationItem.searchController = self.search;
  self.navigationItem.hidesSearchBarWhenScrolling = NO;
  self.definesPresentationContext = YES;
}

/// 抽屉顶部：开启新对话 + 搜索框
- (void)buildDrawerHeader {
  UIView *header = [[UIView alloc] init];
  header.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:header];
  _drawerHeader = header;

  UIButton *newChat = [UIButton buttonWithType:UIButtonTypeSystem];
  newChat.translatesAutoresizingMaskIntoConstraints = NO;
  newChat.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  [newChat setTitle:DSStrStartNewChat forState:UIControlStateNormal];   // sessionListNewChatButton
  newChat.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  [newChat setTitleColor:[DSTheme labelPrimary] forState:UIControlStateNormal];
  [newChat setImage:[DSIcon image:DSIconPlus size:DSIconPointSizeAction] forState:UIControlStateNormal];
  newChat.tintColor = [DSTheme labelPrimary];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  newChat.imageEdgeInsets = UIEdgeInsetsMake(0, -2, 0, 2);
  newChat.titleEdgeInsets = UIEdgeInsetsMake(0, 2, 0, -2);
  newChat.contentEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
#pragma clang diagnostic pop
  [newChat addTarget:self action:@selector(newChat) forControlEvents:UIControlEventTouchUpInside];
  [header addSubview:newChat];

  // 搜索框：浅灰圆角 + 放大镜，官方 SessionListSearchBarView 同形态
  UITextField *field = [[UITextField alloc] init];
  field.translatesAutoresizingMaskIntoConstraints = NO;
  field.placeholder = DSStrSearchHint;   // searchHint = 搜索对话内容...
  field.font = [UIFont systemFontOfSize:14];
  field.textColor = [DSTheme labelPrimary];
  field.backgroundColor = [DSTheme bgHover];
  field.layer.cornerRadius = 10;
  field.layer.cornerCurve = kCACornerCurveContinuous;
  field.clearButtonMode = UITextFieldViewModeWhileEditing;
  field.returnKeyType = UIReturnKeySearch;
  [field addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];

  UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 36)];
  UIImageView *mag = [[UIImageView alloc] initWithImage:[DSIcon image:DSIconSearch size:16]];
  mag.tintColor = [DSTheme labelTertiary];
  mag.frame = CGRectMake(10, 10, 16, 16);
  [pad addSubview:mag];
  field.leftView = pad;
  field.leftViewMode = UITextFieldViewModeAlways;
  [header addSubview:field];
  _searchField = field;

  [NSLayoutConstraint activateConstraints:@[
    [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

    [newChat.topAnchor constraintEqualToAnchor:header.topAnchor constant:4],
    [newChat.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:12],
    [newChat.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12],
    [newChat.heightAnchor constraintEqualToConstant:44],

    [field.topAnchor constraintEqualToAnchor:newChat.bottomAnchor constant:4],
    [field.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
    [field.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
    [field.heightAnchor constraintEqualToConstant:36],
    [field.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
  ]];
}

/// 抽屉底部：设置入口
- (void)buildDrawerFooter {
  UIView *footer = [[UIView alloc] init];
  footer.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:footer];
  _drawerFooter = footer;

  UIView *line = [[UIView alloc] init];
  line.translatesAutoresizingMaskIntoConstraints = NO;
  line.backgroundColor = [DSTheme borderL2];
  [footer addSubview:line];

  UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
  settings.translatesAutoresizingMaskIntoConstraints = NO;
  settings.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  [settings setTitle:DSStrSettings forState:UIControlStateNormal];   // profileTitle = 设置
  settings.titleLabel.font = [UIFont systemFontOfSize:15];
  [settings setTitleColor:[DSTheme labelPrimary] forState:UIControlStateNormal];
  [settings setImage:[DSIcon image:DSIconUserCircle size:DSIconPointSizeAction] forState:UIControlStateNormal];
  settings.tintColor = [DSTheme labelSecondary];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  settings.imageEdgeInsets = UIEdgeInsetsMake(0, -2, 0, 2);
  settings.titleEdgeInsets = UIEdgeInsetsMake(0, 2, 0, -2);
  settings.contentEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
#pragma clang diagnostic pop
  [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
  [footer addSubview:settings];

  [NSLayoutConstraint activateConstraints:@[
    [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [footer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

    [line.topAnchor constraintEqualToAnchor:footer.topAnchor],
    [line.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:16],
    [line.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16],
    [line.heightAnchor constraintEqualToConstant:0.5],

    [settings.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:4],
    [settings.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:12],
    [settings.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-12],
    [settings.heightAnchor constraintEqualToConstant:46],
    [settings.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:-6],
  ]];
}

#pragma mark - 列表

- (void)buildCollectionView {
  UICollectionViewCompositionalLayout *layout =
      [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:
        ^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> env) {
    NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidth:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:DSSessionRowHeight]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidth:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:DSSessionRowHeight]];
    NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup verticalGroupWithLayoutSize:groupSize subitem:item count:1];

    NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:group];
    // 组与组之间留一口气，靠分组头的上边距撑，不在分区底部再加 —— 否则
    // 最后一组下面会多出一段空白。
    sec.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);

    NSCollectionLayoutSize *headerSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidth:1.0]
                                       heightDimension:[NSCollectionLayoutDimension estimatedDimension:30]];
    NSCollectionLayoutBoundarySupplementaryItem *header =
        [NSCollectionLayoutBoundarySupplementaryItem
            boundarySupplementaryItemWithLayoutSize:headerSize
                                         elementKind:UICollectionElementKindSectionHeader
                                           alignment:NSRectAlignmentTop];
    // 官方分组头是吸顶的（VirtualRootCell 顶住不滚）。
    header.pinToVisibleBounds = YES;
    sec.boundarySupplementaryItems = @[header];
    return sec;
  }];

  self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
  self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
  self.collectionView.dataSource = self;
  self.collectionView.delegate = self;
  self.collectionView.backgroundColor = [DSTheme bgBase];
  self.collectionView.alwaysBounceVertical = YES;
  self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  [self.collectionView registerClass:DSSessionCell.class forCellWithReuseIdentifier:kCellID];
  [self.collectionView registerClass:DSSessionSectionHeaderView.class
          forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                 withReuseIdentifier:kHeaderID];
  [self.view addSubview:self.collectionView];

  NSLayoutYAxisAnchor *top = self.drawerMode ? _drawerHeader.bottomAnchor
                                             : self.view.safeAreaLayoutGuide.topAnchor;
  NSLayoutYAxisAnchor *bottom = self.drawerMode ? _drawerFooter.topAnchor : self.view.bottomAnchor;
  [NSLayoutConstraint activateConstraints:@[
    [self.collectionView.topAnchor constraintEqualToAnchor:top],
    [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.collectionView.bottomAnchor constraintEqualToAnchor:bottom],
  ]];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  if (!self.drawerMode) [self.navigationController setNavigationBarHidden:NO animated:animated];
  [self reload];
}

/// 当前搜索词：两种模式共用
- (NSString *)currentQuery {
  if (self.drawerMode) return self.searchField.text ?: @"";
  return self.search.searchBar.text ?: @"";
}

- (void)searchChanged:(UITextField *)field {
  [self applyFilter:field.text ?: @""];
}

#pragma mark - 空态

- (void)buildEmptyView {
  _emptyView = [[UIView alloc] init];
  _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
  _emptyView.hidden = YES;
  [self.view addSubview:_emptyView];

  _emptyTitle = [[UILabel alloc] init];
  _emptyTitle.text = DSStrSessionListEmptyTitle;
  _emptyTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
  _emptyTitle.textColor = [DSTheme labelPrimary];
  _emptyTitle.textAlignment = NSTextAlignmentCenter;

  _emptyDesc = [[UILabel alloc] init];
  _emptyDesc.text = DSStrSessionListEmptyDesc;
  _emptyDesc.font = [UIFont systemFontOfSize:14];
  _emptyDesc.textColor = [DSTheme labelTertiary];
  _emptyDesc.textAlignment = NSTextAlignmentCenter;
  _emptyDesc.numberOfLines = 0;

  UIButton *start = [UIButton buttonWithType:UIButtonTypeSystem];
  [start setTitle:DSStrStartNewChat forState:UIControlStateNormal];
  start.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  [start setTitleColor:[DSTheme brand] forState:UIControlStateNormal];
  start.layer.cornerRadius = 10;
  start.layer.borderWidth = 1;
  start.layer.borderColor = [DSTheme borderL2].CGColor;
  // 旧式按钮（configuration 为 nil），inset 仍生效；换成 UIButtonConfiguration 只为消警告不值当
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  start.contentEdgeInsets = UIEdgeInsetsMake(9, 18, 9, 18);
#pragma clang diagnostic pop
  [start addTarget:self action:@selector(newChat) forControlEvents:UIControlEventTouchUpInside];

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_emptyTitle, _emptyDesc, start]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 10;
  [stack setCustomSpacing:20 afterView:_emptyDesc];
  [_emptyView addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [_emptyView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_emptyView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
    [stack.centerXAnchor constraintEqualToAnchor:_emptyView.centerXAnchor],
    [stack.topAnchor constraintEqualToAnchor:_emptyView.topAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:_emptyView.bottomAnchor],
    [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_emptyView.leadingAnchor constant:40],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:_emptyView.trailingAnchor constant:-40],
  ]];
}

#pragma mark - 数据

- (void)reload {
  self.items = [[DSBoxService shared] allConversations];
  // 置顶优先，再按更新时间倒序（与 Web 版一致）
  self.items = [self.items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    BOOL pa = [a[@"pinned"] boolValue], pb = [b[@"pinned"] boolValue];
    if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
    return [b[@"updatedAt"] compare:a[@"updatedAt"]];
  }];
  [self applyFilter:[self currentQuery]];
}

- (void)applyFilter:(NSString *)query {
  if (query.length == 0) {
    self.filtered = self.items;
  } else {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *c in self.items) {
      NSString *hay = [NSString stringWithFormat:@"%@ %@", c[@"title"] ?: @"", c[@"preview"] ?: @""];
      if ([hay localizedCaseInsensitiveContainsString:query]) [out addObject:c];
    }
    self.filtered = out;
  }
  [self rebuildSections];
  [self updateEmptyState];
  [self.collectionView reloadData];
}

/// 按官方分组：置顶 / 今天 / 昨天 / 7 天内 / 30 天内 / 更早
- (void)rebuildSections {
  NSMutableArray *pinned = [NSMutableArray array];
  NSMutableArray *today = [NSMutableArray array];
  NSMutableArray *yesterday = [NSMutableArray array];
  NSMutableArray *week = [NSMutableArray array];
  NSMutableArray *month = [NSMutableArray array];
  NSMutableArray *earlier = [NSMutableArray array];

  NSCalendar *cal = NSCalendar.currentCalendar;
  NSDate *now = NSDate.date;
  NSDate *startOfToday = [cal startOfDayForDate:now];
  NSDate *startOfYesterday = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:startOfToday options:0];
  NSDate *startOf7 = [cal dateByAddingUnit:NSCalendarUnitDay value:-7 toDate:startOfToday options:0];
  NSDate *startOf30 = [cal dateByAddingUnit:NSCalendarUnitDay value:-30 toDate:startOfToday options:0];

  for (NSDictionary *c in self.filtered) {
    if ([c[@"pinned"] boolValue]) {
      [pinned addObject:c];
      continue;
    }
    int64_t ms = [c[@"updatedAt"] longLongValue];
    NSDate *d = ms > 0 ? [NSDate dateWithTimeIntervalSince1970:ms / 1000.0] : startOf30;
    if ([d compare:startOfToday] != NSOrderedAscending) [today addObject:c];
    else if ([d compare:startOfYesterday] != NSOrderedAscending) [yesterday addObject:c];
    else if ([d compare:startOf7] != NSOrderedAscending) [week addObject:c];
    else if ([d compare:startOf30] != NSOrderedAscending) [month addObject:c];
    else [earlier addObject:c];
  }

  NSMutableArray *out = [NSMutableArray array];
  void (^push)(NSString *, NSArray *) = ^(NSString *title, NSArray *list) {
    if (list.count > 0) [out addObject:@{@"title": title, @"items": list}];
  };
  push(DSStrGroupPinned, pinned);
  push(DSStrGroupToday, today);
  push(DSStrGroupYesterday, yesterday);
  push(DSStrGroup7Days, week);
  push(DSStrGroup30Days, month);
  push(DSStrGroupEarlier, earlier);
  self.sections = out;
}

- (void)updateEmptyState {
  BOOL searching = [self currentQuery].length > 0;
  BOOL empty = self.filtered.count == 0;
  self.emptyView.hidden = !empty;
  self.collectionView.hidden = empty;
  if (searching) {
    _emptyTitle.text = DSStrSearchNoResult;
    _emptyDesc.text = @"";
  } else {
    _emptyTitle.text = DSStrSessionListEmptyTitle;
    _emptyDesc.text = DSStrSessionListEmptyDesc;
  }
}

/// 取第 indexPath 行对应的会话。越界返回 nil —— 删除后 collection view 还没刷新的
/// 那一帧里，回调用旧 indexPath 是可能的，不防会直接崩。
- (nullable NSDictionary *)conversationAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.section >= (NSInteger)self.sections.count) return nil;
  NSArray *list = self.sections[(NSUInteger)indexPath.section][@"items"];
  if (indexPath.item >= (NSInteger)list.count) return nil;
  return list[(NSUInteger)indexPath.item];
}

#pragma mark - 操作

- (void)newChat {
  if (self.onNewChat) { self.onNewChat(); return; }
  NSDictionary *conv = [[DSBoxService shared] createConversation];
  [self reload];
  DSChatViewController *chat = [[DSChatViewController alloc] initWithConversationId:conv[@"id"]];
  [self.navigationController pushViewController:chat animated:YES];
}

- (void)openSettings {
  if (self.onOpenSettings) { self.onOpenSettings(); return; }
  DSSettingsViewController *vc = [[DSSettingsViewController alloc] init];
  [self.navigationController pushViewController:vc animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
  [self applyFilter:searchController.searchBar.text ?: @""];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
  return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
  return [(NSArray *)self.sections[(NSUInteger)section][@"items"] count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
  DSSessionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellID
                                                                 forIndexPath:indexPath];
  NSDictionary *c = [self conversationAtIndexPath:indexPath];
  NSString *title = [c[@"title"] length] ? c[@"title"] : DSStrNewChatTitle;
  [cell configureTitle:title preview:c[@"preview"] pinned:[c[@"pinned"] boolValue]];

  // 「…」的点击落到哪个会话，在 configure 时就把上下文绑好 ——
  // 不再靠点击位置反查 indexPath：collection view 的 cell 会复用，
  // 反查拿到的行和真正点的那一行不一定是一回事。
  // cell 用 weak 捕获：block 存在 cell 自己身上，强捕获就是自引用环。
  __weak __typeof(self) ws = self;
  __weak DSSessionCell *weakCell = cell;
  cell.onMore = ^{
    __typeof(self) ss = ws;
    if (!ss) return;
    [ss presentMenuForConversation:c sourceView:weakCell ?: ss.view];
  };
  return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
  if (![kind isEqualToString:UICollectionElementKindSectionHeader]) return nil;
  DSSessionSectionHeaderView *h =
      [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                          withReuseIdentifier:kHeaderID
                                                 forIndexPath:indexPath];
  if (indexPath.section < (NSInteger)self.sections.count) {
    h.title = self.sections[(NSUInteger)indexPath.section][@"title"];
  }
  return h;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView
    didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
  [collectionView deselectItemAtIndexPath:indexPath animated:YES];
  NSDictionary *c = [self conversationAtIndexPath:indexPath];
  if (!c) return;
  if (self.onSelectConversation) { self.onSelectConversation(c[@"id"]); return; }
  DSChatViewController *chat = [[DSChatViewController alloc] initWithConversationId:c[@"id"]];
  [self.navigationController pushViewController:chat animated:YES];
}

- (UISwipeActionsConfiguration *)collectionView:(UICollectionView *)collectionView
                                         layout:(UICollectionViewLayout *)layout
    trailingSwipeActionsConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath {
  NSDictionary *c = [self conversationAtIndexPath:indexPath];
  if (!c) return nil;

  __weak __typeof(self) ws = self;
  UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
      title:DSStrDeleteSession handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
    [ws deleteConversation:c];
    completion(YES);
  }];

  UIContextualAction *pin = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
      title:[c[@"pinned"] boolValue] ? DSStrUnpinSession : DSStrPinSession
      handler:^(UIContextualAction *a, UIView *s, void (^done)(BOOL)) {
    [ws togglePin:c];
    done(YES);
  }];
  pin.backgroundColor = [DSTheme labelTertiary];
  return [UISwipeActionsConfiguration configurationWithActions:@[del, pin]];
}

/// 长按出菜单。官方也有这套（`ContextMenuGestureDelegate`），不是只有「…」一条路。
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath
                                         point:(CGPoint)point {
  NSDictionary *c = [self conversationAtIndexPath:indexPath];
  if (!c) return nil;
  __weak __typeof(self) ws = self;
  return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                 previewProvider:nil
                                                  actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
    BOOL pinned = [c[@"pinned"] boolValue];
    UIAction *pin = [UIAction actionWithTitle:(pinned ? DSStrUnpinSession : DSStrPinSession)
                                       image:[DSIcon image:pinned ? DSIconUnpin : DSIconPin
                                                      size:DSIconPointSizeAction]
                                  identifier:nil
                                     handler:^(UIAction *a) { [ws togglePin:c]; }];
    UIAction *rename = [UIAction actionWithTitle:DSStrRenameSession
                                          image:[DSIcon image:DSIconEdit size:DSIconPointSizeAction]
                                     identifier:nil
                                        handler:^(UIAction *a) { [ws promptRename:c]; }];
    UIAction *del = [UIAction actionWithTitle:DSStrDeleteSession
                                       image:[DSIcon image:DSIconTrash size:DSIconPointSizeAction]
                                  identifier:nil
                                     handler:^(UIAction *a) { [ws confirmDelete:c]; }];
    del.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:@"" children:@[pin, rename, del]];
  }];
}

#pragma mark - 单条会话的「…」菜单

- (void)presentMenuForConversation:(NSDictionary *)c sourceView:(UIView *)src {
  BOOL pinned = [c[@"pinned"] boolValue];
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
  __weak __typeof(self) ws = self;

  [sheet addAction:[UIAlertAction actionWithTitle:(pinned ? DSStrUnpinSession : DSStrPinSession)
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *a) { [ws togglePin:c]; }]];

  [sheet addAction:[UIAlertAction actionWithTitle:DSStrRenameSession
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *a) { [ws promptRename:c]; }]];

  [sheet addAction:[UIAlertAction actionWithTitle:DSStrDeleteSession
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction *a) { [ws confirmDelete:c]; }]];

  [sheet addAction:[UIAlertAction actionWithTitle:DSStrCancel
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  // iPad 上 actionSheet 必须给锚点，否则 present 直接抛异常。
  sheet.popoverPresentationController.sourceView = src;
  sheet.popoverPresentationController.sourceRect = src.bounds;
  [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 三个具体动作（菜单、侧滑、长按共用）

- (void)togglePin:(NSDictionary *)c {
  BOOL pinned = [c[@"pinned"] boolValue];
  NSError *e = nil;
  [[DSBoxService shared] updateConversation:c[@"id"] patch:@{@"pinned": @(!pinned)} error:&e];
  [self reload];
}

- (void)deleteConversation:(NSDictionary *)c {
  NSError *e = nil;
  [[DSBoxService shared] deleteConversation:c[@"id"] error:&e];
  [self reload];
  // 删的如果是当前正在看的那条，容器得换一个会话，否则聊天页悬空
  if (self.onConversationDeleted) self.onConversationDeleted(c[@"id"]);
}

- (void)promptRename:(NSDictionary *)c {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:DSStrRenameSessionTitle
                                                             message:nil
                                                      preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.text = [c[@"title"] isKindOfClass:NSString.class] ? c[@"title"] : @"";
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.returnKeyType = UIReturnKeyDone;
  }];
  __weak __typeof(self) ws = self;
  [a addAction:[UIAlertAction actionWithTitle:DSStrCancel style:UIAlertActionStyleCancel handler:nil]];
  [a addAction:[UIAlertAction actionWithTitle:DSStrOK style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
    NSString *t = a.textFields.firstObject.text ?: @"";
    t = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return;                     // 空标题不写库，保持原名
    NSError *e = nil;
    [[DSBoxService shared] updateConversation:c[@"id"] patch:@{@"title": t} error:&e];
    [ws reload];
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmDelete:(NSDictionary *)c {
  NSString *msg = [NSString stringWithFormat:@"%@\n%@", DSStrDeleteSessionModal, DSStrDeleteSessionDesc];
  UIAlertController *a = [UIAlertController alertControllerWithTitle:DSStrDeleteSession
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
  __weak __typeof(self) ws = self;
  [a addAction:[UIAlertAction actionWithTitle:DSStrCancel style:UIAlertActionStyleCancel handler:nil]];
  [a addAction:[UIAlertAction actionWithTitle:DSStrDeleteSession
                                        style:UIAlertActionStyleDestructive
                                      handler:^(UIAlertAction *x) { [ws deleteConversation:c]; }]];
  [self presentViewController:a animated:YES completion:nil];
}

@end
