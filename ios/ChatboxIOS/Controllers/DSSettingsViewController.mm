#import "DSSettingsViewController.h"
#import "DSBoxService.h"
#import "DSStrings.h"

@interface DSSettingsViewController ()
@property (nonatomic, strong) NSDictionary *settings;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@end

@implementation DSSettingsViewController

/// 模型 id → 展示名。
/// 官方 2.7.1 已取消「快速/专家/识图」三档，这里直接显示 API 模型名，不再套旧叫法。
- (NSString *)displayNameForModel:(NSString *)model {
  if (model.length == 0) return @"-";
  return model;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"设置";
  [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"s"];
  self.tableView.tableFooterView = [UIView new];
  [self reload];
}

- (void)reload {
  self.settings = [[DSBoxService shared] settings];
  self.sectionTitles = @[@"API Key", @"模型与对话", @"本地工具", @"语音", @"数据"];
  [self.tableView reloadData];
}

#pragma mark - 表格
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sectionTitles.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  return self.sectionTitles[section];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case 0: return 3;   // 状态 / 设置 Key / 清除
    case 1: return 6;   // 模型 / 思考 / 强度 / 上下文 / 温度 / 系统提示
    case 2: return 3;   // 本地工具 / 工具数 / 余额
    case 3: return 2;   // TTS 音色 / ASR 说明
    case 4: return 2;   // 导出 / 导入
    default: return 0;
  }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"s" forIndexPath:indexPath];
  cell.accessoryType = UITableViewCellAccessoryNone;
  NSDictionary *s = self.settings;

  if (indexPath.section == 0) {
    if (indexPath.row == 0) {
      BOOL has = [[DSBoxService shared] hasStoredKey];
      cell.textLabel.text = @"状态";
      cell.detailTextLabel.text = has
        ? ([NSString stringWithFormat:@"已加密保存（%@）%@", [DSBoxService shared].keyPreview,
            [[DSBoxService shared] isUnlocked] ? @"· 已解锁" : @"· 未解锁"])
        : @"未设置";
    } else if (indexPath.row == 1) {
      cell.textLabel.text = @"设置 / 更换 API Key";
      cell.detailTextLabel.text = nil;
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
      cell.textLabel.text = @"清除 Key";
      cell.textLabel.textColor = UIColor.systemRedColor;
    }
  } else if (indexPath.section == 1) {
    switch (indexPath.row) {
      case 0:
        cell.textLabel.text = @"模型";
        cell.detailTextLabel.text = [self displayNameForModel:s[@"model"]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        break;
      case 1: {
        cell.textLabel.text = @"思考模式";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [s[@"thinking"] boolValue];
        [sw addTarget:self action:@selector(toggleThinking:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        break;
      }
      case 2: {
        cell.textLabel.text = @"思考强度";
        cell.detailTextLabel.text = s[@"effort"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        break;
      }
      case 3: {
        cell.textLabel.text = @"上下文限制";
        NSNumber *limit = s[@"contextLimit"];
        cell.detailTextLabel.text = limit && limit.integerValue > 0
          ? [NSString stringWithFormat:@"%@ tokens", limit] : @"自动";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        break;
      }
      case 4: {
        cell.textLabel.text = @"温度";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", s[@"temperature"] ?: @1];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        break;
      }
      default:
        cell.textLabel.text = @"系统提示词";
        cell.detailTextLabel.text = [s[@"systemPrompt"] length] ? @"已设置" : @"无";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        break;
    }
  } else if (indexPath.section == 2) {
    if (indexPath.row == 0) {
      cell.textLabel.text = @"启用本地工具";
      UISwitch *sw = [[UISwitch alloc] init];
      sw.on = [s[@"localTools"] boolValue];
      [sw addTarget:self action:@selector(toggleTools:) forControlEvents:UIControlEventValueChanged];
      cell.accessoryView = sw;
    } else if (indexPath.row == 1) {
      cell.textLabel.text = @"内置工具数";
      cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu",
          (unsigned long)[[DSBoxService shared] toolDefinitions].count];
    } else {
      cell.textLabel.text = @"查询账户余额";
      cell.detailTextLabel.text = nil;
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
  } else if (indexPath.section == 3) {
    if (indexPath.row == 0) {
      cell.textLabel.text = @"TTS 音色";
      cell.detailTextLabel.text = s[@"ttsVoice"];
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
      cell.textLabel.text = @"语音识别 (ASR)";
      cell.detailTextLabel.text = @"长按输入框使用";
    }
  } else {
    cell.textLabel.text = indexPath.row == 0 ? @"导出数据快照" : @"导入数据快照";
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  }
  cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
  return cell;
}

#pragma mark - 交互
- (void)toggleThinking:(UISwitch *)sw {
  [[DSBoxService shared] saveSettingsPatch:@{@"thinking": @(sw.on)}];
}
- (void)toggleTools:(UISwitch *)sw {
  [[DSBoxService shared] saveSettingsPatch:@{@"localTools": @(sw.on)}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (indexPath.section == 0 && indexPath.row == 1) [self setupKey];
  else if (indexPath.section == 0 && indexPath.row == 2) [self clearKey];
  else if (indexPath.section == 1 && indexPath.row == 0) [self pickModel];
  else if (indexPath.section == 1 && indexPath.row == 2) [self pickEffort];
  else if (indexPath.section == 1 && indexPath.row == 3) [self inputContextLimit];
  else if (indexPath.section == 1 && indexPath.row == 4) [self inputTemperature];
  else if (indexPath.section == 1 && indexPath.row == 5) [self inputSystemPrompt];
  else if (indexPath.section == 2 && indexPath.row == 2) [self showBalance];
  else if (indexPath.section == 4 && indexPath.row == 0) [self exportData];
  else if (indexPath.section == 4 && indexPath.row == 1) [self importData];
}

- (void)setupKey {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:@"设置 API Key"
      message:@"Key 用 PIN 加密存在本机，PIN 不落盘" preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"sk-..."; }];
  [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.placeholder = @"PIN（至少 4 位）"; tf.secureTextEntry = YES;
  }];
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
  __weak __typeof(self) weakSelf = self;
  [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
    NSError *err = nil;
    BOOL ok = [[DSBoxService shared] setApiKey:a.textFields[0].text pin:a.textFields[1].text error:&err];
    if (!ok) [weakSelf alert:@"保存失败" message:err.localizedDescription];
    [weakSelf reload];
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)clearKey {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清除 Key"
      message:@"确定删除本机保存的 API Key？" preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
  __weak __typeof(self) weakSelf = self;
  [a addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
    [[DSBoxService shared] clearStoredKey];
    [weakSelf reload];
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)pickModel {
  NSArray *models = [[DSBoxService shared] listModelsWithError:nil];
  NSMutableArray *names = [NSMutableArray arrayWithObject:self.settings[@"model"] ?: @"deepseek-chat"];
  for (NSDictionary *m in models) if (m[@"id"] && ![names containsObject:m[@"id"]]) [names addObject:m[@"id"]];
  [self showPicker:@"选择模型" items:names selected:self.settings[@"model"] key:@"model"];
}

- (void)pickEffort {
  [self showPicker:@"思考强度" items:@[@"low", @"high", @"max"]
          selected:self.settings[@"effort"] key:@"effort"];
}

- (void)showPicker:(NSString *)title items:(NSArray *)items selected:(NSString *)selected key:(NSString *)key {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil
      preferredStyle:UIAlertControllerStyleActionSheet];
  for (NSString *item in items) {
    [a addAction:[UIAlertAction actionWithTitle:item
        style:[item isEqualToString:selected] ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
        handler:^(UIAlertAction *act) {
          [[DSBoxService shared] saveSettingsPatch:@{key: item}];
          [self reload];
        }]];
  }
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
  a.popoverPresentationController.sourceView = self.tableView;
  [self presentViewController:a animated:YES completion:nil];
}

- (void)inputContextLimit {
  [self inputNumber:@"上下文限制（tokens，0=自动）" key:@"contextLimit"
           current:self.settings[@"contextLimit"]];
}
- (void)inputTemperature {
  [self inputNumber:@"温度（0-2）" key:@"temperature" current:self.settings[@"temperature"]];
}
- (void)inputNumber:(NSString *)title key:(NSString *)key current:(id)current {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil
      preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.text = [current description] ?: @"0"; tf.keyboardType = UIKeyboardTypeDecimalPad;
  }];
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
  __weak __typeof(self) weakSelf = self;
  [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
    double v = [a.textFields.firstObject.text doubleValue];
    [[DSBoxService shared] saveSettingsPatch:@{key: @(v)}];
    [weakSelf reload];
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)inputSystemPrompt {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:@"系统提示词" message:nil
      preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = self.settings[@"systemPrompt"] ?: @""; }];
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
  __weak __typeof(self) weakSelf = self;
  [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
    [[DSBoxService shared] saveSettingsPatch:@{@"systemPrompt": a.textFields.firstObject.text ?: @""}];
    [weakSelf reload];
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)showBalance {
  NSError *err = nil;
  NSDictionary *b = [[DSBoxService shared] getBalanceWithError:&err];
  if (err) { [self alert:@"查询失败" message:err.localizedDescription]; return; }
  [self alert:@"账户余额" message:b.description];
}

- (void)exportData {
  NSDictionary *snap = [[DSBoxService shared] exportSnapshot];
  NSData *data = [NSJSONSerialization dataWithJSONObject:snap options:NSJSONWritingPrettyPrinted error:nil];
  NSString *path = [[DSBoxService shared].documentsPath stringByAppendingPathComponent:@"chatbox-snapshot.json"];
  NSURL *url = [NSURL fileURLWithPath:path];
  [data writeToURL:url atomically:YES];
  UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
  vc.popoverPresentationController.sourceView = self.tableView;
  [self presentViewController:vc animated:YES completion:nil];
}

- (void)importData {
  [self alert:@"导入数据" message:@"请用「文件」App 打开 .json 快照后分享到本应用（后续版本提供文件选择器）"];
}

- (void)alert:(NSString *)title message:(NSString *)message {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
      preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:a animated:YES completion:nil];
}

@end
