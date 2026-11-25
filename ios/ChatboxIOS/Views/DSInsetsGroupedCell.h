//
//  DSInsetsGroupedCell.h
//  ChatboxIOS
//
//  对齐官方 `ProfileViewController.InsetsGroupedCell` / `InsetsGroupedLayer`。
//
//  官方的分组不是 UITableView 自带的 grouped 样式：整组共用**一张内缩卡片**，
//  左右各留 16，只有首行和末行有圆角，行与行之间没有缝，分隔线从标题起始位置开始。
//  自带的 grouped 样式做不到「一组一张卡」—— 它是每行一张卡，行间还有 8pt 缝，
//  这就是观感差距的来源。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 卡片左右内缩量。分组头/尾的文字也按「卡片左边 + 行内边距」对齐。
extern const CGFloat DSGroupedCardInset;
/// 卡片圆角。
extern const CGFloat DSGroupedCardCornerRadius;
/// 行高。
extern const CGFloat DSGroupedRowHeight;

/// 行在组内的位置。只有首/尾行带圆角，中间的直角 —— 这样整组才像一张卡。
typedef NS_ENUM(NSInteger, DSGroupedRowPosition) {
  DSGroupedRowPositionSingle = 0,   // 独占一组：四角全圆
  DSGroupedRowPositionFirst,        // 组内首行：上两角圆
  DSGroupedRowPositionMiddle,       // 组内中间：直角
  DSGroupedRowPositionLast,         // 组内末行：下两角圆
};

@interface DSInsetsGroupedCell : UITableViewCell

/// 行位置。决定圆角与分隔线，必须在 cellForRow 里按 row 与总数算好再给。
@property (nonatomic, assign) DSGroupedRowPosition position;

/// 右侧前进箭头（官方 `ForwardChevron`）。
@property (nonatomic, assign) BOOL showsChevron;

/// 右侧附加控件（UISwitch 之类）。设了它就不再显示箭头 —— 两者同时出现会挤。
@property (nonatomic, strong, nullable) UIView *accessoryControl;

@property (nonatomic, strong, readonly) UILabel *titleLabel;
/// 右侧的当前值。nil / 空串就隐藏。
@property (nonatomic, strong, readonly) UILabel *valueLabel;

/// 标题走危险色（删除类操作）。
@property (nonatomic, assign) BOOL destructive;

@end

#pragma mark - 分区头 / 尾

/// 官方的 `SectionHeader`：13pt 次要色，贴着卡片左边再内缩一个行内边距。
@interface DSSectionHeaderView : UITableViewHeaderFooterView
@property (nonatomic, copy, nullable) NSString *title;
@end

/// 官方的 `SectionFooter`：13pt 更浅一档，多行说明。
@interface DSSectionFooterView : UITableViewHeaderFooterView
@property (nonatomic, copy, nullable) NSString *detail;
@end

NS_ASSUME_NONNULL_END
