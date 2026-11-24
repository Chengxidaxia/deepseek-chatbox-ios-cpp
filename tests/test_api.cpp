#include "api.hpp"
#include "util.hpp"
#include <iostream>

using namespace ds;
static int failed = 0;
#define CHECK(cond, msg) do { if (!(cond)) { std::cerr << "FAIL: " << msg << " (line " << __LINE__ << ")\n"; failed++; } else { std::cout << "  ok: " << msg << "\n"; } } while(0)

int main() {
  std::cout.setf(std::ios::unitbuf);
  std::cout << "=== toApiMessages ===\n";
  {
    Settings s;
    s.systemPrompt = "你是一个助手";
    std::vector<Message> history;
    Message u; u.role="user"; u.content="你好";
    Attachment a; a.kind="text"; a.name="note.txt"; a.dataUrl="文件 note.txt：\n```txt\n内容\n```";
    u.attachments.push_back(a);
    history.push_back(u);
    Message asst; asst.role="assistant"; asst.content="你好呀"; asst.reasoning="思考";
    ToolCall tc; tc.id="c1"; tc.name="calculator"; tc.arguments="{\"expr\":\"1+1\"}";
    asst.toolCalls.push_back(tc);
    history.push_back(asst);
    Message tool; tool.role="tool"; tool.toolCallId="c1"; tool.content="2";
    history.push_back(tool);

    json msgs = ApiClient::toApiMessages(history, s, "2026-11-24,星期一,,iOS,中文");
    CHECK(msgs.size() == 5, "消息数=5 (system+reminder+user+assistant+tool): " + std::to_string(msgs.size()));
    CHECK(msgs[0]["role"]=="system" && msgs[0]["content"]=="你是一个助手", "system 消息");
    CHECK(msgs[1]["role"]=="latest_reminder", "reminder 消息");
    CHECK(msgs[2]["role"]=="user" && msgs[2]["content"].get<std::string>().find("note.txt")!=std::string::npos, "用户消息含文本附件");
    CHECK(msgs[3].contains("reasoning_content") && msgs[3]["reasoning_content"]=="思考", "助手思考字段");
    CHECK(msgs[3]["tool_calls"].size()==1 && msgs[3]["tool_calls"][0]["function"]["name"]=="calculator", "助手 tool_calls");
    CHECK(msgs[4]["role"]=="tool" && msgs[4]["tool_call_id"]=="c1", "tool 结果消息");

    // 识图：图片附件转多模态 content 数组
    Settings sv;
    std::vector<Message> vh;
    Message vu; vu.role="user"; vu.content="这张图是什么";
    Attachment img; img.kind="image"; img.name="a.jpg"; img.mime="image/jpeg";
    img.dataUrl="data:image/jpeg;base64,AAAA";
    vu.attachments.push_back(img);
    vh.push_back(vu);
    json vm = ApiClient::toApiMessages(vh, sv, "");
    CHECK(vm.size()==1 && vm[0]["content"].is_array(), "图片消息 content 为数组");
    CHECK(vm[0]["content"][0]["type"]=="text" && vm[0]["content"][1]["type"]=="image_url",
          "多模态 parts 顺序：text → image_url");
  }

  std::cout << "=== buildPayload ===\n";
  {
    Settings s;
    s.model="deepseek-chat"; s.thinking=true; s.effort="max"; s.stream=true;
    s.temperature=0.7; s.maxTokens=4096; s.safety=true; s.jsonMode=true;
    std::vector<Message> history;
    Message u; u.role="user"; u.content="测试"; history.push_back(u);
    json defs = json::array();
    defs.push_back({{"type","function"},{"function",{{"name","calculator"}}}});
    json p = ApiClient::buildPayload(history, s, defs, true);
    CHECK(p["model"]=="deepseek-chat", "payload model");
    CHECK(p["stream"]==true && p["stream_options"]["include_usage"]==true, "stream_options");
    CHECK(p["thinking"]["type"]=="enabled" && p["reasoning_effort"]=="max", "thinking + effort");
    CHECK(p["max_tokens"]==4096, "max_tokens");
    CHECK(p["title"]["enabled"]==true, "wantTitle");
    CHECK(p["tools"].size()==1, "tools 下发");
    CHECK(p["safety_check"]["level"]=="high", "safety");
    // thinking 开启时不下发 temperature（对齐 Web 版）
    CHECK(!p.contains("temperature"), "thinking 时无 temperature");

    Settings s2; s2.thinking=false; s2.temperature=0.5; s2.topP=0.9;
    json p2 = ApiClient::buildPayload(history, s2, {});
    CHECK(p2["thinking"]["type"]=="disabled", "thinking disabled");
    CHECK(p2.contains("temperature") && p2["temperature"]==0.5, "非 thinking 下发 temperature");
    CHECK(p2.contains("top_p") && p2["top_p"]==0.9, "非 thinking 下发 top_p");
  }

  std::cout << "=== friendlyError ===\n";
  {
    CHECK(ApiClient::friendlyError(401, R"({"error":{"message":"Invalid key"}})").find("API Key")!=std::string::npos, "401 提示");
    CHECK(ApiClient::friendlyError(402, "").find("余额")!=std::string::npos, "402 提示");
    CHECK(ApiClient::friendlyError(429, "").find("频繁")!=std::string::npos, "429 提示");
    CHECK(ApiClient::friendlyError(999, "").find("HTTP 999")!=std::string::npos, "未知状态码");
    CHECK(ApiClient::friendlyError(400, "plain text body").find("plain text")!=std::string::npos, "非 JSON body");
  }

  std::cout << "=== ModelInfo ===\n";
  {
    auto models = ApiClient().cachedModels();
    CHECK(models.size()==2, "fallback 模型数=2");
    CHECK(models[0].id=="deepseek-flash" && models[0].contextWindow==1048576, "fallback 模型字段");
    CHECK(models[0].effortLevels.size()==3, "effort 档位");
  }

  if (failed) { std::cerr << "\n" << failed << " 项失败\n"; return 1; }
  std::cout << "\nAPI 层测试全部通过 ✓\n";
  return 0;
}
