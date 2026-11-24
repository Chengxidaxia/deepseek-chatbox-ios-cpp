#import "DSBoxService.h"
#import <UIKit/UIKit.h>

// C++ core（本文件是 .mm，ObjC++ 可直接 include C++ 头）
#include "store.hpp"
#include "api.hpp"
#include "crypto.hpp"
#include "tools.hpp"
#include "util.hpp"

#include <atomic>
#include <memory>
#include <string>
#include <vector>

using namespace ds;

// ------------------------------ json <-> ObjC ------------------------------
static NSString *NSStr(const std::string &s) {
  return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}
static std::string StdStr(NSString *s) {
  if (!s) return "";
  return std::string([s UTF8String], [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

static id ToObjC(const json &j);
static NSDictionary *ToDict(const json &j) {
  if (!j.is_object()) return @{};
  NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:j.size()];
  for (auto it = j.begin(); it != j.end(); ++it) out[NSStr(it.key())] = ToObjC(it.value()) ?: NSNull.null;
  return out;
}
static NSArray *ToArray(const json &j) {
  if (!j.is_array()) return @[];
  NSMutableArray *out = [NSMutableArray arrayWithCapacity:j.size()];
  for (const auto &v : j) [out addObject:ToObjC(v) ?: NSNull.null];
  return out;
}
static id ToObjC(const json &j) {
  if (j.is_null()) return NSNull.null;
  if (j.is_boolean()) return @(j.get<bool>());
  if (j.is_number_integer()) {
    int64_t v = j.get<int64_t>();
    return [NSNumber numberWithLongLong:v];
  }
  if (j.is_number_unsigned()) return [NSNumber numberWithUnsignedLongLong:j.get<uint64_t>()];
  if (j.is_number_float()) return @(j.get<double>());
  if (j.is_string()) return NSStr(j.get<std::string>());
  if (j.is_array()) return ToArray(j);
  if (j.is_object()) return ToDict(j);
  return NSNull.null;
}
static json ToJson(id obj) {
  if (!obj || obj == NSNull.null) return nullptr;
  if ([obj isKindOfClass:NSString.class]) return StdStr((NSString *)obj);
  if ([obj isKindOfClass:NSNumber.class]) {
    NSNumber *n = (NSNumber *)obj;
    // 区分布尔与数字：ObjC 里 __NSCFBoolean / __NSCFNumber
    if (strcmp([n objCType], @encode(BOOL)) == 0) return (bool)n.boolValue;
    return n.longLongValue;
  }
  if ([obj isKindOfClass:NSArray.class]) {
    json a = json::array();
    for (id v in (NSArray *)obj) a.push_back(ToJson(v));
    return a;
  }
  if ([obj isKindOfClass:NSDictionary.class]) {
    json o = json::object();
    for (NSString *k in (NSDictionary *)obj) o[StdStr(k)] = ToJson(((NSDictionary *)obj)[k]);
    return o;
  }
  return nullptr;
}
static NSError *MakeErr(NSString *msg, NSInteger code = -1) {
  return [NSError errorWithDomain:@"DSBoxCore" code:code
                         userInfo:@{NSLocalizedDescriptionKey: msg ?: @"未知错误"}];
}

// ------------------------------ 内部状态 ------------------------------
@interface DSBoxService () {
  std::unique_ptr<Store> store_;
  std::unique_ptr<ApiClient> api_;
  std::string unlockedKey_;
  std::atomic<bool> stop_;
  __weak id<DSBoxChatDelegate> streamDelegate_;  // 弱引用，避免页面释放后仍被回调
}
- (void)runAgentLoopWithHistory:(std::vector<Message>)history
                       settings:(Settings)st
                       toolDefs:(std::vector<json>)toolDefs
                 continuePrefix:(std::string)continuePrefix
                       delegate:(id<DSBoxChatDelegate>)delegate
                         apiKey:(std::string)apiKey;
- (void)emitToDelegate:(id<DSBoxChatDelegate>)delegate
                  type:(DSBoxStreamEventType)type
                  text:(NSString *)text
                  data:(NSDictionary *)data;
@end

@implementation DSBoxService

+ (instancetype)shared {
  static DSBoxService *s = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ s = [[self alloc] init]; });
  return s;
}

- (instancetype)init {
  if (self = [super init]) {
    stop_.store(false);
    api_ = std::make_unique<ApiClient>();
  }
  return self;
}

- (BOOL)openStoreWithError:(NSError **)error {
  NSString *docs = self.documentsPath;
  NSString *dbPath = [docs stringByAppendingPathComponent:@"db.sqlite3"];
  try {
    store_ = std::make_unique<Store>(StdStr(dbPath));
    std::string err;
    if (!store_->open(&err)) {
      if (error) *error = MakeErr(NSStr(err));
      return NO;
    }
    // 已加密存的 Key：把 hasKey/keyPreview 同步进 settings，UI 可直接显示
    Settings st = store_->settings();
    st.hasKey = store_->hasKeyEncrypted();
    if (st.hasKey && st.keyPreview.empty()) st.keyPreview = @"••••••••".UTF8String;
    store_->saveSettings(st.toJson());
    return YES;
  } catch (const std::exception &e) {
    if (error) *error = MakeErr(NSStr(std::string("数据库打开失败: ") + e.what()));
    return NO;
  }
}

- (NSString *)documentsPath {
  static NSString *p = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    p = paths.firstObject ?: NSHomeDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
  });
  return p;
}

#pragma mark - 会话
- (NSArray<NSDictionary *> *)allConversations {
  if (!store_) return @[];
  NSMutableArray *out = [NSMutableArray array];
  for (const auto &c : store_->allConversations()) {
    [out addObject:@{
      @"id": NSStr(c.id), @"uuid": NSStr(c.uuid), @"title": NSStr(c.title),
      @"createdAt": @(c.createdAt), @"updatedAt": @(c.updatedAt),
      @"pinned": @(c.pinned), @"groupId": NSStr(c.groupId),
      @"messageCount": @(c.messages.size()),
      @"preview": NSStr(c.messages.empty() ? "" : c.messages.back().content).length > 120
        ? [NSStr(c.messages.back().content) substringToIndex:120]
        : NSStr(c.messages.empty() ? "" : c.messages.back().content),
    }];
  }
  return out;
}

- (NSDictionary *)createConversation {
  if (!store_) return @{};
  Conversation c = store_->createConversation();
  return ToDict(c.toJson());
}

- (NSDictionary *)conversationWithId:(NSString *)convId {
  if (!store_) return @{};
  auto c = store_->getConversation(StdStr(convId));
  return c ? ToDict(c->toJson()) : @{};
}

- (NSDictionary *)conversationWithUuid:(NSString *)uuid {
  if (!store_) return @{};
  auto c = store_->getConversationByUuid(StdStr(uuid));
  return c ? ToDict(c->toJson()) : @{};
}

- (NSArray<NSDictionary *> *)messagesOfConversation:(NSString *)convId {
  if (!store_) return @[];
  auto c = store_->getConversation(StdStr(convId));
  if (!c) return @[];
  NSMutableArray *out = [NSMutableArray arrayWithCapacity:c->messages.size()];
  for (const auto &m : c->messages) [out addObject:ToDict(m.toJson())];
  return out;
}

- (BOOL)updateConversation:(NSString *)convId patch:(NSDictionary *)patch error:(NSError **)error {
  if (!store_) { if (error) *error = MakeErr(@"存储未初始化"); return NO; }
  if (!store_->updateConversation(StdStr(convId), ToJson(patch))) {
    if (error) *error = MakeErr(@"更新会话失败");
    return NO;
  }
  return YES;
}

- (BOOL)deleteConversation:(NSString *)convId error:(NSError **)error {
  if (!store_) { if (error) *error = MakeErr(@"存储未初始化"); return NO; }
  if (!store_->deleteConversation(StdStr(convId))) {
    if (error) *error = MakeErr(@"删除会话失败");
    return NO;
  }
  return YES;
}

- (void)clearConversations { if (store_) store_->clearConversations(); }

- (NSDictionary *)appendMessage:(NSDictionary *)message toConversation:(NSString *)convId {
  if (!store_) return @{};
  auto c = store_->getConversation(StdStr(convId));
  if (!c) return @{};
  Message m = Message::fromJson(ToJson(message));
  if (m.id.empty()) m.id = util::uuid();
  if (m.createdAt == 0) m.createdAt = (int64_t)time(nullptr);
  c->messages.push_back(m);
  c->updatedAt = (int64_t)time(nullptr);
  store_->updateConversation(StdStr(convId), c->toJson());
  return ToDict(m.toJson());
}

- (NSArray<NSDictionary *> *)appendMessages:(NSArray<NSDictionary *> *)messages
                             toConversation:(NSString *)convId {
  if (!store_ || messages.count == 0) return @[];
  auto c = store_->getConversation(StdStr(convId));
  if (!c) return @[];
  NSMutableArray *out = [NSMutableArray array];
  for (NSDictionary *d in messages) {
    Message m = Message::fromJson(ToJson(d));
    if (m.id.empty()) m.id = util::uuid();
    if (m.createdAt == 0) m.createdAt = (int64_t)time(nullptr);
    c->messages.push_back(m);
    [out addObject:ToDict(m.toJson())];
  }
  c->updatedAt = (int64_t)time(nullptr);
  store_->updateConversation(StdStr(convId), c->toJson());
  return out;
}

- (BOOL)updateMessageWithId:(NSString *)msgId
             inConversation:(NSString *)convId
                      patch:(NSDictionary *)patch {
  if (!store_ || msgId.length == 0) return NO;
  auto c = store_->getConversation(StdStr(convId));
  if (!c) return NO;
  std::string id = StdStr(msgId);
  for (auto &m : c->messages) {
    if (m.id != id) continue;
    // 在已有 JSON 上打补丁，再重建结构体：保留未提及字段（含 extra 透传）
    json j = m.toJson();
    json p = ToJson(patch);
    for (auto it = p.begin(); it != p.end(); ++it) j[it.key()] = it.value();
    m = Message::fromJson(j);
    m.id = id;
    c->updatedAt = (int64_t)time(nullptr);
    return store_->updateConversation(StdStr(convId), c->toJson());
  }
  return NO;
}

- (BOOL)replaceMessages:(NSArray<NSDictionary *> *)messages
         inConversation:(NSString *)convId {
  if (!store_) return NO;
  auto c = store_->getConversation(StdStr(convId));
  if (!c) return NO;
  c->messages.clear();
  for (NSDictionary *d in messages) {
    Message m = Message::fromJson(ToJson(d));
    if (m.id.empty()) m.id = util::uuid();
    if (m.createdAt == 0) m.createdAt = (int64_t)time(nullptr);
    c->messages.push_back(m);
  }
  c->updatedAt = (int64_t)time(nullptr);
  return store_->updateConversation(StdStr(convId), c->toJson());
}

#pragma mark - 附件

- (NSString *)putAttachmentData:(NSData *)data
                       filename:(NSString *)filename
                           mime:(NSString *)mime {
  if (!store_ || data.length == 0) return @"";
  std::vector<unsigned char> buf((const unsigned char *)data.bytes,
                                 (const unsigned char *)data.bytes + data.length);
  return NSStr(store_->putAttachment(StdStr(filename ?: @"file"), StdStr(mime ?: @"application/octet-stream"), buf));
}

- (NSData *)attachmentDataWithId:(NSString *)attId {
  if (!store_) return nil;
  auto a = store_->getAttachment(StdStr(attId));
  if (!a || a->data.empty()) return nil;
  return [NSData dataWithBytes:a->data.data() length:a->data.size()];
}

- (NSDictionary *)exportSnapshot { return store_ ? ToDict(store_->snapshot()) : @{}; }
- (BOOL)importSnapshot:(NSDictionary *)snap error:(NSError **)error {
  if (!store_) { if (error) *error = MakeErr(@"存储未初始化"); return NO; }
  if (!store_->importSnapshot(ToJson(snap))) {
    if (error) *error = MakeErr(@"导入快照失败");
    return NO;
  }
  return YES;
}

#pragma mark - 设置 / UI
- (NSDictionary *)settings {
  if (!store_) return @{};
  Settings s = store_->settings();
  s.hasKey = store_->hasKeyEncrypted();
  return ToDict(s.toJson());
}
- (void)saveSettingsPatch:(NSDictionary *)patch {
  if (store_) store_->saveSettings(ToJson(patch));
}
- (NSDictionary *)uiState { return store_ ? ToDict(store_->ui().toJson()) : @{}; }
- (void)saveUIPatch:(NSDictionary *)patch { if (store_) store_->saveUI(ToJson(patch)); }

#pragma mark - 分组
- (NSArray<NSDictionary *> *)allGroups {
  if (!store_) return @[];
  NSMutableArray *out = [NSMutableArray array];
  for (const auto &g : store_->allGroups()) [out addObject:ToDict(g.toJson())];
  return out;
}
- (BOOL)saveGroups:(NSArray<NSDictionary *> *)groups error:(NSError **)error {
  if (!store_) { if (error) *error = MakeErr(@"存储未初始化"); return NO; }
  std::vector<Group> gs;
  for (NSDictionary *d in groups) gs.push_back(Group::fromJson(ToJson(d)));
  if (!store_->saveGroups(gs)) { if (error) *error = MakeErr(@"保存分组失败"); return NO; }
  return YES;
}

#pragma mark - API Key
- (BOOL)hasStoredKey { return store_ && store_->hasKeyEncrypted(); }
- (BOOL)setApiKey:(NSString *)key pin:(NSString *)pin error:(NSError **)error {
  if (!store_) { if (error) *error = MakeErr(@"存储未初始化"); return NO; }
  if (pin.length < 4) { if (error) *error = MakeErr(@"PIN 至少 4 位"); return NO; }
  std::string err;
  if (!store_->setKeyEncrypted(StdStr(key), StdStr(pin), &err)) {
    if (error) *error = MakeErr(NSStr(err.empty() ? "保存 Key 失败" : err));
    return NO;
  }
  unlockedKey_ = StdStr(key);  // 设置后立即处于解锁态
  Settings st = store_->settings();
  st.hasKey = true;
  st.keyPreview = util::maskKey(StdStr(key));  // 返回 std::string，直接赋给 Settings
  store_->saveSettings(st.toJson());
  return YES;
}
- (BOOL)unlockWithPin:(NSString *)pin error:(NSError **)error {
  if (!store_) { if (error) *error = MakeErr(@"存储未初始化"); return NO; }
  std::string err;
  std::string key = store_->unlockKey(StdStr(pin), &err);
  if (key.empty()) {
    if (error) *error = MakeErr(NSStr(err.empty() ? std::string("PIN 错误") : err));
    return NO;
  }
  unlockedKey_ = key;
  return YES;
}
- (void)lockKey { unlockedKey_.clear(); }
- (void)clearStoredKey {
  if (store_) store_->clearKey();
  unlockedKey_.clear();
  if (store_) {
    Settings st = store_->settings();
    st.hasKey = false;
    st.keyPreview.clear();
    store_->saveSettings(st.toJson());
  }
}
- (BOOL)isUnlocked { return !unlockedKey_.empty(); }
- (NSString *)keyPreview { return store_ ? NSStr(store_->settings().keyPreview) : @""; }

#pragma mark - 工具
- (NSArray<NSDictionary *> *)toolDefinitions {
  auto &eng = ToolEngine::instance();
  if (eng.definitions().empty()) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"tool_defs" ofType:@"json"];
    std::string err;
    eng.loadDefinitions(StdStr(path ?: @""), &err);
  }
  NSMutableArray *out = [NSMutableArray array];
  for (const auto &n : eng.names()) {
    // 从 defs 找对应描述
    NSString *desc = @"";
    for (const auto &d : eng.definitions()) {
      if (d.contains("function") && d["function"].value("name", "") == n) {
        desc = NSStr(d["function"].value("description", ""));
        break;
      }
    }
    [out addObject:@{@"name": NSStr(n), @"description": desc}];
  }
  return out;
}
- (NSArray<NSString *> *)searchTools:(NSString *)query topK:(NSInteger)topK {
  auto &eng = ToolEngine::instance();
  NSMutableArray *out = [NSMutableArray array];
  for (const auto &h : eng.search(StdStr(query), (int)topK)) [out addObject:NSStr(h.first)];
  return out;
}
- (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args {
  ToolContext ctx;
  ctx.apiKey = unlockedKey_;
  // ObjC 方法里没有 C++ 的 this；lambda 捕获 self，访问 ivar 用 self->
  ctx.conversations = [self]() { return self->store_ ? self->store_->allConversations() : std::vector<Conversation>{}; };
  ctx.getBalance = [self](const std::string &key, std::string *err) {
    return self->api_ ? self->api_->getBalance(key, err) : Balance{};
  };
  ctx.listModels = [self](const std::string &key, std::string *err) {
    return self->api_ ? self->api_->listModels(key, err) : std::vector<ModelInfo>{};
  };
  ToolResult r = ToolEngine::instance().call(StdStr(name), ToJson(args), ctx);
  return ToDict(r.toJson());
}

#pragma mark - 模型 / 余额
- (NSArray<NSDictionary *> *)listModelsWithError:(NSError **)error {
  if (!api_ || unlockedKey_.empty()) { if (error) *error = MakeErr(@"请先解锁 Key"); return @[]; }
  std::string err;
  auto models = api_->listModels(unlockedKey_, &err);
  if (!err.empty() && models.empty()) { if (error) *error = MakeErr(NSStr(err)); return @[]; }
  NSMutableArray *out = [NSMutableArray array];
  for (const auto &m : models) [out addObject:ToDict(m.toJson())];
  return out;
}
- (NSDictionary *)getBalanceWithError:(NSError **)error {
  if (!api_ || unlockedKey_.empty()) { if (error) *error = MakeErr(@"请先解锁 Key"); return @{}; }
  std::string err;
  Balance b = api_->getBalance(unlockedKey_, &err);
  if (!err.empty() && b.raw.empty()) { if (error) *error = MakeErr(NSStr(err)); return @{}; }
  return ToDict(b.raw);
}

#pragma mark - 语音
- (NSString *)synthesizeText:(NSString *)text voice:(NSString *)voice error:(NSError **)error {
  if (!api_ || unlockedKey_.empty()) { if (error) *error = MakeErr(@"请先解锁 Key"); return nil; }
  std::vector<unsigned char> wav;
  std::string err;
  if (!api_->synthesize(StdStr(text), StdStr(voice), unlockedKey_, &wav, &err)) {
    if (error) *error = MakeErr(NSStr(err.empty() ? std::string("语音合成失败") : err));
    return nil;
  }
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"tts-%lld.wav", (long long)[[NSDate date] timeIntervalSince1970]*1000]];
  NSData *data = [NSData dataWithBytes:wav.data() length:wav.size()];
  if (![data writeToFile:path atomically:YES]) {
    if (error) *error = MakeErr(@"写入语音文件失败");
    return nil;
  }
  return path;
}
- (NSString *)transcribeFile:(NSString *)path filename:(NSString *)filename error:(NSError **)error {
  if (!api_ || unlockedKey_.empty()) { if (error) *error = MakeErr(@"请先解锁 Key"); return nil; }
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data) { if (error) *error = MakeErr(@"读取音频失败"); return nil; }
  std::vector<unsigned char> audio((const unsigned char *)data.bytes, (const unsigned char *)data.bytes + data.length);
  json out; std::string err;
  if (!api_->transcribe(audio, StdStr(filename), unlockedKey_, &out, &err)) {
    if (error) *error = MakeErr(NSStr(err.empty() ? std::string("语音识别失败") : err));
    return nil;
  }
  if (out.contains("text") && out["text"].is_string()) return NSStr(out["text"].get<std::string>());
  return NSStr(out.dump());
}

#pragma mark - 对话（流式）
- (NSDictionary *)buildPayloadForConversation:(NSString *)convId {
  if (!store_) return @{};
  auto c = store_->getConversation(StdStr(convId));
  if (!c) return @{};
  Settings st = store_->settings();
  std::vector<json> toolDefs;
  if (st.localTools) {
    auto &eng = ToolEngine::instance();
    std::string query;
    for (auto it = c->messages.rbegin(); it != c->messages.rend(); ++it) {
      if (it->role == "user") { query = it->content; break; }
    }
    auto hits = query.empty() ? std::vector<std::pair<std::string, json>>{}
                              : eng.search(query, st.toolTopK);
    for (const auto &h : hits) toolDefs.push_back(h.second);
  }
  return ToDict(ApiClient::buildPayload(c->messages, st, toolDefs));
}

- (BOOL)streamChatWithConversation:(NSString *)convId
                          delegate:(id<DSBoxChatDelegate>)delegate
                             error:(NSError **)error {
  return [self streamChatWithConversation:convId continuePrefix:nil delegate:delegate error:error];
}

- (BOOL)streamChatWithConversation:(NSString *)convId
                    continuePrefix:(NSString *)continuePrefix
                          delegate:(id<DSBoxChatDelegate>)delegate
                             error:(NSError **)error {
  if (!store_ || !api_) { if (error) *error = MakeErr(@"核心未初始化"); return NO; }
  if (unlockedKey_.empty()) { if (error) *error = MakeErr(@"请先解锁 Key"); return NO; }
  auto c = store_->getConversation(StdStr(convId));
  if (!c) { if (error) *error = MakeErr(@"会话不存在"); return NO; }

  streamDelegate_ = delegate;
  stop_.store(false);

  // 历史与工具定义在这里取一次快照，交给后台循环；循环内不再读库，保证同一轮提问内一致
  Settings st = store_->settings();
  std::vector<Message> history = c->messages;
  const std::string prefix = StdStr(continuePrefix ?: @"");
  if (!prefix.empty()) {
    // 续写：被续写的那条回答不作为历史发送，改由 buildPayload 以 prefix 形式追加到末尾
    while (!history.empty() && history.back().role == "assistant" && history.back().content.empty() &&
           history.back().toolCalls.empty())
      history.pop_back();
    if (!history.empty() && history.back().role == "assistant") history.pop_back();
  }
  // 图片附件按 attId 从库里补出 data URL（存在库里而不是消息 JSON 里，避免消息膨胀）
  for (auto &m : history) {
    for (auto &a : m.attachments) {
      if (a.kind != "image" || !a.dataUrl.empty() || a.id.empty()) continue;
      auto rec = store_->getAttachment(a.id);
      if (!rec || rec->data.empty()) continue;
      std::string bytes(reinterpret_cast<const char *>(rec->data.data()), rec->data.size());
      std::string mime = rec->mime.empty() ? "image/jpeg" : rec->mime;
      a.dataUrl = "data:" + mime + ";base64," + util::base64Encode(bytes);
    }
  }
  std::vector<json> toolDefs;
  if (st.localTools) {
    auto &eng = ToolEngine::instance();
    // 对齐 Web 版动态工具检索：用最后一条用户消息作检索词
    std::string query;
    for (auto it = history.rbegin(); it != history.rend(); ++it) {
      if (it->role == "user") { query = it->content; break; }
    }
    auto hits = query.empty() ? std::vector<std::pair<std::string, json>>{}
                              : eng.search(query, st.toolTopK);
    for (const auto &h : hits) toolDefs.push_back(h.second);
  }
  std::string apiKey = unlockedKey_;  // 复制到请求线程，避免竞态

  // libcurl + 工具执行都在后台队列，UI 只收事件
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self runAgentLoopWithHistory:history settings:st toolDefs:toolDefs
                   continuePrefix:prefix delegate:delegate apiKey:apiKey];
  });
  return YES;
}

#pragma mark - 多轮工具循环

/// 一次提问 = 若干轮「思考 → 工具调用 → 结果」，直到模型不再请求工具。
/// 中间消息只通过回调交给 UI，由 UI 统一落盘，避免半截历史写进库。
/// 上限、收尾提示与 Web 版 MAX_TOOL_ROUNDS 保持一致。
- (void)runAgentLoopWithHistory:(std::vector<Message>)history
                       settings:(Settings)st
                       toolDefs:(std::vector<json>)toolDefs
                 continuePrefix:(std::string)continuePrefix
                       delegate:(id<DSBoxChatDelegate>)delegate
                         apiKey:(std::string)apiKey {
  const int kMaxRounds = 10;

  // 事件转发：C++ lambda 调用 ObjC 方法，由方法把事件放到主线程。
  // 不直接捕获 ObjC block，避免 C++ lambda 捕获 block 时的 ARC 歧义。
  auto emit = [self, delegate](DSBoxStreamEventType type, NSString *text, NSDictionary *data) {
    [self emitToDelegate:delegate type:type text:text data:data];
  };

  std::string fatal;

  for (int round = 0; round < kMaxRounds && fatal.empty(); ++round) {
    if (stop_.load()) break;
    emit(DSBoxStreamEventRound, nil, @{@"round": @(round)});

    // 轮次用满：关掉工具通道并说明原因，让模型基于已有结果收尾，而不是静默中断
    const bool lastRound = (round == kMaxRounds - 1);
    json payload = ApiClient::buildPayload(history, st,
        lastRound ? std::vector<json>{} : toolDefs, false,
        round == 0 ? continuePrefix : std::string());
    if (lastRound && payload.contains("messages") && payload["messages"].is_array()) {
      const std::string note =
          "【系统提示】本次提问中，「请求工具 → 看结果 → 再请求」的往返轮次已经用满（上限 10 轮），"
          "工具通道现已关闭，不能再发起任何工具调用。请基于已有结果直接作答。";
      json &msgs = payload["messages"];
      if (!msgs.empty() && msgs[0].value("role", "") == "system")
        msgs[0]["content"] = msgs[0].value("content", std::string()) + "\n\n" + note;
      else
        msgs.insert(msgs.begin(), json{{"role", "system"}, {"content", note}});
    }

    std::string content, reasoning;
    json usage = nullptr, serverTools = nullptr, annotations = nullptr;
    std::vector<ToolCall> calls;
    std::vector<std::string> argsBuf;

    StreamOptions opts;
    opts.apiKey = apiKey;
    opts.baseUrl = st.baseUrl;
    // 续写只有第一轮带前缀，且必须走 beta 端点（官方文档要求）
    opts.beta = (round == 0 && !continuePrefix.empty());
    opts.shouldStop = [self]() { return self->stop_.load(); };
    opts.onEvent = [&](const StreamEvent &e) {
      switch (e.type) {
        case StreamEvent::Content:
          content += e.text;
          emit(DSBoxStreamEventContent, NSStr(e.text), nil);
          break;
        case StreamEvent::Reasoning:
          reasoning += e.text;
          emit(DSBoxStreamEventReasoning, NSStr(e.text), nil);
          break;
        case StreamEvent::ToolCallDelta: {
          // 分片累积：id 覆盖、name 只取第一次、arguments 拼接（同 Web 版）
          if (!e.data.is_array()) break;
          int autoIdx = 0;
          for (const auto &d : e.data) {
            int idx = d.value("index", autoIdx++);
            if (idx < 0) idx = 0;
            while ((int)calls.size() <= idx) { calls.push_back(ToolCall{}); argsBuf.push_back(""); }
            if (d.contains("id") && d["id"].is_string() && !d["id"].get<std::string>().empty())
              calls[idx].id = d["id"].get<std::string>();
            if (d.contains("function") && d["function"].is_object()) {
              const auto &f = d["function"];
              if (f.contains("name") && f["name"].is_string() && calls[idx].name.empty())
                calls[idx].name = f["name"].get<std::string>();
              if (f.contains("arguments") && f["arguments"].is_string())
                argsBuf[idx] += f["arguments"].get<std::string>();
            }
          }
          break;
        }
        case StreamEvent::Usage:
          usage = e.data;
          emit(DSBoxStreamEventUsage, nil, ToDict(e.data));
          break;
        case StreamEvent::Title:
          emit(DSBoxStreamEventTitle, NSStr(e.text), nil);
          break;
        case StreamEvent::Refusal:
          emit(DSBoxStreamEventRefusal, NSStr(e.message.empty() ? e.text : e.message), nil);
          break;
        case StreamEvent::ServerToolCalls:
          serverTools = e.data;
          emit(DSBoxStreamEventServerTool, nil, @{@"calls": ToObjC(e.data) ?: @[]});
          break;
        case StreamEvent::ToolEvent:
          emit(DSBoxStreamEventServerTool, nil, @{@"event": ToObjC(e.data) ?: @{}});
          break;
        case StreamEvent::Annotations:
          annotations = e.data;
          emit(DSBoxStreamEventAnnotations, nil, @{@"annotations": ToObjC(e.data) ?: @[]});
          break;
        case StreamEvent::Finish:
          emit(DSBoxStreamEventFinish, e.text.empty() ? nil : NSStr(e.text), nil);
          break;
        case StreamEvent::Error:
          fatal = e.message.empty() ? "生成失败" : e.message;
          break;
        case StreamEvent::Done:
          break;  // 单轮 HTTP 结束；是否继续下一轮由循环决定
      }
    };

    std::string err;
    if (!api_ || !api_->streamChat(payload, opts, &err)) {
      if (fatal.empty()) fatal = err.empty() ? "请求失败" : err;
      break;
    }
    if (!fatal.empty()) break;

    // ---- 本轮 assistant 定稿 ----
    Message asst;
    asst.id = util::uuid();
    asst.role = "assistant";
    asst.content = content;
    asst.reasoning = reasoning;
    asst.createdAt = (int64_t)time(nullptr);
    for (size_t i = 0; i < calls.size(); ++i) {
      ToolCall tc = calls[i];
      if (tc.name.empty()) continue;
      tc.arguments = argsBuf[i].empty() ? "{}" : argsBuf[i];
      if (tc.id.empty()) tc.id = "call_" + std::to_string((long long)i);
      asst.toolCalls.push_back(tc);
    }
    if (usage.is_object()) {
      if (usage.contains("prompt_tokens") && usage["prompt_tokens"].is_number())
        asst.promptTokens = usage["prompt_tokens"].get<int64_t>();
      if (usage.contains("completion_tokens") && usage["completion_tokens"].is_number())
        asst.completionTokens = usage["completion_tokens"].get<int64_t>();
    }
    if (!serverTools.is_null()) asst.serverToolCalls = serverTools;
    if (!annotations.is_null()) asst.annotations = annotations;
    history.push_back(asst);
    emit(DSBoxStreamEventRoundEnd, nil, ToDict(asst.toJson()));

    if (asst.toolCalls.empty()) break;  // 已是最终回答

    // ---- 逐个执行本地工具，结果作为 role=tool 消息回灌 ----
    for (const auto &tc : asst.toolCalls) {
      if (stop_.load()) break;
      json args = json::parse(tc.arguments, nullptr, false);
      if (args.is_discarded() || !args.is_object()) args = json::object();
      emit(DSBoxStreamEventToolStart, NSStr(tc.name),
           @{@"id": NSStr(tc.id), @"name": NSStr(tc.name), @"args": ToDict(args)});

      ToolContext ctx;
      ctx.apiKey = apiKey;
      ctx.conversations = [self]() {
        return self->store_ ? self->store_->allConversations() : std::vector<Conversation>{};
      };
      ctx.getBalance = [self](const std::string &key, std::string *e2) {
        return self->api_ ? self->api_->getBalance(key, e2) : Balance{};
      };
      ctx.listModels = [self](const std::string &key, std::string *e2) {
        return self->api_ ? self->api_->listModels(key, e2) : std::vector<ModelInfo>{};
      };

      int64_t t0 = util::nowMs();
      ToolResult r = ToolEngine::instance().call(tc.name, args, ctx);
      int64_t ms = util::nowMs() - t0;

      Message tm;
      tm.id = util::uuid();
      tm.role = "tool";
      tm.toolCallId = tc.id;
      tm.name = tc.name;
      tm.content = r.text;
      tm.toolOk = r.ok;
      tm.toolMs = ms;
      tm.createdAt = (int64_t)time(nullptr);
      history.push_back(tm);

      NSMutableDictionary *d = [@{
        @"id": NSStr(tc.id), @"messageId": NSStr(tm.id), @"name": NSStr(tc.name),
        @"ok": @(r.ok), @"text": NSStr(r.text), @"ms": @(ms),
      } mutableCopy];
      if (r.data.is_object() && !r.data.empty()) d[@"data"] = ToDict(r.data);
      if (!r.images.empty()) {
        NSMutableArray *imgs = [NSMutableArray array];
        for (const auto &s : r.images) [imgs addObject:NSStr(s)];
        d[@"images"] = imgs;
      }
      emit(DSBoxStreamEventToolEnd, nil, d);
    }
    if (stop_.load()) break;
  }

  NSError *finalErr = fatal.empty() ? nil : MakeErr(NSStr(fatal));
  if (finalErr) emit(DSBoxStreamEventError, finalErr.localizedDescription, nil);
  dispatch_async(dispatch_get_main_queue(), ^{
    id<DSBoxChatDelegate> d = delegate;
    if ([d respondsToSelector:@selector(dsboxDidFinishWithError:)])
      [d dsboxDidFinishWithError:finalErr];
  });
}

/// 供 lambda 内部取弱引用目标（避免在 block 里直接访问 ivar）
- (id<DSBoxChatDelegate>)streamDelegateForCallback { return streamDelegate_; }

/// 把流式事件投回主线程（block 内持强引用，避免 delegate 在排队期间被释放）
- (void)emitToDelegate:(id<DSBoxChatDelegate>)delegate
                  type:(DSBoxStreamEventType)type
                  text:(NSString *)text
                  data:(NSDictionary *)data {
  __strong id<DSBoxChatDelegate> target = delegate;
  if (!target) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    [target dsboxDidReceiveEvent:type text:text data:data];
  });
}

- (void)stopStream { stop_.store(true); }

@end
