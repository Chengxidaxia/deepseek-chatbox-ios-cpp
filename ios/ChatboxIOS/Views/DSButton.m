//
//  DSButton.m
//  ChatboxIOS
//

#import "DSButton.h"
#import "DSTheme.h"

@implementation DSButtonConfig

+ (instancetype)style:(DSButtonStyle)style icon:(DSIconName)icon title:(NSString *)title {
  DSButtonConfig *c = [[DSButtonConfig alloc] init];
  c.style = style;
  c.icon = icon;
  c.title = title;
  // 官方按钮尺寸收敛在 16/20/24 三档（Assets.car 里图标画布就这三种），
  // 这里按语义给默认值，需要时再单独覆盖。
  switch (style) {
    case DSButtonStylePlain:
      c.iconSize = DSIconPointSizeNav;        // 24：顶栏
      c.hPadding = 8;
      c.vPadding = 8;
      c.iconTitleGap = 6;
      break;
    case DSButtonStyleTinted:
      c.iconSize = DSIconPointSizeInline;     // 16：输入条 chip
      c.hPadding = 10;
      c.vPadding = 6;
      c.iconTitleGap = 4;
      break;
    case DSButtonStyleFilled:
      c.iconSize = DSIconPointSizeInline;
      c.hPadding = 0;
      c.vPadding = 0;
      c.iconTitleGap = 0;
      break;
    case DSButtonStyleOutline:
      c.iconSize = DSIconPointSizeAction;     // 20
      c.hPadding = 12;
      c.vPadding = 8;
      c.iconTitleGap = 6;
      break;
  }
  c.minSize = CGSizeMake(44, 44);
  return c;
}

- (instancetype)init {
  self = [super init];
  if (!self) return nil;
  _style = DSButtonStylePlain;
  _iconSize = DSIconPointSizeAction;
  _cornerRadius = -1;      // 负数表示「胶囊：取高度一半」
  _iconTitleGap = 6;
  _minSize = CGSizeMake(44, 44);
  return self;
}

/// `DSButton.config` 声明成 copy，所以必须实现 NSCopying —— 否则赋值时
/// 走 `copyWithZone:` 会直接 unrecognized selector 崩掉。
- (id)copyWithZone:(NSZone *)zone {
  DSButtonConfig *c = [[DSButtonConfig allocWithZone:zone] init];
  c.style = self.style;
  c.icon = self.icon;
  c.iconSize = self.iconSize;
  c.title = self.title;
  c.font = self.font;
  c.tint = self.tint;
  c.background = self.background;
  c.selectedTint = self.selectedTint;
  c.selectedBackground = self.selectedBackground;
  c.cornerRadius = self.cornerRadius;
  c.borderWidth = self.borderWidth;
  c.borderColor = self.borderColor;
  c.hPadding = self.hPadding;
  c.vPadding = self.vPadding;
  c.iconTitleGap = self.iconTitleGap;
  c.minSize = self.minSize;
  return c;
}

@end

#pragma mark -

@interface DSButton ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *textLabel2;
@end

@implementation DSButton

+ (instancetype)buttonWithConfig:(DSButtonConfig *)config {
  // 不用 `[DSButton buttonWithType:]`：UIButton 的工厂方法在某些系统版本上
  // 返回的是 UIButton 本身而不是子类，那就拿不到 layoutSubviews 里的自定义布局。
  // alloc/init 出来的 buttonType 就是 custom，行为确定。
  DSButton *b = [[DSButton alloc] initWithFrame:CGRectZero];
  b.translatesAutoresizingMaskIntoConstraints = NO;
  b.config = config;
  return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  [self setupSubviews];
  return self;
}

- (void)setupSubviews {
  _iconView = [[UIImageView alloc] init];
  _iconView.contentMode = UIViewContentModeScaleAspectFit;
  _iconView.userInteractionEnabled = NO;
  [self addSubview:_iconView];

  _textLabel2 = [[UILabel alloc] init];
  _textLabel2.userInteractionEnabled = NO;
  [self addSubview:_textLabel2];
}

- (void)setConfig:(DSButtonConfig *)config {
  _config = [config copy];
  [self applyConfig];
}

/// 应用配置。**每次状态变化都要重走一遍**，否则选中/禁用态不会跟着变。
- (void)applyConfig {
  DSButtonConfig *c = self.config;
  if (!c) return;

  BOOL on = self.selected;

  // ---- 颜色 ----
  UIColor *tint = on ? (c.selectedTint ?: c.tint) : c.tint;
  UIColor *bg = on ? (c.selectedBackground ?: c.background) : c.background;

  if (!tint) {
    switch (c.style) {
      case DSButtonStyleFilled:
        tint = UIColor.whiteColor;
        break;
      case DSButtonStylePlain:
      case DSButtonStyleTinted:
      case DSButtonStyleOutline:
        tint = on ? [DSTheme brand] : [DSTheme labelSecondary];
        break;
    }
  }
  if (!bg) {
    switch (c.style) {
      case DSButtonStyleFilled:
        bg = [DSTheme brand];
        break;
      case DSButtonStyleTinted:
        bg = on ? [[DSTheme brand] colorWithAlphaComponent:0.12] : [DSTheme bgActive];
        break;
      case DSButtonStyleOutline:
      case DSButtonStylePlain:
        bg = UIColor.clearColor;
        break;
    }
  }

  self.backgroundColor = bg;
  self.tintColor = tint;

  // ---- 图标 ----
  BOOL hasIcon = (c.iconSize > 0);   // 想只显示文字就把 iconSize 设 0，别拿 icon==0 当哨兵（DSIconMenu 就是 0）
  UIImage *img = hasIcon ? [DSIcon image:c.icon size:c.iconSize] : nil;
  _iconView.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
  _iconView.tintColor = tint;
  _iconView.hidden = (img == nil);

  // ---- 文字 ----
  _textLabel2.hidden = (c.title.length == 0);
  if (c.title.length) {
    _textLabel2.text = c.title;
    _textLabel2.font = c.font ?: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _textLabel2.textColor = tint;
  }

  // ---- 描边 / 圆角 ----
  if (c.borderWidth > 0) {
    self.layer.borderWidth = c.borderWidth;
    self.layer.borderColor = (c.borderColor ?: [DSTheme borderL2]).CGColor;
  } else if (c.style == DSButtonStyleOutline) {
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [DSTheme borderL2].CGColor;
  } else {
    self.layer.borderWidth = 0;
  }
  self.layer.cornerCurve = kCACornerCurveContinuous;
  self.layer.cornerRadius = (c.cornerRadius >= 0) ? c.cornerRadius : CGRectGetHeight(self.bounds) / 2;

  // ---- 禁用态 ----
  self.alpha = self.enabled ? 1.0 : 0.4;

  [self setNeedsLayout];
  [self invalidateIntrinsicContentSize];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  DSButtonConfig *c = self.config;
  if (!c) return;

  // 胶囊圆角依赖最终高度，所以在这里再算一次（bounds 这时才可靠）
  if (c.cornerRadius < 0) {
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2;
  }

  BOOL hasIcon = !_iconView.hidden;
  BOOL hasText = !_textLabel2.hidden;
  CGFloat gap = (hasIcon && hasText) ? c.iconTitleGap : 0;

  CGSize iconSize = hasIcon ? _iconView.image.size : CGSizeZero;
  CGSize textSize = hasText ? [_textLabel2 sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)]
                            : CGSizeZero;
  CGFloat contentW = iconSize.width + gap + textSize.width;
  CGFloat contentH = MAX(iconSize.height, textSize.height);

  CGFloat x = (CGRectGetWidth(self.bounds) - contentW) / 2.0;
  CGFloat cy = CGRectGetMidY(self.bounds);

  if (hasIcon) {
    _iconView.frame = CGRectMake(round(x), round(cy - iconSize.height / 2.0),
                                 iconSize.width, iconSize.height);
    x += iconSize.width + gap;
  }
  if (hasText) {
    _textLabel2.frame = CGRectMake(round(x), round(cy - textSize.height / 2.0),
                                   textSize.width, textSize.height);
  }
}

- (CGSize)intrinsicContentSize {
  DSButtonConfig *c = self.config;
  if (!c) return [super intrinsicContentSize];

  BOOL hasIcon = (c.iconSize > 0);
  BOOL hasText = (c.title.length > 0);
  CGFloat gap = (hasIcon && hasText) ? c.iconTitleGap : 0;

  CGSize iconSize = hasIcon ? CGSizeMake(c.iconSize, c.iconSize) : CGSizeZero;
  UIFont *f = c.font ?: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
  CGSize textSize = hasText ? [c.title sizeWithAttributes:@{NSFontAttributeName: f}] : CGSizeZero;

  CGFloat w = iconSize.width + gap + textSize.width + c.hPadding * 2;
  CGFloat h = MAX(iconSize.height, textSize.height) + c.vPadding * 2;

  w = MAX(w, c.minSize.width);
  h = MAX(h, c.minSize.height);
  return CGSizeMake(ceil(w), ceil(h));
}

#pragma mark - 状态

// 三个状态入口都重走 applyConfig：官方用 ConfigurationUpdateHandler 做的就是这个事。

- (void)setSelected:(BOOL)selected {
  [super setSelected:selected];
  [self applyConfig];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyConfig];
}

- (void)setHighlighted:(BOOL)highlighted {
  [super setHighlighted:highlighted];
  // 高亮只改透明度，不改配色 —— 官方按钮按下是整体压暗，不是换色。
  self.alpha = (self.enabled ? 1.0 : 0.4) * (highlighted ? 0.7 : 1.0);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
  [super traitCollectionDidChange:previous];
  if (!previous) return;
  if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  [self applyConfig];   // 深浅色切换要重取 dynamic color
}

@end
