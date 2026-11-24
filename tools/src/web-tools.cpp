// 联网类工具：http_request / fetch_url / web_search（libcurl + 本地 HTML 正文提取）。
// 对照 Web 版 server/tools-core.cjs:1983 / 1791 / 1751。
//
// 移植取舍：
//  * Web 版用 V8 正则链做正文提取；libstdc++ 的 std::regex 在数 MB HTML 上跑
//    `[\s\S]*?<\/\1>` 这种模式会退化成灾难性回溯（手机上会卡死），所以标签级
//    变换改成**单趟线性扫描**，只在「已经切小了的块」上用 std::regex（搜索结果解析）。
//  * 编码识别靠 iconv（iOS 走系统 libiconv，MinGW 走 -liconv），gb2312 用 gbk 超集解。
#include "web-tools.hpp"
#include "util.hpp"

#include <curl/curl.h>
#include <iconv.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstring>
#include <regex>
#include <stdexcept>
#include <string>
#include <vector>

namespace ds {
namespace webtools {
namespace {

using json = nlohmann::json;
using ojson = nlohmann::ordered_json;  // 保留键顺序，对齐 JS 的 JSON.stringify

const char* kUA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36";
constexpr size_t kMaxHtmlBytes = 4 * 1024 * 1024;

// ------------------------------ 参数 / 结果 ------------------------------
std::string sarg(const json& a, const char* k, const std::string& def = "") {
  if (!a.contains(k) || a[k].is_null()) return def;
  if (a[k].is_string()) return a[k].get<std::string>();
  return a[k].dump();
}
long long iarg(const json& a, const char* k, long long def) {
  if (!a.contains(k) || a[k].is_null()) return def;
  if (a[k].is_number()) return a[k].get<long long>();
  if (a[k].is_string()) { try { return std::stoll(a[k].get<std::string>()); } catch (...) { return def; } }
  return def;
}
ToolResult fail(const std::string& msg) { ToolResult r; r.ok = false; r.text = msg; return r; }
ToolResult ok(const std::string& text, json data = json::object()) {
  ToolResult r; r.ok = true; r.text = text; r.data = data.is_null() ? json::object() : data; return r;
}

// ------------------------------ 字符串基元 ------------------------------
std::string toLowerAscii(std::string s) {
  for (auto& c : s) c = (char)std::tolower((unsigned char)c);
  return s;
}
std::string toLowerCopy(const std::string& s) { return toLowerAscii(s); }

// JS 的 \s 还包含 nbsp / 全角空格等，这里按「码点」判定
bool isSpaceCp(unsigned cp) {
  return cp == ' ' || cp == '\t' || cp == '\n' || cp == '\r' || cp == '\f' || cp == '\v' ||
         cp == 0x00A0 || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 ||
         cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000 || cp == 0xFEFF;
}

void appendUtf8(std::string& out, unsigned cp) {
  if (cp < 0x80) {
    out += (char)cp;
  } else if (cp < 0x800) {
    out += (char)(0xC0 | (cp >> 6));
    out += (char)(0x80 | (cp & 0x3F));
  } else if (cp < 0x10000) {
    out += (char)(0xE0 | (cp >> 12));
    out += (char)(0x80 | ((cp >> 6) & 0x3F));
    out += (char)(0x80 | (cp & 0x3F));
  } else {
    out += (char)(0xF0 | (cp >> 18));
    out += (char)(0x80 | ((cp >> 12) & 0x3F));
    out += (char)(0x80 | ((cp >> 6) & 0x3F));
    out += (char)(0x80 | (cp & 0x3F));
  }
}

// 逐码点遍历（坏字节按 1 字节前进，不抛异常）
struct CpWalker {
  const std::string& s;
  size_t i = 0;
  explicit CpWalker(const std::string& str) : s(str) {}
  bool next(unsigned* cp) {
    if (i >= s.size()) return false;
    const unsigned char c = (unsigned char)s[i];
    size_t need = 0;
    unsigned v = 0;
    if (c < 0x80) { *cp = c; i += 1; return true; }
    if ((c & 0xE0) == 0xC0) { need = 1; v = c & 0x1F; }
    else if ((c & 0xF0) == 0xE0) { need = 2; v = c & 0x0F; }
    else if ((c & 0xF8) == 0xF0) { need = 3; v = c & 0x07; }
    else { *cp = 0xFFFD; i += 1; return true; }
    if (i + need >= s.size()) { *cp = 0xFFFD; i += 1; return true; }
    for (size_t k = 1; k <= need; k++) {
      const unsigned char b = (unsigned char)s[i + k];
      if ((b & 0xC0) != 0x80) { *cp = 0xFFFD; i += 1; return true; }
      v = (v << 6) | (b & 0x3F);
    }
    *cp = v;
    i += need + 1;
    return true;
  }
};

int cpLength(const std::string& s) {
  CpWalker w(s);
  int n = 0;
  unsigned cp;
  while (w.next(&cp)) n++;
  return n;
}

// 等价 String(s).replace(/\s+/g, ' ').trim()
std::string collapseWs(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  bool pendingSpace = false;
  CpWalker w(s);
  unsigned cp;
  while (w.next(&cp)) {
    if (isSpaceCp(cp)) { pendingSpace = true; continue; }
    if (pendingSpace && !out.empty()) out += ' ';
    pendingSpace = false;
    appendUtf8(out, cp);
  }
  return out;
}

// ------------------------------ 实体解码 ------------------------------
const char* kEntityNames[] = {"amp", "lt", "gt", "quot", "apos", "nbsp", "ldquo", "rdquo", "lsquo",
                              "rsquo", "hellip", "mdash", "ndash", "middot", "bull", "times",
                              "copy", "reg", "trade", "deg", "euro", "pound", "yen"};
const char* kEntityVals[] = {"&", "<", ">", "\"", "'", " ", "\xE2\x80\x9C", "\xE2\x80\x9D",
                             "\xE2\x80\x98", "\xE2\x80\x99", "\xE2\x80\xA6", "\xE2\x80\x94",
                             "\xE2\x80\x93", "\xC2\xB7", "\xE2\x80\xA2", "\xC3\x97", "\xC2\xA9",
                             "\xC2\xAE", "\xE2\x84\xA2", "\xC2\xB0", "\xE2\x82\xAC", "\xC2\xA3",
                             "\xC2\xA5"};

std::string decodeEntities(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  const size_t n = s.size();
  size_t i = 0;
  while (i < n) {
    const size_t amp = s.find('&', i);
    if (amp == std::string::npos) { out.append(s, i, std::string::npos); break; }
    out.append(s, i, amp - i);
    const size_t semi = s.find(';', amp + 1);
    // 实体长度上限（&#x10ffff; 也就 10 来个字符）
    if (semi == std::string::npos || semi - amp > 12) { out += '&'; i = amp + 1; continue; }
    const std::string body = s.substr(amp + 1, semi - amp - 1);
    bool matched = false;
    if (!body.empty() && body[0] == '#') {
      unsigned cp = 0;
      bool okNum = false;
      try {
        if (body.size() > 1 && (body[1] == 'x' || body[1] == 'X')) {
          if (body.size() > 2) { cp = (unsigned)std::stoul(body.substr(2), nullptr, 16); okNum = true; }
        } else if (body.size() > 1) {
          cp = (unsigned)std::stoul(body.substr(1), nullptr, 10); okNum = true;
        }
      } catch (...) { okNum = false; }
      if (okNum && cp > 0 && cp <= 0x10FFFF) { appendUtf8(out, cp); matched = true; }
    } else if (!body.empty() && std::isalpha((unsigned char)body[0])) {
      bool allWord = true;
      for (char c : body)
        if (!std::isalnum((unsigned char)c)) { allWord = false; break; }
      if (allWord) {
        const std::string low = toLowerCopy(body);
        for (size_t k = 0; k < sizeof(kEntityNames) / sizeof(kEntityNames[0]); k++) {
          if (low == kEntityNames[k]) { out += kEntityVals[k]; matched = true; break; }
        }
      }
    }
    if (matched) { i = semi + 1; }
    else { out += '&'; i = amp + 1; }
  }
  return out;
}

// ------------------------------ 标签扫描 ------------------------------
struct Tag {
  size_t pos = 0;      // '<' 的位置
  size_t end = 0;      // '>' 之后的位置
  std::string name;    // 小写标签名
  bool closing = false;
  bool selfClosing = false;
};

// 单趟线性扫描出所有标签的位置，供 dropNoiseBlocks / pickMainHtml / htmlToText 复用
std::vector<Tag> scanTags(const std::string& html) {
  std::vector<Tag> tags;
  const size_t n = html.size();
  size_t i = 0;
  while (i < n) {
    const size_t lt = html.find('<', i);
    if (lt == std::string::npos) break;
    if (lt + 4 <= n && html.compare(lt, 4, "<!--") == 0) {
      const size_t e = html.find("-->", lt + 4);
      i = (e == std::string::npos) ? n : e + 3;
      continue;
    }
    // <!DOCTYPE ...> / <?xml ...> 这类声明也当标签处理（Web 版靠最后的 <[^>]+> 顺手剥掉）
    if (lt + 1 < n && (html[lt + 1] == '!' || html[lt + 1] == '?')) {
      const size_t gt = html.find('>', lt + 1);
      if (gt == std::string::npos) break;
      Tag t;
      t.pos = lt;
      t.end = gt + 1;
      t.name = "!";
      t.selfClosing = true;
      tags.push_back(t);
      i = t.end;
      continue;
    }
    if (lt + 1 < n && (std::isalpha((unsigned char)html[lt + 1]) || html[lt + 1] == '/')) {
      size_t p = lt + 1;
      bool closing = false;
      if (html[p] == '/') { closing = true; p++; }
      const size_t nameStart = p;
      while (p < n && (std::isalnum((unsigned char)html[p]) || html[p] == '-' || html[p] == ':')) p++;
      if (p == nameStart) { i = lt + 1; continue; }
      Tag t;
      t.pos = lt;
      t.closing = closing;
      t.name = toLowerCopy(html.substr(nameStart, p - nameStart));
      // 找 '>'，跳过引号内的内容
      size_t q = p;
      char quote = 0;
      bool found = false;
      while (q < n) {
        const char c = html[q];
        if (quote) { if (c == quote) quote = 0; }
        else if (c == '"' || c == '\'') quote = c;
        else if (c == '>') { found = true; break; }
        q++;
      }
      if (!found) break;
      t.end = q + 1;
      size_t b = q;
      while (b > lt && std::isspace((unsigned char)html[b - 1])) b--;
      t.selfClosing = (b > lt && html[b - 1] == '/');
      tags.push_back(t);
      i = t.end;
    } else {
      i = lt + 1;
    }
  }
  return tags;
}

// stripTags：去标签 → 解实体 → 压空白
std::string stripTags(const std::string& s) {
  std::string noTags;
  noTags.reserve(s.size());
  const size_t n = s.size();
  size_t i = 0;
  while (i < n) {
    const size_t lt = s.find('<', i);
    if (lt == std::string::npos) { noTags.append(s, i, std::string::npos); break; }
    noTags.append(s, i, lt - i);
    const size_t gt = s.find('>', lt + 1);
    if (gt == std::string::npos) break;
    noTags += ' ';
    i = gt + 1;
  }
  return collapseWs(decodeEntities(noTags));
}

// 取 <tag ...>...</tag> 的第一段内容（线性，避免大页面上跑正则）
bool firstTagInner(const std::string& html, const std::string& name, std::string* out) {
  const std::string open = "<" + name;
  const std::string close = "</" + name;
  const std::string low = toLowerCopy(html);  // 只为大小写不敏感；页面大小在 4MB 以内可接受
  size_t p = low.find(open);
  while (p != std::string::npos) {
    // 确保是完整标签名（后面跟空白或 '>'）
    const size_t after = p + open.size();
    if (after < low.size() && (std::isspace((unsigned char)low[after]) || low[after] == '>' ||
                              low[after] == '/')) {
      const size_t gt = low.find('>', after);
      if (gt == std::string::npos) return false;
      const size_t e = low.find(close, gt + 1);
      if (e == std::string::npos) return false;
      *out = html.substr(gt + 1, e - gt - 1);
      return true;
    }
    p = low.find(open, p + 1);
  }
  return false;
}

// 取 <article>…</article> 或 <main>…</main> 的第一段（Web 版用非贪婪正则，语义一致）
bool firstWholeBlock(const std::string& html, const std::string& name, std::string* out) {
  const std::string low = toLowerCopy(html);
  const std::string open = "<" + name;
  const std::string close = "</" + name;
  size_t p = low.find(open);
  while (p != std::string::npos) {
    const size_t after = p + open.size();
    if (after < low.size() && (std::isspace((unsigned char)low[after]) || low[after] == '>' ||
                              low[after] == '/')) {
      const size_t e = low.find(close, after);
      if (e == std::string::npos) return false;
      const size_t gt = low.find('>', e);
      if (gt == std::string::npos) return false;
      *out = html.substr(p, gt + 1 - p);
      return true;
    }
    p = low.find(open, p + 1);
  }
  return false;
}

// 按 class/id 命中噪声关键词的容器整块删掉（栈配对，未闭合的区间直接放弃）
std::string dropNoiseBlocks(const std::string& html) {
  static const std::regex NOISE(
      "(?:nav|menu|crumb|sidebar|side-bar|footer|copyright|qrcode|share|related|comment|advert|"
      "banner|toolbar|top-?bar|topbar|recommend|hot-?city|breadcrumb|site-?map)",
      std::regex::icase);
  static const std::regex ATTR("(?:class|id)\\s*=\\s*[\"']([^\"']*)[\"']", std::regex::icase);

  const std::vector<Tag> tags = scanTags(html);
  const double limit = (double)html.size() * 0.4;
  std::vector<std::pair<size_t, size_t>> ranges;

  bool inBlock = false;
  std::vector<std::string> stack;
  size_t start = 0;

  for (const Tag& t : tags) {
    if (inBlock) {
      if (t.closing) {
        // 等价 JS 的 stack.lastIndexOf(name) + stack.length = i（连该元素一起截掉）
        auto it = std::find(stack.rbegin(), stack.rend(), t.name);
        if (it != stack.rend()) {
          const size_t idx = stack.size() - 1 - (size_t)(it - stack.rbegin());
          stack.resize(idx);
        }
        if (stack.empty()) {
          if ((double)(t.end - start) <= limit) ranges.emplace_back(start, t.end);
          inBlock = false;
        }
      } else if (!t.selfClosing) {
        stack.push_back(t.name);
      }
      continue;
    }
    if (t.closing) continue;
    // 只在 div/section/ul/ol/nav/aside/footer 上判断（与 Web 版的 TAG 集合一致）
    if (t.name != "div" && t.name != "section" && t.name != "ul" && t.name != "ol" &&
        t.name != "nav" && t.name != "aside" && t.name != "footer")
      continue;
    const std::string whole = html.substr(t.pos, t.end - t.pos);
    std::smatch mAttr;
    if (!std::regex_search(whole, mAttr, ATTR)) continue;
    const std::string attrVal = mAttr[1].str();
    if (!std::regex_search(attrVal, NOISE)) continue;
    start = t.pos;
    if (t.selfClosing) {
      ranges.emplace_back(start, t.end);
    } else {
      stack.clear();
      stack.push_back(t.name);
      inBlock = true;
    }
  }

  if (ranges.empty()) return html;
  std::string out;
  size_t cur = 0;
  for (const auto& r : ranges) {
    if (r.first < cur) continue;
    out.append(html, cur, r.first - cur);
    cur = r.second;
  }
  out.append(html, cur, std::string::npos);
  return out;
}

// 文本密度选主容器：得分 = 纯文本量 − 链接文本量×2
std::string pickMainHtml(const std::string& html) {
  struct Frame {
    std::string name;
    size_t start = 0, end = 0;
    long long text = 0, link = 0;
  };
  static const std::regex ATAG("</?(div|section|article|main|td|ul|nav|aside|footer|header|a)\\b[^>]*>",
                               std::regex::icase);

  std::vector<Frame> frames;
  std::vector<Frame> cands;
  size_t last = 0;
  int linkDepth = 0;

  auto segLen = [&](size_t from, size_t to) -> long long {
    if (to <= from) return 0;
    return (long long)cpLength(stripTags(html.substr(from, to - from)));
  };

  // 这里用正则迭代器只为拿到「位置 + 标签名」，输入长度在 4MB 以内、模式简单，
  // 不会像 `[\s\S]*?` 那样回溯爆炸。
  std::string lowered = toLowerCopy(html);
  std::sregex_iterator it(lowered.begin(), lowered.end(), ATAG), end;
  for (; it != end; ++it) {
    const std::smatch& m = *it;
    const size_t pos = (size_t)m.position(0);
    if (!frames.empty() && pos > last) {
      const long long n = segLen(last, pos);
      if (n) {
        Frame& top = frames.back();
        top.text += n;
        if (linkDepth > 0) top.link += n;
      }
    }
    last = pos + (size_t)m.length(0);
    const std::string whole = m.str(0);
    const bool closing = whole.size() > 1 && whole[1] == '/';
    const std::string name = toLowerCopy(m[1].str());
    if (name == "a") {
      if (closing) linkDepth = std::max(0, linkDepth - 1);
      else if (!(whole.size() >= 2 && whole.compare(whole.size() - 2, 2, "/>") == 0)) linkDepth++;
      continue;
    }
    if (closing) {
      int i = (int)frames.size() - 1;
      while (i >= 0 && frames[(size_t)i].name != name) i--;
      if (i < 0) continue;
      while ((int)frames.size() - 1 > i) {
        Frame f = frames.back();
        frames.pop_back();
        f.end = last;
        if (f.text >= 200) cands.push_back(f);
        if (!frames.empty()) { frames.back().text += f.text; frames.back().link += f.link; }
      }
      Frame f = frames.back();
      frames.pop_back();
      f.end = last;
      if (f.text >= 200) cands.push_back(f);
      if (!frames.empty()) { frames.back().text += f.text; frames.back().link += f.link; }
    } else if (!(whole.size() >= 2 && whole.compare(whole.size() - 2, 2, "/>") == 0)) {
      Frame f;
      f.name = name;
      f.start = pos;
      f.end = last;
      frames.push_back(f);
    }
  }

  const Frame* best = nullptr;
  long long bestScore = 0;
  for (const auto& c : cands) {
    const long long score = c.text - c.link * 2;
    if (score > bestScore) { bestScore = score; best = &c; }
  }
  if (!best || bestScore < 200) return html;
  const long long total = (long long)cpLength(collapseWs(decodeEntities(html)));
  if (best->text < 400 || best->text < (long long)((double)total * 0.3)) return html;
  if (best->end <= best->start) return html;
  return html.substr(best->start, best->end - best->start);
}

struct HtmlDoc {
  std::string title;
  std::string text;
};

// HTML → 纯文本：剥标签、保段落、压空白（对应 Web 版 htmlToText 的正则链）
HtmlDoc htmlToText(const std::string& html) {
  HtmlDoc doc;
  {
    std::string inner;
    if (firstTagInner(html, "title", &inner)) doc.title = stripTags(inner);
  }

  // 正文优先：<article> / <main> 存在时只取它；否则按文本密度挑主容器
  std::string scope = html;
  std::string art;
  bool picked = false;
  if (firstWholeBlock(html, "article", &art) && art.size() > 800) { scope = art; picked = true; }
  else if (firstWholeBlock(html, "main", &art) && art.size() > 800) { scope = art; picked = true; }
  if (!picked) {
    const std::string cand = pickMainHtml(html);
    if (cand.size() > 500 && cand.size() < (size_t)((double)html.size() * 0.95)) scope = cand;
  }
  // 超大页面跳过去噪，避免扫描过慢
  if (scope.size() < 2 * 1024 * 1024) scope = dropNoiseBlocks(scope);

  // ---- 单趟扫描：剥块、保段落 ----
  static const char* kDropNames[] = {"script", "style", "noscript", "template", "svg",  "canvas",
                                     "iframe", "object", "embed",    "form",     "select", "textarea",
                                     "button", "nav",    "aside",    "footer"};
  static const char* kBlockClose[] = {"p",     "div",    "section", "article", "li",    "tr",
                                      "h1",    "h2",     "h3",      "h4",      "h5",    "h6",
                                      "blockquote", "pre", "table", "ul",     "ol",    "dd",
                                      "dt",    "figure", "figcaption", "header"};
  auto inList = [](const std::string& name, const char* const* list, size_t n) {
    for (size_t k = 0; k < n; k++)
      if (name == list[k]) return true;
    return false;
  };

  std::string flat;
  flat.reserve(scope.size());
  const std::vector<Tag> tags = scanTags(scope);
  size_t cur = 0;
  for (size_t k = 0; k < tags.size(); k++) {
    const Tag& t = tags[k];
    if (t.pos > cur) flat.append(scope, cur, t.pos - cur);
    cur = t.end;

    if (t.closing) {
      if (inList(t.name, kBlockClose, sizeof(kBlockClose) / sizeof(kBlockClose[0]))) flat += '\n';
      else flat += ' ';
      continue;
    }
    if (t.name == "br") { flat += '\n'; continue; }
    if (inList(t.name, kDropNames, sizeof(kDropNames) / sizeof(kDropNames[0]))) {
      // 跳到同名闭合标签之后（按同名嵌套计深度，比 Web 版取「第一个 </name>」更稳）
      size_t j = k + 1;
      int depth = 1;
      for (; j < tags.size(); j++) {
        if (tags[j].name != t.name) continue;
        if (tags[j].closing) { if (--depth == 0) break; }
        else if (!tags[j].selfClosing) depth++;
      }
      if (j < tags.size()) { cur = tags[j].end; k = j; }
      else { cur = scope.size(); k = tags.size(); }
      flat += ' ';
      continue;
    }
    if (t.selfClosing) { flat += ' '; continue; }
    if (t.name == "li") { flat += "\n- "; continue; }
    if (t.name.size() == 2 && t.name[0] == 'h' && t.name[1] >= '1' && t.name[1] <= '6') {
      flat += '\n';
      flat.append((size_t)(t.name[1] - '0'), '#');
      flat += ' ';
      continue;
    }
    flat += ' ';
  }
  if (cur < scope.size()) flat.append(scope, cur, std::string::npos);

  // ---- 逐行规范化 ----
  std::string s = decodeEntities(flat);
  s.erase(std::remove(s.begin(), s.end(), '\r'), s.end());

  std::vector<std::string> lines;
  {
    size_t i = 0;
    while (i <= s.size()) {
      const size_t nl = s.find('\n', i);
      std::string line = (nl == std::string::npos) ? s.substr(i) : s.substr(i, nl - i);
      // 行内连续空白（含 nbsp / 全角空格）压成一个空格，并去首尾空白
      line = collapseWs(line);
      lines.push_back(line);
      if (nl == std::string::npos) break;
      i = nl + 1;
    }
  }

  // 去掉与页面标题重复的行
  if (!doc.title.empty()) {
    lines.erase(std::remove_if(lines.begin(), lines.end(),
                               [&](const std::string& l) { return util::trim(l) == doc.title; }),
                lines.end());
  }

  // 导航行：用 | 或 · 串起一长串短词的，基本是菜单
  {
    std::vector<std::string> kept;
    for (const auto& line : lines) {
      std::vector<std::string> parts;
      std::string curPart;
      for (size_t i = 0; i < line.size();) {
        // 分隔符：'|' '｜' '·'
        if (line.compare(i, 3, "\xEF\xBD\x9C") == 0) { parts.push_back(util::trim(curPart)); curPart.clear(); i += 3; continue; }
        if (line.compare(i, 2, "\xC2\xB7") == 0) { parts.push_back(util::trim(curPart)); curPart.clear(); i += 2; continue; }
        if (line[i] == '|') { parts.push_back(util::trim(curPart)); curPart.clear(); i++; continue; }
        curPart += line[i];
        i++;
      }
      parts.push_back(util::trim(curPart));
      parts.erase(std::remove_if(parts.begin(), parts.end(), [](const std::string& p) { return p.empty(); }),
                  parts.end());
      bool navLine = parts.size() >= 5;
      if (navLine) {
        for (const auto& p : parts)
          if (cpLength(p) > 10) { navLine = false; break; }
      }
      if (!navLine) kept.push_back(line);
    }
    lines.swap(kept);
  }

  // 连续 8 行以上、且多数是「- 」列表项的极短行（导航栏、页脚链接）整块丢掉
  {
    auto isShort = [](const std::string& line) {
      std::string t = line;
      if (t.rfind("- ", 0) == 0) t = util::trim(t.substr(1));
      if (util::trim(t).empty()) return true;
      if (cpLength(t) > 12) return false;
      static const char* punct = "。，、；：！？,.!?;:";
      for (unsigned char c : t)
        if (c < 0x80 && std::strchr(punct, (char)c)) return false;
      // 全角标点（多字节）
      if (t.find("\xE3\x80\x82") != std::string::npos || t.find("\xEF\xBC\x8C") != std::string::npos ||
          t.find("\xE3\x80\x81") != std::string::npos || t.find("\xEF\xBC\x9B") != std::string::npos ||
          t.find("\xEF\xBC\x9A") != std::string::npos || t.find("\xEF\xBC\x81") != std::string::npos ||
          t.find("\xEF\xBC\x9F") != std::string::npos)
        return false;
      // 连续两位以上数字
      int run = 0;
      for (unsigned char c : t) {
        if (std::isdigit(c)) { if (++run >= 2) return false; }
        else run = 0;
      }
      return true;
    };
    auto dashy = [](const std::vector<std::string>& run) {
      if (run.empty()) return false;
      size_t d = 0;
      for (const auto& l : run) {
        const std::string t = util::trim(l);
        if (t.rfind("- ", 0) == 0 || t == "-") d++;
      }
      return (double)d / (double)run.size() >= 0.6;
    };

    std::vector<std::string> kept;
    std::vector<std::string> run;
    auto flush = [&]() {
      if (run.size() < 8 || !dashy(run)) kept.insert(kept.end(), run.begin(), run.end());
      run.clear();
    };
    for (const auto& line : lines) {
      if (util::trim(line).empty()) { flush(); kept.push_back(""); continue; }
      if (isShort(line)) { run.push_back(line); continue; }
      flush();
      kept.push_back(line);
    }
    flush();
    lines.swap(kept);
  }

  // 清掉空行（含只有「-」的行），连续空行最多留一行
  {
    std::string joined;
    int blank = 0;
    for (const auto& line : lines) {
      const std::string t = util::trim(line);
      if (t.empty() || t == "-") { blank++; continue; }
      if (blank && !joined.empty()) joined += '\n';  // 上一行已带 '\n'，再加一个就是一个空行
      blank = 0;
      joined += t;
      joined += '\n';
    }
    doc.text = util::trim(joined);
  }
  return doc;
}

// ------------------------------ 编码 ------------------------------
std::string sniffCharset(const std::string& buf, const std::string& contentType) {
  static const std::regex CT("charset=[\"']?([\\w-]+)", std::regex::icase);
  std::smatch m;
  if (std::regex_search(contentType, m, CT)) return toLowerCopy(m[1].str());
  const std::string head = buf.substr(0, std::min<size_t>(4096, buf.size()));
  static const std::regex META1("<meta[^>]+charset=[\"']?([\\w-]+)", std::regex::icase);
  static const std::regex META2("charset=[\"']?([\\w-]+)", std::regex::icase);
  if (std::regex_search(head, m, META1)) return toLowerCopy(m[1].str());
  if (std::regex_search(head, m, META2)) return toLowerCopy(m[1].str());
  return "utf-8";
}

std::string decodeBuf(const std::string& buf, const std::string& charset) {
  std::string cs = toLowerCopy(charset);
  if (cs.empty() || cs == "utf-8" || cs == "utf8") return buf;
  // 别名：gb2312 用 gbk 超集解（与 Web 版一致）
  if (cs == "gb2312" || cs == "x-gbk") cs = "gbk";
  iconv_t cd = iconv_open("UTF-8", cs.c_str());
  if (cd == (iconv_t)-1) return buf;  // 不认识的编码就按 UTF-8 原样返回

  std::string out;
  out.reserve(buf.size() * 3 / 2);
  std::vector<char> in(buf.begin(), buf.end());
  char* ip = in.data();
  size_t il = in.size();
  char chunk[8192];
  while (il > 0) {
    char* op = chunk;
    size_t ol = sizeof(chunk);
    const size_t rc = iconv(cd, &ip, &il, &op, &ol);
    out.append(chunk, sizeof(chunk) - ol);
    if (rc == (size_t)-1) {
      if (errno == E2BIG) continue;
      // EILSEQ / EINVAL：跳过 1 字节继续（等价 TextDecoder 的 fatal:false 替换）
      if (il > 0) { ip++; il--; out += "\xEF\xBF\xBD"; }
      else break;
    }
  }
  iconv_close(cd);
  return out;
}

// ------------------------------ URL 校验 ------------------------------
bool isIpv4Like(const std::string& h) {
  int parts = 0;
  size_t i = 0;
  while (i < h.size()) {
    size_t j = i;
    while (j < h.size() && std::isdigit((unsigned char)h[j])) j++;
    if (j == i || j - i > 3) return false;
    if (j < h.size() && h[j] != '.') return false;
    parts++;
    if (j < h.size()) j++;
    i = j;
  }
  return parts == 4;
}

// 放行公网 http(s) 与 127.0.0.1；其余本机/保留地址一律拦住（与 Web 版同规则）
bool assertPublicUrl(const std::string& raw, std::string* out, std::string* err) {
  const std::string s = util::trim(raw);
  const size_t schemeEnd = s.find("://");
  if (schemeEnd == std::string::npos) { *err = "URL 格式不正确"; return false; }
  const std::string scheme = toLowerCopy(s.substr(0, schemeEnd));
  if (scheme != "http" && scheme != "https") { *err = "只支持 http / https 链接"; return false; }
  size_t p = schemeEnd + 3;
  // 去掉 userinfo
  const size_t slash = s.find('/', p);
  const size_t authEnd = (slash == std::string::npos) ? s.size() : slash;
  const std::string authority = s.substr(p, authEnd - p);
  std::string host = authority;
  const size_t at = host.rfind('@');
  if (at != std::string::npos) host = host.substr(at + 1);
  if (!host.empty() && host[0] == '[') {
    const size_t rb = host.find(']');
    host = (rb == std::string::npos) ? host.substr(1) : host.substr(1, rb - 1);
  } else {
    const size_t colon = host.rfind(':');
    if (colon != std::string::npos && isIpv4Like(host.substr(0, colon))) host = host.substr(0, colon);
    else if (colon != std::string::npos && host.find(':') == colon) host = host.substr(0, colon);
  }
  host = toLowerCopy(host);
  if (host.empty()) { *err = "URL 格式不正确"; return false; }

  bool blocked = (host.rfind("127.", 0) == 0 && host != "127.0.0.1") || host == "localhost" ||
                 host == "0.0.0.0" || host == "::1" || host.rfind("169.254.", 0) == 0 ||
                 host.rfind("fe80:", 0) == 0;
  if (blocked) { *err = "出于安全考虑，只允许抓取公网地址或 127.0.0.1"; return false; }
  *out = s;
  return true;
}

// ------------------------------ curl ------------------------------
struct CurlGuard {
  CurlGuard() { curl_global_init(CURL_GLOBAL_DEFAULT); }
  ~CurlGuard() { curl_global_cleanup(); }
};
void ensureCurl() { static CurlGuard g; }

struct FetchOpts {
  long timeoutMs = 20000;
  size_t maxBytes = kMaxHtmlBytes;
  std::string method = "GET";
  std::string body;
  bool sendBody = false;
  std::vector<std::string> extraHeaders;
};

struct FetchResult {
  bool transportOk = false;
  std::string err;
  long status = 0;
  std::string statusText;
  std::string body;
  std::string contentType;
  std::string finalUrl;
  std::vector<std::string> headers;
  bool truncated = false;
};

struct Sink {
  std::string data;
  size_t maxBytes = 0;
  bool truncated = false;
};

size_t writeCb(char* ptr, size_t size, size_t nmemb, void* ud) {
  auto* s = static_cast<Sink*>(ud);
  const size_t n = size * nmemb;
  if (s->data.size() + n > s->maxBytes) {
    const size_t keep = s->maxBytes > s->data.size() ? s->maxBytes - s->data.size() : 0;
    if (keep) s->data.append(ptr, keep);
    s->truncated = true;
    return 0;  // 主动中止传输，curl 会返回 CURLE_WRITE_ERROR
  }
  s->data.append(ptr, n);
  return n;
}

size_t headerCb(char* ptr, size_t size, size_t nmemb, void* ud) {
  auto* r = static_cast<FetchResult*>(ud);
  const size_t n = size * nmemb;
  std::string line(ptr, n);
  while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) line.pop_back();
  if (line.rfind("HTTP/", 0) == 0) {
    // 状态行：HTTP/1.1 200 OK —— 取状态码后的文字
    const size_t sp1 = line.find(' ');
    if (sp1 != std::string::npos) {
      const size_t sp2 = line.find(' ', sp1 + 1);
      if (sp2 != std::string::npos) r->statusText = line.substr(sp2 + 1);
    }
    r->headers.clear();  // 重定向后会再来一条状态行，只保留最后一次的响应头
  } else if (!line.empty()) {
    if (r->headers.size() < 20) r->headers.push_back(line);
  }
  return n;
}

FetchResult curlFetch(const std::string& url, const FetchOpts& o) {
  ensureCurl();
  FetchResult r;
  CURL* h = curl_easy_init();
  if (!h) { r.err = "curl 初始化失败"; return r; }

  Sink sink;
  sink.maxBytes = o.maxBytes;

  struct curl_slist* hdrs = nullptr;
  const std::string ua = std::string("user-agent: ") + kUA;
  hdrs = curl_slist_append(hdrs, ua.c_str());
  hdrs = curl_slist_append(hdrs, "accept-language: zh-CN,zh;q=0.9,en;q=0.8");
  hdrs = curl_slist_append(
      hdrs,
      "accept: text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,"
      "text/plain;q=0.7,*/*;q=0.5");
  for (const auto& e : o.extraHeaders) hdrs = curl_slist_append(hdrs, e.c_str());

  curl_easy_setopt(h, CURLOPT_URL, url.c_str());
  curl_easy_setopt(h, CURLOPT_HTTPHEADER, hdrs);
  curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(h, CURLOPT_MAXREDIRS, 5L);
  curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, o.timeoutMs);
  curl_easy_setopt(h, CURLOPT_CONNECTTIMEOUT_MS, std::min<long>(o.timeoutMs, 8000));
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, writeCb);
  curl_easy_setopt(h, CURLOPT_WRITEDATA, &sink);
  curl_easy_setopt(h, CURLOPT_HEADERFUNCTION, headerCb);
  curl_easy_setopt(h, CURLOPT_HEADERDATA, &r);
  curl_easy_setopt(h, CURLOPT_ACCEPT_ENCODING, "");  // 让 curl 自动解 gzip/deflate/br
  curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(h, CURLOPT_USERAGENT, kUA);
#if defined(__APPLE__)
  // iOS 上 curl 的证书校验走系统信任链，保持默认即可
#endif
  if (o.sendBody) {
    curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, o.method.c_str());
    curl_easy_setopt(h, CURLOPT_POSTFIELDS, o.body.c_str());
    curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, (long)o.body.size());
  } else if (o.method != "GET") {
    curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, o.method.c_str());
  }
  if (o.method == "HEAD") curl_easy_setopt(h, CURLOPT_NOBODY, 1L);

  const CURLcode rc = curl_easy_perform(h);
  r.body = std::move(sink.data);
  r.truncated = sink.truncated;
  if (rc == CURLE_OK || (rc == CURLE_WRITE_ERROR && sink.truncated)) {
    r.transportOk = true;
    long code = 0;
    curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &code);
    r.status = code;
    char* ct = nullptr;
    curl_easy_getinfo(h, CURLINFO_CONTENT_TYPE, &ct);
    if (ct) r.contentType = ct;
    char* eff = nullptr;
    curl_easy_getinfo(h, CURLINFO_EFFECTIVE_URL, &eff);
    r.finalUrl = eff ? eff : url;
  } else {
    r.err = curl_easy_strerror(rc);
  }
  curl_slist_free_all(hdrs);
  curl_easy_cleanup(h);
  return r;
}

// ------------------------------ JSON 美化 ------------------------------
// 等价 JSON.stringify(JSON.parse(text), null, 2)；用 ordered_json 保住键顺序
std::string prettyJson(const std::string& text) {
  try {
    ojson j = ojson::parse(text);
    return j.dump(2);
  } catch (...) {
    return text;
  }
}

bool looksLikeJson(const std::string& head) {
  for (char c : head) {
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
    return c == '{' || c == '[';
  }
  return false;
}

std::string headOf(const std::string& s, size_t n) { return s.substr(0, std::min(n, s.size())); }

// ------------------------------ 搜索结果解析 ------------------------------
std::string xmlValue(const std::string& xml, const std::string& tag) {
  const std::string open = "<" + tag;
  const std::string close = "</" + tag + ">";
  const std::string low = toLowerCopy(xml);
  size_t p = low.find(open);
  if (p == std::string::npos) return "";
  const size_t gt = low.find('>', p);
  if (gt == std::string::npos) return "";
  const size_t e = low.find(close, gt + 1);
  if (e == std::string::npos) return "";
  std::string raw = xml.substr(gt + 1, e - gt - 1);
  // 去 CDATA 包裹
  {
    const std::string t = util::trim(raw);
    if (t.rfind("<![CDATA[", 0) == 0 && t.size() >= 12 && t.compare(t.size() - 3, 3, "]]>") == 0)
      raw = t.substr(9, t.size() - 12);
  }
  return stripTags(raw);
}

std::string pad2(int v) {
  std::string s = std::to_string(v);
  return s.size() < 2 ? "0" + s : s;
}

// RSS 的 pubDate 转 YYYY-MM-DD；Bing 中文站返回「周日, 23 11月 2026 00:53:00 GMT」
std::string shortDate(const std::string& in) {
  if (util::trim(in).empty()) return "";
  const std::string str = util::trim(in);
  {
    static const std::regex ISO("(\\d{4})-(\\d{1,2})-(\\d{1,2})");
    std::smatch m;
    if (std::regex_search(str, m, ISO))
      return m[1].str() + "-" + pad2(std::stoi(m[2].str())) + "-" + pad2(std::stoi(m[3].str()));
  }
  {
    // 中文格式：22 11月 2026
    static const std::regex ZH("(\\d{1,2})\\s+(\\d{1,2})\\s*月\\s*(\\d{4})");
    std::smatch m;
    if (std::regex_search(str, m, ZH))
      return m[3].str() + "-" + pad2(std::stoi(m[2].str())) + "-" + pad2(std::stoi(m[1].str()));
  }
  {
    static const std::regex EN(",\\s*(\\d{1,2})\\s+([A-Za-z]{3,})\\s+(\\d{4})");
    std::smatch m;
    if (std::regex_search(str, m, EN)) {
      static const char* MON[] = {"jan", "feb", "mar", "apr", "may", "jun",
                                  "jul", "aug", "sep", "oct", "nov", "dec"};
      const int day = std::stoi(m[1].str());
      const std::string monName = toLowerCopy(m[2].str().substr(0, 3));
      int mon = 0;
      for (int k = 0; k < 12; k++)
        if (monName == MON[k]) { mon = k + 1; break; }
      if (mon >= 1 && mon <= 12 && day >= 1 && day <= 31)
        return m[3].str() + "-" + pad2(mon) + "-" + pad2(day);
    }
  }
  return str.substr(0, std::min<size_t>(20, str.size()));
}

// 把 <open ...> ... </close> 的块按出现顺序切出来（线性，避免大页面上跑正则）
std::vector<std::string> splitBlocks(const std::string& html, const std::string& openNeedle,
                                    const std::string& closeNeedle) {
  std::vector<std::string> out;
  const std::string low = toLowerCopy(html);
  const std::string openLow = toLowerCopy(openNeedle);
  const std::string closeLow = toLowerCopy(closeNeedle);
  size_t p = 0;
  while (true) {
    const size_t s = low.find(openLow, p);
    if (s == std::string::npos) break;
    const size_t e = low.find(closeLow, s + openLow.size());
    if (e == std::string::npos) break;
    out.push_back(html.substr(s, e + closeLow.size() - s));
    p = e + closeLow.size();
  }
  return out;
}

bool isHttpUrl(const std::string& u) {
  const std::string low = toLowerCopy(u);
  return low.rfind("http://", 0) == 0 || low.rfind("https://", 0) == 0;
}

std::vector<json> searchBingRss(const std::string& query, int count) {
  const std::string url = "https://cn.bing.com/search?format=rss&setlang=zh-CN&cc=CN&count=" +
                          std::to_string(count) + "&q=" + util::urlEncode(query);
  FetchOpts o;
  o.timeoutMs = 12000;
  o.maxBytes = 1024 * 1024;
  FetchResult r = curlFetch(url, o);
  if (!r.transportOk) throw std::runtime_error(r.err);
  if (!r.body.empty() && r.status >= 400) throw std::runtime_error("HTTP " + std::to_string(r.status));
  const std::string text = decodeBuf(r.body, sniffCharset(r.body, r.contentType));
  std::vector<json> out;
  for (const auto& it : splitBlocks(text, "<item>", "</item>")) {
    json row = {{"title", xmlValue(it, "title")},
                {"url", xmlValue(it, "link")},
                {"snippet", headOf(xmlValue(it, "description"), 320)},
                {"date", shortDate(xmlValue(it, "pubDate"))},
                {"engine", "bing"}};
    if (!row["title"].get<std::string>().empty() && isHttpUrl(row["url"].get<std::string>()))
      out.push_back(row);
  }
  return out;
}

std::vector<json> searchBingHtml(const std::string& query, int count) {
  const std::string url =
      "https://cn.bing.com/search?count=" + std::to_string(count) + "&q=" + util::urlEncode(query);
  FetchOpts o;
  o.timeoutMs = 12000;
  o.maxBytes = 2 * 1024 * 1024;
  FetchResult r = curlFetch(url, o);
  if (!r.transportOk) throw std::runtime_error(r.err);
  const std::string text = decodeBuf(r.body, sniffCharset(r.body, r.contentType));
  static const std::regex A("<h2[^>]*>\\s*<a[^>]+href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</a>",
                            std::regex::icase);
  static const std::regex P("<p[^>]*>([\\s\\S]*?)</p>", std::regex::icase);
  std::vector<json> out;
  for (const auto& block : splitBlocks(text, "<li class=\"b_algo\"", "</li>")) {
    std::smatch m;
    if (!std::regex_search(block, m, A)) continue;
    json row = {{"title", stripTags(m[2].str())},
                {"url", decodeEntities(m[1].str())},
                {"snippet", ""},
                {"engine", "bing"}};
    std::smatch pm;
    if (std::regex_search(block, pm, P)) row["snippet"] = headOf(stripTags(pm[1].str()), 320);
    if (!row["title"].get<std::string>().empty() && isHttpUrl(row["url"].get<std::string>()))
      out.push_back(row);
  }
  return out;
}

std::vector<json> search360(const std::string& query, int count) {
  const std::string url = "https://www.so.com/s?q=" + util::urlEncode(query) + "&pn=1";
  FetchOpts o;
  o.timeoutMs = 12000;
  o.maxBytes = 2 * 1024 * 1024;
  FetchResult r = curlFetch(url, o);
  if (!r.transportOk) throw std::runtime_error(r.err);
  const std::string text = decodeBuf(r.body, sniffCharset(r.body, r.contentType));
  static const std::regex A("<h3[^>]*>[\\s\\S]*?<a[^>]+href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</a>",
                            std::regex::icase);
  static const std::regex D1("<p class=\"res-desc[^\"]*\"[^>]*>([\\s\\S]*?)</p>",
                             std::regex::icase);
  static const std::regex D2("<div class=\"res-comm-con[\\s\\S]*?<p[^>]*>([\\s\\S]*?)</p>",
                             std::regex::icase);
  std::vector<json> out;
  for (const auto& block : splitBlocks(text, "<li class=\"res-list", "</li>")) {
    std::smatch m;
    if (!std::regex_search(block, m, A)) continue;
    json row = {{"title", stripTags(m[2].str())},
                {"url", decodeEntities(m[1].str())},
                {"snippet", ""},
                {"engine", "360"}};
    std::smatch dm;
    if (std::regex_search(block, dm, D1) || std::regex_search(block, dm, D2))
      row["snippet"] = headOf(stripTags(dm[1].str()), 320);
    if (!row["title"].get<std::string>().empty() && isHttpUrl(row["url"].get<std::string>()))
      out.push_back(row);
  }
  return out;
}

}  // namespace

// ---------------------------------------------------------------------------
// http_request —— tools-core.cjs:1983
// ---------------------------------------------------------------------------
ToolResult httpRequest(const json& a) {
  const std::string raw = util::trim(sarg(a, "url"));
  if (raw.empty()) return fail("缺少 url 参数。");
  std::string url, err;
  if (!assertPublicUrl(raw, &url, &err)) return fail(err);

  std::string method = toLowerCopy(util::trim(sarg(a, "method", "GET")));
  std::transform(method.begin(), method.end(), method.begin(),
                 [](unsigned char c) { return (char)std::toupper(c); });
  if (method != "GET" && method != "POST" && method != "PUT" && method != "DELETE" &&
      method != "HEAD" && method != "PATCH")
    return fail("不支持的方法 " + method + "，可选 GET/POST/PUT/DELETE/HEAD/PATCH。");

  long long maxChars = iarg(a, "max_chars", 6000);
  maxChars = std::min<long long>(30000, std::max<long long>(200, maxChars));

  FetchOpts o;
  o.timeoutMs = 20000;
  o.method = method;
  o.sendBody = (method == "POST" || method == "PUT" || method == "PATCH");
  if (o.sendBody) o.body = sarg(a, "body");
  if (a.contains("headers") && a["headers"].is_object()) {
    for (auto it = a["headers"].begin(); it != a["headers"].end(); ++it) {
      const std::string v = it.value().is_string() ? it.value().get<std::string>() : it.value().dump();
      o.extraHeaders.push_back(it.key() + ": " + v);
    }
  }

  FetchResult r = curlFetch(url, o);
  if (!r.transportOk) return fail("请求失败：" + r.err);

  std::string text = decodeBuf(r.body, sniffCharset(r.body, r.contentType));
  const long long total = cpLength(text);
  const bool cut = total > maxChars;
  if (cut) {
    // 按码点截断，避免把多字节字符切一半
    std::string out;
    CpWalker w(text);
    unsigned cp;
    long long n = 0;
    while (n < maxChars && w.next(&cp)) { appendUtf8(out, cp); n++; }
    text.swap(out);
  }
  const std::string ct = r.contentType;
  if (toLowerCopy(ct).find("json") != std::string::npos ||
      toLowerCopy(ct).find("javascript") != std::string::npos || looksLikeJson(headOf(text, 64)))
    text = prettyJson(text);

  std::string hs;
  for (size_t i = 0; i < r.headers.size() && i < 20; i++) {
    if (i) hs += '\n';
    hs += r.headers[i];
  }
  std::string out = method + " " + url;
  out += "\n\n状态：" + std::to_string(r.status) + (r.statusText.empty() ? "" : " " + r.statusText);
  out += "\n\n最终地址：" + r.finalUrl;
  out += "\n\n响应头：\n" + hs;
  out += "\n\n正文";
  if (cut) out += "（共 " + std::to_string(total) + " 字，截断到前 " + std::to_string(maxChars) + " 字）";
  out += "：\n" + (text.empty() ? std::string("（空）") : text);

  ToolResult res;
  res.ok = (r.status >= 200 && r.status < 300);
  res.text = out;
  res.data = {{"status", r.status}, {"finalUrl", r.finalUrl}, {"contentType", ct},
              {"truncated", cut}};
  return res;
}

// ---------------------------------------------------------------------------
// fetch_url —— tools-core.cjs:1791
// ---------------------------------------------------------------------------
ToolResult fetchUrl(const json& a) {
  const std::string raw = util::trim(sarg(a, "url"));
  if (raw.empty()) return fail("缺少 url 参数。");
  std::string url, err;
  if (!assertPublicUrl(raw, &url, &err)) return fail(err);
  long long maxChars = iarg(a, "max_chars", 8000);
  maxChars = std::min<long long>(40000, std::max<long long>(500, maxChars));

  FetchOpts o;
  o.timeoutMs = 20000;
  o.maxBytes = kMaxHtmlBytes;
  FetchResult r = curlFetch(url, o);
  if (!r.transportOk) return fail("抓取失败：" + r.err + "（" + url + "）。可以换个链接或改用搜索引擎摘要。");
  if (r.status < 200 || r.status >= 400)
    return fail("抓取失败：HTTP " + std::to_string(r.status) + "（" + url +
                "）。可以换个链接或改用搜索引擎摘要。");

  const std::string charset = sniffCharset(r.body, r.contentType);
  const std::string text0 = decodeBuf(r.body, charset);
  const std::string ctLow = toLowerCopy(r.contentType);
  static const std::regex BINARY(
      "application/(pdf|zip|octet-stream)|image/|video/|audio/", std::regex::icase);
  if (std::regex_search(ctLow, BINARY)) {
    std::string shortCt = r.contentType.substr(0, r.contentType.find(';'));
    return fail("该链接不是网页正文（" + shortCt + "），无法提取文本：" + url);
  }

  std::string title, text;
  if (ctLow.find("json") != std::string::npos || ctLow.find("javascript") != std::string::npos ||
      looksLikeJson(headOf(text0, 64))) {
    text = prettyJson(text0);
  } else if (ctLow.find("html") != std::string::npos || ctLow.find("xml") != std::string::npos ||
             [&] {
               const std::string head = toLowerCopy(headOf(text0, 2048));
               return head.find("<html") != std::string::npos ||
                      head.find("<body") != std::string::npos ||
                      head.find("<div") != std::string::npos;
             }()) {
    HtmlDoc doc = htmlToText(text0);
    title = doc.title;
    text = doc.text;
  } else {
    text = util::trim(text0);
  }
  if (util::trim(text).empty())
    return fail("页面里没有提取到正文（可能是纯前端渲染或缺内容）：" + url);

  const long long total = cpLength(text);
  const bool cut = total > maxChars;
  if (cut) {
    std::string out;
    CpWalker w(text);
    unsigned cp;
    long long n = 0;
    while (n < maxChars && w.next(&cp)) { appendUtf8(out, cp); n++; }
    text.swap(out);
  }

  std::string head = "链接：" + r.finalUrl;
  if (!title.empty()) head += "\n标题：" + title;
  if (charset != "utf-8") head += "\n编码：" + charset;
  std::string tail;
  if (cut)
    tail = "\n\n（正文共 " + std::to_string(total) + " 字，已截断到前 " + std::to_string(maxChars) +
           " 字；需要更多可提高 max_chars 或分段抓取）";
  return ok(head + "\n\n" + text + tail,
            {{"url", r.finalUrl}, {"title", title}, {"total", total}, {"truncated", cut}});
}

// ---------------------------------------------------------------------------
// web_search —— tools-core.cjs:1751
// ---------------------------------------------------------------------------
ToolResult webSearch(const json& a) {
  const std::string query = util::trim(sarg(a, "query"));
  if (query.empty()) return fail("缺少 query 参数。");
  long long count = iarg(a, "count", 8);
  count = std::min<long long>(20, std::max<long long>(1, count));

  struct Engine {
    const char* name;
    std::vector<json> (*fn)(const std::string&, int);
  };
  const Engine engines[] = {{"bing-rss", &searchBingRss},
                            {"bing-html", &searchBingHtml},
                            {"360", &search360}};

  std::vector<json> results;
  std::string used;
  std::vector<std::string> errors;
  for (const auto& e : engines) {
    try {
      auto rows = e.fn(query, (int)count);
      if (!rows.empty()) { results = std::move(rows); used = e.name; break; }
      errors.push_back(std::string(e.name) + " 无结果");
    } catch (const std::exception& ex) {
      errors.push_back(std::string(e.name) + " 失败：" + ex.what());
    }
  }
  if (results.empty()) {
    std::string why;
    for (size_t i = 0; i < errors.size(); i++) { if (i) why += "；"; why += errors[i]; }
    return fail("搜索「" + query + "」没有拿到结果（" + why +
                "）。可以换个关键词重试，或直接让用户提供网址。");
  }

  // 去重（去掉 #? 之后的片段）后按搜索引擎给出的顺序输出
  std::vector<json> list;
  std::vector<std::string> seen;
  for (const auto& r : results) {
    std::string key = r.value("url", std::string());
    const size_t cut = key.find_first_of("#?");
    if (cut != std::string::npos) key = key.substr(0, cut);
    if (std::find(seen.begin(), seen.end(), key) != seen.end()) continue;
    seen.push_back(key);
    list.push_back(r);
    if ((long long)list.size() >= count) break;
  }

  std::string body;
  for (size_t i = 0; i < list.size(); i++) {
    const std::string title = list[i].value("title", std::string());
    const std::string url = list[i].value("url", std::string());
    const std::string snip = list[i].value("snippet", std::string());
    const std::string date = list[i].value("date", std::string());
    body += std::to_string(i + 1) + ". " + title + "\n   " + url;
    if (!snip.empty()) body += "\n   " + snip;
    if (!date.empty()) body += "\n   时间：" + date;
    if (i + 1 < list.size()) body += "\n";
  }
  const std::string text = "搜索「" + query + "」共 " + std::to_string(list.size()) + " 条（来源 " +
                           used + "）：\n" + body +
                           "\n\n提示：需要原文细节时用 fetch_url 打开上面最相关的链接。";
  return ok(text, {{"query", query}, {"engine", used}, {"results", list}});
}

}  // namespace webtools
}  // namespace ds
