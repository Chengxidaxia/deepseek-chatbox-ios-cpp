#pragma once
// API 层：对照 Web 版 api.js —— libcurl 直连官方，SSE 流式解析。
#include "model.hpp"
#include <string>
#include <vector>
#include <functional>
#include <memory>

namespace ds {

// 模型信息
struct ModelInfo {
  std::string id, name, ownedBy;
  int64_t contextWindow = 0, maxOutputTokens = 0;
  std::vector<std::string> inputModalities;
  std::vector<std::string> effortLevels;
  json toJson() const {
    return {{"id",id},{"name",name},{"owned_by",ownedBy},
            {"context_window",contextWindow},{"max_output_tokens",maxOutputTokens},
            {"input_modalities",inputModalities},{"effort",{{"supported_levels",effortLevels}}}};
  }
  static ModelInfo fromJson(const json& j) {
    ModelInfo m;
    m.id = j.value("id",""); m.name = j.value("name", m.id); m.ownedBy = j.value("owned_by","deepseek");
    m.contextWindow = j.value("context_window", (int64_t)0);
    m.maxOutputTokens = j.value("max_output_tokens", (int64_t)0);
    if (j.contains("input_modalities")) m.inputModalities = j["input_modalities"].get<std::vector<std::string>>();
    else m.inputModalities = {"text"};
    if (j.contains("effort") && j["effort"].contains("supported_levels"))
      m.effortLevels = j["effort"]["supported_levels"].get<std::vector<std::string>>();
    else m.effortLevels = {"low","high","max"};
    return m;
  }
};

// SSE 事件
struct StreamEvent {
  enum Type { Content, Reasoning, ToolCallDelta, Usage, Title, Refusal, ServerToolCalls, ToolEvent, Annotations, Finish, Done, Error } type;
  std::string text;
  json data;  // usage / calls / annotations 等
  std::string message;  // Error 时的消息
};

struct StreamOptions {
  std::function<void(const StreamEvent&)> onEvent;
  std::function<bool()> shouldStop;  // 返回 true 则中止
  std::string apiKey;
  std::string baseUrl;
  // 续写（对话前缀续写 Beta）必须走 beta 端点：
  // https://api-docs.deepseek.com/guides/chat_prefix_completion
  bool beta = false;
};

// 余额
struct Balance {
  json raw;
  std::string totalBalance, giftBalance, rechargeBalance;
  bool available = false;
  static Balance fromJson(const json& j) {
    Balance b; b.raw = j;
    auto gs = [&](const char* k){ return j.contains(k) && j[k].is_string() ? j[k].get<std::string>() : (j.contains(k)?j[k].dump():""); };
    b.totalBalance = gs("total_balance"); b.giftBalance = gs("gift_balance"); b.rechargeBalance = gs("recharge_balance");
    b.available = j.value("is_available", false);
    return b;
  }
};

class ApiClient {
 public:
  explicit ApiClient(std::string baseUrl = "https://api.deepseek.com");
  void setBaseUrl(const std::string& url) { baseUrl_ = trimSlash(url); }

  // 模型列表（带 fallback）
  std::vector<ModelInfo> listModels(const std::string& apiKey, std::string* err = nullptr);
  std::vector<ModelInfo> cachedModels() const;

  // 余额
  Balance getBalance(const std::string& apiKey, std::string* err = nullptr);

  // 语音合成：返回 WAV 字节
  bool synthesize(const std::string& text, const std::string& voice,
                  const std::string& apiKey, std::vector<unsigned char>* out, std::string* err = nullptr);

  // 语音识别：multipart 上传音频
  bool transcribe(const std::vector<unsigned char>& audio, const std::string& filename,
                  const std::string& apiKey, json* out, std::string* err = nullptr);

  // 流式对话：payload 是 JSON 字符串，逐行解析 SSE
  bool streamChat(const json& payload, const StreamOptions& opts, std::string* err = nullptr);

  // 构造 API 消息（对照 toApiMessages）
  static json toApiMessages(const std::vector<Message>& history,
                            const Settings& settings,
                            const std::string& reminderContent = "");

  // 构造请求体（对照 buildPayload，简化工具检索：调用方传入已选工具定义）
  static json buildPayload(const std::vector<Message>& history, const Settings& settings,
                           const std::vector<json>& toolDefs,
                           bool wantTitle = false, const std::string& continuePrefix = "");

  // 友好错误信息（对照 friendlyError）
  static std::string friendlyError(int status, const std::string& body);

 private:
  std::string baseUrl_;
  std::vector<ModelInfo> modelCache_;
  static std::string trimSlash(std::string s);
  // libcurl 通用请求
  bool request(const std::string& method, const std::string& path, const std::string& apiKey,
               const std::string& body, const std::string& contentType,
               int* status, std::string* out, std::string* err);
  // multipart 请求
  bool requestMultipart(const std::string& path, const std::string& apiKey,
                        const std::vector<std::pair<std::string,std::string>>& fields,
                        const std::string& fileField, const std::string& filename,
                        const std::vector<unsigned char>& fileData, const std::string& fileMime,
                        int* status, std::string* out, std::string* err);
};

}  // namespace ds
