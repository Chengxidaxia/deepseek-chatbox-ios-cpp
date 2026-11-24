//
//  DSAttachmentPanel.m
//  ChatboxIOS
//

#import "DSAttachmentPanel.h"
#import "DSTheme.h"
#import "DSStrings.h"
#import "DSIcon.h"

#pragma mark - 面板

@interface DSAttachmentPanel ()
@property (nonatomic, copy) void (^handler)(DSAttachSource);
@end

@implementation DSAttachmentPanel

+ (instancetype)panelWithHandler:(void (^)(DSAttachSource))handler {
  DSAttachmentPanel *p = [[DSAttachmentPanel alloc] init];
  p.handler = handler;
  p.modalPresentationStyle = UIModalPresentationPageSheet;
  if (@available(iOS 15.0, *)) {
    UISheetPresentationController *sheet = p.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = 20;
  }
  return p;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [DSTheme bgBase];

  NSArray<NSDictionary *> *options = @[
    @{@"title": DSStrUploadAlbum, @"icon": @(DSIconPhoto), @"tag": @(DSAttachSourceAlbum)},
    @{@"title": DSStrUploadCamera, @"icon": @(DSIconCamera), @"tag": @(DSAttachSourceCamera)},
    @{@"title": DSStrUploadFile, @"icon": @(DSIconFile), @"tag": @(DSAttachSourceFile)},
  ];

  UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[]];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.axis = UILayoutConstraintAxisHorizontal;
  row.distribution = UIStackViewDistributionFillEqually;
  row.spacing = 12;

  for (NSDictionary *o in options) {
    UIControl *cell = [[UIControl alloc] init];
    cell.translatesAutoresizingMaskIntoConstraints = NO;
    cell.backgroundColor = [DSTheme bgLayer1];
    cell.layer.cornerRadius = 16;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layer.borderWidth = 1;
    cell.layer.borderColor = [DSTheme borderL2].CGColor;
    cell.tag = [o[@"tag"] integerValue];

    UIImageView *icon = [[UIImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [DSIcon image:(DSIconName)[o[@"icon"] integerValue] size:26];
    icon.tintColor = [DSTheme labelSecondary];
    icon.contentMode = UIViewContentModeCenter;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = o[@"title"];
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [DSTheme labelSecondary];
    label.textAlignment = NSTextAlignmentCenter;

    [cell addSubview:icon];
    [cell addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
      [icon.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
      [icon.topAnchor constraintEqualToAnchor:cell.topAnchor constant:22],
      [icon.widthAnchor constraintEqualToConstant:28],
      [icon.heightAnchor constraintEqualToConstant:28],
      [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:10],
      [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
      [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
    ]];
    [cell addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [row addArrangedSubview:cell];
  }

  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = DSStrAttachments;
  title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
  title.textColor = [DSTheme labelPrimary];

  [self.view addSubview:title];
  [self.view addSubview:row];
  [NSLayoutConstraint activateConstraints:@[
    [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
    [title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:24],
    [row.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
    [row.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    [row.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
    [row.heightAnchor constraintEqualToConstant:104],
  ]];
}

- (void)optionTapped:(UIControl *)sender {
  DSAttachSource src = (DSAttachSource)sender.tag;
  void (^h)(DSAttachSource) = self.handler;
  [self dismissViewControllerAnimated:YES completion:^{
    if (h) h(src);
  }];
}

@end

#pragma mark - 附件条目

@implementation DSAttachmentItem

+ (instancetype)itemWithData:(NSData *)data name:(NSString *)name mime:(NSString *)mime {
  DSAttachmentItem *it = [[DSAttachmentItem alloc] init];
  it.data = data;
  it.name = name.length ? name : @"文件";
  it.mime = mime.length ? mime : @"application/octet-stream";
  it.size = (NSInteger)data.length;
  if ([mime hasPrefix:@"image/"]) {
    it.kind = @"image";
    it.thumbnail = [UIImage imageWithData:data];
  } else if ([mime hasPrefix:@"text/"] || [mime containsString:@"json"] || [mime containsString:@"csv"]) {
    it.kind = @"text";
  } else {
    it.kind = @"file";
  }
  return it;
}

@end

#pragma mark - 附件条

@interface DSAttachmentStrip ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation DSAttachmentStrip

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll = [[UIScrollView alloc] init];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.showsHorizontalScrollIndicator = NO;
    [self addSubview:_scroll];

    _stack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisHorizontal;
    _stack.spacing = 8;
    [_scroll addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
      [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
      [_scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [_stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
      [_stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
      [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
      [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
      [_stack.heightAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.heightAnchor],
    ]];
    self.hidden = YES;
  }
  return self;
}

- (void)setItems:(NSArray<DSAttachmentItem *> *)items {
  for (UIView *v in _stack.arrangedSubviews) {
    [_stack removeArrangedSubview:v];
    [v removeFromSuperview];
  }
  self.hidden = items.count == 0;
  NSUInteger idx = 0;
  for (DSAttachmentItem *it in items) {
    [_stack addArrangedSubview:[self chipForItem:it index:idx]];
    idx++;
  }
}

- (UIView *)chipForItem:(DSAttachmentItem *)it index:(NSUInteger)index {
  UIView *chip = [[UIView alloc] init];
  chip.translatesAutoresizingMaskIntoConstraints = NO;
  chip.backgroundColor = [DSTheme bgLayer1];
  chip.layer.cornerRadius = 12;
  chip.layer.cornerCurve = kCACornerCurveContinuous;
  chip.layer.borderWidth = 1;
  chip.layer.borderColor = [DSTheme borderL2].CGColor;

  UIView *thumbHost = [[UIView alloc] init];
  thumbHost.translatesAutoresizingMaskIntoConstraints = NO;
  thumbHost.backgroundColor = [DSTheme bgHover];
  thumbHost.layer.cornerRadius = 8;
  thumbHost.clipsToBounds = YES;
  [chip addSubview:thumbHost];

  if (it.thumbnail) {
    UIImageView *iv = [[UIImageView alloc] initWithImage:it.thumbnail];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    [thumbHost addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[
      [iv.leadingAnchor constraintEqualToAnchor:thumbHost.leadingAnchor],
      [iv.trailingAnchor constraintEqualToAnchor:thumbHost.trailingAnchor],
      [iv.topAnchor constraintEqualToAnchor:thumbHost.topAnchor],
      [iv.bottomAnchor constraintEqualToAnchor:thumbHost.bottomAnchor],
    ]];
  } else {
    UIImageView *iv = [[UIImageView alloc] init];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.image = [DSIcon image:DSIconFile size:18];
    iv.tintColor = [DSTheme labelTertiary];
    iv.contentMode = UIViewContentModeCenter;
    [thumbHost addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[
      [iv.centerXAnchor constraintEqualToAnchor:thumbHost.centerXAnchor],
      [iv.centerYAnchor constraintEqualToAnchor:thumbHost.centerYAnchor],
      [iv.widthAnchor constraintEqualToConstant:20],
      [iv.heightAnchor constraintEqualToConstant:20],
    ]];
  }

  UILabel *name = [[UILabel alloc] init];
  name.translatesAutoresizingMaskIntoConstraints = NO;
  name.text = it.name;
  name.font = [UIFont systemFontOfSize:12];
  name.textColor = [DSTheme labelSecondary];
  name.lineBreakMode = NSLineBreakByTruncatingMiddle;
  [name setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                        forAxis:UILayoutConstraintAxisHorizontal];
  [chip addSubview:name];

  UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
  del.translatesAutoresizingMaskIntoConstraints = NO;
  [del setImage:[DSIcon image:DSIconClose size:10] forState:UIControlStateNormal];
  del.tintColor = [DSTheme labelTertiary];
  del.tag = (NSInteger)index;
  [del addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
  [chip addSubview:del];

  [NSLayoutConstraint activateConstraints:@[
    [chip.heightAnchor constraintEqualToConstant:40],
    [chip.widthAnchor constraintLessThanOrEqualToConstant:170],
    [thumbHost.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:4],
    [thumbHost.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
    [thumbHost.widthAnchor constraintEqualToConstant:32],
    [thumbHost.heightAnchor constraintEqualToConstant:32],
    [name.leadingAnchor constraintEqualToAnchor:thumbHost.trailingAnchor constant:8],
    [name.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
    [del.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:6],
    [del.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-8],
    [del.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
    [del.widthAnchor constraintEqualToConstant:18],
    [del.heightAnchor constraintEqualToConstant:18],
  ]];
  return chip;
}

- (void)removeTapped:(UIButton *)sender {
  if (self.onRemove) self.onRemove((NSUInteger)sender.tag);
}

@end
