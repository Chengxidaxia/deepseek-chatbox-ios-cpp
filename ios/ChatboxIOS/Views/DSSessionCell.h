//
//  DSSessionCell.h
//  ChatboxIOS
//
//  对齐官方 `SessionListCollectionView.Cell` 与 `VirtualRootCell`（分组标题）。
//
//  之前的实现是 UITableViewCellStyleSubtitle —— 标题和预览用的是系统内置的两个
//  label，位置、行高、截断方式全由 UIKit 决定，右侧「…」只能挂 accessoryView。
//  换成自绘 cell 之后，标题/预览/按钮的位置都是我们自己的数，跟官方一致。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat DSSessionRowHeight;

@interface DSSessionCell : UICollectionViewCell

/// 右侧「…」被点。由列表决定弹什么菜单 —— cell 不该知道业务。
@property (nonatomic, copy, nullable) void (^onMore)(void);

- (void)configureTitle:(nullable NSString *)title
               preview:(nullable NSString *)preview
                pinned:(BOOL)pinned;

@end

#pragma mark - 分组标题

/// 对应官方 `VirtualRootCell` 承担的「分组标题」职责。
/// 官方是拿一个 cell 当分组容器，我们这里用 collection view 的分区头 ——
/// 视觉一致，而且能直接吃到 sticky header，不用自己算吸顶。
@interface DSSessionSectionHeaderView : UICollectionReusableView
@property (nonatomic, copy, nullable) NSString *title;
@end

NS_ASSUME_NONNULL_END
