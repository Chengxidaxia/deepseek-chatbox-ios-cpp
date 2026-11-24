#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 流式对话事件类型（对齐 C++ StreamEvent）
typedef NS_ENUM(NSInteger, DSBoxStreamEventType) {
  DSBoxStreamEventContent = 0,      ///< 正文增量，text 携带片段
  DSBoxStreamEventReasoning = 1,    ///< 思考增量，text 携带片段
  DSBoxStreamEventToolCall = 2,     ///< 模型发起的本地工具调用增量，data 为 tool_calls 数组
  DSBoxStreamEventUsage = 3,        ///< token 用量，data 携带 prompt/completion
  DSBoxStreamEventTitle = 4,        ///< 自动生成标题，text 携带标题
  DSBoxStreamEventRefusal = 5,      ///< 拒答，text 携带原因
  DSBoxStreamEventServerTool = 6,   ///< 服务端工具调用（web_search 等），data 为 server_tool_calls 数组
  DSBoxStreamEventFinish = 7,       ///< 本轮完成，text 携带 finish_reason
  DSBoxStreamEventDone = 8,         ///< 单次 HTTP 流结束（多轮工具循环中每轮都会出现）
  DSBoxStreamEventError = 9,        ///< 错误，text 携带友好错误信息
  // ---- 多轮工具循环（对齐官方 Fragment 序列：思考 → 该轮工具 → 下一轮…）----
  DSBoxStreamEventRound = 10,       ///< 新一轮回答开始，data {round}
  DSBoxStreamEventRoundEnd = 11,    ///< 本轮 assistant 定稿，data 为该消息（含 tool_calls / server_tool_calls / usage）
  DSBoxStreamEventToolStart = 12,   ///< 本地工具开始执行，data {id,name,args,label,kind,query}
  DSBoxStreamEventToolEnd = 13,     ///< 本地工具执行结束，data {id,name,ok,text,ms,images}
  DSBoxStreamEventAnnotations = 14, ///< 引用来源，data 为 annotations 数组
};

@protocol DSBoxChatDelegate <NSObject>
/// 流式事件，已切回主线程
- (void)dsboxDidReceiveEvent:(DSBoxStreamEventType)type
                        text:(nullable NSString *)text
                        data:(nullable NSDictionary *)data;
@optional
/// 一轮完整结束（成功或失败），error 为 nil 表示成功
- (void)dsboxDidFinishWithError:(nullable NSError *)error;
@end

/// C++ core 的 ObjC++ 门面。UI 层只依赖本类，不接触任何 C++ 类型。
@interface DSBoxService : NSObject

+ (instancetype)shared;

/// 初始化本地存储（Documents/db.sqlite3）。必须在首次使用前调用一次。
- (BOOL)openStoreWithError:(NSError **)error;
/// 数据库文件所在目录（用于「导出数据」功能）
- (NSString *)documentsPath;

#pragma mark - 会话
- (NSArray<NSDictionary *> *)allConversations;             // id/uuid/title/updatedAt/pinned/group/messageCount
- (NSDictionary *)createConversation;                       // 新建空会话，返回整条
- (nullable NSDictionary *)conversationWithId:(NSString *)convId;
- (nullable NSDictionary *)conversationWithUuid:(NSString *)uuid;
- (NSArray<NSDictionary *> *)messagesOfConversation:(NSString *)convId;
- (BOOL)updateConversation:(NSString *)convId patch:(NSDictionary *)patch error:(NSError **)error;
- (BOOL)deleteConversation:(NSString *)convId error:(NSError **)error;
- (void)clearConversations;
/// 追加一条消息到会话（user/assistant 通用），返回带 id 的消息
- (NSDictionary *)appendMessage:(NSDictionary *)message toConversation:(NSString *)convId;
/// 批量追加（一次写盘，避免多轮工具消息产生多次全量更新）
- (NSArray<NSDictionary *> *)appendMessages:(NSArray<NSDictionary *> *)messages
                             toConversation:(NSString *)convId;
/// 按 id 更新一条消息的若干字段（用于分支候选、工具结果回填等）
- (BOOL)updateMessageWithId:(NSString *)msgId
             inConversation:(NSString *)convId
                      patch:(NSDictionary *)patch;
/// 用给定消息数组整体替换会话消息（分支切换 / 重新生成后的落盘）
- (BOOL)replaceMessages:(NSArray<NSDictionary *> *)messages
         inConversation:(NSString *)convId;
/// 整条会话快照导入导出
- (NSDictionary *)exportSnapshot;
- (BOOL)importSnapshot:(NSDictionary *)snap error:(NSError **)error;

#pragma mark - 附件
/// 把文件内容存进本地库，返回附件 id（att_xxx）
- (NSString *)putAttachmentData:(NSData *)data
                       filename:(NSString *)filename
                           mime:(NSString *)mime;
- (nullable NSData *)attachmentDataWithId:(NSString *)attId;

#pragma mark - 设置 / UI
- (NSDictionary *)settings;
- (void)saveSettingsPatch:(NSDictionary *)patch;
- (NSDictionary *)uiState;
- (void)saveUIPatch:(NSDictionary *)patch;

#pragma mark - 分组
- (NSArray<NSDictionary *> *)allGroups;
- (BOOL)saveGroups:(NSArray<NSDictionary *> *)groups error:(NSError **)error;

#pragma mark - API Key（PIN 加密存储）
- (BOOL)hasStoredKey;
- (BOOL)setApiKey:(NSString *)key pin:(NSString *)pin error:(NSError **)error;
/// 解锁并把 Key 留在内存供后续请求使用；PIN 不落盘
- (BOOL)unlockWithPin:(NSString *)pin error:(NSError **)error;
- (void)lockKey;                 // 清除内存中的 Key
- (void)clearStoredKey;          // 删除本机加密保存的 Key（含内存）
- (BOOL)isUnlocked;
- (NSString *)keyPreview;

#pragma mark - 工具
- (NSArray<NSDictionary *> *)toolDefinitions;              // 全部 40 个工具定义（名字/描述/参数）
- (NSArray<NSString *> *)searchTools:(NSString *)query topK:(NSInteger)topK;
/// 调用本地工具，返回 {ok, text, data, images}
- (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args;

#pragma mark - 模型 / 余额
- (NSArray<NSDictionary *> *)listModelsWithError:(NSError **)error;   // 需已解锁
- (NSDictionary *)getBalanceWithError:(NSError **)error;              // 需已解锁

#pragma mark - 语音
/// TTS：文本合成 WAV，写入临时文件返回路径
- (nullable NSString *)synthesizeText:(NSString *)text
                               voice:(NSString *)voice
                               error:(NSError **)error;
/// ASR：音频文件转文字（multipart 上传）
- (nullable NSString *)transcribeFile:(NSString *)path
                             filename:(NSString *)filename
                                error:(NSError **)error;

#pragma mark - 对话（流式）
/// 发起一轮流式对话。payload 由 core 的 buildPayload 构造；所有事件回调到 delegate（主线程）。
/// 返回 NO 表示入参校验失败（如未解锁 Key）；网络/API 错误走 delegate 的 Error 事件。
- (BOOL)streamChatWithConversation:(NSString *)convId
                          delegate:(id<DSBoxChatDelegate>)delegate
                             error:(NSError **)error;
/// 续写：把 continuePrefix 作为 assistant 前缀继续生成（对齐 Web 版 continueMode）。
/// 历史里的最后一条 assistant（即被续写的那条）会从请求中摘掉，服务端只返回新增内容，
/// 调用方负责把新内容拼回原消息。
- (BOOL)streamChatWithConversation:(NSString *)convId
                    continuePrefix:(nullable NSString *)continuePrefix
                          delegate:(id<DSBoxChatDelegate>)delegate
                             error:(NSError **)error;
/// 中止当前流式请求（UI 的「停止」按钮）
- (void)stopStream;

/// 构造 API 请求体（UI 预览/调试用）
- (NSDictionary *)buildPayloadForConversation:(NSString *)convId;

@end

NS_ASSUME_NONNULL_END
