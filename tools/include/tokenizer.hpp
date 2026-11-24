#pragma once
// DeepSeek V4.1-Flash 分词器（byte-level BPE），对照 Web 版 server/tokenizer-core.cjs。
//
// 词表不打 JSON（6.37 MB，nlohmann 解析会在手机上产生 100 MB 量级峰值），
// 而是由 scripts/gen-tokenizer-bin.py 在构建期转成 tools/tokenizer.bin（约 3.9 MB），
// 运行时一次读进内存，所有字符串用 string_view 指进这块 buffer，零拷贝。
#include <string>
#include <vector>

namespace ds {
namespace tok {

struct Result {
  int count = 0;
  std::vector<std::string> pieces;  // detail=true 时填
  std::vector<int> ids;             // detail=true 时填
  int vocabSize = 0;
};

/** 显式指定 tokenizer.bin 路径（iOS 侧从 app bundle 取；不设则按内置候选路径找） */
void setDataFile(const std::string& path);

/** 词表是否已成功加载 */
bool available();

/** 分词。失败时返回 false 并写 err */
bool tokenize(const std::string& text, bool detail, Result* out, std::string* err);

/** 字符规则粗估（词表缺失时的兜底，与 util::estimateTokens 同口径） */
int estimateFallback(const std::string& text);

}  // namespace tok
}  // namespace ds
