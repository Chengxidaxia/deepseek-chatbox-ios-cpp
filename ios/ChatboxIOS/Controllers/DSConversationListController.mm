#import "DSConversationListController.h"
#import "DSBoxService.h"
#import "DSChatViewController.h"
#import "DSSettingsViewController.h"

@interface DSConversationListController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;   // 全量
@property (nonatomic, strong) NSArray<NSDictionary *> *visible; // 过滤后
@property (nonatomic, strong) UISearchController *search;
@end

@implementation DSConversationListController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"DeepSeek Chatbox";
  self.view.backgroundColor = UIColor.systemBackgroundColor;

  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"设置"
      style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
      target:self action:@selector(newChat)];

  self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
  self.search.searchResultsUpdater = self;
  self.search.obscuresBackgroundDuringPresentation = NO;
  self.navigationItem.searchController = self.search;
  self.definesPresentationContext = YES;

  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
  self.tableView.rowHeight = 72;
  [self.view addSubview:self.tableView];
  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  ]];
  [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self reload];
}

- (void)reload {
  self.items = [[DSBoxService shared] allConversations];
  // 置顶优先，再按更新时间倒序（与 Web 版一致）
  self.items = [self.items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    BOOL pa = [a[@"pinned"] boolValue], pb = [b[@"pinned"] boolValue];
    if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
    return [b[@"updatedAt"] compare:a[@"updatedAt"]];
  }];
  NSString *q = self.search.searchBar.text ?: @"";
  [self applyFilter:q];
}

- (void)applyFilter:(NSString *)query {
  if (query.length == 0) self.visible = self.items;
  else {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *c in self.items) {
      NSString *hay = [NSString stringWithFormat:@"%@ %@", c[@"title"] ?: @"", c[@"preview"] ?: @""];
      if ([hay localizedCaseInsensitiveContainsString:query]) [out addObject:c];
    }
    self.visible = out;
  }
  [self.tableView reloadData];
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

#pragma mark - 搜索
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
  [self applyFilter:searchController.searchBar.text ?: @""];
}

#pragma mark - 表格
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.visible.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
  NSDictionary *c = self.visible[indexPath.row];
  cell.textLabel.text = [c[@"title"] length] ? c[@"title"] : @"新对话";
  cell.detailTextLabel.text = c[@"preview"];
  cell.detailTextLabel.numberOfLines = 1;
  cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
  cell.accessoryType = [c[@"pinned"] boolValue] ? UITableViewCellAccessoryDetailDisclosureButton
                                                : UITableViewCellAccessoryDisclosureIndicator;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSDictionary *c = self.visible[indexPath.row];
  DSChatViewController *chat = [[DSChatViewController alloc] initWithConversationId:c[@"id"]];
  [self.navigationController pushViewController:chat animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSDictionary *c = self.visible[indexPath.row];
  UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
      title:@"删除" handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
    NSError *err = nil;
    BOOL ok = [[DSBoxService shared] deleteConversation:c[@"id"] error:&err];
    if (!ok) {
      UIAlertController *a = [UIAlertController alertControllerWithTitle:@"删除失败"
          message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
      [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
      [self presentViewController:a animated:YES completion:nil];
    }
    [self reload];
    completion(YES);
  }];
  __weak typeof(self) weakSelf = self;
  UIContextualAction *pin = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
      title:[c[@"pinned"] boolValue] ? @"取消置顶" : @"置顶" handler:^(UIContextualAction *a, UIView *s, void (^done)(BOOL)) {
    NSError *e = nil;
    [[DSBoxService shared] updateConversation:c[@"id"]
        patch:@{@"pinned": @(![c[@"pinned"] boolValue])} error:&e];
    [weakSelf reload];
    done(YES);
  }];
  return [UISwipeActionsConfiguration configurationWithActions:@[del, pin]];
}

@end
