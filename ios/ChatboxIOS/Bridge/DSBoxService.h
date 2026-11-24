#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 流式对话事件类型（对齐 C++ StreamEvent）
typedef NS_ENUM(NSInteger, DSBoxStreamEventType) {
  DSBoxStreamEventContent = 0,      ///< 正文增量，text 携带片段
  DSBoxStreamEventReasoning = 1,    ///< 思考增量，text 携带片段
  DSBoxStreamEventToolCall = 2,     ///< 工具调用，data 携带 name/arguments
  DSBoxStreamEventUsage = 3,        ///< token 用量，data 携带 prompt/completion
  DSBoxStreamEventTitle = 4,        ///< 自动生成标题，text 携带标题
  DSBoxStreamEventRefusal = 5,      ///< 拒答，text 携带原因
  DSBoxStreamEventServerTool = 6,   ///< 服务端工具调用（web_search 等）
  DSBoxStreamEventFinish = 7,       ///< 本轮完成，data 携带 finish_reason
  DSBoxStreamEventDone = 8,         ///< 流结束
  DSBoxStreamEventError = 9,        ///< 错误，text 携带友好错误信息
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
/// 整条会话快照导入导出
- (NSDictionary *)exportSnapshot;
- (BOOL)importSnapshot:(NSDictionary *)snap error:(NSError **)error;

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
/// 中止当前流式请求（UI 的「停止」按钮）
- (void)stopStream;

/// 构造 API 请求体（UI 预览/调试用）
- (NSDictionary *)buildPayloadForConversation:(NSString *)convId;

@end

NS_ASSUME_NONNULL_END
