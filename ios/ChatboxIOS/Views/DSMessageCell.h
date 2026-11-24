#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DSMessageCell;

@protocol DSMessageCellDelegate <NSObject>
@optional
/// 点「再试一次」：以该消息为起点重新生成
- (void)messageCellDidTapRegenerate:(DSMessageCell *)cell;
/// 点「复制」之后（已写入剪贴板）
- (void)messageCellDidCopy:(DSMessageCell *)cell;
@end

@interface DSMessageCell : UITableViewCell

/// 当前渲染的消息（含 id / role / content / reasoning 等）
@property (nonatomic, strong, readonly, nullable) NSDictionary *message;
@property (nonatomic, weak, nullable) id<DSMessageCellDelegate> delegate;

- (void)configure:(NSDictionary *)message;

/// 展开/收起思考块（默认按 thinkingAutoFold 折叠）
- (void)setThinkExpanded:(BOOL)expanded;

@end

NS_ASSUME_NONNULL_END
