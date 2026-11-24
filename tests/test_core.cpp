#include "model.hpp"
#include "util.hpp"
#include "crypto.hpp"
#include "store.hpp"
#include <iostream>
#include <cassert>
#include <filesystem>
#include <fstream>

using namespace ds;

#define CHECK(cond, msg) do { if (!(cond)) { std::cerr << "FAIL: " << msg << " (line " << __LINE__ << ")\n"; return 1; } else { std::cout << "  ok: " << msg << "\n"; } } while(0)

int main() {
  int failed = 0;
  std::cout.setf(std::ios::unitbuf);  // 无缓冲，便于定位段错误
  std::cout << "=== util ===\n";
  {
    std::string u = util::uuid();
    CHECK(u.size() == 36, "uuid 长度 36: " + u);
    CHECK(u[14] == '4', "uuid version=4");
    auto hexval = [](char c){ return c>='0'&&c<='9'?c-'0':(c>='a'&&c<='f'?c-'a'+10:0); };
    CHECK((hexval(u[19]) & 0x8) == 0x8, "uuid variant=10xx");
    CHECK(util::estimateTokens("你好世界") >= 3 && util::estimateTokens("你好世界") <= 5, "CJK token 估算");
    CHECK(util::estimateTokens("hello world") >= 3, "ASCII token 估算");
    std::string enc = util::base64Encode("hello");
    CHECK(enc == "aGVsbG8=", "base64 编码: " + enc);
    CHECK(util::base64Decode(enc) == "hello", "base64 解码");
    CHECK(util::maskKey("sk-1234567890abcdef").find("****") != std::string::npos, "key 掩码");
  }

  std::cout << "=== crypto ===\n";
  {
    std::string pin = "1234";
    auto e = crypto::encrypt("sk-secret-key-xyz", pin);
    CHECK(!e.serialize().empty(), "加密产出密文");
    auto e2 = crypto::Encrypted::deserialize(e.serialize());
    CHECK(e2.saltB64 == e.saltB64 && e2.cipherB64 == e.cipherB64, "密文序列化往返");
    std::string plain = crypto::decrypt(e2, pin);
    CHECK(plain == "sk-secret-key-xyz", "解密还原明文: " + plain);
    std::string bad = crypto::decrypt(e2, "9999");
    CHECK(bad.empty(), "错误 PIN 解密失败");
    CHECK(crypto::sha256hex("abc").substr(0,7) == "ba7816b", "SHA256(abc) 前7位");
  }

  std::cout << "=== model 序列化 ===\n";
  {
    Conversation c;
    c.id = "c_test"; c.uuid = util::uuid(); c.title = "测试会话";
    c.createdAt = util::nowMs(); c.updatedAt = c.createdAt;
    Message m; m.id = "m1"; m.role = "assistant"; m.content = "你好"; m.reasoning = "思考中";
    ToolCall tc; tc.id = "call1"; tc.name = "calculator"; tc.arguments = "{\"expr\":\"1+1\"}";
    m.toolCalls.push_back(tc);
    c.messages.push_back(m);
    json j = c.toJson();
    auto c2 = Conversation::fromJson(j);
    CHECK(c2.title == "测试会话", "会话标题往返");
    CHECK(c2.messages.size() == 1 && c2.messages[0].reasoning == "思考中", "消息思考字段往返");
    CHECK(c2.messages[0].toolCalls.size() == 1 && c2.messages[0].toolCalls[0].name == "calculator", "tool_calls 往返");

    Settings s;
    s.model = "deepseek-chat"; s.thinking = false; s.effort = "max"; s.contextLimit = 32000;
    auto s2 = Settings::fromJson(s.toJson());
    CHECK(s2.model == "deepseek-chat" && s2.effort == "max" && s2.contextLimit == 32000, "设置往返");
  }

  std::cout << "=== store (SQLite) ===\n";
  {
    std::string db = ".build/test_core.sqlite3";
    std::filesystem::remove(db);
    Store st(db);
    std::string err;
    CHECK(st.open(&err), "打开数据库: " + err);

    auto c1 = st.createConversation({{"title","会话A"}});
    auto c2 = st.createConversation();
    CHECK(!c1.id.empty() && !c2.id.empty(), "创建两个会话");
    CHECK(c1.id != c2.id && c1.uuid != c2.uuid, "会话 id/uuid 唯一");

    CHECK(st.updateConversation(c1.id, {{"title","会话A改"},{"pinned",true}}), "更新会话");
    auto got = st.getConversation(c1.id);
    CHECK(got && got->title == "会话A改" && got->pinned, "读回更新结果");

    auto byUuid = st.getConversationByUuid(c1.uuid);
    CHECK(byUuid && byUuid->id == c1.id, "按 uuid 查询");

    auto all = st.allConversations();
    CHECK(all.size() == 2, "全部会话数: " + std::to_string(all.size()));
    CHECK(all[0].pinned, "置顶会话排前面");

    st.saveSettings({{"model","deepseek-reasoner"},{"toolTopK",12}});
    CHECK(st.settings().model == "deepseek-reasoner" && st.settings().toolTopK == 12, "保存设置");

    std::vector<unsigned char> blob = {'P','N','G',0,1,2};
    std::string aid = st.putAttachment("a.png", "image/png", blob);
    auto att = st.getAttachment(aid);
    CHECK(att && att->filename == "a.png" && att->data == blob, "附件 blob 存取");

    CHECK(st.setKeyEncrypted("sk-my-real-key", "5678", &err), "加密保存 Key: " + err);
    CHECK(st.hasKeyEncrypted(), "检测 Key 存在");
    CHECK(st.unlockKey("5678") == "sk-my-real-key", "PIN 解锁 Key");
    CHECK(st.unlockKey("0000").empty(), "错误 PIN 解锁失败");
    st.clearKey();
    CHECK(!st.hasKeyEncrypted(), "清除 Key");

    json snap = st.snapshot();
    CHECK(snap["conversations"].size() == 2, "快照会话数");
    st.clearConversations();
    CHECK(st.allConversations().empty(), "清空会话");
    CHECK(st.importSnapshot(snap), "导入快照");
    CHECK(st.allConversations().size() == 2, "导入后会话数恢复");

    std::error_code ec;  // db 句柄仍开着，Windows 下删不掉，忽略
    std::filesystem::remove(db, ec);
    std::filesystem::remove(db + "-wal", ec);
    std::filesystem::remove(db + "-shm", ec);
  }

  if (failed) { std::cerr << "\n" << failed << " 项失败\n"; return 1; }
  std::cout << "\n全部测试通过 ✓\n";
  return 0;
}
