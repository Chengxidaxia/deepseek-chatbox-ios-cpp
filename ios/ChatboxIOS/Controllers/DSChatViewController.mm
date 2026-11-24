#import "DSChatViewController.h"
#import "DSBoxService.h"
#import "DSMessageCell.h"

@interface DSChatViewController () <UITableViewDataSource, UITableViewDelegate,
    UITextViewDelegate, DSBoxChatDelegate>
@property (nonatomic, copy) NSString *convId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *messages;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UIButton *sendBtn;
@property (nonatomic, strong) UIButton *stopBtn;
@property (nonatomic, assign) BOOL streaming;
// 当前流式助手消息（累积增量）
@property (nonatomic, strong) NSMutableDictionary *streamMsg;
@property (nonatomic, strong) NSIndexPath *streamIndexPath;
@end

@implementation DSChatViewController

- (instancetype)initWithConversationId:(NSString *)convId {
  if (self = [super init]) {
    _convId = [convId copy];
    NSArray *msgs = [[DSBoxService shared] messagesOfConversation:convId];
    _messages = [NSMutableArray array];
    for (NSDictionary *m in msgs) [_messages addObject:[m mutableCopy]];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  NSDictionary *conv = [[DSBoxService shared] conversationWithId:self.convId];
  self.title = [conv[@"title"] length] ? conv[@"title"] : @"新对话";
  self.view.backgroundColor = UIColor.systemBackgroundColor;

  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 80;
  self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  [self.tableView registerClass:DSMessageCell.class forCellReuseIdentifier:@"msg"];
  [self.view addSubview:self.tableView];

  UIView *bar = [[UIView alloc] init];
  bar.translatesAutoresizingMaskIntoConstraints = NO;
  bar.backgroundColor = UIColor.secondarySystemBackgroundColor;
  [self.view addSubview:bar];

  self.input = [[UITextView alloc] init];
  self.input.translatesAutoresizingMaskIntoConstraints = NO;
  self.input.font = [UIFont systemFontOfSize:16];
  self.input.backgroundColor = UIColor.tertiarySystemBackgroundColor;
  self.input.layer.cornerRadius = 8;
  self.input.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
  self.input.delegate = self;
  [bar addSubview:self.input];

  self.sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  self.sendBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [self.sendBtn setTitle:@"发送" forState:UIControlStateNormal];
  [self.sendBtn addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
  [bar addSubview:self.sendBtn];

  self.stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  self.stopBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [self.stopBtn setTitle:@"停止" forState:UIControlStateNormal];
  [self.stopBtn addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
  self.stopBtn.hidden = YES;
  [bar addSubview:self.stopBtn];

  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:bar.topAnchor],
    [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    [self.input.topAnchor constraintEqualToAnchor:bar.topAnchor constant:8],
    [self.input.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
    [self.input.trailingAnchor constraintEqualToAnchor:self.sendBtn.leadingAnchor constant:-8],
    [self.input.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-8],
    [self.input.heightAnchor constraintGreaterThanOrEqualToConstant:40],
    [self.input.heightAnchor constraintLessThanOrEqualToConstant:120],
    [self.sendBtn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
    [self.sendBtn.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
    [self.stopBtn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
    [self.stopBtn.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
  ]];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardUp:)
      name:UIKeyboardWillShowNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDown:)
      name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)keyboardUp:(NSNotification *)n {
  CGRect r = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  self.view.transform = CGAffineTransformMakeTranslation(0, -r.size.height);
}
- (void)keyboardDown:(NSNotification *)n { self.view.transform = CGAffineTransformIdentity; }

#pragma mark - 发送 / 停止
- (void)send {
  NSString *text = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length == 0 || self.streaming) return;

  // 先落库 user 消息
  NSDictionary *saved = [[DSBoxService shared] appendMessage:@{@"role": @"user", @"content": text}
                                               toConversation:self.convId];
  [self.messages addObject:[saved mutableCopy]];
  self.input.text = @"";
  [self scrollBottom];

  // 若 Key 未解锁，弹 PIN
  if (![[DSBoxService shared] isUnlocked]) {
    [self promptPinThenStart];
    return;
  }
  [self startStream];
}

- (void)promptPinThenStart {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:@"解锁 API Key"
      message:@"输入 PIN 以解锁本机加密保存的 Key" preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.placeholder = @"PIN"; tf.secureTextEntry = YES;
  }];
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
  __weak __typeof(self) weakSelf = self;
  [a addAction:[UIAlertAction actionWithTitle:@"解锁并发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
    NSError *err = nil;
    BOOL ok = [[DSBoxService shared] unlockWithPin:a.textFields.firstObject.text error:&err];
    if (ok) [weakSelf startStream];
    else {
      UIAlertController *bad = [UIAlertController alertControllerWithTitle:@"解锁失败"
          message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
      [bad addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
      [weakSelf presentViewController:bad animated:YES completion:nil];
    }
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)startStream {
  self.streaming = YES;
  self.sendBtn.hidden = YES;
  self.stopBtn.hidden = NO;

  // 先插入一条空的助手消息用于流式填充
  NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:@{
    @"role": @"assistant", @"content": @"", @"reasoning": @"", @"streaming": @YES,
  }];
  [self.messages addObject:m];
  self.streamMsg = m;
  [self.tableView reloadData];
  [self scrollBottom];

  NSError *err = nil;
  if (![[DSBoxService shared] streamChatWithConversation:self.convId delegate:self error:&err]) {
    [self finishWithError:err];
  }
}

- (void)stop {
  [[DSBoxService shared] stopStream];
  [self finishWithError:nil];
}

- (void)finishWithError:(NSError *)error {
  self.streaming = NO;
  self.sendBtn.hidden = NO;
  self.stopBtn.hidden = YES;
  self.streamMsg[@"streaming"] = @NO;
  self.streamMsg = nil;
  [self.tableView reloadData];
  if (error) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"请求失败"
        message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
  }
}

#pragma mark - DSBoxChatDelegate（已从 C++ 回调切到主线程）
- (void)dsboxDidReceiveEvent:(DSBoxStreamEventType)type
                        text:(NSString *)text
                        data:(NSDictionary *)data {
  switch (type) {
    case DSBoxStreamEventContent:
      [self appendText:text ?: @"" toKey:@"content"];
      break;
    case DSBoxStreamEventReasoning:
      [self appendText:text ?: @"" toKey:@"reasoning"];
      break;
    case DSBoxStreamEventUsage:
      self.streamMsg[@"prompt_tokens"] = data[@"prompt_tokens"] ?: data[@"prompt"];
      self.streamMsg[@"completion_tokens"] = data[@"completion_tokens"] ?: data[@"completion"];
      [self refreshStreamCell];
      break;
    case DSBoxStreamEventTitle:
      self.title = text ?: self.title;
      break;
    case DSBoxStreamEventError:
      break;  // 由 didFinishWithError 处理
    case DSBoxStreamEventDone:
      break;
    default:
      break;
  }
}

- (void)appendText:(NSString *)text toKey:(NSString *)key {
  NSString *old = self.streamMsg[key] ?: @"";
  self.streamMsg[key] = [old stringByAppendingString:text];
  [self refreshStreamCell];
}

- (void)refreshStreamCell {
  NSInteger row = self.messages.count - 1;
  if (row < 0) return;
  NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:0];
  [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
  [self scrollBottom];
}

- (void)dsboxDidFinishWithError:(NSError *)error {
  // 落库流式结果
  if (self.streamMsg) {
    [[DSBoxService shared] appendMessage:self.streamMsg toConversation:self.convId];
  }
  [self finishWithError:error];
}

- (void)scrollBottom {
  if (self.messages.count == 0) return;
  NSIndexPath *ip = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
  [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:NO];
}

#pragma mark - 表格
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  DSMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"msg" forIndexPath:indexPath];
  [cell configure:self.messages[indexPath.row]];
  return cell;
}

@end
