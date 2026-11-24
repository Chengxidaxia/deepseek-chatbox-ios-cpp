#import "DSMessageCell.h"

@interface DSMessageCell ()
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *thinkLabel;
@property (nonatomic, strong) UILabel *contentLabel;
@property (nonatomic, strong) UILabel *usageLabel;
@property (nonatomic, strong) UIView *bubble;
@end

@implementation DSMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;

    _bubble = [[UIView alloc] init];
    _bubble.translatesAutoresizingMaskIntoConstraints = NO;
    _bubble.layer.cornerRadius = 12;
    [self.contentView addSubview:_bubble];

    _roleLabel = [UILabel new];
    _roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _roleLabel.textColor = UIColor.secondaryLabelColor;
    [_bubble addSubview:_roleLabel];

    _thinkLabel = [UILabel new];
    _thinkLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _thinkLabel.font = [UIFont systemFontOfSize:13];
    _thinkLabel.textColor = UIColor.secondaryLabelColor;
    _thinkLabel.numberOfLines = 0;
    [_bubble addSubview:_thinkLabel];

    _contentLabel = [UILabel new];
    _contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _contentLabel.font = [UIFont systemFontOfSize:15];
    _contentLabel.numberOfLines = 0;
    [_bubble addSubview:_contentLabel];

    _usageLabel = [UILabel new];
    _usageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usageLabel.font = [UIFont systemFontOfSize:11];
    _usageLabel.textColor = UIColor.tertiaryLabelColor;
    [_bubble addSubview:_usageLabel];

    [NSLayoutConstraint activateConstraints:@[
      [_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
      [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
      [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
      [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],

      [_roleLabel.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:8],
      [_roleLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
      [_roleLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],

      [_thinkLabel.topAnchor constraintEqualToAnchor:_roleLabel.bottomAnchor constant:4],
      [_thinkLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
      [_thinkLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],

      [_contentLabel.topAnchor constraintEqualToAnchor:_thinkLabel.bottomAnchor constant:6],
      [_contentLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
      [_contentLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],

      [_usageLabel.topAnchor constraintEqualToAnchor:_contentLabel.bottomAnchor constant:6],
      [_usageLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
      [_usageLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
      [_usageLabel.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-8],
    ]];
  }
  return self;
}

- (void)configure:(NSDictionary *)m {
  NSString *role = m[@"role"] ?: @"";
  BOOL user = [role isEqualToString:@"user"];
  self.roleLabel.text = user ? @"你" : @"DeepSeek";
  self.bubble.backgroundColor = user ? UIColor.systemBlueColor
      : UIColor.secondarySystemBackgroundColor;
  self.contentLabel.textColor = user ? UIColor.whiteColor : UIColor.labelColor;
  self.thinkLabel.textColor = user ? [UIColor.whiteColor colorWithAlphaComponent:0.75]
      : UIColor.secondaryLabelColor;
  self.usageLabel.textColor = user ? [UIColor.whiteColor colorWithAlphaComponent:0.7]
      : UIColor.tertiaryLabelColor;
  // 用户气泡靠右：通过内容对齐模拟
  self.contentLabel.textAlignment = user ? NSTextAlignmentRight : NSTextAlignmentLeft;
  self.thinkLabel.textAlignment = user ? NSTextAlignmentRight : NSTextAlignmentLeft;
  self.usageLabel.textAlignment = user ? NSTextAlignmentRight : NSTextAlignmentLeft;
  self.roleLabel.textAlignment = user ? NSTextAlignmentRight : NSTextAlignmentLeft;

  NSString *reasoning = m[@"reasoning"] ?: @"";
  if (reasoning.length) {
    self.thinkLabel.text = [NSString stringWithFormat:@"[思考] %@", reasoning];
    self.thinkLabel.hidden = NO;
  } else {
    self.thinkLabel.text = nil;
    self.thinkLabel.hidden = YES;
  }

  self.contentLabel.text = m[@"content"] ?: @"";

  NSNumber *p = m[@"prompt_tokens"], *c = m[@"completion_tokens"];
  if (p || c) {
    self.usageLabel.text = [NSString stringWithFormat:@"↑%@ ↓%@ tokens", p ?: @0, c ?: @0];
    self.usageLabel.hidden = NO;
  } else {
    self.usageLabel.text = nil;
    self.usageLabel.hidden = YES;
  }

  if ([m[@"streaming"] boolValue] && ![self.contentLabel.text hasSuffix:@"|"]) {
    self.contentLabel.text = [self.contentLabel.text stringByAppendingString:@"|"];
  }
}

@end
