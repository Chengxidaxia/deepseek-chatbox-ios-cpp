//
//  DSTopBarView.h
//  ChatboxIOS
//
//  官方聊天页顶栏（对应 `chat/top_bar/*`）：**自绘，不是 UINavigationBar**。
//  左 ☰（`Ic_menu_outline_24`）打开侧边会话抽屉；中间是模型选择（`modelChoose`，
//  模型名 + ⌄，点开是带勾的列表）；右 ＋（`ic_new_chat_outline_24`）新对话。
//  与页面同色、无分割线、无投影 —— 内容从下面滚过去看不出边界。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSTopBarView : UIView

/// 左侧 ☰
@property (nonatomic, copy, nullable) void (^onMenu)(void);
/// 中间模型名（点开模型列表）
@property (nonatomic, copy, nullable) void (^onModel)(void);
/// 右侧 ＋（新对话）
@property (nonatomic, copy, nullable) void (^onNewChat)(void);

/// 中间显示的文字（当前模型展示名）
@property (nonatomic, copy, nullable) NSString *modelTitle;

/// 设计高度（不含安全区）
@property (class, nonatomic, readonly) CGFloat preferredHeight;

/// 中间那个按钮本身（iPad 上弹模型列表时当 popover 锚点用）
@property (nonatomic, strong, readonly) UIButton *modelButton;

@end

NS_ASSUME_NONNULL_END
