//
//  DSInsetsGroupedCell.m
//  ChatboxIOS
//

#import "DSInsetsGroupedCell.h"
#import "DSTheme.h"
#import "DSIcon.h"

const CGFloat DSGroupedCardInset = 16.0;
const CGFloat DSGroupedCardCornerRadius = 12.0;
const CGFloat DSGroupedRowHeight = 48.0;

/// 卡片内部的左右内边距。分隔线也从标题起始位置开始，跟 iOS 设置页一致。
static const CGFloat kInset = 16.0;

#pragma mark - DSInsetsGroupedCell

@interface DSInsetsGroupedCell ()
// 对外只读（.h 里是 readonly），所以内部用另外的属性名持有，
// 再实现同名 getter 暴露出去。直接重声明成 readwrite 会连带合成 ivar，
// 而一旦自己写了 setter/getter 就不再合成 —— `_titleLabel` 会变成未声明标识符。
@property (nonatomic, strong) UILabel *titleTextLabel;
@property (nonatomic, strong) UILabel *valueTextLabel;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIView *separatorView;
@end

@implementation DSInsetsGroupedCell

- (UILabel *)titleLabel { return self.titleTextLabel; }
- (UILabel *)valueLabel { return self.valueTextLabel; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (!self) return nil;

  // 行本身完全透明：可见的只有里面那张卡片，行与行之间才不会出现自带的缝。
  self.backgroundColor = UIColor.clearColor;
  self.contentView.backgroundColor = UIColor.clearColor;
  self.selectionStyle = UITableViewCellSelectionStyleNone;
  self.separatorInset = UIEdgeInsetsZero;

  // 卡片底色用 bgHover：浅色下压在白底上是一层很淡的灰，深色下压在 #151517 上
  // 抬到 #232324 左右 —— 正好是官方设置页卡片那一档，不会像 bgLayer1 那样
  // 在浅色模式下和白底糊成一片。
  _cardView = [[UIView alloc] init];
  _cardView.backgroundColor = [DSTheme bgHover];
  _cardView.clipsToBounds = YES;
  _cardView.layer.cornerCurve = kCACornerCurveContinuous;
  _cardView.layer.cornerRadius = DSGroupedCardCornerRadius;
  [self.contentView addSubview:_cardView];

  _titleTextLabel = [[UILabel alloc] init];
  _titleTextLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
  _titleTextLabel.textColor = [DSTheme labelPrimary];
  _titleTextLabel.numberOfLines = 1;
  _titleTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [_cardView addSubview:_titleTextLabel];

  _valueTextLabel = [[UILabel alloc] init];
  _valueTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
  _valueTextLabel.textColor = [DSTheme labelTertiary];
  _valueTextLabel.numberOfLines = 1;
  _valueTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  _valueTextLabel.textAlignment = NSTextAlignmentRight;
  // 抗压缩优先级给高：标题再长也先让值完整显示，标题自己截断。
  [_valueTextLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisHorizontal];
  [_cardView addSubview:_valueTextLabel];

  _chevronView = [[UIImageView alloc] init];
  _chevronView.image = [[DSIcon image:DSIconChevronRight size:DSIconPointSizeInline]
      imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
  _chevronView.tintColor = [DSTheme labelCaption];
  _chevronView.contentMode = UIViewContentModeScaleAspectFit;
  _chevronView.hidden = YES;
  [_cardView addSubview:_chevronView];

  _separatorView = [[UIView alloc] init];
  _separatorView.backgroundColor = [DSTheme borderL2];
  [_cardView addSubview:_separatorView];

  return self;
}

#pragma mark - 属性

- (void)setPosition:(DSGroupedRowPosition)position {
  _position = position;

  // 整组共用一张卡片，所以只有首/尾行该有圆角，中间的直角。
  // 用 maskedCorners 而不是拆成四个图层：cornerRadius 只算一次，改位置时不用重建。
  CACornerMask mask = 0;
  switch (position) {
    case DSGroupedRowPositionSingle:
      mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
             kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
      break;
    case DSGroupedRowPositionFirst:
      mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
      break;
    case DSGroupedRowPositionLast:
      mask = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
      break;
    case DSGroupedRowPositionMiddle:
      mask = 0;
      break;
  }
  _cardView.layer.maskedCorners = mask;
  _cardView.layer.cornerRadius = (mask == 0) ? 0 : DSGroupedCardCornerRadius;

  // 末行不画分隔线 —— 否则会和卡片下边缘叠在一起，看着像多了一条边。
  _separatorView.hidden = (position == DSGroupedRowPositionLast ||
                           position == DSGroupedRowPositionSingle);
  [self setNeedsLayout];
}

- (void)setShowsChevron:(BOOL)showsChevron {
  _showsChevron = showsChevron;
  _chevronView.hidden = !showsChevron;
  [self setNeedsLayout];
}

- (void)setAccessoryControl:(UIView *)accessoryControl {
  [_accessoryControl removeFromSuperview];
  _accessoryControl = accessoryControl;
  if (accessoryControl) [_cardView addSubview:accessoryControl];
  [self setNeedsLayout];
}

- (void)setDestructive:(BOOL)destructive {
  _destructive = destructive;
  _titleTextLabel.textColor = destructive ? [DSTheme danger] : [DSTheme labelPrimary];
}

/// 按下反馈只改卡片底色。
/// 系统自带的 selectionStyle 会在**整个 cell 矩形**上盖一层灰 —— 那是个直角矩形，
/// 和内缩圆角卡片对不上，一眼就能看出穿帮，所以这里关掉它自己画。
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
  [super setHighlighted:highlighted animated:animated];
  _cardView.backgroundColor = highlighted ? [DSTheme bgActive] : [DSTheme bgHover];
}

/// 深浅色切换后要重取一遍颜色。
/// DSTheme 给的是 colorWithDynamicProvider，但只在**赋值那一刻**解析；
/// 已经画好的图层不会自己跟着变，所以必须在这里重新赋一次。
- (void)applyThemeColors {
  _cardView.backgroundColor = self.highlighted ? [DSTheme bgActive] : [DSTheme bgHover];
  _titleTextLabel.textColor = self.destructive ? [DSTheme danger] : [DSTheme labelPrimary];
  _valueTextLabel.textColor = [DSTheme labelTertiary];
  _chevronView.tintColor = [DSTheme labelCaption];
  _separatorView.backgroundColor = [DSTheme borderL2];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
  [super traitCollectionDidChange:previous];
  if (!previous) return;
  if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  [self applyThemeColors];
}

#pragma mark - 布局

- (void)layoutSubviews {
  [super layoutSubviews];

  // 卡片横向内缩 16，纵向铺满整行 —— 相邻行紧贴，视觉上连成一张卡。
  _cardView.frame = CGRectMake(DSGroupedCardInset, 0,
                               MAX(0, CGRectGetWidth(self.contentView.bounds) - DSGroupedCardInset * 2),
                               CGRectGetHeight(self.contentView.bounds));

  CGFloat cardW = CGRectGetWidth(_cardView.bounds);
  CGFloat cardH = CGRectGetHeight(_cardView.bounds);
  if (cardW <= 0 || cardH <= 0) return;

  CGFloat rightEdge = cardW - kInset;

  // 右侧从外到内依次是：箭头 / 附加控件 / 值。每占用一个就往左让。
  if (_showsChevron) {
    CGFloat s = DSIconPointSizeInline;
    _chevronView.frame = CGRectMake(rightEdge - s, round((cardH - s) / 2.0), s, s);
    rightEdge -= (s + 8);
  }

  if (_accessoryControl) {
    CGSize fit = [_accessoryControl sizeThatFits:CGSizeMake(CGFLOAT_MAX, cardH)];
    _accessoryControl.frame = CGRectMake(rightEdge - fit.width,
                                         round((cardH - fit.height) / 2.0),
                                         fit.width, fit.height);
    rightEdge -= (fit.width + 8);
  }

  // 值优先占满它需要的宽度，剩下的给标题。
  if (_valueTextLabel.text.length > 0) {
    CGFloat maxValueW = MAX(0, rightEdge - (kInset + 48));   // 至少给标题留 48
    CGSize fit = [_valueTextLabel sizeThatFits:CGSizeMake(maxValueW, cardH)];
    CGFloat w = MIN(ceil(fit.width), maxValueW);
    _valueTextLabel.hidden = NO;
    _valueTextLabel.frame = CGRectMake(rightEdge - w, 0, w, cardH);
    rightEdge -= (w + 12);
  } else {
    _valueTextLabel.hidden = YES;
    _valueTextLabel.frame = CGRectZero;
  }

  _titleTextLabel.frame = CGRectMake(kInset, 0, MAX(0, rightEdge - kInset), cardH);

  // 分隔线：从标题起始位置开始，右边到卡片边缘 —— 跟 iOS 设置页一样不贯穿整行。
  CGFloat hairline = 1.0 / MAX(1.0, UIScreen.mainScreen.scale);
  _separatorView.frame = CGRectMake(kInset, cardH - hairline, MAX(0, cardW - kInset), hairline);
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.accessoryControl = nil;
  self.showsChevron = NO;
  self.destructive = NO;
  self.valueLabel.text = nil;
  self.titleLabel.text = nil;
}

@end

#pragma mark - DSSectionHeaderView

@interface DSSectionHeaderView ()
@property (nonatomic, strong) UILabel *label;
@end

@implementation DSSectionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithReuseIdentifier:reuseIdentifier];
  if (!self) return nil;
  self.contentView.backgroundColor = UIColor.clearColor;

  _label = [[UILabel alloc] init];
  _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  _label.textColor = [DSTheme labelSecondary];
  _label.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:_label];

  // 文字对齐到卡片左边再内缩一个行内边距 —— 和行标题同一条竖线。
  [NSLayoutConstraint activateConstraints:@[
    [_label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                         constant:DSGroupedCardInset + kInset],
    [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                    constant:-(DSGroupedCardInset + kInset)],
    [_label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
  ]];
  return self;
}

- (void)setTitle:(NSString *)title {
  _title = [title copy];
  _label.text = title;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
  [super traitCollectionDidChange:previous];
  if (!previous) return;
  if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  _label.textColor = [DSTheme labelSecondary];
}

@end

#pragma mark - DSSectionFooterView

@interface DSSectionFooterView ()
@property (nonatomic, strong) UILabel *label;
@end

@implementation DSSectionFooterView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithReuseIdentifier:reuseIdentifier];
  if (!self) return nil;
  self.contentView.backgroundColor = UIColor.clearColor;

  _label = [[UILabel alloc] init];
  _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
  _label.textColor = [DSTheme labelCaption];
  _label.numberOfLines = 0;
  _label.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:_label];

  [NSLayoutConstraint activateConstraints:@[
    [_label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                         constant:DSGroupedCardInset + kInset],
    [_label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                          constant:-(DSGroupedCardInset + kInset)],
    [_label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
    [_label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
  ]];
  return self;
}

- (void)setDetail:(NSString *)detail {
  _detail = [detail copy];
  _label.text = detail;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
  [super traitCollectionDidChange:previous];
  if (!previous) return;
  if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
  _label.textColor = [DSTheme labelCaption];
}

@end
