//
//  DSOperationView.h
//  ChatboxIOS
//
//  对齐官方 `InputAreaView` 下的两个运行态视图：
//      SearchOperationView      正在搜索
//      ReasoningOperationView   正在深度思考
//  它们在 `ActionAreaView` 里，和 `ToggleButtonGroup` 平级 —— 也就是说
//  **运行态不是「把 chip 变个颜色」**，而是一块独立的、带文案和计时的胶囊。
//  之前我们只改 chip 配色，信息量差很多。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DSOperationKind) {
  /// 深度思考中
  DSOperationKindReasoning = 0,
  /// 正在搜索 / 正在读取网页
  DSOperationKindSearch,
};

@interface DSOperationView : UIView

- (instancetype)initWithKind:(DSOperationKind)kind;

@property (nonatomic, readonly) DSOperationKind kind;

/// 中间那行文字，例如「正在深度思考」「正在搜索 3 个网页」。
@property (nonatomic, copy) NSString *text;

/// 开始计时并显示。重复调用不会重置起点。
- (void)start;

/// 停止并隐藏。返回本次持续秒数（<0 表示本来就没在跑）。
- (NSTimeInterval)stop;

/// 是否正在运行。
@property (nonatomic, readonly) BOOL running;

@end

NS_ASSUME_NONNULL_END
