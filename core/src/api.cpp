#include "api.hpp"
#include "util.hpp"
#include <curl/curl.h>
#include <algorithm>
#include <cstring>

namespace ds {

std::string ApiClient::trimSlash(std::string s) {
  while (!s.empty() && s.back()=='/') s.pop_back();
  return s.empty() ? "https://api.deepseek.com" : s;
}

ApiClient::ApiClient(std::string baseUrl) : baseUrl_(trimSlash(std::move(baseUrl))) {}

// ------------------------------ libcurl 回调 ------------------------------
namespace {
struct Buf { std::string data; };
size_t writeCb(char* ptr, size_t size, size_t nmemb, void* userdata) {
  auto* b = static_cast<Buf*>(userdata);
  b->data.append(ptr, size*nmemb);
  return size*nmemb;
}
struct StreamCtx {
  const StreamOptions* opts;
  std::string buf;
  bool done = false;
  bool stop = false;
};
size_t streamCb(char* ptr, size_t size, size_t nmemb, void* userdata) {
  auto* ctx = static_cast<StreamCtx*>(userdata);
  size_t n = size*nmemb;
  ctx->buf.append(ptr, n);
  // 逐行处理
  size_t idx;
  while ((idx = ctx->buf.find('\n')) != std::string::npos) {
    std::string line = ctx->buf.substr(0, idx);
    ctx->buf.erase(0, idx+1);
    if (!line.empty() && line.back()=='\r') line.pop_back();
    std::string s = util::trim(line);
    if (s.empty() || s[0]==':') continue;        // 注释 / keep-alive
    if (s.rfind("data:",0) != 0) continue;
    std::string data = util::trim(s.substr(5));
    if (data == "[DONE]") { ctx->done = true; break; }
    try {
      json j = json::parse(data);
      if (j.contains("error")) {
        StreamEvent e; e.type = StreamEvent::Error;
        e.message = j["error"].value("message","生成失败");
        ctx->opts->onEvent(e); ctx->stop = true; return 0;
      }
      if (j.contains("usage") && ctx->opts->onEvent) {
        StreamEvent e; e.type = StreamEvent::Usage; e.data = j["usage"];
        ctx->opts->onEvent(e);
      }
      if (!j.contains("choices") || !j["choices"].is_array() || j["choices"].empty()) continue;
      const auto& ch = j["choices"][0];
      if (!ch.contains("delta")) {
        // 非流式兜底：choices[0].message
        if (ch.contains("message")) {
          const auto& msg = ch["message"];
          if (msg.contains("content") && ctx->opts->onEvent && msg["content"].is_string()) {
            StreamEvent e; e.type = StreamEvent::Content; e.text = msg["content"].get<std::string>();
            ctx->opts->onEvent(e);
          }
        }
        continue;
      }
      const auto& d = ch["delta"];
      auto emit = [&](StreamEvent e){ if (ctx->opts->onEvent) ctx->opts->onEvent(e); };
      if (d.contains("reasoning_content") && d["reasoning_content"].is_string()) {
        StreamEvent e; e.type=StreamEvent::Reasoning; e.text=d["reasoning_content"].get<std::string>(); emit(e);
      }
      if (d.contains("content") && d["content"].is_string()) {
        StreamEvent e; e.type=StreamEvent::Content; e.text=d["content"].get<std::string>(); emit(e);
      }
      if (d.contains("tool_calls")) {
        StreamEvent e; e.type=StreamEvent::ToolCallDelta; e.data=d["tool_calls"]; emit(e);
      }
      if (d.contains("title")) {
        StreamEvent e; e.type=StreamEvent::Title; e.text=d.value("title",""); emit(e);
      }
      if (d.contains("refusal")) {
        StreamEvent e; e.type=StreamEvent::Refusal; e.message=d.value("refusal",""); emit(e);
      }
      if (d.contains("server_tool_calls")) {
        StreamEvent e; e.type=StreamEvent::ServerToolCalls; e.data=d["server_tool_calls"]; emit(e);
      }
      if ((d.contains("annotations") || ch.contains("annotations"))) {
        StreamEvent e; e.type=StreamEvent::Annotations;
        e.data = d.contains("annotations") ? d["annotations"] : ch["annotations"]; emit(e);
      }
      if (ch.contains("server_tool_event")) {
        StreamEvent e; e.type=StreamEvent::ToolEvent; e.data=ch["server_tool_event"]; emit(e);
      }
      if (ch.contains("finish_reason") && !ch["finish_reason"].is_null()) {
        StreamEvent e; e.type=StreamEvent::Finish; e.text=ch["finish_reason"].get<std::string>(); emit(e);
      }
    } catch (...) { /* 忽略半包 JSON */ }
    if (ctx->done || ctx->stop) return 0;
  }
  return n;
}
}  // namespace

std::string ApiClient::friendlyError(int status, const std::string& body) {
  std::string msg;
  try {
    json j = json::parse(body);
    if (j.contains("error") && j["error"].is_object())
      msg = j["error"].value("message", j["error"].value("message",""));
    else if (j.contains("message")) msg = j["message"].get<std::string>();
  } catch (...) { msg = body.substr(0, 300); }
  const char* tbl = nullptr;
  switch (status) {
    case 400: tbl="请求格式有误"; break;
    case 401: tbl="API Key 无效或未填写"; break;
    case 402: tbl="账号余额不足"; break;
    case 403: tbl="请求被拒绝"; break;
    case 404: tbl="接口不存在（检查 Base URL）"; break;
    case 408: tbl="请求超时"; break;
    case 413: tbl="请求体过大"; break;
    case 422: tbl="参数错误"; break;
    case 429: tbl="请求过于频繁，请稍后重试"; break;
    case 500: tbl="服务器故障"; break;
    case 503: tbl="服务器繁忙"; break;
    case 504: tbl="网关超时"; break;
  }
  std::string prefix = tbl ? ("HTTP " + std::to_string(status) + " " + tbl)
                           : ("HTTP " + std::to_string(status));
  return msg.empty() ? prefix : (prefix + "：" + msg);
}

bool ApiClient::request(const std::string& method, const std::string& path, const std::string& apiKey,
                        const std::string& body, const std::string& contentType,
                        int* status, std::string* out, std::string* err) {
  CURL* curl = curl_easy_init();
  if (!curl) { if (err) *err="curl 初始化失败"; return false; }
  std::string url = baseUrl_ + path;
  Buf buf;
  curl_slist* headers = nullptr;
  headers = curl_slist_append(headers, ("Authorization: Bearer " + apiKey).c_str());
  if (!contentType.empty()) headers = curl_slist_append(headers, ("Content-Type: "+contentType).c_str());
  curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCb);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "dsbox-ios/1.0");
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 60L);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  if (method == "POST") curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
  else if (method == "DELETE") curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
  CURLcode rc = curl_easy_perform(curl);
  long httpStatus = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpStatus);
  if (status) *status = (int)httpStatus;
  if (rc != CURLE_OK) {
    if (err) *err = std::string("网络请求失败: ") + curl_easy_strerror(rc);
    curl_slist_free_all(headers); curl_easy_cleanup(curl); return false;
  }
  *out = buf.data;
  bool ok = httpStatus >= 200 && httpStatus < 300;
  if (!ok && err) *err = friendlyError((int)httpStatus, buf.data);
  curl_slist_free_all(headers);
  curl_easy_cleanup(curl);
  return ok;
}

bool ApiClient::requestMultipart(const std::string& path, const std::string& apiKey,
                                 const std::vector<std::pair<std::string,std::string>>& fields,
                                 const std::string& fileField, const std::string& filename,
                                 const std::vector<unsigned char>& fileData, const std::string& fileMime,
                                 int* status, std::string* out, std::string* err) {
  CURL* curl = curl_easy_init();
  if (!curl) { if (err) *err="curl 初始化失败"; return false; }
  curl_mime* mime = curl_mime_init(curl);
  for (const auto& kv : fields) {
    curl_mimepart* p = curl_mime_addpart(mime);
    curl_mime_name(p, kv.first.c_str());
    curl_mime_data(p, kv.second.c_str(), CURL_ZERO_TERMINATED);
  }
  curl_mimepart* fp = curl_mime_addpart(mime);
  curl_mime_name(fp, fileField.c_str());
  curl_mime_filename(fp, filename.c_str());
  curl_mime_type(fp, fileMime.c_str());
  const char* filePtr = fileData.empty() ? "" : reinterpret_cast<const char*>(fileData.data());
  curl_mime_data(fp, filePtr, fileData.size());

  std::string url = baseUrl_ + path;
  Buf buf;
  curl_slist* headers = curl_slist_append(headers, ("Authorization: Bearer "+apiKey).c_str());
  curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(curl, CURLOPT_MIMEPOST, mime);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCb);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 60L);
  CURLcode rc = curl_easy_perform(curl);
  long httpStatus = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpStatus);
  if (status) *status = (int)httpStatus;
  *out = buf.data;
  bool ok = (rc == CURLE_OK && httpStatus >= 200 && httpStatus < 300);
  if (!ok && err) {
    *err = (rc != CURLE_OK) ? (std::string("网络请求失败: ")+curl_easy_strerror(rc))
                            : friendlyError((int)httpStatus, buf.data);
  }
  curl_slist_free_all(headers);
  curl_mime_free(mime);
  curl_easy_cleanup(curl);
  return ok;
}

// ------------------------------ 模型 ------------------------------
static const char* FALLBACK_MODELS_JSON = R"JSON([
 {"id":"deepseek-flash","name":"DeepSeek-V4.1-Flash","owned_by":"deepseek","context_window":1048576,"max_output_tokens":393216,"input_modalities":["text","image"],"effort":{"supported_levels":["low","high","max"]}},
 {"id":"deepseek-v4-pro","name":"DeepSeek-V4-Pro","owned_by":"deepseek","context_window":1048576,"max_output_tokens":393216,"input_modalities":["text"],"effort":{"supported_levels":["low","high","max"]}}
])JSON";

std::vector<ModelInfo> ApiClient::cachedModels() const {
  if (!modelCache_.empty()) return modelCache_;
  std::vector<ModelInfo> out;
  json j = json::parse(FALLBACK_MODELS_JSON);
  for (const auto& m : j) out.push_back(ModelInfo::fromJson(m));
  return out;
}

std::vector<ModelInfo> ApiClient::listModels(const std::string& apiKey, std::string* err) {
  std::string body; int status=0; std::string e;
  if (!request("GET", "/models", apiKey, "", "", &status, &body, &e)) {
    if (err) *err=e;
    return cachedModels();
  }
  try {
    json j = json::parse(body);
    if (j.contains("data") && j["data"].is_array() && !j["data"].empty()) {
      modelCache_.clear();
      for (const auto& m : j["data"]) modelCache_.push_back(ModelInfo::fromJson(m));
    }
  } catch (...) { if (err) *err="模型列表解析失败"; }
  return cachedModels();
}

Balance ApiClient::getBalance(const std::string& apiKey, std::string* err) {
  std::string body; int status=0; std::string e;
  if (!request("GET", "/user/balance", apiKey, "", "", &status, &body, &e)) {
    if (err) *err=e;
    return Balance{};
  }
  try { return Balance::fromJson(json::parse(body)); }
  catch (...) { if (err) *err="余额解析失败"; return Balance{}; }
}

bool ApiClient::synthesize(const std::string& text, const std::string& voice,
                           const std::string& apiKey, std::vector<unsigned char>* out, std::string* err) {
  json body = {{"text",text},{"voice_id",voice},{"format","wav"}};
  std::string resp; int status=0; std::string e;
  // TTS 返回二进制 WAV，request() 会以字符串承载（二进制安全：std::string 可含 \0）
  if (!request("POST", "/v1/tools/tts", apiKey, body.dump(), "application/json", &status, &resp, &e)) {
    if (err) *err=e; return false;
  }
  out->assign(resp.begin(), resp.end());
  return true;
}

bool ApiClient::transcribe(const std::vector<unsigned char>& audio, const std::string& filename,
                           const std::string& apiKey, json* out, std::string* err) {
  std::string resp; int status=0; std::string e;
  std::string mime = "audio/wav";
  if (!requestMultipart("/v1/tools/asr", apiKey, {}, "file", filename, audio, mime, &status, &resp, &e)) {
    if (err) *err=e; return false;
  }
  try { *out = json::parse(resp); return true; }
  catch (...) { if (err) *err="语音识别结果解析失败"; return false; }
}

// ------------------------------ 消息构造 ------------------------------
json ApiClient::toApiMessages(const std::vector<Message>& history, const Settings& s,
                              const std::string& reminderContent) {
  json out = json::array();
  if (!s.systemPrompt.empty()) out.push_back({{"role","system"},{"content",s.systemPrompt}});
  for (const auto& m : history) {
    if (m.role == "user") {
      if (!reminderContent.empty()) out.push_back({{"role","latest_reminder"},{"content",reminderContent}});
      // 文本附件内联
      std::string body = m.content;
      for (const auto& a : m.attachments) {
        if (a.kind == "text" && !a.dataUrl.empty()) {
          // dataUrl 里放的是 "文件名\n```ext\n内容" 形式（由 App 层组装）
          body += "\n\n" + a.dataUrl;
        }
      }
      // 图片附件：拼成 OpenAI 多模态 content 数组（识图模式用）
      json parts = json::array();
      bool hasImage = false;
      for (const auto& a : m.attachments) {
        if (a.kind != "image" || a.dataUrl.rfind("data:image/", 0) != 0) continue;
        hasImage = true;
        parts.push_back({{"type","image_url"},{"image_url",{{"url",a.dataUrl}}}});
      }
      if (hasImage) {
        json content = json::array();
        content.push_back({{"type","text"},{"text",body.empty()?" ":body}});
        for (auto& p : parts) content.push_back(p);
        out.push_back({{"role","user"},{"content",content}});
      } else {
        out.push_back({{"role","user"},{"content",body.empty()?" ":body}});
      }
    } else if (m.role == "assistant") {
      if (m.content.empty() && m.reasoning.empty() && m.toolCalls.empty()) continue;
      json msg = {{"role","assistant"},{"content",m.content}};
      if (!m.reasoning.empty()) msg["reasoning_content"] = m.reasoning;
      if (!m.toolCalls.empty()) {
        json calls = json::array();
        for (const auto& tc : m.toolCalls) {
          json args = json::parse(tc.arguments, nullptr, false);
          if (args.is_discarded()) args = json::object();
          calls.push_back({{"id",tc.id},{"type","function"},
                           {"function",{{"name",tc.name},{"arguments",args.dump()}}}});
        }
        msg["tool_calls"] = calls;
      }
      out.push_back(msg);
    } else if (m.role == "tool") {
      out.push_back({{"role","tool"},{"tool_call_id",m.toolCallId},{"content",m.content}});
    }
  }
  return out;
}

json ApiClient::buildPayload(const std::vector<Message>& history, const Settings& s,
                             const std::vector<json>& toolDefs, bool wantTitle,
                             const std::string& continuePrefix) {
  json messages = toApiMessages(history, s, "");
  if (!continuePrefix.empty())
    messages.push_back({{"role","assistant"},{"content",continuePrefix},{"prefix",true}});
  json payload = {{"model",s.model},{"messages",messages},{"stream",s.stream}};
  if (s.stream) payload["stream_options"] = {{"include_usage",true}};
  if (s.thinking) {
    payload["thinking"] = {{"type","enabled"}};
    if (!s.effort.empty()) payload["reasoning_effort"] = s.effort;
  } else payload["thinking"] = {{"type","disabled"}};
  if (s.maxTokens) payload["max_tokens"] = *s.maxTokens;
  if (!s.thinking && toolDefs.empty()) {
    payload["temperature"] = s.temperature;
    if (s.topP) payload["top_p"] = *s.topP;
  }
  if (!s.stop.empty() && toolDefs.empty())
    payload["stop"] = s.stop;
  if (s.jsonMode && toolDefs.empty()) payload["response_format"] = {{"type","json_object"}};
  if (s.safety) payload["safety_check"] = {{"level","high"}};
  if (wantTitle) payload["title"] = {{"enabled",true}};
  if (!s.userId.empty()) payload["user_id"] = s.userId;
  if (!toolDefs.empty()) payload["tools"] = toolDefs;
  return payload;
}

// ------------------------------ 流式对话 ------------------------------
bool ApiClient::streamChat(const json& payload, const StreamOptions& opts, std::string* err) {
  CURL* curl = curl_easy_init();
  if (!curl) { if (err) *err="curl 初始化失败"; return false; }
  // 续写走 beta 端点（官方要求），其余走常规端点
  std::string url = baseUrl_ + (opts.beta ? "/beta/chat/completions" : "/chat/completions");
  std::string bodyStr = payload.dump();
  curl_slist* headers = nullptr;
  headers = curl_slist_append(headers, ("Authorization: Bearer "+opts.apiKey).c_str());
  headers = curl_slist_append(headers, "Content-Type: application/json");
  headers = curl_slist_append(headers, "Accept: text/event-stream");
  StreamCtx ctx; ctx.opts = &opts;
  curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(curl, CURLOPT_POST, 1L);
  curl_easy_setopt(curl, CURLOPT_POSTFIELDS, bodyStr.c_str());
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, streamCb);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ctx);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "dsbox-ios/1.0");
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 300L);
  CURLcode rc = curl_easy_perform(curl);
  long httpStatus = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpStatus);
  curl_slist_free_all(headers);
  curl_easy_cleanup(curl);
  if (rc != CURLE_OK) { if (err) *err=std::string("网络请求失败: ")+curl_easy_strerror(rc); return false; }
  if (httpStatus < 200 || httpStatus >= 300) {
    if (err) *err = friendlyError((int)httpStatus, ""); return false;
  }
  // 收尾：处理残留 buf
  if (!ctx.buf.empty() && !ctx.stop && opts.onEvent) {
    // 简单处理最后一行
    StreamEvent e; e.type = StreamEvent::Done; opts.onEvent(e);
  } else if (opts.onEvent) {
    StreamEvent e; e.type = StreamEvent::Done; opts.onEvent(e);
  }
  return true;
}

}  // namespace ds
