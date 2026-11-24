// DeepSeek V4.1-Flash 分词器（byte-level BPE），对照 Web 版 server/tokenizer-core.cjs。
//
// 数据来自 tools/tokenizer.bin（构建期由 scripts/gen-tokenizer-bin.py 从 tokenizer.json 转出）：
// 词表 128000、merges 127741、added_tokens 1283，外加 \p{N}/\p{L}/\p{M}/\p{P}/\p{S}
// 五个 Unicode 大类的区间表（std::regex 不支持 \p{...}，只能自己带表）。
//
// 流程与 Web 版一致：
//   1) added_tokens 前缀匹配（长的优先），命中就整块当一个特殊 token
//   2) 三条 Split 预分词（数字 / CJK 连串 / 词与标点），Isolated 语义
//   3) ByteLevel 把 UTF-8 字节映射成 U+0000..U+0143 的可见字符
//   4) 按 merges 的 rank 做贪心合并，直到合不动
#include "tokenizer.hpp"
#include "util.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace ds {
namespace tok {
namespace {

constexpr char kMagic[6] = {'D', 'S', 'B', 'P', 'E', '1'};

// ------------------------------ 二进制读取 ------------------------------
struct Blob {
  std::string data;  // 整个文件
  size_t pos = 0;

  bool need(size_t n) const { return pos + n <= data.size(); }
  unsigned u16() {
    if (!need(2)) return 0;
    const unsigned v = (unsigned char)data[pos] | ((unsigned char)data[pos + 1] << 8);
    pos += 2;
    return v;
  }
  unsigned u32() {
    if (!need(4)) return 0;
    const auto* p = reinterpret_cast<const unsigned char*>(data.data() + pos);
    const unsigned v = (unsigned)p[0] | ((unsigned)p[1] << 8) | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24);
    pos += 4;
    return v;
  }
  std::string_view bytes(size_t n) {
    if (!need(n)) return {};
    std::string_view v(data.data() + pos, n);
    pos += n;
    return v;
  }
};

// ------------------------------ Unicode 类别 ------------------------------
struct CatTable {
  std::vector<std::pair<unsigned, unsigned>> ranges;  // 闭区间，按 start 升序

  bool has(unsigned cp) const {
    size_t lo = 0, hi = ranges.size();
    while (lo < hi) {
      const size_t mid = (lo + hi) / 2;
      if (cp < ranges[mid].first) hi = mid;
      else if (cp > ranges[mid].second) lo = mid + 1;
      else return true;
    }
    return false;
  }
};

// JS 的 \s：WhiteSpace + LineTerminator
bool isJsSpace(unsigned cp) {
  switch (cp) {
    case 0x09: case 0x0A: case 0x0B: case 0x0C: case 0x0D: case 0x20:
    case 0xA0: case 0x1680: case 0x2028: case 0x2029: case 0x202F:
    case 0x205F: case 0x3000: case 0xFEFF:
      return true;
    default:
      return cp >= 0x2000 && cp <= 0x200A;
  }
}

// ------------------------------ 词表 ------------------------------
struct PairKey {
  std::string_view a, b;
};
struct PairHash {
  size_t operator()(const PairKey& k) const {
    // FNV-1a 分别算两段再混，避免拼字符串
    auto fnv = [](std::string_view s) {
      size_t h = 1469598103934665603ULL;
      for (unsigned char c : s) { h ^= c; h *= 1099511628211ULL; }
      return h;
    };
    const size_t ha = fnv(k.a), hb = fnv(k.b);
    return ha ^ (hb + 0x9e3779b97f4a7c15ULL + (ha << 6) + (ha >> 2));
  }
};
struct PairEq {
  bool operator()(const PairKey& x, const PairKey& y) const { return x.a == y.a && x.b == y.b; }
};

struct Tokenizer {
  bool loaded = false;
  std::string err;

  Blob blob;
  CatTable cats[5];  // N, L, M, P, S

  // vocab：token -> id。key 指向 blob 内部，零拷贝
  std::unordered_map<std::string_view, int> vocab;
  // merges：pair -> rank。key 指向 blob 的 merges 区
  std::unordered_map<PairKey, int, PairHash, PairEq> ranks;
  // added_tokens：按首字节分桶，桶内按长度降序（长的先匹配）
  std::array<std::vector<std::pair<std::string_view, int>>, 256> added;

  // ByteLevel：byte -> 码点
  std::array<unsigned, 256> b2c{};
  // 每个码点对应的 UTF-8 字节串（1~2 字节）
  std::array<std::string, 256> levelStr{};

  int vocabSize = 0;
};

Tokenizer& inst() {
  static Tokenizer t;
  return t;
}

std::string g_explicitPath;

std::array<unsigned, 256> buildB2C() {
  std::array<unsigned, 256> m{};
  std::array<bool, 256> used{};
  for (int i = 33; i <= 126; i++) { m[i] = (unsigned)i; used[i] = true; }
  for (int i = 161; i <= 172; i++) { m[i] = (unsigned)i; used[i] = true; }
  for (int i = 174; i <= 255; i++) { m[i] = (unsigned)i; used[i] = true; }
  unsigned p = 0;
  for (int b = 0; b < 256; b++)
    if (!used[b]) m[b] = 256 + p++;
  return m;
}

std::string utf8Of(unsigned cp) {
  std::string s;
  if (cp < 0x80) {
    s += (char)cp;
  } else if (cp < 0x800) {
    s += (char)(0xC0 | (cp >> 6));
    s += (char)(0x80 | (cp & 0x3F));
  } else if (cp < 0x10000) {
    s += (char)(0xE0 | (cp >> 12));
    s += (char)(0x80 | ((cp >> 6) & 0x3F));
    s += (char)(0x80 | (cp & 0x3F));
  } else {
    s += (char)(0xF0 | (cp >> 18));
    s += (char)(0x80 | ((cp >> 12) & 0x3F));
    s += (char)(0x80 | ((cp >> 6) & 0x3F));
    s += (char)(0x80 | (cp & 0x3F));
  }
  return s;
}

bool readFile(const std::string& path, std::string* out) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  f.seekg(0, std::ios::end);
  const auto n = f.tellg();
  if (n <= 0) return false;
  out->resize((size_t)n);
  f.seekg(0, std::ios::beg);
  f.read(&(*out)[0], (std::streamsize)n);
  return (bool)f;
}

bool load() {
  Tokenizer& t = inst();
  if (t.loaded) return true;
  if (!t.err.empty()) return false;  // 失败过就不再重试

  std::vector<std::string> candidates;
  if (!g_explicitPath.empty()) candidates.push_back(g_explicitPath);
  candidates.push_back("tools/tokenizer.bin");
  candidates.push_back("tokenizer.bin");

  bool okRead = false;
  for (const auto& p : candidates) {
    if (readFile(p, &t.blob.data)) { okRead = true; break; }
  }
  if (!okRead) {
    t.err = "找不到 tokenizer.bin（应在 app 资源或 tools/tokenizer.bin）";
    return false;
  }

  Blob& b = t.blob;
  b.pos = 0;
  if (!b.need(8) || std::memcmp(b.data.data(), kMagic, 6) != 0) {
    t.err = "tokenizer.bin 格式不对（magic 不匹配）";
    return false;
  }
  b.pos = 6;
  const unsigned ver = b.u16();
  if (ver != 1) { t.err = "tokenizer.bin 版本不支持：" + std::to_string(ver); return false; }

  const unsigned vocabCount = b.u32();
  const unsigned mergeCount = b.u32();
  const unsigned addedCount = b.u32();
  unsigned catCount[5] = {0, 0, 0, 0, 0};
  for (int i = 0; i < 5; i++) catCount[i] = b.u32();
  if (!b.need(1)) { t.err = "tokenizer.bin 截断（头）"; return false; }

  // 区间表
  for (int c = 0; c < 5; c++) {
    t.cats[c].ranges.reserve(catCount[c]);
    for (unsigned k = 0; k < catCount[c]; k++) {
      const unsigned s = b.u32();
      const unsigned e = b.u32();
      t.cats[c].ranges.emplace_back(s, e);
    }
  }

  // vocab：下标即 id
  t.vocab.reserve(vocabCount * 2);
  for (unsigned i = 0; i < vocabCount; i++) {
    const unsigned len = b.u32();
    const std::string_view tok = b.bytes(len);
    if (tok.data() == nullptr) { t.err = "tokenizer.bin 截断（vocab）"; return false; }
    t.vocab.emplace(tok, (int)i);
  }

  // merges：下标即 rank
  t.ranks.reserve(mergeCount * 2);
  for (unsigned i = 0; i < mergeCount; i++) {
    const unsigned la = b.u32();
    const std::string_view a = b.bytes(la);
    const unsigned lb = b.u32();
    const std::string_view bb = b.bytes(lb);
    if (a.data() == nullptr || bb.data() == nullptr) { t.err = "tokenizer.bin 截断（merges）"; return false; }
    t.ranks.emplace(PairKey{a, bb}, (int)i);
  }

  // added_tokens
  for (unsigned i = 0; i < addedCount; i++) {
    const unsigned id = b.u32();
    const unsigned len = b.u32();
    const std::string_view s = b.bytes(len);
    if (s.data() == nullptr) { t.err = "tokenizer.bin 截断（added）"; return false; }
    if (!s.empty()) t.added[(unsigned char)s[0]].emplace_back(s, (int)id);
  }
  for (auto& bucket : t.added) {
    std::sort(bucket.begin(), bucket.end(),
              [](const auto& x, const auto& y) { return x.first.size() > y.first.size(); });
  }

  t.b2c = buildB2C();
  for (int i = 0; i < 256; i++) t.levelStr[i] = utf8Of(t.b2c[i]);
  t.vocabSize = (int)vocabCount;
  t.loaded = true;
  return true;
}

// ------------------------------ UTF-8 ------------------------------
// 解一个码点；坏字节按 1 字节前进并返回 0xFFFD
unsigned decodeOne(const std::string& s, size_t i, size_t* len) {
  const unsigned char c = (unsigned char)s[i];
  if (c < 0x80) { *len = 1; return c; }
  size_t need = 0;
  unsigned v = 0;
  if ((c & 0xE0) == 0xC0) { need = 1; v = c & 0x1F; }
  else if ((c & 0xF0) == 0xE0) { need = 2; v = c & 0x0F; }
  else if ((c & 0xF8) == 0xF0) { need = 3; v = c & 0x07; }
  else { *len = 1; return 0xFFFD; }
  if (i + need >= s.size()) { *len = 1; return 0xFFFD; }
  for (size_t k = 1; k <= need; k++) {
    const unsigned char b = (unsigned char)s[i + k];
    if ((b & 0xC0) != 0x80) { *len = 1; return 0xFFFD; }
    v = (v << 6) | (b & 0x3F);
  }
  *len = need + 1;
  return v;
}

// ------------------------------ 预分词 ------------------------------
struct Cps {
  std::vector<unsigned> cp;   // 码点
  std::vector<size_t> off;    // off[i] = 第 i 个码点起始字节；off[n] = size
};

Cps toCps(const std::string& s) {
  Cps r;
  size_t i = 0;
  while (i < s.size()) {
    size_t len = 1;
    const unsigned c = decodeOne(s, i, &len);
    r.cp.push_back(c);
    r.off.push_back(i);
    i += len;
  }
  r.off.push_back(s.size());
  return r;
}

bool isCjkRange(unsigned cp) {
  return (cp >= 0x4E00 && cp <= 0x9FA5) || (cp >= 0x3040 && cp <= 0x309F) ||
         (cp >= 0x30A0 && cp <= 0x30FF);
}

// RE_WORD 里显式列出的 ASCII 标点：!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
bool isWordPunctAscii(unsigned cp) {
  if (cp >= 0x80) return false;
  static const char* kSet = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
  return cp != 0 && std::strchr(kSet, (char)cp) != nullptr;
}

// 在 cps[i..end) 上匹配 RE_WORD，返回匹配的码点数（0 = 不匹配）
size_t matchWord(const Cps& w, size_t i, size_t end, const Tokenizer& t) {
  const auto isL = [&](size_t k) { return t.cats[1].has(w.cp[k]); };
  const auto isM = [&](size_t k) { return t.cats[2].has(w.cp[k]); };
  const auto isP = [&](size_t k) { return t.cats[3].has(w.cp[k]); };
  const auto isS = [&](size_t k) { return t.cats[4].has(w.cp[k]); };
  const auto isLM = [&](size_t k) { return isL(k) || isM(k); };
  const auto isPS = [&](size_t k) { return isP(k) || isS(k); };
  const auto isCRLF = [&](size_t k) { return w.cp[k] == '\r' || w.cp[k] == '\n'; };
  auto runOf = [&](size_t from, auto pred) {
    size_t k = from;
    while (k < end && pred(k)) k++;
    return k;
  };

  // 1) [!\"#$...~][A-Za-z]+
  if (isWordPunctAscii(w.cp[i])) {
    size_t k = i + 1;
    while (k < end) {
      const unsigned c = w.cp[k];
      if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) k++;
      else break;
    }
    if (k > i + 1) return k - i;
  }

  // 2) [^\r\n\p{L}\p{P}\p{S}]?[\p{L}\p{M}]+
  if (isLM(i)) return runOf(i, isLM) - i;
  if (!isCRLF(i) && !isL(i) && !isP(i) && !isS(i) && i + 1 < end && isLM(i + 1))
    return runOf(i + 1, isLM) - i;

  // 3) ' ?' [\p{P}\p{S}]+ [\r\n]*
  {
    size_t start = SIZE_MAX;
    if (w.cp[i] == ' ' && i + 1 < end && isPS(i + 1)) start = i + 1;
    else if (isPS(i)) start = i;
    if (start != SIZE_MAX) {
      size_t k = runOf(start, isPS);
      while (k < end && isCRLF(k)) k++;
      return k - i;
    }
  }

  // 空白段 [i, j)，后面第一个非空白位置就是 j
  const size_t wsEnd = runOf(i, [&](size_t k) { return isJsSpace(w.cp[k]); });

  // 4) \s* [\r\n]+
  //    贪婪的 \s* 先吃满整段空白，再回溯到「最靠后的 \r/\n」处起匹配 [\r\n]+
  if (wsEnd > i) {
    size_t k = wsEnd;
    while (k > i && !isCRLF(k - 1)) k--;
    if (k > i) {
      size_t e = k - 1;
      while (e < end && isCRLF(e)) e++;
      return e - i;
    }
  }

  // 5) \s+ (?!\S)
  //    \s+ 贪婪吃满后看下一个字符：是 \S 就回溯掉一个，再试。
  //    因为 i..wsEnd 全是空白，回溯一次后位置落在空白上必然成功，
  //    所以结果只有三种：整段（段尾就是串尾）/ 少一个（后面跟 \S）/ 不匹配（R==1）。
  if (wsEnd > i) {
    const size_t run = wsEnd - i;
    if (wsEnd == end) return run;  // 段尾：\s+ 吃满后 (?!\S) 直接成立
    if (run >= 2) return run - 1;  // 后面跟 \S：回溯掉最后一个空白
    // run == 1 且后面是 \S：本分支失败，落到 6)
  }

  // 6) \s+
  if (wsEnd > i) return wsEnd - i;
  return 0;
}

// ------------------------------ BPE ------------------------------
std::vector<std::string> bpe(const std::string& level, const Tokenizer& t) {
  std::vector<std::string> word;
  if (level.empty()) return word;
  {
    size_t i = 0;
    while (i < level.size()) {
      size_t len = 1;
      decodeOne(level, i, &len);
      word.emplace_back(level, i, len);
      i += len;
    }
  }
  while (word.size() > 1) {
    int best = INT32_MAX;
    size_t bestIdx = SIZE_MAX;
    for (size_t i = 0; i + 1 < word.size(); i++) {
      auto it = t.ranks.find(PairKey{word[i], word[i + 1]});
      if (it != t.ranks.end() && it->second < best) { best = it->second; bestIdx = i; }
    }
    if (bestIdx == SIZE_MAX) break;
    word[bestIdx] += word[bestIdx + 1];
    word.erase(word.begin() + (long)bestIdx + 1);
  }
  return word;
}

std::string toLevel(const std::string& text, const Tokenizer& t) {
  std::string out;
  out.reserve(text.size() * 2);
  for (unsigned char c : text) out += t.levelStr[c];
  return out;
}

}  // namespace

// ------------------------------ 对外接口 ------------------------------
void setDataFile(const std::string& path) {
  g_explicitPath = path;
  Tokenizer& t = inst();
  t.loaded = false;
  t.err.clear();
}

bool available() { return load(); }

int estimateFallback(const std::string& text) {
  // 与 util::estimateTokens 同口径：CJK 1 token/字，ASCII 每 3.2 字符 1 token
  int cjk = 0, ascii = 0;
  size_t i = 0;
  while (i < text.size()) {
    const unsigned char c = (unsigned char)text[i];
    if (c < 0x80) { i += 1; ascii++; }
    else if ((c & 0xE0) == 0xC0) { i += 2; cjk++; }
    else if ((c & 0xF0) == 0xE0) { i += 3; cjk++; }
    else { i += 4; cjk++; }
  }
  return cjk + (int)(ascii / 3.2);
}

bool tokenize(const std::string& text, bool detail, Result* out, std::string* err) {
  if (!load()) {
    if (err) *err = inst().err;
    return false;
  }
  const Tokenizer& t = inst();
  if (out) {
    out->count = 0;
    out->pieces.clear();
    out->ids.clear();
    out->vocabSize = t.vocabSize;
  }

  // ---- 1) added_tokens 前缀匹配（按首字节分桶，桶内长的优先）----
  struct Part {
    std::string_view text;
    bool special = false;
    int id = -1;
  };
  std::vector<Part> parts;
  bool changed = false;
  {
    size_t i = 0;
    while (i < text.size()) {
      const auto& bucket = t.added[(unsigned char)text[i]];
      const std::string_view rest(text.data() + i, text.size() - i);
      const std::pair<std::string_view, int>* hit = nullptr;
      for (const auto& kv : bucket) {
        if (rest.size() >= kv.first.size() && rest.compare(0, kv.first.size(), kv.first) == 0) {
          hit = &kv;
          break;
        }
      }
      if (hit) {
        parts.push_back({std::string_view(text.data() + i, hit->first.size()), true, hit->second});
        i += hit->first.size();
        changed = true;
      } else {
        size_t len = 1;
        decodeOne(text, i, &len);
        parts.push_back({std::string_view(text.data() + i, len), false, -1});
        i += len;
      }
    }
  }
  if (!changed) {
    parts.clear();
    parts.push_back({std::string_view(text), false, -1});
  }

  // ---- 2) 逐 part 预分词 + BPE ----
  for (const auto& part : parts) {
    if (part.special) {
      if (out) {
        out->count++;
        if (detail) { out->pieces.emplace_back(part.text.data(), part.text.size()); out->ids.push_back(part.id); }
      }
      continue;
    }
    if (part.text.empty()) continue;
    const std::string seg(part.text);
    const Cps w = toCps(seg);
    const size_t n = w.cp.size();

    std::vector<char> mark(n, 0);
    for (size_t i = 0; i < n; i++) {
      if (t.cats[0].has(w.cp[i])) mark[i] = 1;      // \p{N}
      else if (isCjkRange(w.cp[i])) mark[i] = 1;    // CJK 三段
    }

    auto emit = [&](size_t a, size_t b) {
      if (b <= a) return;
      const std::string piece = seg.substr(w.off[a], w.off[b] - w.off[a]);
      const std::string level = toLevel(piece, t);
      for (const auto& sym : bpe(level, t)) {
        auto it = t.vocab.find(std::string_view(sym));
        if (it == t.vocab.end()) continue;
        if (out) {
          out->count++;
          if (detail) { out->pieces.push_back(sym); out->ids.push_back(it->second); }
        }
      }
    };

    size_t i = 0;
    while (i < n) {
      if (mark[i]) {
        size_t j = i + 1;
        while (j < n && mark[j]) j++;
        emit(i, j);  // 连续标记段整体当一个 isolated piece
        i = j;
      } else {
        size_t j = i + 1;
        while (j < n && !mark[j]) j++;
        // 未标记段内跑 RE_WORD，匹配之间的空隙也保留成 piece
        size_t k = i, last = i;
        while (k < j) {
          const size_t m = matchWord(w, k, j, t);
          if (m == 0) { k++; continue; }
          if (k > last) emit(last, k);
          emit(k, k + m);
          last = k + m;
          k = last;
        }
        if (last < j) emit(last, j);
        i = j;
      }
    }
  }
  return true;
}

}  // namespace tok
}  // namespace ds
