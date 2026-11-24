#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSChatViewController : UIViewController
- (instancetype)initWithConversationId:(NSString *)convId;

/// 顶栏左侧 ☰：打开侧边会话抽屉（由 DSRootViewController 注入）
@property (nonatomic, copy, nullable) void (^onMenuTap)(void);
/// 顶栏右侧 ＋：开启新对话（由 DSRootViewController 注入，负责换掉整个聊天页）
@property (nonatomic, copy, nullable) void (^onNewChat)(void);

/// 当前会话 id
@property (nonatomic, readonly) NSString *conversationId;
@end

NS_ASSUME_NONNULL_END
