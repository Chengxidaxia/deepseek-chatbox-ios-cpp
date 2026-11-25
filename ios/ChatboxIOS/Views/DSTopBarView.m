//
//  DSTopBarView.m
//  ChatboxIOS
//

#import "DSTopBarView.h"
#import "DSIcon.h"
#import "DSIconButton.h"
#import "DSTheme.h"

@interface DSTopBarView ()
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong, readwrite) UIButton *modelButton;
// 名字不能以 new 开头：ARC 的 new-family 命名约定会要求返回「拥有」的对象，
// 属性声明直接编译报错（property follows Cocoa naming convention for returning 'owned' objects）。
@property (nonatomic, strong) UIButton *composeButton;
@end

@implementation DSTopBarView

+ (CGFloat)preferredHeight { return 44.0; }

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.backgroundColor = [DSTheme bgBase];

  // 左：☰
  // 三个按钮都换成 DSIconButton：系统按钮按下去只压 tint，图标不动，
  // 顶栏底色和图标颜色本来就接近，等于没有反馈 —— 用户会以为没点到。
  _menuButton = [DSIconButton buttonWithIcon:[DSIcon image:DSIconMenu size:DSIconPointSizeNav]
                                       tint:[DSTheme labelPrimary]];
  _menuButton.accessibilityLabel = @"会话列表";
  [_menuButton addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];

  // 中：模型名 + ⌄
  _modelButton = [[DSIconButton alloc] initWithFrame:CGRectZero];
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
  // 尺寸用官方 24 的画布（ic_new_chat_outline_24），之前给的是 22，比左侧 ☰ 小一圈。
  _composeButton = [DSIconButton buttonWithIcon:[DSIcon image:DSIconNewChat size:DSIconPointSizeNav]
                                          tint:[DSTheme labelPrimary]];
  _composeButton.accessibilityLabel = @"开启新对话";
  [_composeButton addTarget:self action:@selector(newChatTapped) forControlEvents:UIControlEventTouchUpInside];

  [self addSubview:_menuButton];
  [self addSubview:_modelButton];
  [self addSubview:_composeButton];

  [NSLayoutConstraint activateConstraints:@[
    [_menuButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
    [_menuButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_menuButton.widthAnchor constraintEqualToConstant:44],
    [_menuButton.heightAnchor constraintEqualToConstant:44],

    [_composeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
    [_composeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_composeButton.widthAnchor constraintEqualToConstant:44],
    [_composeButton.heightAnchor constraintEqualToConstant:44],

    [_modelButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [_modelButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_modelButton.heightAnchor constraintEqualToConstant:36],
    // 中间标题不许压到两侧按钮
    [_modelButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_menuButton.trailingAnchor constant:4],
    [_modelButton.trailingAnchor constraintLessThanOrEqualToAnchor:_composeButton.leadingAnchor constant:-4],
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
