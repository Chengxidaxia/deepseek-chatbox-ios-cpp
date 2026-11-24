#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 会话列表。两种用法：
/// - 抽屉模式（官方形态）：`drawerMode = YES`，自带「开启新对话 / 搜索 / 列表 / 设置」四段，
///   选中会话通过 `onSelectConversation` 回调，不自己 push。
/// - 独立页模式：`drawerMode = NO`，沿用导航栏 + push。
@interface DSConversationListController : UIViewController

@property (nonatomic, assign) BOOL drawerMode;

@property (nonatomic, copy, nullable) void (^onSelectConversation)(NSString *convId);
@property (nonatomic, copy, nullable) void (^onNewChat)(void);
@property (nonatomic, copy, nullable) void (^onOpenSettings)(void);
/// 某个会话被删除。删的若是当前正在看的那条，容器需要换一个会话，
/// 否则聊天页会停在一个已经不存在的会话上。
@property (nonatomic, copy, nullable) void (^onConversationDeleted)(NSString *convId);

@end

NS_ASSUME_NONNULL_END
