//
//  DSConversationListController.m
//  ChatboxIOS
//
//  对齐官方会话列表：按「置顶 / 今天 / 昨天 / 7 天内 / 30 天内 / 更早」分组，
//  空态给标题 + 说明 + 「开启新对话」入口（对应 SessionListEmptyView）。
//

#import "DSConversationListController.h"
#import "DSBoxService.h"
#import "DSChatViewController.h"
#import "DSSettingsViewController.h"
#import "DSTheme.h"
#import "DSStrings.h"

@interface DSConversationListController () <UITableViewDataSource, UITableViewDelegate,
    UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;    // 全量
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered; // 过滤后
@property (nonatomic, strong) NSArray<NSDictionary *> *sections; // {title, items}
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyTitle;
@property (nonatomic, strong) UILabel *emptyDesc;
@end

@implementation DSConversationListController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"DeepSeek Chatbox";
  self.view.backgroundColor = [DSTheme bgBase];

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

  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = 64;
  self.tableView.backgroundColor = [DSTheme bgBase];
  self.tableView.separatorInset = UIEdgeInsetsMake(0, [DSTheme messageListPadding], 0, 0);
  self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  [self.view addSubview:self.tableView];

  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  ]];

  [self buildEmptyView];
  [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setNavigationBarHidden:NO animated:animated];
  [self reload];
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
  [self applyFilter:self.search.searchBar.text ?: @""];
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
  [self.tableView reloadData];
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
  BOOL searching = (self.search.searchBar.text ?: @"").length > 0;
  BOOL empty = self.filtered.count == 0;
  self.emptyView.hidden = !empty;
  self.tableView.hidden = empty;
  if (searching) {
    _emptyTitle.text = DSStrSearchNoResult;
    _emptyDesc.text = @"";
  } else {
    _emptyTitle.text = DSStrSessionListEmptyTitle;
    _emptyDesc.text = DSStrSessionListEmptyDesc;
  }
}

#pragma mark - 操作

- (void)newChat {
  NSDictionary *conv = [[DSBoxService shared] createConversation];
  [self reload];
  DSChatViewController *chat = [[DSChatViewController alloc] initWithConversationId:conv[@"id"]];
  [self.navigationController pushViewController:chat animated:YES];
}

- (void)openSettings {
  DSSettingsViewController *vc = [[DSSettingsViewController alloc] init];
  [self.navigationController pushViewController:vc animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
  [self applyFilter:searchController.searchBar.text ?: @""];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  return self.sections[section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return [(NSArray *)self.sections[section][@"items"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString *const kCell = @"session";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCell];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCell];
    cell.backgroundColor = [DSTheme bgBase];
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    cell.textLabel.textColor = [DSTheme labelPrimary];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.textColor = [DSTheme labelTertiary];
  }
  NSArray *list = self.sections[indexPath.section][@"items"];
  NSDictionary *c = list[indexPath.row];
  cell.textLabel.text = [c[@"title"] length] ? c[@"title"] : DSStrNewChatTitle;
  cell.detailTextLabel.text = c[@"preview"];
  cell.detailTextLabel.numberOfLines = 1;
  cell.accessoryType = UITableViewCellAccessoryNone;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSArray *list = self.sections[indexPath.section][@"items"];
  NSDictionary *c = list[indexPath.row];
  DSChatViewController *chat = [[DSChatViewController alloc] initWithConversationId:c[@"id"]];
  [self.navigationController pushViewController:chat animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSArray *list = self.sections[indexPath.section][@"items"];
  NSDictionary *c = list[indexPath.row];

  __weak __typeof(self) weakSelf = self;
  UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
      title:DSStrDeleteSession handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
    NSError *err = nil;
    BOOL ok = [[DSBoxService shared] deleteConversation:c[@"id"] error:&err];
    if (!ok) {
      UIAlertController *a = [UIAlertController alertControllerWithTitle:err.localizedDescription
          message:nil preferredStyle:UIAlertControllerStyleAlert];
      [a addAction:[UIAlertAction actionWithTitle:DSStrOK style:UIAlertActionStyleDefault handler:nil]];
      [weakSelf presentViewController:a animated:YES completion:nil];
    }
    [weakSelf reload];
    completion(YES);
  }];

  UIContextualAction *pin = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
      title:[c[@"pinned"] boolValue] ? DSStrUnpinSession : DSStrPinSession
      handler:^(UIContextualAction *a, UIView *s, void (^done)(BOOL)) {
    NSError *e = nil;
    [[DSBoxService shared] updateConversation:c[@"id"]
                                        patch:@{@"pinned": @(![c[@"pinned"] boolValue])}
                                        error:&e];
    [weakSelf reload];
    done(YES);
  }];
  pin.backgroundColor = [DSTheme labelTertiary];
  return [UISwipeActionsConfiguration configurationWithActions:@[del, pin]];
}

@end
