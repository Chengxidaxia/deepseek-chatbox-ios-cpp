#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DSMessageCell;
@class DSTurn;

@protocol DSMessageCellDelegate <NSObject>
@optional
/// 点「再试一次」：以该 turn 为起点重新生成
- (void)messageCellDidTapRegenerate:(DSMessageCell *)cell;
/// 点「继续生成」：以该 turn 收尾正文为前缀续写（对齐 Web 版 continueGeneration）
- (void)messageCellDidTapContinue:(DSMessageCell *)cell;
/// 点「复制」之后（已写入剪贴板）
- (void)messageCellDidCopy:(DSMessageCell *)cell;
/// 分支切换：delta = -1 上一条，+1 下一条
- (void)messageCell:(DSMessageCell *)cell didSwitchBranch:(NSInteger)delta;
/// 点引用来源 / 搜索结果
- (void)messageCell:(DSMessageCell *)cell didTapURL:(NSURL *)url;
@end

@interface DSMessageCell : UITableViewCell

/// 当前渲染的 turn
@property (nonatomic, strong, readonly, nullable) DSTurn *turn;
@property (nonatomic, weak, nullable) id<DSMessageCellDelegate> delegate;
/// 是否显示「继续生成」：只有最后一条回答才能续写
@property (nonatomic, assign) BOOL showContinue;

/// 按 turn 渲染：用户气泡 / 助手 Fragment 序列（思考 → 该轮工具 → … → 正文）
- (void)configureWithTurn:(DSTurn *)turn;

@end

NS_ASSUME_NONNULL_END
