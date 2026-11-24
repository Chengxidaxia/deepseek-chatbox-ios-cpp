#pragma once
// 数据模型：对照 Web 版 public/js/store.js 的 DEFAULT_SETTINGS / Conversation / Message。
// 用 nlohmann/json 做序列化，字段名与 Web 版保持一致，方便导入导出互通。
#include "../vendor/json.hpp"
#include <string>
#include <vector>
#include <optional>
#include <cstdint>

namespace ds {

using json = nlohmann::json;

// ------------------------------ 消息 ------------------------------
struct ToolCall {
  std::string id;
  std::string name;       // 工具名
  std::string arguments;  // JSON 字符串
};

struct Attachment {
  std::string id;         // attId
  std::string name;
  std::string kind;       // image / text / file
  std::string mime;
  int64_t size = 0;
  std::string dataUrl;    // 可选：内嵌 base64（小文件）
};

struct Message {
  std::string id;
  std::string role;          // user / assistant / system / tool
  std::string content;
  std::string reasoning;     // reasoning_content（思考过程）
  std::vector<ToolCall> toolCalls;
  std::string toolCallId;    // role=tool 时对应 tool_call_id
  std::string name;          // role=tool 时的工具名
  int64_t createdAt = 0;
  std::vector<Attachment> attachments;
  // token 用量（assistant 消息，来自 usage）
  std::optional<int64_t> promptTokens;
  std::optional<int64_t> completionTokens;

  // ---- 工具 / 引用（对照 Web 版同名驼峰字段）----
  json serverToolCalls;      // 服务端工具调用（联网搜索），SSE 原样透传
  json annotations;          // 引用来源
  bool toolOk = true;        // role=tool：执行是否成功
  int64_t toolMs = 0;        // role=tool：耗时毫秒

  // 未识别的键原样保留（UI 层附加数据，如分支候选 branches）。
  // 不做透传的话，updateConversation 重建 JSON 时这些字段会被丢掉。
  json extra;

  json toJson() const {
    // 先铺开 extra，再用已知字段覆盖，保证已知字段永远以结构体为准
    json j = (extra.is_object() && !extra.empty()) ? extra : json::object();
    j["id"] = id;
    j["role"] = role;
    j["content"] = content;
    j["createdAt"] = createdAt;
    if (!reasoning.empty()) j["reasoning"] = reasoning;
    if (!toolCallId.empty()) j["tool_call_id"] = toolCallId;
    if (!name.empty()) j["name"] = name;
    if (promptTokens) j["prompt_tokens"] = *promptTokens;
    if (completionTokens) j["completion_tokens"] = *completionTokens;
    if (!toolCalls.empty()) {
      json arr = json::array();
      for (const auto& tc : toolCalls) {
        arr.push_back({{"id", tc.id}, {"name", tc.name}, {"arguments", tc.arguments}});
      }
      j["tool_calls"] = arr;
    }
    if (!attachments.empty()) {
      json arr = json::array();
      for (const auto& a : attachments) {
        arr.push_back({{"id", a.id}, {"name", a.name}, {"kind", a.kind},
                       {"mime", a.mime}, {"size", a.size}, {"dataUrl", a.dataUrl}});
      }
      j["attachments"] = arr;
    }
    // serverToolCalls / annotations 允许是空数组（清空语义），用 is_null 判断是否写入
    if (!serverToolCalls.is_null()) j["server_tool_calls"] = serverToolCalls;
    if (!annotations.is_null()) j["annotations"] = annotations;
    if (role == "tool") {
      j["toolOk"] = toolOk;
      j["toolMs"] = toolMs;
    }
    return j;
  }

  static Message fromJson(const json& j) {
    Message m;
    m.id = j.value("id", "");
    m.role = j.value("role", "");
    m.content = j.value("content", "");
    m.reasoning = j.value("reasoning", "");
    m.toolCallId = j.value("tool_call_id", "");
    m.name = j.value("name", "");
    m.createdAt = j.value("createdAt", (int64_t)0);
    if (j.contains("prompt_tokens")) m.promptTokens = j["prompt_tokens"].get<int64_t>();
    if (j.contains("completion_tokens")) m.completionTokens = j["completion_tokens"].get<int64_t>();
    if (j.contains("tool_calls") && j["tool_calls"].is_array()) {
      for (const auto& t : j["tool_calls"]) {
        m.toolCalls.push_back({
          t.value("id", ""), t.value("name", ""),
          t.contains("arguments") && t["arguments"].is_string()
            ? t["arguments"].get<std::string>()
            : (t.contains("arguments") ? t["arguments"].dump() : "{}")
        });
      }
    }
    if (j.contains("attachments") && j["attachments"].is_array()) {
      for (const auto& a : j["attachments"]) {
        m.attachments.push_back({
          a.value("id", ""), a.value("name", ""), a.value("kind", ""),
          a.value("mime", ""), a.value("size", (int64_t)0), a.value("dataUrl", "")
        });
      }
    }
    if (j.contains("server_tool_calls")) m.serverToolCalls = j["server_tool_calls"];
    if (j.contains("annotations")) m.annotations = j["annotations"];
    m.toolOk = j.value("toolOk", true);
    m.toolMs = j.value("toolMs", (int64_t)0);
    // 未识别字段进 extra（例如 UI 层的 branches / altIndex），保证回存时不丢
    static const char* known[] = {
      "id", "role", "content", "reasoning", "tool_call_id", "name", "createdAt",
      "prompt_tokens", "completion_tokens", "tool_calls", "attachments",
      "server_tool_calls", "annotations", "toolOk", "toolMs",
    };
    for (auto it = j.begin(); it != j.end(); ++it) {
      bool hit = false;
      for (const char* k : known) if (it.key() == k) { hit = true; break; }
      if (!hit) {
        if (m.extra.is_null()) m.extra = json::object();
        m.extra[it.key()] = it.value();
      }
    }
    return m;
  }
};

// ------------------------------ 会话 ------------------------------
struct Conversation {
  std::string id;
  std::string uuid;        // 分享链接 /a/chat/s/<uuid>
  std::string title;
  int64_t createdAt = 0;
  int64_t updatedAt = 0;
  bool pinned = false;
  std::string groupId;
  std::vector<Message> messages;
  json extra;              // 未识别字段透传（UI 层附加数据）

  json toJson() const {
    json arr = json::array();
    for (const auto& m : messages) arr.push_back(m.toJson());
    json j = (extra.is_object() && !extra.empty()) ? extra : json::object();
    j["id"] = id;
    j["uuid"] = uuid;
    j["title"] = title;
    j["createdAt"] = createdAt;
    j["updatedAt"] = updatedAt;
    j["pinned"] = pinned;
    j["messages"] = arr;
    if (!groupId.empty()) j["groupId"] = groupId;
    return j;
  }

  static Conversation fromJson(const json& j) {
    Conversation c;
    c.id = j.value("id", "");
    c.uuid = j.value("uuid", "");
    c.title = j.value("title", "");
    c.createdAt = j.value("createdAt", (int64_t)0);
    c.updatedAt = j.value("updatedAt", (int64_t)0);
    c.pinned = j.value("pinned", false);
    c.groupId = j.value("groupId", "");
    if (j.contains("messages") && j["messages"].is_array()) {
      for (const auto& m : j["messages"]) c.messages.push_back(Message::fromJson(m));
    }
    static const char* known[] = {
      "id", "uuid", "title", "createdAt", "updatedAt", "pinned", "groupId", "messages",
    };
    for (auto it = j.begin(); it != j.end(); ++it) {
      bool hit = false;
      for (const char* k : known) if (it.key() == k) { hit = true; break; }
      if (!hit) {
        if (c.extra.is_null()) c.extra = json::object();
        c.extra[it.key()] = it.value();
      }
    }
    return c;
  }
};

// ------------------------------ 分组 ------------------------------
struct Group {
  std::string id;
  std::string name;
  int64_t createdAt = 0;

  json toJson() const {
    return {{"id", id}, {"name", name}, {"createdAt", createdAt}};
  }
  static Group fromJson(const json& j) {
    Group g;
    g.id = j.value("id", "");
    g.name = j.value("name", "");
    g.createdAt = j.value("createdAt", (int64_t)0);
    return g;
  }
};

// ------------------------------ 设置 ------------------------------
struct Prices {
  std::string currency = "CNY";
  // flash
  double flashHitIdle=0.02, flashHitPeak=0.04, flashMissIdle=1, flashMissPeak=2, flashOutIdle=4, flashOutPeak=8;
  // pro
  double proHitIdle=0.15, proHitPeak=0.3, proMissIdle=4.5, proMissPeak=9, proOutIdle=13.5, proOutPeak=27;

  json toJson() const {
    return {
      {"currency", currency},
      {"flash", {{"hitIdle",flashHitIdle},{"hitPeak",flashHitPeak},{"missIdle",flashMissIdle},
                 {"missPeak",flashMissPeak},{"outIdle",flashOutIdle},{"outPeak",flashOutPeak}}},
      {"pro", {{"hitIdle",proHitIdle},{"hitPeak",proHitPeak},{"missIdle",proMissIdle},
               {"missPeak",proMissPeak},{"outIdle",proOutIdle},{"outPeak",proOutPeak}}},
    };
  }
  static Prices fromJson(const json& j) {
    Prices p;
    p.currency = j.value("currency", "CNY");
    if (j.contains("flash")) {
      const auto& f = j["flash"];
      p.flashHitIdle=f.value("hitIdle",p.flashHitIdle); p.flashHitPeak=f.value("hitPeak",p.flashHitPeak);
      p.flashMissIdle=f.value("missIdle",p.flashMissIdle); p.flashMissPeak=f.value("missPeak",p.flashMissPeak);
      p.flashOutIdle=f.value("outIdle",p.flashOutIdle); p.flashOutPeak=f.value("outPeak",p.flashOutPeak);
    }
    if (j.contains("pro")) {
      const auto& f = j["pro"];
      p.proHitIdle=f.value("hitIdle",p.proHitIdle); p.proHitPeak=f.value("hitPeak",p.proHitPeak);
      p.proMissIdle=f.value("missIdle",p.proMissIdle); p.proMissPeak=f.value("missPeak",p.proMissPeak);
      p.proOutIdle=f.value("outIdle",p.proOutIdle); p.proOutPeak=f.value("outPeak",p.proOutPeak);
    }
    return p;
  }
};

/// 读布尔字段。**不要直接写 j.value<bool>(k, def)**：只要 JSON 里该字段是 0/1
/// （历史上 ObjC 桥接把 @(YES) 当数字发过、或外部导入的数据），nlohmann 会抛
/// type_error.302，而且是在 Settings::fromJson 里抛 —— 一份字段坏掉，整份设置都读不出来。
/// 这里对数字做容忍，布尔语义不变。
inline bool jsonBool(const json& j, const char* key, bool fallback) {
  auto it = j.find(key);
  if (it == j.end() || it->is_null()) return fallback;
  if (it->is_boolean()) return it->get<bool>();
  if (it->is_number()) return it->get<double>() != 0.0;
  return fallback;
}

struct Settings {
  std::string baseUrl = "https://api.deepseek.com";
  std::string model = "deepseek-flash";
  bool thinking = true;
  std::string effort = "high";
  bool search = false;
  bool readUrl = false;
  bool safety = false;
  bool jsonMode = false;
  double temperature = 1;
  std::optional<double> topP;
  std::optional<int64_t> maxTokens;
  std::string stop;
  std::string systemPrompt;
  std::string userId;
  bool reminderEnabled = true;
  std::string reminderLocation;
  std::string reminderLanguage = "中文";
  std::string theme = "system";
  std::string lang = "zh";
  bool mock = false;
  std::string docLayout = "text_recognition";
  std::string ttsVoice = "stella";
  bool autoTitle = true;
  bool stream = true;
  bool localTools = true;
  bool cmdEnabled = false;
  int toolTopK = 8;
  std::string searchMode = "local";
  std::string peakMode = "auto";
  int64_t contextLimit = 0;
  bool hasKey = false;
  std::string keyPreview;
  Prices prices;

  json toJson() const {
    json j = {
      {"baseUrl", baseUrl}, {"model", model}, {"thinking", thinking}, {"effort", effort},
      {"search", search}, {"readUrl", readUrl}, {"safety", safety}, {"jsonMode", jsonMode},
      {"temperature", temperature}, {"stop", stop}, {"systemPrompt", systemPrompt},
      {"userId", userId},
      {"reminder", {{"enabled",reminderEnabled},{"location",reminderLocation},{"language",reminderLanguage}}},
      {"theme", theme}, {"lang", lang}, {"mock", mock}, {"docLayout", docLayout},
      {"ttsVoice", ttsVoice}, {"autoTitle", autoTitle}, {"stream", stream},
      {"localTools", localTools}, {"cmdEnabled", cmdEnabled}, {"toolTopK", toolTopK},
      {"searchMode", searchMode}, {"peakMode", peakMode}, {"contextLimit", contextLimit},
      {"hasKey", hasKey}, {"keyPreview", keyPreview}, {"prices", prices.toJson()},
    };
    if (topP) j["topP"] = *topP;
    if (maxTokens) j["maxTokens"] = *maxTokens;
    return j;
  }

  static Settings fromJson(const json& j) {
    Settings s;
    s.baseUrl = j.value("baseUrl", s.baseUrl);
    s.model = j.value("model", s.model);
    s.thinking = jsonBool(j, "thinking", s.thinking);
    s.effort = j.value("effort", s.effort);
    s.search = jsonBool(j, "search", s.search);
    s.readUrl = jsonBool(j, "readUrl", s.readUrl);
    s.safety = jsonBool(j, "safety", s.safety);
    s.jsonMode = jsonBool(j, "jsonMode", s.jsonMode);
    s.temperature = j.value("temperature", s.temperature);
    if (j.contains("topP") && j["topP"].is_number()) s.topP = j["topP"].get<double>();
    if (j.contains("maxTokens") && j["maxTokens"].is_number()) s.maxTokens = j["maxTokens"].get<int64_t>();
    s.stop = j.value("stop", s.stop);
    s.systemPrompt = j.value("systemPrompt", s.systemPrompt);
    s.userId = j.value("userId", s.userId);
    if (j.contains("reminder")) {
      const auto& r = j["reminder"];
      s.reminderEnabled = jsonBool(r, "enabled", s.reminderEnabled);
      s.reminderLocation = r.value("location", s.reminderLocation);
      s.reminderLanguage = r.value("language", s.reminderLanguage);
    }
    s.theme = j.value("theme", s.theme);
    s.lang = j.value("lang", s.lang);
    s.mock = jsonBool(j, "mock", s.mock);
    s.docLayout = j.value("docLayout", s.docLayout);
    s.ttsVoice = j.value("ttsVoice", s.ttsVoice);
    s.autoTitle = jsonBool(j, "autoTitle", s.autoTitle);
    s.stream = jsonBool(j, "stream", s.stream);
    s.localTools = jsonBool(j, "localTools", s.localTools);
    s.cmdEnabled = jsonBool(j, "cmdEnabled", s.cmdEnabled);
    s.toolTopK = j.value("toolTopK", s.toolTopK);
    s.searchMode = j.value("searchMode", s.searchMode);
    s.peakMode = j.value("peakMode", s.peakMode);
    s.contextLimit = j.value("contextLimit", s.contextLimit);
    s.hasKey = jsonBool(j, "hasKey", s.hasKey);
    s.keyPreview = j.value("keyPreview", s.keyPreview);
    if (j.contains("prices")) s.prices = Prices::fromJson(j["prices"]);
    return s;
  }
};

struct UIState {
  bool sidebarCollapsed = false;
  std::string activeId;
  json toJson() const { return {{"sidebarCollapsed", sidebarCollapsed}, {"activeId", activeId}}; }
  static UIState fromJson(const json& j) {
    UIState u;
    u.sidebarCollapsed = jsonBool(j, "sidebarCollapsed", false);
    u.activeId = j.value("activeId", "");
    return u;
  }
};

}  // namespace ds
