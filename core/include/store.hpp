#pragma once
// 本地存储层：对照 Web 版 store.js + IndexedDB 改造版 local-store.js。
// C++ 版用 SQLite 落盘（iOS Documents/ 目录），单文件 db.sqlite3。
#include "model.hpp"
#include <string>
#include <vector>
#include <memory>
#include <mutex>
#include <functional>

struct sqlite3;

namespace ds {

class Store {
 public:
  explicit Store(const std::string& dbPath);
  ~Store();

  // 打开数据库并建表
  bool open(std::string* err = nullptr);

  // ---- 全量快照（导入导出用，对照 GET /api/store）----
  json snapshot();
  bool importSnapshot(const json& snap, const std::string& mode = "replace");

  // ---- 会话 ----
  std::vector<Conversation> allConversations();
  std::optional<Conversation> getConversation(const std::string& id);
  std::optional<Conversation> getConversationByUuid(const std::string& uuid);
  Conversation createConversation(const json& partial = json::object());
  bool updateConversation(const std::string& id, const json& patch);
  bool deleteConversation(const std::string& id);
  void clearConversations();

  // ---- 设置 / UI ----
  Settings settings() const { return settings_; }
  UIState ui() const { return ui_; }
  void saveSettings(const json& patch);
  void saveUI(const json& patch);

  // ---- 分组 ----
  std::vector<Group> allGroups();
  bool saveGroups(const std::vector<Group>& groups);

  // ---- 附件（文件存 Documents/attachments/，库里只留相对路径）----
  struct AttachmentRecord {
    std::string id, filename, mime;
    std::string path;                 // 相对 attachments/ 的文件名；老库迁移前为空
    std::vector<unsigned char> data;  // 按需从文件读出
    int64_t createdAt = 0;
  };
  std::optional<AttachmentRecord> getAttachment(const std::string& id);
  std::string putAttachment(const std::string& filename, const std::string& mime,
                            const std::vector<unsigned char>& data);
  bool deleteAttachment(const std::string& id);

  // ---- API Key（加密存储，对照 secure-key.js）----
  // 密文存 meta 表；PIN 由调用方持有，不落盘
  bool hasKeyEncrypted();
  bool setKeyEncrypted(const std::string& apiKey, const std::string& pin, std::string* err = nullptr);
  std::string unlockKey(const std::string& pin, std::string* err = nullptr);
  void clearKey();

  // 数据库路径
  const std::string& dbPath() const { return dbPath_; }
  // 附件目录（Documents/attachments/），open() 后有效
  const std::string& attachmentsDir() const { return attachmentsDir_; }

 private:
  std::string dbPath_;
  std::string attachmentsDir_;
  sqlite3* db_ = nullptr;
  mutable std::mutex mu_;
  Settings settings_;
  UIState ui_;
  bool loadMeta();
  bool persistMeta();
  bool exec(const std::string& sql, std::string* err = nullptr);
  // 老库把 blob 搬成文件：写文件 + 清空 blob + 回填 path
  bool migrateAttachmentsToFiles();
  bool ensureAttachmentColumn();
};

}  // namespace ds
