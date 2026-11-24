//
//  DSTurn.h
//  ChatboxIOS
//
//  渲染单元。官方把一条回答拆成「Fragment 按顺序排列」，
//  这里把一屏要画的内容先归并成 turn：
//  - 用户 turn：一条 user 消息
//  - 助手 turn：从该提问开始的一串 assistant 消息（思考/工具/正文分多轮）
//    + 对应的 tool 结果，按发生顺序保留
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DSTurnRole) {
  DSTurnRoleUser = 0,
  DSTurnRoleAssistant,
};

@interface DSTurn : NSObject

@property (nonatomic, assign) DSTurnRole role;
/// 用户 turn 为用户消息；助手 turn 为该串消息里的第一条 assistant
@property (nonatomic, strong) NSDictionary *anchor;
/// 助手 turn：按顺序的 assistant 消息（最后一轮通常是带正文的收尾）
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rounds;
/// tool_call_id -> role=tool 的结果消息
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *toolResults;
/// 并联的 server_tool_calls（联网搜索），按到达顺序合并
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *serverCalls;
/// 引用来源 annotations
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *citations;

/// 分支：同一提问下的多条候选回答（1 表示没有分支）
@property (nonatomic, assign) NSInteger branchIndex;
@property (nonatomic, assign) NSInteger branchTotal;
/// 分支消息段（用于切换时整段替换），形如 {rounds:[...], tools:[...]}
@property (nonatomic, strong, nullable) NSArray<NSDictionary *> *branches;

@property (nonatomic, assign) BOOL streaming;
/// 状态提示（已停止生成 / 错误）
@property (nonatomic, copy, nullable) NSString *statusNote;

/// 把扁平的消息数组归并成 turn 列表
+ (NSArray<DSTurn *> *)turnsFromMessages:(NSArray<NSDictionary *> *)messages;

/// 取该 turn 有正文的那一轮（收尾轮），没有正文时取最后一轮
@property (nonatomic, readonly, nullable) NSDictionary *tailRound;

@end

NS_ASSUME_NONNULL_END
