//
//  DSSessionCell.m
//  ChatboxIOS
//

#import "DSSessionCell.h"
#import "DSTheme.h"
#import "DSIcon.h"
#import "DSButton.h"

const CGFloat DSSessionRowHeight = 56.0;

static const CGFloat kPadLeading = 16.0;
static const CGFloat kPadTrailing = 12.0;
static const CGFloat kMoreWidth = 36.0;

#pragma mark - DSSessionCell

@interface DSSessionCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) DSButton *moreButton;
@property (nonatomic, strong) UIView *selectedBG;
@end

@implementation DSSessionCell

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;

  self.contentView.backgroundColor = UIColor.clearColor;
  self.backgroundColor = UIColor.clearColor;

  // 选中态自己画：系统默认的灰底是直角矩形，压在这套无边框列表上会显得很脏。
  _selectedBG = [[UIView alloc] init];
  _selectedBG.backgroundColor = [DSTheme bgHover];
  self.selectedBackgroundView = _selectedBG;

  _titleLabel = [[UILabel alloc] init];
  _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  _titleLabel.textColor = [DSTheme labelPrimary];
  _titleLabel.numberOfLines = 1;
  _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.contentView addSubview:_titleLabel];

  _previewLabel = [[UILabel alloc] init];
  _previewLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
  _previewLabel.textColor = [DSTheme labelTertiary];
  _previewLabel.numberOfLines = 1;
  _previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.contentView addSubview:_previewLabel];

  DSButtonConfig *cfg = [DSButtonConfig style:DSButtonStylePlain icon:DSIconMore title:nil];
  cfg.iconSize = DSIconPointSizeAction;      // 20，官方 ic_ellipsis_outline_20
  cfg.minSize = CGSizeMake(kMoreWidth, 44);
  cfg.hPadding = 0;
  cfg.vPadding = 0;
  cfg.cornerRadius = 0;
  cfg.tint = [DSTheme labelTertiary];
  _moreButton = [DSButton buttonWithConfig:cfg];
  // 手动排 frame 的容器里必须把 TAMIC 打开并给死尺寸 ——
  // buttonWithConfig: 为了约束布局把它关掉了，不打开就解不出尺寸，按钮等于不存在。
  _moreButton.translatesAutoresizingMaskIntoConstraints = YES;
  _moreButton.frame = CGRectMake(0, 0, kMoreWidth, 44);
  _moreButton.accessibilityLabel = @"更多操作";
  [_moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.contentView addSubview:_moreButton];

  return self;
}

- (void)configureTitle:(NSString *)title preview:(NSString *)preview pinned:(BOOL)pinned {
  _titleLabel.text = title;
  _previewLabel.text = preview;
  // 置顶的会话给标题一点分量差：官方也是靠分组标题 + 排序表达置顶，
  // 这里只用字重做一个很轻的补充，不加图标，免得和「…」抢视线。
  _titleLabel.font = [UIFont systemFontOfSize:15
                                       weight:pinned ? UIFontWeightSemibold : UIFontWeightMedium];
}

- (void)moreTapped {
  if (self.onMore) self.onMore();
}

- (void)layoutSubviews {
  [super layoutSubviews];

  CGFloat w = CGRectGetWidth(self.contentView.bounds);
  CGFloat h = CGRectGetHeight(self.contentView.bounds);
  if (w <= 0 || h <= 0) return;

  // 「…」贴右，垂直居中；标题和预览在它左边收住。
  CGFloat moreX = w - kPadTrailing - kMoreWidth;
  _moreButton.frame = CGRectMake(moreX, round((h - 44) / 2.0), kMoreWidth, 44);

  CGFloat textW = MAX(0, moreX - kPadLeading - 4);
  CGFloat titleH = 20;
  CGFloat previewH = 17;
  CGFloat gap = 2;
  CGFloat totalH = titleH + gap + previewH;
  CGFloat top = round((h - totalH) / 2.0);

  _titleLabel.frame = CGRectMake(kPadLeading, top, textW, titleH);
  _previewLabel.frame = CGRectMake(kPadLeading, top + titleH + gap, textW, previewH);
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.onMore = nil;
  _titleLabel.text = nil;
  _previewLabel.text = nil;
  _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
}

- (void)setHighlighted:(BOOL)highlighted {
  [super setHighlighted:highlighted];
  // 按下时压一点，不换色 —— 列表项不需要「选中」这种语义。
  self.contentView.alpha = highlighted ? 0.6 : 1.0;
}

@end

#pragma mark - DSSessionSectionHeaderView

@interface DSSessionSectionHeaderView ()
@property (nonatomic, strong) UILabel *label;
@end

@implementation DSSessionSectionHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;

  // 吸顶时头会盖在内容上，必须是不透明底色，否则能看到下面的行透出来。
  self.backgroundColor = [DSTheme bgBase];

  _label = [[UILabel alloc] init];
  _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  _label.textColor = [DSTheme labelSecondary];
  [self addSubview:_label];
  return self;
}

- (void)setTitle:(NSString *)title {
  _title = [title copy];
  _label.text = title;
  [self setNeedsLayout];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat h = CGRectGetHeight(self.bounds);
  // 文字基线靠下，跟下面第一行拉开距离；吸顶时留一点上边距不至于贴着顶。
  _label.frame = CGRectMake(kPadLeading, 0, MAX(0, CGRectGetWidth(self.bounds) - kPadLeading * 2), h);
}

@end
