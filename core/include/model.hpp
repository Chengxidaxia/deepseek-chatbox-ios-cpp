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

  json toJson() const {
    json j = {
      {"id", id}, {"role", role}, {"content", content},
      {"createdAt", createdAt},
    };
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

  json toJson() const {
    json arr = json::array();
    for (const auto& m : messages) arr.push_back(m.toJson());
    json j = {
      {"id", id}, {"uuid", uuid}, {"title", title},
      {"createdAt", createdAt}, {"updatedAt", updatedAt},
      {"pinned", pinned}, {"messages", arr},
    };
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
    s.thinking = j.value("thinking", s.thinking);
    s.effort = j.value("effort", s.effort);
    s.search = j.value("search", s.search);
    s.readUrl = j.value("readUrl", s.readUrl);
    s.safety = j.value("safety", s.safety);
    s.jsonMode = j.value("jsonMode", s.jsonMode);
    s.temperature = j.value("temperature", s.temperature);
    if (j.contains("topP") && j["topP"].is_number()) s.topP = j["topP"].get<double>();
    if (j.contains("maxTokens") && j["maxTokens"].is_number()) s.maxTokens = j["maxTokens"].get<int64_t>();
    s.stop = j.value("stop", s.stop);
    s.systemPrompt = j.value("systemPrompt", s.systemPrompt);
    s.userId = j.value("userId", s.userId);
    if (j.contains("reminder")) {
      const auto& r = j["reminder"];
      s.reminderEnabled = r.value("enabled", s.reminderEnabled);
      s.reminderLocation = r.value("location", s.reminderLocation);
      s.reminderLanguage = r.value("language", s.reminderLanguage);
    }
    s.theme = j.value("theme", s.theme);
    s.lang = j.value("lang", s.lang);
    s.mock = j.value("mock", s.mock);
    s.docLayout = j.value("docLayout", s.docLayout);
    s.ttsVoice = j.value("ttsVoice", s.ttsVoice);
    s.autoTitle = j.value("autoTitle", s.autoTitle);
    s.stream = j.value("stream", s.stream);
    s.localTools = j.value("localTools", s.localTools);
    s.cmdEnabled = j.value("cmdEnabled", s.cmdEnabled);
    s.toolTopK = j.value("toolTopK", s.toolTopK);
    s.searchMode = j.value("searchMode", s.searchMode);
    s.peakMode = j.value("peakMode", s.peakMode);
    s.contextLimit = j.value("contextLimit", s.contextLimit);
    s.hasKey = j.value("hasKey", s.hasKey);
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
    u.sidebarCollapsed = j.value("sidebarCollapsed", false);
    u.activeId = j.value("activeId", "");
    return u;
  }
};

}  // namespace ds
