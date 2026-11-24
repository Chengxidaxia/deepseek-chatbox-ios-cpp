//
//  DSTopBarView.m
//  ChatboxIOS
//

#import "DSTopBarView.h"
#import "DSIcon.h"
#import "DSTheme.h"

@interface DSTopBarView ()
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong, readwrite) UIButton *modelButton;
@property (nonatomic, strong) UIButton *newChatButton;
@end

@implementation DSTopBarView

+ (CGFloat)preferredHeight { return 44.0; }

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.backgroundColor = [DSTheme bgBase];

  // 左：☰
  _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _menuButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_menuButton setImage:[DSIcon image:DSIconMenu size:DSIconPointSizeNav] forState:UIControlStateNormal];
  _menuButton.tintColor = [DSTheme labelPrimary];
  _menuButton.accessibilityLabel = @"会话列表";
  [_menuButton addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];

  // 中：模型名 + ⌄
  _modelButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _modelButton.translatesAutoresizingMaskIntoConstraints = NO;
  _modelButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
  [_modelButton setTitleColor:[DSTheme labelPrimary] forState:UIControlStateNormal];
  [_modelButton setImage:[DSIcon image:DSIconChevronDown size:14] forState:UIControlStateNormal];
  _modelButton.tintColor = [DSTheme labelTertiary];
  // 官方是「模型名 ⌄」，箭头在右
  _modelButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  _modelButton.imageEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
  _modelButton.titleEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
  _modelButton.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
#pragma clang diagnostic pop
  [_modelButton addTarget:self action:@selector(modelTapped) forControlEvents:UIControlEventTouchUpInside];

  // 右：＋
  _newChatButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _newChatButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_newChatButton setImage:[DSIcon image:DSIconNewChat size:22] forState:UIControlStateNormal];
  _newChatButton.tintColor = [DSTheme labelPrimary];
  _newChatButton.accessibilityLabel = @"开启新对话";
  [_newChatButton addTarget:self action:@selector(newChatTapped) forControlEvents:UIControlEventTouchUpInside];

  [self addSubview:_menuButton];
  [self addSubview:_modelButton];
  [self addSubview:_newChatButton];

  [NSLayoutConstraint activateConstraints:@[
    [_menuButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
    [_menuButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_menuButton.widthAnchor constraintEqualToConstant:44],
    [_menuButton.heightAnchor constraintEqualToConstant:44],

    [_newChatButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
    [_newChatButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_newChatButton.widthAnchor constraintEqualToConstant:44],
    [_newChatButton.heightAnchor constraintEqualToConstant:44],

    [_modelButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [_modelButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_modelButton.heightAnchor constraintEqualToConstant:36],
    // 中间标题不许压到两侧按钮
    [_modelButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_menuButton.trailingAnchor constant:4],
    [_modelButton.trailingAnchor constraintLessThanOrEqualToAnchor:_newChatButton.leadingAnchor constant:-4],
  ]];
  return self;
}

- (void)setModelTitle:(NSString *)modelTitle {
  _modelTitle = [modelTitle copy];
  [self.modelButton setTitle:modelTitle ?: @"" forState:UIControlStateNormal];
}

- (void)menuTapped {
  if (self.onMenu) self.onMenu();
}

- (void)modelTapped {
  if (self.onModel) self.onModel();
}

- (void)newChatTapped {
  if (self.onNewChat) self.onNewChat();
}

@end
