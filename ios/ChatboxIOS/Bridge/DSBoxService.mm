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
  if (!store_ || !api_) { if (error) *error = MakeErr(@"核心未初始化"); return NO; }
  if (unlockedKey_.empty()) { if (error) *error = MakeErr(@"请先解锁 Key"); return NO; }
  auto c = store_->getConversation(StdStr(convId));
  if (!c) { if (error) *error = MakeErr(@"会话不存在"); return NO; }

  streamDelegate_ = delegate;
  stop_.store(false);

  // 直接从 C++ 构造 payload（不走 NSDictionary 往返，避免 int64 精度丢失）
  Settings st = store_->settings();
  std::vector<json> toolDefs;
  if (st.localTools) {
    auto &eng = ToolEngine::instance();
    // 对齐 Web 版动态工具检索：用最后一条用户消息作检索词
    std::string query;
    for (auto it = c->messages.rbegin(); it != c->messages.rend(); ++it) {
      if (it->role == "user") { query = it->content; break; }
    }
    auto hits = query.empty() ? std::vector<std::pair<std::string, json>>{}
                              : eng.search(query, st.toolTopK);
    for (const auto &h : hits) toolDefs.push_back(h.second);
  }
  json payloadJ = ApiClient::buildPayload(c->messages, st, toolDefs);

  std::string apiKey = unlockedKey_;  // 复制到请求线程，避免竞态
  __weak DSBoxService *ws = self;      // block/lambda 里避免强引用循环
  StreamOptions opts;
  opts.apiKey = apiKey;
  opts.baseUrl = st.baseUrl;
  opts.shouldStop = [self]() { return self->stop_.load(); };
  opts.onEvent = [ws, delegate](const StreamEvent &e) {
    // libcurl 在后台线程回调，统一切主线程
    dispatch_async(dispatch_get_main_queue(), ^{
      id<DSBoxChatDelegate> d = delegate ?: [ws streamDelegateForCallback];
      if (!d) return;
      NSDictionary *data = e.data.is_object() ? ToDict(e.data) : nil;
      NSString *text = e.text.empty() ? nil : NSStr(e.text);
      switch (e.type) {
        case StreamEvent::Content:      [d dsboxDidReceiveEvent:DSBoxStreamEventContent text:text data:data]; break;
        case StreamEvent::Reasoning:    [d dsboxDidReceiveEvent:DSBoxStreamEventReasoning text:text data:data]; break;
        case StreamEvent::ToolCallDelta:[d dsboxDidReceiveEvent:DSBoxStreamEventToolCall text:text data:data]; break;
        case StreamEvent::Usage:        [d dsboxDidReceiveEvent:DSBoxStreamEventUsage text:text data:data]; break;
        case StreamEvent::Title:        [d dsboxDidReceiveEvent:DSBoxStreamEventTitle text:text data:data]; break;
        case StreamEvent::Refusal:      [d dsboxDidReceiveEvent:DSBoxStreamEventRefusal text:text data:data]; break;
        case StreamEvent::ServerToolCalls:[d dsboxDidReceiveEvent:DSBoxStreamEventServerTool text:text data:data]; break;
        case StreamEvent::ToolEvent:    [d dsboxDidReceiveEvent:DSBoxStreamEventToolCall text:text data:data]; break;
        case StreamEvent::Annotations:  break;  // UI 暂不展示
        case StreamEvent::Finish:       [d dsboxDidReceiveEvent:DSBoxStreamEventFinish text:text data:data]; break;
        case StreamEvent::Error:        [d dsboxDidReceiveEvent:DSBoxStreamEventError text:text data:data]; break;
        case StreamEvent::Done:
          [d dsboxDidReceiveEvent:DSBoxStreamEventDone text:nil data:nil];
          if ([d respondsToSelector:@selector(dsboxDidFinishWithError:)]) [d dsboxDidFinishWithError:nil];
          break;
      }
    });
  };

  // 在后台串行队列跑 libcurl，避免阻塞 UI
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    std::string err;
    BOOL ok = self->api_ ? self->api_->streamChat(payloadJ, opts, &err) : NO;
    if (!ok) {
      dispatch_async(dispatch_get_main_queue(), ^{
        id<DSBoxChatDelegate> d = delegate;
        NSString *msg = NSStr(err.empty() ? std::string("请求失败") : err);
        [d dsboxDidReceiveEvent:DSBoxStreamEventError text:msg data:nil];
        if ([d respondsToSelector:@selector(dsboxDidFinishWithError:)])
          [d dsboxDidFinishWithError:MakeErr(msg)];
      });
    }
  });
  return YES;
}

/// 供 lambda 内部取弱引用目标（避免在 block 里直接访问 ivar）
- (id<DSBoxChatDelegate>)streamDelegateForCallback { return streamDelegate_; }

- (void)stopStream { stop_.store(true); }

@end
