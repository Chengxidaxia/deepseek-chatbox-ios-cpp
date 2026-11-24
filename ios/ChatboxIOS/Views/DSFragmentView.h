//
//  DSFragmentView.h
//  ChatboxIOS
//
//  助手回答的最小组成单元，对齐官方 Fragment 体系：
//  - DSToolCardView     ← ToolSearchFragmentView / ToolOpenFragmentView / ToolFindFragmentView
//  - DSToolGroupView    ← AgentGroupView（同一轮多个工具调用折叠成一组）
//  - DSBranchBar        ← BranchChooseView
//  - DSCitationListView ← CitationView / CiteIconsView
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DSToolStatus) {
  DSToolStatusRunning = 0,
  DSToolStatusOK,
  DSToolStatusFailed,
};

#pragma mark - 工具卡片

/// 单个工具调用的卡片：头部一行说明（三态），点开看完整结果。
@interface DSToolCardView : UIView

/// name: 工具名；args: 模型给出的参数（用来取 query/url 等副标题）
- (instancetype)initWithToolName:(NSString *)name arguments:(nullable NSDictionary *)args;

/// 状态变化（执行中 → 成功/失败）时更新文案
- (void)applyStatus:(DSToolStatus)status text:(nullable NSString *)text milliseconds:(NSInteger)ms;

/// 展开/收起导致高度变化时回调（宿主表格需要刷新行高）
@property (nonatomic, copy, nullable) void (^onLayoutChange)(void);
/// 点「展开」时把结果原文交给外部（用于「查看全文」等，可选）
@property (nonatomic, assign, readonly) BOOL expanded;

@end

#pragma mark - 联网搜索卡片

/// 服务端工具（web_search / 深度搜索）的搜索结果卡片，
/// 对齐官方 ToolSearchFragmentView：头部一行状态，展开看逐条来源。
@interface DSSearchResultCardView : UIView

/// calls: server_tool_calls 数组（每项含 type / status / action.queries / sources）
/// 传 nil 表示还没有结果，只显示「搜索中...」
- (void)applyServerToolCalls:(nullable NSArray<NSDictionary *> *)calls;

@property (nonatomic, copy, nullable) void (^onOpenURL)(NSURL *url);
@property (nonatomic, copy, nullable) void (^onLayoutChange)(void);

@end

#pragma mark - 分支切换

/// 「第 n 条消息（共 m 条）」+ 左右箭头，对齐官方 BranchChooseView
@interface DSBranchBar : UIView
@property (nonatomic, copy, nullable) void (^onPrev)(void);
@property (nonatomic, copy, nullable) void (^onNext)(void);
- (void)setIndex:(NSInteger)index total:(NSInteger)total;
@end

#pragma mark - 引用来源

@interface DSCitationListView : UIView
/// items: annotations 数组，元素形如 {title, url, site_name, snippet}
- (void)setCitations:(NSArray<NSDictionary *> *)items;
@property (nonatomic, copy, nullable) void (^onOpenURL)(NSURL *url);
@end

NS_ASSUME_NONNULL_END
