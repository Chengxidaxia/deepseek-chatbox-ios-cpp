//
//  DSChatViewController.m
//  ChatboxIOS
//
//  输入区对齐官方（InputAreaView）：左侧「+」附件、中间圆角输入框、右侧发送/停止圆钮。
//  消息按官方 Fragment 顺序渲染（见 DSMessageCell）。
//

#import "DSChatViewController.h"
#import "DSBoxService.h"
#import "DSMessageCell.h"
#import "DSTheme.h"
#import "DSStrings.h"

@interface DSChatViewController () <UITableViewDataSource, UITableViewDelegate,
    UITextViewDelegate, DSBoxChatDelegate, DSMessageCellDelegate>
@property (nonatomic, copy) NSString *convId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *messages;
@property (nonatomic, strong) UIView *composer;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) NSLayoutConstraint *composerBottom;
@property (nonatomic, assign) BOOL streaming;
@property (nonatomic, strong) NSMutableDictionary *streamMsg;
@end

@implementation DSChatViewController

- (instancetype)initWithConversationId:(NSString *)convId {
  if ((self = [super init])) {
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
  self.title = [conv[@"title"] length] ? conv[@"title"] : DSStrNewChatTitle;
  self.view.backgroundColor = [DSTheme bgBase];

  [self buildTableView];
  [self buildComposer];

  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.pencil"]
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(newChatHere)];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:)
      name:UIKeyboardWillChangeFrameNotification object:nil];
  [self scrollToBottomAnimated:NO];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - 视图

- (void)buildTableView {
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 96;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.backgroundColor = [DSTheme bgBase];
  self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
  [self.tableView registerClass:DSMessageCell.class forCellReuseIdentifier:@"msg"];
  [self.view addSubview:self.tableView];
}

- (void)buildComposer {
  _composer = [[UIView alloc] init];
  _composer.translatesAutoresizingMaskIntoConstraints = NO;
  _composer.backgroundColor = [DSTheme bgBase];
  [self.view addSubview:_composer];

  // 附件按钮
  _attachButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _attachButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_attachButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
  _attachButton.tintColor = [DSTheme labelSecondary];
  [_attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];

  // 输入框容器（圆角 + 描边）
  UIView *field = [[UIView alloc] init];
  field.translatesAutoresizingMaskIntoConstraints = NO;
  field.backgroundColor = [DSTheme bgLayer1];
  field.layer.cornerRadius = 20;
  field.layer.cornerCurve = kCACornerCurveContinuous;
  field.layer.borderWidth = 1;
  field.layer.borderColor = [DSTheme borderL2].CGColor;

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

  // 发送 / 停止
  _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_sendButton setImage:[UIImage systemImageNamed:@"arrow.up"] forState:UIControlStateNormal];
  _sendButton.tintColor = UIColor.whiteColor;
  _sendButton.backgroundColor = [DSTheme brand];
  _sendButton.layer.cornerRadius = 16;
  _sendButton.layer.cornerCurve = kCACornerCurveContinuous;
  _sendButton.enabled = NO;
  _sendButton.alpha = 0.4;
  [_sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];

  _stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_stopButton setImage:[UIImage systemImageNamed:@"stop.fill"] forState:UIControlStateNormal];
  _stopButton.tintColor = UIColor.whiteColor;
  _stopButton.backgroundColor = [DSTheme labelPrimary];
  _stopButton.layer.cornerRadius = 16;
  _stopButton.layer.cornerCurve = kCACornerCurveContinuous;
  _stopButton.hidden = YES;
  [_stopButton addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];

  [_composer addSubview:_attachButton];
  [_composer addSubview:field];
  [_composer addSubview:_sendButton];
  [_composer addSubview:_stopButton];

  _composerBottom = [_composer.bottomAnchor
      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];

  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:_composer.topAnchor],

    [_composer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_composer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    _composerBottom,

    [_attachButton.leadingAnchor constraintEqualToAnchor:_composer.leadingAnchor constant:8],
    [_attachButton.bottomAnchor constraintEqualToAnchor:field.bottomAnchor],
    [_attachButton.widthAnchor constraintEqualToConstant:34],
    [_attachButton.heightAnchor constraintEqualToConstant:34],

    [field.topAnchor constraintEqualToAnchor:_composer.topAnchor constant:8],
    [field.leadingAnchor constraintEqualToAnchor:_attachButton.trailingAnchor constant:2],
    [field.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-8],
    [field.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-8],
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:38],
    [field.heightAnchor constraintLessThanOrEqualToConstant:132],

    [_input.leadingAnchor constraintEqualToAnchor:field.leadingAnchor constant:4],
    [_input.trailingAnchor constraintEqualToAnchor:field.trailingAnchor constant:-4],
    [_input.topAnchor constraintEqualToAnchor:field.topAnchor constant:1],
    [_input.bottomAnchor constraintEqualToAnchor:field.bottomAnchor constant:-1],

    [_placeholder.leadingAnchor constraintEqualToAnchor:_input.leadingAnchor constant:10],
    [_placeholder.topAnchor constraintEqualToAnchor:_input.topAnchor constant:9],

    [_sendButton.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-14],
    [_sendButton.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-13],
    [_sendButton.widthAnchor constraintEqualToConstant:32],
    [_sendButton.heightAnchor constraintEqualToConstant:32],
    [_stopButton.centerXAnchor constraintEqualToAnchor:_sendButton.centerXAnchor],
    [_stopButton.centerYAnchor constraintEqualToAnchor:_sendButton.centerYAnchor],
    [_stopButton.widthAnchor constraintEqualToConstant:32],
    [_stopButton.heightAnchor constraintEqualToConstant:32],
  ]];
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
  if (text.length == 0 || self.streaming) return;

  NSDictionary *saved = [[DSBoxService shared] appendMessage:@{@"role": @"user", @"content": text}
                                             toConversation:self.convId];
  [self.messages addObject:[saved mutableCopy]];
  self.input.text = @"";
  [self updateSendState];
  [self.tableView reloadData];
  [self scrollToBottomAnimated:YES];

  if (![[DSBoxService shared] isUnlocked]) {
    [self promptUnlockThenStart];
    return;
  }
  [self startStream];
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
  __weak __typeof(self) weakSelf = self;
  [a addAction:[UIAlertAction actionWithTitle:DSStrConfirm
                                       style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
    NSError *err = nil;
    BOOL ok = [[DSBoxService shared] unlockWithPin:a.textFields.firstObject.text error:&err];
    if (ok) {
      [weakSelf startStream];
    } else {
      UIAlertController *bad = [UIAlertController alertControllerWithTitle:err.localizedDescription
          message:nil preferredStyle:UIAlertControllerStyleAlert];
      [bad addAction:[UIAlertAction actionWithTitle:DSStrOK style:UIAlertActionStyleDefault handler:nil]];
      [weakSelf presentViewController:bad animated:YES completion:nil];
    }
  }]];
  [self presentViewController:a animated:YES completion:nil];
}

- (void)startStream {
  self.streaming = YES;
  [self updateSendState];

  NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:@{
    @"role": @"assistant", @"content": @"", @"reasoning": @"", @"streaming": @YES,
  }];
  [self.messages addObject:m];
  self.streamMsg = m;
  [self.tableView reloadData];
  [self scrollToBottomAnimated:YES];

  NSError *err = nil;
  if (![[DSBoxService shared] streamChatWithConversation:self.convId delegate:self error:&err]) {
    [self finishWithError:err];
  }
}

- (void)stop {
  [[DSBoxService shared] stopStream];
  [self finishWithError:nil];
}

- (void)updateSendState {
  BOOL hasText = self.input.text.length > 0;
  self.placeholder.hidden = hasText;
  self.sendButton.hidden = self.streaming;
  self.stopButton.hidden = !self.streaming;
  self.sendButton.enabled = hasText && !self.streaming;
  self.sendButton.alpha = self.sendButton.enabled ? 1.0 : 0.4;
}

- (void)finishWithError:(NSError *)error {
  self.streaming = NO;
  self.streamMsg[@"streaming"] = @NO;
  self.streamMsg = nil;
  [self updateSendState];
  [self.tableView reloadData];
  if (error) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:error.localizedDescription
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:DSStrOK style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
  }
}

- (void)attachTapped {
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
      message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  [sheet addAction:[UIAlertAction actionWithTitle:DSStrUploadAlbum style:UIAlertActionStyleDefault handler:nil]];
  [sheet addAction:[UIAlertAction actionWithTitle:DSStrUploadCamera style:UIAlertActionStyleDefault handler:nil]];
  [sheet addAction:[UIAlertAction actionWithTitle:DSStrUploadFile style:UIAlertActionStyleDefault handler:nil]];
  [sheet addAction:[UIAlertAction actionWithTitle:DSStrCancel style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.sourceView = self.attachButton;
  sheet.popoverPresentationController.sourceRect = self.attachButton.bounds;
  [self presentViewController:sheet animated:YES completion:nil];
}

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
  switch (type) {
    case DSBoxStreamEventContent:
      [self appendText:text toKey:@"content"];
      break;
    case DSBoxStreamEventReasoning:
      [self appendText:text toKey:@"reasoning"];
      break;
    case DSBoxStreamEventUsage:
      self.streamMsg[@"prompt_tokens"] = data[@"prompt_tokens"] ?: data[@"prompt"];
      self.streamMsg[@"completion_tokens"] = data[@"completion_tokens"] ?: data[@"completion"];
      [self refreshStreamCell];
      break;
    case DSBoxStreamEventTitle:
      if (text.length) self.title = text;
      break;
    default:
      break;
  }
}

- (void)appendText:(NSString *)text toKey:(NSString *)key {
  if (text.length == 0) return;
  NSString *old = self.streamMsg[key] ?: @"";
  self.streamMsg[key] = [old stringByAppendingString:text];
  [self refreshStreamCell];
}

- (void)refreshStreamCell {
  NSInteger row = self.messages.count - 1;
  if (row < 0) return;
  NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:0];
  [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
  [self scrollToBottomAnimated:NO];
}

- (void)dsboxDidFinishWithError:(NSError *)error {
  if (self.streamMsg) {
    [[DSBoxService shared] appendMessage:self.streamMsg toConversation:self.convId];
  }
  [self finishWithError:error];
}

#pragma mark - DSMessageCellDelegate

- (void)messageCellDidCopy:(DSMessageCell *)cell {
  // 轻提示：官方 copyOk = 已复制
  UIWindow *win = self.view.window;
  UILabel *toast = [[UILabel alloc] init];
  toast.text = DSStrCopied;
  toast.font = [UIFont systemFontOfSize:13];
  toast.textColor = UIColor.whiteColor;
  toast.backgroundColor = [[DSTheme labelPrimary] colorWithAlphaComponent:0.9];
  toast.textAlignment = NSTextAlignmentCenter;
  toast.layer.cornerRadius = 8;
  toast.layer.masksToBounds = YES;
  [toast sizeToFit];
  CGRect f = toast.frame;
  toast.frame = CGRectMake(0, 0, f.size.width + 28, 34);
  toast.center = CGPointMake(win.center.x, win.bounds.size.height - 120);
  [win addSubview:toast];
  [UIView animateWithDuration:0.25 delay:1.1 options:0 animations:^{
    toast.alpha = 0;
  } completion:^(BOOL done) {
    [toast removeFromSuperview];
  }];
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  DSMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"msg" forIndexPath:indexPath];
  cell.delegate = self;
  [cell configure:self.messages[indexPath.row]];
  return cell;
}

- (void)scrollToBottomAnimated:(BOOL)animated {
  if (self.messages.count == 0) return;
  NSIndexPath *ip = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
  [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

@end
