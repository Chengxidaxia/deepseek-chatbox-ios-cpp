#pragma once
// 内置工具引擎：对照 Web 版 tools-browser.js + server/tools-core.cjs
// 手机端移除 D 类系统工具（cmd_run/dns_lookup/port_check/local_ip）。
#include "json.hpp"
#include "model.hpp"
#include "api.hpp"   // Balance / ModelInfo
#include <string>
#include <vector>
#include <functional>

namespace ds {
using json = nlohmann::json;

struct ToolResult {
  bool ok = false;
  std::string text;
  json data = json::object();
  std::vector<std::string> images;  // base64 dataURL（qr_text）
  json toJson() const {
    json j = {{"ok",ok},{"text",text},{"data",data}};
    if (!images.empty()) j["images"] = images;
    return j;
  }
};

struct ToolContext {
  std::function<std::vector<Conversation>()> conversations;  // search_history / usage_stats
  std::function<Balance(const std::string&, std::string*)> getBalance;
  std::function<std::vector<ModelInfo>(const std::string&, std::string*)> listModels;
  std::string apiKey;
};

class ToolEngine {
 public:
  static ToolEngine& instance();

  // 加载工具定义（tool_defs.json 的内容）
  bool loadDefinitions(const std::string& jsonPath, std::string* err = nullptr);
  void setDefinitions(const json& defs) { defs_ = defs; }
  const json& definitions() const { return defs_; }
  std::vector<std::string> names() const;

  // 调用工具
  ToolResult call(const std::string& name, const json& args, const ToolContext& ctx = {});

  // 简单关键词搜索（对照 find_tool / tool-search.js）
  std::vector<std::pair<std::string, json>> search(const std::string& query, int topK = 5);

 private:
  ToolEngine() = default;
  json defs_ = json::array();
};

}  // namespace ds
