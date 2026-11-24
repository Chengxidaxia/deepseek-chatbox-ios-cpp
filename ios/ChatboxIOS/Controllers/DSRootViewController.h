//
//  DSRootViewController.h
//  ChatboxIOS
//
//  根容器。官方是 `RootViewController` + `SidebarViewController`：
//  聊天页常驻，会话列表是**从左侧滑出的抽屉**（不是导航栈里 push 出来的一页）。
//  这里就照这个结构做：聊天页做子控制器，抽屉盖在上面，配一层可点击关闭的遮罩。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSRootViewController : UIViewController

/// 传 nil 时自动用「上次打开的会话」，没有就新建一个。
- (instancetype)initWithConversationId:(nullable NSString *)convId;

- (void)openSidebar;
- (void)closeSidebar;

@end

NS_ASSUME_NONNULL_END
