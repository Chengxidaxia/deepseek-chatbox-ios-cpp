#include "store.hpp"
#include "util.hpp"
#include "crypto.hpp"
#include <sqlite3.h>
#include <filesystem>
#include <stdexcept>

namespace fs = std::filesystem;
namespace ds {

Store::Store(const std::string& dbPath) : dbPath_(dbPath) {}
Store::~Store() { if (db_) sqlite3_close(db_); }

bool Store::exec(const std::string& sql, std::string* err) {
  char* e = nullptr;
  int rc = sqlite3_exec(db_, sql.c_str(), nullptr, nullptr, &e);
  if (rc != SQLITE_OK) {
    if (err) *err = e ? e : sqlite3_errmsg(db_);
    sqlite3_free(e);
    return false;
  }
  return true;
}

bool Store::open(std::string* err) {
  std::lock_guard<std::mutex> lk(mu_);
  if (db_) return true;
  // 确保父目录存在
  try {
    fs::path p(dbPath_);
    if (p.has_parent_path()) fs::create_directories(p.parent_path());
  } catch (const std::exception& ex) {
    if (err) *err = std::string("创建数据目录失败: ") + ex.what();
    return false;
  }
  int rc = sqlite3_open(dbPath_.c_str(), &db_);
  if (rc != SQLITE_OK) {
    if (err) *err = sqlite3_errmsg(db_);
    return false;
  }
  exec("PRAGMA journal_mode=WAL;");
  const char* ddl = R"SQL(
    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY, uuid TEXT, title TEXT, pinned INTEGER DEFAULT 0,
      group_id TEXT, created_at INTEGER, updated_at INTEGER, data TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_conv_updated ON conversations(updated_at DESC);
    CREATE TABLE IF NOT EXISTS attachments (
      id TEXT PRIMARY KEY, filename TEXT, mime TEXT, data BLOB, created_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
  )SQL";
  if (!exec(ddl, err)) return false;
  loadMeta();
  return true;
}

// ------------------------------ meta（设置/UI/key密文）------------------------------
bool Store::loadMeta() {
  if (!db_) return false;
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT key,value FROM meta", -1, &st, nullptr) != SQLITE_OK) return false;
  while (sqlite3_step(st) == SQLITE_ROW) {
    std::string k = (const char*)sqlite3_column_text(st, 0);
    std::string v = (const char*)sqlite3_column_text(st, 1);
    try {
      json j = json::parse(v);
      if (k == "settings") settings_ = Settings::fromJson(j);
      else if (k == "ui") ui_ = UIState::fromJson(j);
    } catch (...) {}
  }
  sqlite3_finalize(st);
  return true;
}

bool Store::persistMeta() {
  auto put = [&](const char* key, const std::string& val) {
    sqlite3_stmt* st = nullptr;
    if (sqlite3_prepare_v2(db_, "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", -1, &st, nullptr) != SQLITE_OK) return;
    sqlite3_bind_text(st, 1, key, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 2, val.c_str(), (int)val.size(), SQLITE_TRANSIENT);
    sqlite3_step(st);
    sqlite3_finalize(st);
  };
  put("settings", settings_.toJson().dump());
  put("ui", ui_.toJson().dump());
  return true;
}

void Store::saveSettings(const json& patch) {
  std::lock_guard<std::mutex> lk(mu_);
  json cur = settings_.toJson();
  for (auto it = patch.begin(); it != patch.end(); ++it) cur[it.key()] = it.value();
  settings_ = Settings::fromJson(cur);
  persistMeta();
}

void Store::saveUI(const json& patch) {
  std::lock_guard<std::mutex> lk(mu_);
  json cur = ui_.toJson();
  for (auto it = patch.begin(); it != patch.end(); ++it) cur[it.key()] = it.value();
  ui_ = UIState::fromJson(cur);
  persistMeta();
}

// ------------------------------ 会话 ------------------------------
std::vector<Conversation> Store::allConversations() {
  std::lock_guard<std::mutex> lk(mu_);
  std::vector<Conversation> out;
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT data FROM conversations ORDER BY pinned DESC, updated_at DESC", -1, &st, nullptr) != SQLITE_OK) return out;
  while (sqlite3_step(st) == SQLITE_ROW) {
    std::string data = (const char*)sqlite3_column_text(st, 0);
    try { out.push_back(Conversation::fromJson(json::parse(data))); } catch (...) {}
  }
  sqlite3_finalize(st);
  return out;
}

std::optional<Conversation> Store::getConversation(const std::string& id) {
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT data FROM conversations WHERE id=?", -1, &st, nullptr) != SQLITE_OK) return std::nullopt;
  sqlite3_bind_text(st, 1, id.c_str(), -1, SQLITE_TRANSIENT);
  std::optional<Conversation> out;
  if (sqlite3_step(st) == SQLITE_ROW) {
    try { out = Conversation::fromJson(json::parse((const char*)sqlite3_column_text(st, 0))); } catch (...) {}
  }
  sqlite3_finalize(st);
  return out;
}

std::optional<Conversation> Store::getConversationByUuid(const std::string& uuid) {
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT data FROM conversations WHERE uuid=?", -1, &st, nullptr) != SQLITE_OK) return std::nullopt;
  sqlite3_bind_text(st, 1, uuid.c_str(), -1, SQLITE_TRANSIENT);
  std::optional<Conversation> out;
  if (sqlite3_step(st) == SQLITE_ROW) {
    try { out = Conversation::fromJson(json::parse((const char*)sqlite3_column_text(st, 0))); } catch (...) {}
  }
  sqlite3_finalize(st);
  return out;
}

Conversation Store::createConversation(const json& partial) {
  std::lock_guard<std::mutex> lk(mu_);
  int64_t now = util::nowMs();
  Conversation c;
  c.id = "c_" + util::shortId("").substr(1);
  c.uuid = util::uuid();
  c.createdAt = now;
  c.updatedAt = now;
  if (partial.contains("title")) c.title = partial["title"].get<std::string>();
  if (partial.contains("groupId")) c.groupId = partial["groupId"].get<std::string>();
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "INSERT INTO conversations(id,uuid,title,pinned,group_id,created_at,updated_at,data) VALUES(?,?,?,?,?,?,?,?)", -1, &st, nullptr) == SQLITE_OK) {
    std::string data = c.toJson().dump();
    sqlite3_bind_text(st,1,c.id.c_str(),-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(st,2,c.uuid.c_str(),-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(st,3,c.title.c_str(),-1,SQLITE_TRANSIENT);
    sqlite3_bind_int(st,4,0);
    sqlite3_bind_text(st,5,c.groupId.c_str(),-1,SQLITE_TRANSIENT);
    sqlite3_bind_int64(st,6,now);
    sqlite3_bind_int64(st,7,now);
    sqlite3_bind_text(st,8,data.c_str(),(int)data.size(),SQLITE_TRANSIENT);
    sqlite3_step(st);
  }
  sqlite3_finalize(st);
  return c;
}

bool Store::updateConversation(const std::string& id, const json& patch) {
  auto c = getConversation(id);
  if (!c) return false;
  // 应用 patch 到 JSON 再重建
  json j = c->toJson();
  for (auto it = patch.begin(); it != patch.end(); ++it) j[it.key()] = it.value();
  j["updatedAt"] = util::nowMs();
  Conversation next = Conversation::fromJson(j);
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "UPDATE conversations SET uuid=?,title=?,pinned=?,group_id=?,updated_at=?,data=? WHERE id=?", -1, &st, nullptr) != SQLITE_OK) return false;
  std::string data = next.toJson().dump();
  sqlite3_bind_text(st,1,next.uuid.c_str(),-1,SQLITE_TRANSIENT);
  sqlite3_bind_text(st,2,next.title.c_str(),-1,SQLITE_TRANSIENT);
  sqlite3_bind_int(st,3,next.pinned?1:0);
  sqlite3_bind_text(st,4,next.groupId.c_str(),-1,SQLITE_TRANSIENT);
  sqlite3_bind_int64(st,5,next.updatedAt);
  sqlite3_bind_text(st,6,data.c_str(),(int)data.size(),SQLITE_TRANSIENT);
  sqlite3_bind_text(st,7,id.c_str(),-1,SQLITE_TRANSIENT);
  bool ok = sqlite3_step(st) == SQLITE_DONE;
  sqlite3_finalize(st);
  return ok;
}

bool Store::deleteConversation(const std::string& id) {
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "DELETE FROM conversations WHERE id=?", -1, &st, nullptr) != SQLITE_OK) return false;
  sqlite3_bind_text(st,1,id.c_str(),-1,SQLITE_TRANSIENT);
  bool ok = sqlite3_step(st) == SQLITE_DONE;
  sqlite3_finalize(st);
  return ok;
}

void Store::clearConversations() {
  std::lock_guard<std::mutex> lk(mu_);
  exec("DELETE FROM conversations");
}

// ------------------------------ 快照（导入导出）------------------------------
json Store::snapshot() {
  json convs = json::array();
  for (const auto& c : allConversations()) convs.push_back(c.toJson());
  json groups = json::array();
  for (const auto& g : allGroups()) groups.push_back(g.toJson());
  return {{"conversations", convs}, {"settings", settings_.toJson()},
          {"ui", ui_.toJson()}, {"groups", groups}, {"storage", "sqlite"}};
}

bool Store::importSnapshot(const json& snap, const std::string& mode) {
  std::lock_guard<std::mutex> lk(mu_);
  if (mode == "replace") exec("DELETE FROM conversations");
  if (snap.contains("conversations") && snap["conversations"].is_array()) {
    for (const auto& j : snap["conversations"]) {
      auto c = Conversation::fromJson(j);
      sqlite3_stmt* st = nullptr;
      if (sqlite3_prepare_v2(db_, "INSERT OR REPLACE INTO conversations(id,uuid,title,pinned,group_id,created_at,updated_at,data) VALUES(?,?,?,?,?,?,?,?)", -1, &st, nullptr) != SQLITE_OK) continue;
      std::string data = c.toJson().dump();
      sqlite3_bind_text(st,1,c.id.c_str(),-1,SQLITE_TRANSIENT);
      sqlite3_bind_text(st,2,c.uuid.c_str(),-1,SQLITE_TRANSIENT);
      sqlite3_bind_text(st,3,c.title.c_str(),-1,SQLITE_TRANSIENT);
      sqlite3_bind_int(st,4,c.pinned?1:0);
      sqlite3_bind_text(st,5,c.groupId.c_str(),-1,SQLITE_TRANSIENT);
      sqlite3_bind_int64(st,6,c.createdAt);
      sqlite3_bind_int64(st,7,c.updatedAt);
      sqlite3_bind_text(st,8,data.c_str(),(int)data.size(),SQLITE_TRANSIENT);
      sqlite3_step(st);
      sqlite3_finalize(st);
    }
  }
  if (snap.contains("settings")) {
    json cur = settings_.toJson();
    for (auto it = snap["settings"].begin(); it != snap["settings"].end(); ++it) cur[it.key()] = it.value();
    settings_ = Settings::fromJson(cur);
  }
  if (snap.contains("ui")) ui_ = UIState::fromJson(snap["ui"]);
  if (snap.contains("groups") && snap["groups"].is_array()) {
    // 注意：此处已持有 mu_，不能调用 saveGroups()（会再次加锁死锁），内联写入
    json arr = json::array();
    for (const auto& j : snap["groups"]) arr.push_back(Group::fromJson(j).toJson());
    sqlite3_stmt* st = nullptr;
    if (sqlite3_prepare_v2(db_, "INSERT INTO meta(key,value) VALUES('groups',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", -1, &st, nullptr) == SQLITE_OK) {
      std::string v = arr.dump();
      sqlite3_bind_text(st,1,v.c_str(),(int)v.size(),SQLITE_TRANSIENT);
      sqlite3_step(st);
      sqlite3_finalize(st);
    }
  }
  persistMeta();
  return true;
}

// ------------------------------ 分组 ------------------------------
std::vector<Group> Store::allGroups() {
  std::lock_guard<std::mutex> lk(mu_);
  std::vector<Group> out;
  std::string raw;
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT value FROM meta WHERE key='groups'", -1, &st, nullptr) != SQLITE_OK) return out;
  if (sqlite3_step(st) == SQLITE_ROW) raw = (const char*)sqlite3_column_text(st, 0);
  sqlite3_finalize(st);
  if (raw.empty()) return out;
  try {
    json j = json::parse(raw);
    for (const auto& g : j) out.push_back(Group::fromJson(g));
  } catch (...) {}
  return out;
}

bool Store::saveGroups(const std::vector<Group>& groups) {
  std::lock_guard<std::mutex> lk(mu_);
  json arr = json::array();
  for (const auto& g : groups) arr.push_back(g.toJson());
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "INSERT INTO meta(key,value) VALUES('groups',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", -1, &st, nullptr) != SQLITE_OK) return false;
  std::string v = arr.dump();
  sqlite3_bind_text(st,1,v.c_str(),(int)v.size(),SQLITE_TRANSIENT);
  bool ok = sqlite3_step(st) == SQLITE_DONE;
  sqlite3_finalize(st);
  return ok;
}

// ------------------------------ 附件 ------------------------------
std::optional<Store::AttachmentRecord> Store::getAttachment(const std::string& id) {
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT filename,mime,data,created_at FROM attachments WHERE id=?", -1, &st, nullptr) != SQLITE_OK) return std::nullopt;
  sqlite3_bind_text(st,1,id.c_str(),-1,SQLITE_TRANSIENT);
  std::optional<AttachmentRecord> out;
  if (sqlite3_step(st) == SQLITE_ROW) {
    AttachmentRecord a;
    a.id = id;
    a.filename = (const char*)sqlite3_column_text(st,0);
    a.mime = (const char*)sqlite3_column_text(st,1);
    const void* blob = sqlite3_column_blob(st,2);
    int n = sqlite3_column_bytes(st,2);
    if (blob && n > 0) a.data.assign((const unsigned char*)blob, (const unsigned char*)blob + n);
    a.createdAt = sqlite3_column_int64(st,3);
    out = a;
  }
  sqlite3_finalize(st);
  return out;
}

std::string Store::putAttachment(const std::string& filename, const std::string& mime,
                                  const std::vector<unsigned char>& data) {
  std::lock_guard<std::mutex> lk(mu_);
  std::string id = "att_" + util::shortId("").substr(1);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "INSERT INTO attachments(id,filename,mime,data,created_at) VALUES(?,?,?,?,?)", -1, &st, nullptr) == SQLITE_OK) {
    sqlite3_bind_text(st,1,id.c_str(),-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(st,2,filename.c_str(),-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(st,3,mime.c_str(),-1,SQLITE_TRANSIENT);
    sqlite3_bind_blob(st,4,data.empty()?nullptr:data.data(),(int)data.size(),SQLITE_TRANSIENT);
    sqlite3_bind_int64(st,5,util::nowMs());
    sqlite3_step(st);
  }
  sqlite3_finalize(st);
  return id;
}

bool Store::deleteAttachment(const std::string& id) {
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "DELETE FROM attachments WHERE id=?", -1, &st, nullptr) != SQLITE_OK) return false;
  sqlite3_bind_text(st,1,id.c_str(),-1,SQLITE_TRANSIENT);
  bool ok = sqlite3_step(st) == SQLITE_DONE;
  sqlite3_finalize(st);
  return ok;
}

// ------------------------------ Key 加密存储 ------------------------------
bool Store::hasKeyEncrypted() {
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT value FROM meta WHERE key='key_cipher'", -1, &st, nullptr) != SQLITE_OK) return false;
  bool has = sqlite3_step(st) == SQLITE_ROW;
  sqlite3_finalize(st);
  return has;
}

bool Store::setKeyEncrypted(const std::string& apiKey, const std::string& pin, std::string* err) {
  if (pin.size() < 4) { if (err) *err = "PIN 至少 4 位"; return false; }
  std::string cipher = crypto::encrypt(apiKey, pin, err).serialize();
  if (cipher.empty() || (err && !err->empty())) return false;
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "INSERT INTO meta(key,value) VALUES('key_cipher',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", -1, &st, nullptr) != SQLITE_OK) {
    if (err) *err = sqlite3_errmsg(db_); return false;
  }
  sqlite3_bind_text(st,1,cipher.c_str(),(int)cipher.size(),SQLITE_TRANSIENT);
  bool ok = sqlite3_step(st) == SQLITE_DONE;
  sqlite3_finalize(st);
  if (ok) {
    settings_.hasKey = true;
    settings_.keyPreview = util::maskKey(apiKey);
    persistMeta();
  }
  return ok;
}

std::string Store::unlockKey(const std::string& pin, std::string* err) {
  std::lock_guard<std::mutex> lk(mu_);
  sqlite3_stmt* st = nullptr;
  if (sqlite3_prepare_v2(db_, "SELECT value FROM meta WHERE key='key_cipher'", -1, &st, nullptr) != SQLITE_OK) {
    if (err) *err = sqlite3_errmsg(db_); return "";
  }
  if (sqlite3_step(st) != SQLITE_ROW) {
    sqlite3_finalize(st);
    if (err) *err = "未设置 Key"; return "";
  }
  std::string cipher = (const char*)sqlite3_column_text(st,0);
  sqlite3_finalize(st);
  return crypto::decrypt(crypto::Encrypted::deserialize(cipher), pin, err);
}

void Store::clearKey() {
  std::lock_guard<std::mutex> lk(mu_);
  exec("DELETE FROM meta WHERE key='key_cipher'");
  settings_.hasKey = false;
  settings_.keyPreview.clear();
  persistMeta();
}

}  // namespace ds
