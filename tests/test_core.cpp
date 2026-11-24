#include "model.hpp"
#include "util.hpp"
#include "crypto.hpp"
#include "store.hpp"
#include <sqlite3.h>
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

    // UI 附加字段（分支候选）必须原样透传，否则保存会话时会丢
    Message um; um.id = "u1"; um.role = "user"; um.content = "问题";
    um.extra = json{{"branches", json::array({json{{"content","答案A"}}, json{{"content","答案B"}}})},
                    {"branchIndex", 1}};
    json uj = um.toJson();
    CHECK(uj["branches"].size() == 2 && uj["branchIndex"] == 1, "user 消息附加字段写入");
    auto um2 = Message::fromJson(uj);
    CHECK(um2.extra["branches"].size() == 2 && um2.extra["branchIndex"] == 1, "附加字段往返");

    // 服务端工具调用 / 引用 / 工具结果状态
    Message am; am.id = "a1"; am.role = "assistant";
    am.serverToolCalls = json::array({json{{"type","web_search"},{"status","searching"}}});
    am.annotations = json::array();
    json aj = Message::fromJson(am.toJson()).toJson();
    CHECK(aj["server_tool_calls"].size() == 1, "server_tool_calls 往返");
    CHECK(aj["annotations"].is_array() && aj["annotations"].empty(), "空 annotations 不被丢弃");

    Message tm; tm.id = "t1"; tm.role = "tool"; tm.name = "calculator";
    tm.content = "2"; tm.toolOk = false; tm.toolMs = 12;
    auto tm2 = Message::fromJson(tm.toJson());
    CHECK(tm2.toolOk == false && tm2.toolMs == 12, "tool 结果状态往返");

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

    // 布尔补丁必须能存进去。iOS 桥接曾经把 @(YES) 当数字发成 1，
    // Settings::fromJson 的 j.value<bool>() 直接抛 type_error.302，
    // saveSettings 整体失败被 catch 掉 —— 表现就是「开关点了没反应」。
    st.saveSettings({{"search", true}, {"thinking", false}});
    CHECK(st.settings().search && !st.settings().thinking, "布尔设置保存后读回");

    // 就算真被写成 0/1（旧数据、外部导入），也要能读出来而不是抛异常
    st.saveSettings({{"search", 1}, {"readUrl", 0}});
    CHECK(st.settings().search && !st.settings().readUrl, "布尔被写成 0/1 时仍能读回");

    // 关掉再打开，确认落盘往返
    st.saveSettings({{"search", false}});
    CHECK(!st.settings().search, "布尔设置可关闭");

    std::vector<unsigned char> blob = {'P','N','G',0,1,2};
    std::string aid = st.putAttachment("a.png", "image/png", blob);
    auto att = st.getAttachment(aid);
    CHECK(att && att->filename == "a.png" && att->data == blob, "附件读写往返");
    // 落盘：库里只留相对路径，文件真实存在
    CHECK(att && !att->path.empty() && att->path.find("att_") == 0, "附件 path 已回填: " + (att ? att->path : ""));
    CHECK(std::filesystem::exists(std::filesystem::path(st.attachmentsDir()) / (att ? att->path : "")),
          "附件文件已落盘到 attachments/");
    CHECK(st.deleteAttachment(aid), "删除附件");
    CHECK(!st.getAttachment(aid), "删除后读不到");
    CHECK(!std::filesystem::exists(std::filesystem::path(st.attachmentsDir()) / (att ? att->path : "")),
          "删除附件同时删掉文件");

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

  std::cout << "=== 老库附件迁移（blob → 文件）===\n";
  {
    std::string db2 = ".build/test_migrate.sqlite3";
    std::error_code ec;
    std::filesystem::remove(db2, ec);
    std::filesystem::remove(db2 + "-wal", ec);
    std::filesystem::remove(db2 + "-shm", ec);

    // 造一个「老库」：attachments 只有 blob，没有 path 列
    sqlite3* raw = nullptr;
    CHECK(sqlite3_open(db2.c_str(), &raw) == SQLITE_OK, "创建老库");
    CHECK(sqlite3_exec(raw,
          "CREATE TABLE attachments (id TEXT PRIMARY KEY, filename TEXT, mime TEXT, data BLOB, created_at INTEGER);",
          nullptr, nullptr, nullptr) == SQLITE_OK, "老库建表");
    sqlite3_stmt* ins = nullptr;
    CHECK(sqlite3_prepare_v2(raw,
          "INSERT INTO attachments(id,filename,mime,data,created_at) VALUES(?,?,?,?,?)", -1, &ins, nullptr) == SQLITE_OK,
          "老库准备插入");
    const unsigned char oldBlob[] = {'J','P','G',0,9,8};
    sqlite3_bind_text(ins,1,"att_old",-1,SQLITE_STATIC);
    sqlite3_bind_text(ins,2,"old.jpg",-1,SQLITE_STATIC);
    sqlite3_bind_text(ins,3,"image/jpeg",-1,SQLITE_STATIC);
    sqlite3_bind_blob(ins,4,oldBlob,6,SQLITE_STATIC);
    sqlite3_bind_int64(ins,5,1);
    CHECK(sqlite3_step(ins) == SQLITE_DONE, "老库写入 blob");
    sqlite3_finalize(ins);
    sqlite3_close(raw);

    std::string err;
    {
      Store st2(db2);
      CHECK(st2.open(&err), "打开老库并迁移: " + err);
      auto rec = st2.getAttachment("att_old");
      std::vector<unsigned char> expect(oldBlob, oldBlob + 6);
      CHECK(rec && rec->data == expect, "迁移后内容不变");
      CHECK(rec && rec->path == "att_old.jpg", "迁移回填 path: " + (rec ? rec->path : ""));
      CHECK(std::filesystem::exists(std::filesystem::path(st2.attachmentsDir()) / "att_old.jpg"),
            "迁移写出文件");
    }
    {
      // 幂等：二次打开不应重复迁移，也不应报错
      Store st3(db2);
      CHECK(st3.open(&err), "二次打开老库");
      auto rec = st3.getAttachment("att_old");
      CHECK(rec && rec->data.size() == 6, "二次打开仍可读");
    }
    std::filesystem::remove(std::filesystem::path(".build/attachments") / "att_old.jpg", ec);
    std::filesystem::remove(db2, ec);
    std::filesystem::remove(db2 + "-wal", ec);
    std::filesystem::remove(db2 + "-shm", ec);
  }

  if (failed) { std::cerr << "\n" << failed << " 项失败\n"; return 1; }
  std::cout << "\n全部测试通过 ✓\n";
  return 0;
}
