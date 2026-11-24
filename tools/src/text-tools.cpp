// P0 纯字符串类工具实现（对照 Web 版 server/tools-core.cjs）
// 设计约定：零外部依赖、纯标准库；输出文案与 Web 版保持中文一致。
#include "text-tools.hpp"
#include "util.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <iomanip>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace ds {
namespace texttools {
namespace {

using json = nlohmann::json;

// ------------------------------ 参数 / 结果 ------------------------------
std::string sarg(const json& a, const char* k, const std::string& def = "") {
  if (!a.contains(k) || a[k].is_null()) return def;
  if (a[k].is_string()) return a[k].get<std::string>();
  return a[k].dump();
}
double darg(const json& a, const char* k, double def = 0) {
  if (!a.contains(k) || a[k].is_null()) return def;
  if (a[k].is_number()) return a[k].get<double>();
  if (a[k].is_string()) { try { return std::stod(a[k].get<std::string>()); } catch (...) { return def; } }
  return def;
}
int iarg(const json& a, const char* k, int def = 0) { return (int)darg(a, k, def); }
bool barg(const json& a, const char* k, bool def = false) {
  if (!a.contains(k)) return def;
  if (a[k].is_boolean()) return a[k].get<bool>();
  return def;
}
ToolResult fail(const std::string& msg) { ToolResult r; r.ok = false; r.text = msg; return r; }
ToolResult ok(const std::string& text, json data = json::object()) {
  ToolResult r; r.ok = true; r.text = text; r.data = data.is_null() ? json::object() : data; return r;
}
std::string fx(double v, int prec) {
  if (!std::isfinite(v)) return "NaN";
  std::ostringstream os; os << std::fixed << std::setprecision(prec) << v;
  return os.str();
}

// ------------------------------ UTF-8 ------------------------------
// 解码一个码点；返回消耗字节数。非法序列返回 1 且 cp = U+FFFD。
size_t utf8Next(const std::string& s, size_t i, uint32_t* cp) {
  unsigned char c = (unsigned char)s[i];
  if (c < 0x80) { *cp = c; return 1; }
  size_t need; uint32_t v, min;
  if ((c & 0xE0) == 0xC0) { need = 1; v = c & 0x1Fu; min = 0x80; }
  else if ((c & 0xF0) == 0xE0) { need = 2; v = c & 0x0Fu; min = 0x800; }
  else if ((c & 0xF8) == 0xF0) { need = 3; v = c & 0x07u; min = 0x10000; }
  else { *cp = 0xFFFD; return 1; }
  if (i + need >= s.size()) { *cp = 0xFFFD; return 1; }
  for (size_t k = 1; k <= need; k++) {
    unsigned char cc = (unsigned char)s[i + k];
    if ((cc & 0xC0) != 0x80) { *cp = 0xFFFD; return 1; }
    v = (v << 6) | (cc & 0x3Fu);
  }
  if (v < min || v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) { *cp = 0xFFFD; return 1; }
  *cp = v; return need + 1;
}

void utf8Append(std::string& out, uint32_t cp) {
  if (cp < 0x80) out += (char)cp;
  else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
  else if (cp < 0x10000) {
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

// 有损解码（对齐 Node 的 Buffer.toString('utf8')），bad 返回替换字符个数
std::string utf8DecodeLossy(const std::string& bytes, int* bad = nullptr) {
  std::string out; int n = 0;
  for (size_t i = 0; i < bytes.size();) {
    uint32_t cp = 0; size_t adv = utf8Next(bytes, i, &cp);
    if (cp == 0xFFFD && adv == 1) n++;
    utf8Append(out, cp);
    i += adv;
  }
  if (bad) *bad = n;
  return out;
}

// 按 \r?\n 切行（保留尾部空行，与 JS split 行为一致）
std::vector<std::string> splitLines(const std::string& text) {
  std::vector<std::string> out; std::string cur;
  for (char c : text) {
    if (c == '\n') {
      if (!cur.empty() && cur.back() == '\r') cur.pop_back();
      out.push_back(cur); cur.clear();
    } else cur += c;
  }
  out.push_back(cur);
  return out;
}

// ------------------------------ 1. regex_test ------------------------------
// tools-core.cjs:2131
struct RegexPrep {
  std::string pattern;                    // 已把 (?<name>…) 降级成普通捕获组
  std::vector<std::pair<int, std::string>> names;  // 组序号 → 组名
};

RegexPrep prepPattern(const std::string& p) {
  RegexPrep out;
  out.pattern.reserve(p.size());
  int group = 0;
  for (size_t i = 0; i < p.size();) {
    char c = p[i];
    if (c == '\\' && i + 1 < p.size()) { out.pattern += p[i]; out.pattern += p[i + 1]; i += 2; continue; }
    if (c == '[') {  // 字符类整体照抄，避免把 [()] 里的括号当分组
      out.pattern += c; i++;
      if (i < p.size() && p[i] == '^') { out.pattern += p[i]; i++; }
      if (i < p.size() && p[i] == ']') { out.pattern += p[i]; i++; }
      while (i < p.size() && p[i] != ']') {
        if (p[i] == '\\' && i + 1 < p.size()) { out.pattern += p[i]; out.pattern += p[i + 1]; i += 2; continue; }
        out.pattern += p[i]; i++;
      }
      if (i < p.size()) { out.pattern += ']'; i++; }
      continue;
    }
    if (c == '(') {
      // (?<= / (?<! 后行断言：原样保留
      if (i + 3 < p.size() && p[i + 1] == '?' && p[i + 2] == '<' && (p[i + 3] == '=' || p[i + 3] == '!')) {
        out.pattern += c; i++; continue;
      }
      // 命名组 (?<name>…) / (?P<name>…)：降级为普通捕获组并记名
      size_t nameStart = 0;
      if (i + 2 < p.size() && p[i + 1] == '?' && p[i + 2] == '<') nameStart = i + 3;
      else if (i + 3 < p.size() && p[i + 1] == '?' && p[i + 2] == 'P' && p[i + 3] == '<') nameStart = i + 4;
      if (nameStart) {
        size_t close = p.find('>', nameStart);
        if (close != std::string::npos) {
          group++;
          out.names.push_back({group, p.substr(nameStart, close - nameStart)});
          out.pattern += '(';
          i = close + 1;
          continue;
        }
      }
      if (i + 1 < p.size() && p[i + 1] == '?') { out.pattern += c; i++; continue; }  // (?: (?= (?! 等
      group++;
      out.pattern += c; i++;
      continue;
    }
    out.pattern += c; i++;
  }
  return out;
}

}  // namespace

ToolResult regexTest(const json& a) {
  std::string pattern = sarg(a, "pattern");
  std::string flags = sarg(a, "flags", "g");
  std::string text = sarg(a, "text");
  if (pattern.empty()) return fail("缺少 pattern 参数。");
  if (text.size() > 100000) return fail("文本过长（最多 10 万字符），请先截取。");

  std::regex_constants::syntax_option_type opt = std::regex_constants::ECMAScript;
  if (flags.find('i') != std::string::npos) opt |= std::regex_constants::icase;
  if (flags.find('m') != std::string::npos) opt |= std::regex_constants::multiline;

  RegexPrep prep = prepPattern(pattern);
  std::regex re;
  try {
    re = std::regex(prep.pattern, opt);
  } catch (const std::regex_error& e) {
    return fail("正则表达式错误：" + std::string(e.what()) + "（模式 " + pattern + "）");
  } catch (const std::exception& e) {
    return fail("正则表达式错误：" + std::string(e.what()));
  }

  int limit = iarg(a, "limit", 20);
  if (limit == 0) limit = 20;
  limit = std::min(100, std::max(1, limit));

  auto started = std::chrono::steady_clock::now();
  json rows = json::array();
  std::string body;
  int count = 0;
  for (auto it = std::sregex_iterator(text.begin(), text.end(), re);
       it != std::sregex_iterator() && count < limit; ++it) {
    const std::smatch& m = *it;
    count++;
    json named = json::object();
    json numbered = json::array();
    for (int g = 1; g < (int)m.size(); g++) {
      bool captured = m[g].matched;
      std::string val = captured ? m[g].str() : "";
      numbered.push_back(captured ? json(val) : json(""));
      for (const auto& n : prep.names) if (n.first == g) named[n.second] = val;
    }
    std::string idx = std::to_string((long long)m.position(0));
    body += std::to_string(count) + ". 「" + m[0].str() + "」 @" + idx;
    json row = {{"match", m[0].str()}, {"index", (long long)m.position(0)}};
    if (!named.empty()) {
      body += "\n   分组：" + named.dump();
      row["groups"] = named;
    } else if (!numbered.empty()) {
      body += "\n   分组：" + numbered.dump();
    }
    if (!numbered.empty()) row["captures"] = numbered;
    rows.push_back(row);
  }
  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - started).count();

  std::string head = "匹配 " + std::to_string(count) + " 条" +
      (count >= limit ? "（已到上限 " + std::to_string(limit) + "）" : "") +
      "，耗时 " + std::to_string((long long)ms) + "ms：";
  std::string text2 = head + "\n" + (body.empty() ? "（没有匹配）" : body);
  return ok(text2, {{"matches", rows}, {"count", count}});
}

namespace {

// ------------------------------ 2. csv_json ------------------------------
// tools-core.cjs:2182
std::vector<std::vector<std::string>> parseCsv(const std::string& s, char delim) {
  std::vector<std::vector<std::string>> rows;
  std::vector<std::string> row;
  std::string cell;
  bool quoted = false;
  for (size_t i = 0; i < s.size(); i++) {
    char c = s[i];
    if (quoted) {
      if (c == '"' && i + 1 < s.size() && s[i + 1] == '"') { cell += '"'; i++; }
      else if (c == '"') quoted = false;
      else cell += c;
    } else if (c == '"') quoted = true;
    else if (c == delim) { row.push_back(cell); cell.clear(); }
    else if (c == '\n') { row.push_back(cell); rows.push_back(row); row.clear(); cell.clear(); }
    else if (c != '\r') cell += c;
  }
  if (!cell.empty() || !row.empty()) { row.push_back(cell); rows.push_back(row); }

  std::vector<std::vector<std::string>> out;
  for (auto& r : rows) {
    bool any = false;
    for (auto& x : r) if (!x.empty()) { any = true; break; }
    if (any) out.push_back(r);
  }
  return out;
}

std::string csvCell(const json& v) {
  if (v.is_null()) return "";
  if (v.is_string()) return v.get<std::string>();
  if (v.is_boolean()) return v.get<bool>() ? "true" : "false";
  return v.dump();
}

std::string csvEscape(const std::string& s, char delim) {
  bool need = s.find('"') != std::string::npos || s.find('\r') != std::string::npos ||
              s.find('\n') != std::string::npos || s.find(delim) != std::string::npos;
  if (!need) return s;
  std::string out = "\"";
  for (char c : s) { if (c == '"') out += "\"\""; else out += c; }
  out += '"';
  return out;
}

}  // namespace

ToolResult csvJson(const json& a) {
  std::string mode = sarg(a, "mode");
  std::transform(mode.begin(), mode.end(), mode.begin(), [](unsigned char c) { return (char)std::tolower(c); });
  std::string dstr = sarg(a, "delimiter", ",");
  char delim = dstr.empty() ? ',' : dstr[0];
  std::string raw = util::trim(sarg(a, "text"));
  if (raw.empty()) return fail("缺少 text 参数。");

  if (mode == "tojson") {
    auto rows = parseCsv(raw, delim);
    if (rows.size() < 2) return fail("CSV 至少需要表头 + 一行数据。");
    const auto& head = rows[0];
    // 手工拼 JSON，保留列顺序（nlohmann 的 object 会按 key 排序，与 Web 版不一致）
    std::string out = "[\n";
    for (size_t r = 1; r < rows.size(); r++) {
      out += "  {\n";
      for (size_t c = 0; c < head.size(); c++) {
        std::string v = c < rows[r].size() ? rows[r][c] : "";
        out += "    " + json(head[c]).dump() + ": " + json(v).dump();
        if (c + 1 < head.size()) out += ",";
        out += "\n";
      }
      out += "  }";
      if (r + 1 < rows.size()) out += ",";
      out += "\n";
    }
    out += "]";
    return ok(out, {{"rows", (int)rows.size() - 1}, {"columns", (int)head.size()}});
  }

  if (mode == "tocsv") {
    json obj;
    try { obj = json::parse(raw); }
    catch (const std::exception& e) { return fail(std::string("JSON 解析失败：") + e.what()); }
    if (!obj.is_array() || obj.empty()) return fail("需要非空 JSON 数组。");
    std::vector<std::string> keys;
    std::set<std::string> seen;
    for (const auto& o : obj) {
      if (!o.is_object()) continue;
      for (auto it = o.begin(); it != o.end(); ++it)
        if (seen.insert(it.key()).second) keys.push_back(it.key());
    }
    if (keys.empty()) return fail("数组里没有对象，无法确定表头。");
    std::string head;
    for (size_t i = 0; i < keys.size(); i++) {
      if (i) head += delim;
      head += csvEscape(keys[i], delim);
    }
    std::string out = head;
    for (const auto& o : obj) {
      out += "\r\n";
      for (size_t i = 0; i < keys.size(); i++) {
        if (i) out += delim;
        std::string cell = o.is_object() && o.contains(keys[i]) ? csvCell(o[keys[i]]) : "";
        out += csvEscape(cell, delim);
      }
    }
    return ok(out, {{"rows", (int)obj.size()}, {"columns", (int)keys.size()}});
  }
  return fail("mode 只能是 toJson 或 toCsv。");
}

namespace {

// ------------------------------ 3. slugify ------------------------------
// tools-core.cjs:2238
bool isCjkPunct(uint32_t cp) {
  return (cp >= 0x2000 && cp <= 0x206F) ||   // 通用标点（含 ‘’“”—…）
         (cp >= 0x3000 && cp <= 0x303F) ||   // 中日韩标点（、。《》【】等）
         (cp >= 0xFF00 && cp <= 0xFF65) ||   // 全角形式（，！？；：（）等）
         cp == 0x00B7 || cp == 0x2014;
}

}  // namespace

ToolResult slugify(const json& a) {
  std::string raw = util::trim(sarg(a, "text"));
  if (raw.empty()) return fail("缺少 text 参数。");
  std::string sep = sarg(a, "separator", "-");
  if (sep.empty()) sep = "-";
  if (sep.size() > 3) sep = sep.substr(0, 3);
  bool lower = barg(a, "lower", true);

  // 先按 Web 版去掉引号（不产生连接符），再逐码点判定
  std::string src;
  for (size_t i = 0; i < raw.size();) {
    uint32_t cp = 0; size_t adv = utf8Next(raw, i, &cp);
    if (cp == '\'' || cp == '"' || cp == 0x2018 || cp == 0x2019 || cp == 0x201C || cp == 0x201D) { i += adv; continue; }
    src.append(raw, i, adv);
    i += adv;
  }

  std::string out;
  bool pendingSep = false;
  for (size_t i = 0; i < src.size();) {
    uint32_t cp = 0; size_t adv = utf8Next(src, i, &cp);
    bool keep;
    if (cp < 0x80) keep = std::isalnum((int)cp) != 0;
    else keep = !isCjkPunct(cp);
    if (keep) {
      if (pendingSep && !out.empty()) out += sep;
      pendingSep = false;
      out.append(src, i, adv);
    } else {
      pendingSep = true;
    }
    i += adv;
  }
  if (lower) std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) { return (char)std::tolower(c); });
  if (out.empty()) out = sep;
  return ok(out, {{"slug", out}});
}

namespace {

// ------------------------------ 4. id_validator ------------------------------
// tools-core.cjs:2288
bool isLeap(int y) { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0; }

bool validDate(int y, int m, int d) {
  static const int DIM[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  if (y < 1900 || y > 2100 || m < 1 || m > 12 || d < 1) return false;
  int max = DIM[m - 1];
  if (m == 2 && isLeap(y)) max = 29;
  return d <= max;
}

bool allDigits(const std::string& s) {
  if (s.empty()) return false;
  for (unsigned char c : s) if (!std::isdigit(c)) return false;
  return true;
}

std::string lowerAscii(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
  return s;
}

}  // namespace

ToolResult idValidator(const json& a) {
  std::string type = lowerAscii(sarg(a, "type"));
  std::string value = util::trim(sarg(a, "value"));
  if (value.empty()) return fail("缺少 value 参数。");
  bool valid = false;
  std::string detail;

  if (type == "idcard") {
    bool shape = value.size() == 18 && allDigits(value.substr(0, 17)) &&
                 (std::isdigit((unsigned char)value[17]) || value[17] == 'X' || value[17] == 'x');
    if (!shape) {
      detail = "格式应为 17 位数字 + 校验位";
    } else {
      static const int W[17] = {7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2};
      static const char* CODES = "10X98765432";
      int sum = 0;
      for (int i = 0; i < 17; i++) sum += (value[i] - '0') * W[i];
      char check = CODES[sum % 11];
      char last = (char)std::toupper((unsigned char)value[17]);
      valid = last == check;
      detail = valid ? "校验位正确"
                     : std::string("校验位应为 ") + check + "（实际 " + std::string(1, value[17]) + "）";
      int y = std::stoi(value.substr(6, 4));
      int m = std::stoi(value.substr(10, 2));
      int d = std::stoi(value.substr(12, 2));
      if (!validDate(y, m, d)) { valid = false; detail += "；出生日期无效"; }
    }
  } else if (type == "email") {
    static const std::regex re(R"(^[^\s@]+@[^\s@]+\.[^\s@]{2,}$)");
    valid = std::regex_match(value, re);
    detail = valid ? "邮箱格式正确" : "邮箱格式不正确";
  } else if (type == "phone") {
    static const std::regex re(R"(^1[3-9]\d{9}$)");
    valid = std::regex_match(value, re);
    detail = valid ? "中国大陆手机号格式正确" : "不是合法的中国大陆手机号";
  } else if (type == "ipv4") {
    std::vector<std::string> parts;
    std::string cur;
    for (char c : value) { if (c == '.') { parts.push_back(cur); cur.clear(); } else cur += c; }
    parts.push_back(cur);
    valid = parts.size() == 4;
    if (valid) {
      for (const auto& p : parts) {
        if (p.empty() || p.size() > 3 || !allDigits(p)) { valid = false; break; }
        if (std::stoi(p) > 255) { valid = false; break; }
      }
    }
    detail = valid ? "IPv4 格式正确" : "不是合法的 IPv4 地址";
  } else if (type == "uuid") {
    static const std::regex re(
        R"(^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$)");
    valid = std::regex_match(value, re);
    detail = valid ? "UUID 格式正确" : "不是合法的 UUID（v1-v5）";
  } else {
    return fail("type 只能是 idcard / email / phone / ipv4 / uuid。");
  }

  std::string text = value + "：" + (valid ? "合法" : "不合法") + "（" + detail + "）";
  return ok(text, {{"type", type}, {"value", value}, {"valid", valid}, {"detail", detail}});
}

namespace {

// ------------------------------ 5. hex_view ------------------------------
// tools-core.cjs:2561
std::string hexByte(unsigned char b) {
  static const char* T = "0123456789abcdef";
  std::string s;
  s += T[(b >> 4) & 15];
  s += T[b & 15];
  return s;
}

}  // namespace

ToolResult hexView(const json& a) {
  std::string mode = lowerAscii(sarg(a, "mode"));
  std::string raw = sarg(a, "text");
  if (raw.empty()) return fail("缺少 text 参数。");

  if (mode == "tohex") {
    int per = 16;
    if (a.contains("bytes_per_line") && a["bytes_per_line"].is_number() &&
        (int)darg(a, "bytes_per_line") == 0) per = 0;
    else per = std::min(64, std::max(1, iarg(a, "bytes_per_line", 16)));

    std::string fullHex;
    for (unsigned char c : raw) fullHex += hexByte(c);

    std::string out;
    if (per == 0) {
      // 不分行：单行空格分隔的 hex
      for (size_t i = 0; i < raw.size(); i++) {
        if (i) out += ' ';
        out += hexByte((unsigned char)raw[i]);
      }
    } else {
      size_t n = raw.size();
      for (size_t off = 0; off < n; off += (size_t)per) {
        size_t len = std::min((size_t)per, n - off);
        std::string hex, asc;
        for (size_t k = 0; k < len; k++) {
          unsigned char b = (unsigned char)raw[off + k];
          if (k) hex += ' ';
          hex += hexByte(b);
          asc += (b >= 0x20 && b < 0x7f) ? (char)b : '.';
        }
        // hex 右补空格到 per*3-1 列，保证 ASCII 侧栏对齐
        size_t width = (size_t)per * 3 - 1;
        if (hex.size() < width) hex.append(width - hex.size(), ' ');
        char offbuf[16];
        std::snprintf(offbuf, sizeof(offbuf), "%08llx", (unsigned long long)off);
        out += std::string(offbuf) + "  " + hex + "  |" + asc + "|";
        if (off + len < n) out += "\n";
      }
    }
    if (out.empty()) out = "（空）";
    return ok(out, {{"bytes", (int)raw.size()}, {"hex", fullHex}});
  }

  if (mode == "fromhex") {
    std::string clean;
    for (size_t i = 0; i < raw.size();) {
      char c = raw[i];
      if (c == '0' && i + 1 < raw.size() && (raw[i + 1] == 'x' || raw[i + 1] == 'X')) { i += 2; continue; }
      if (c == '\\' && i + 1 < raw.size() && (raw[i + 1] == 'x' || raw[i + 1] == 'X')) { i += 2; continue; }
      if (std::isspace((unsigned char)c) || c == ',' || c == ';' || c == ':' || c == '|') { i++; continue; }
      clean += c; i++;
    }
    for (unsigned char c : clean) {
      if (!std::isxdigit(c)) return fail("含有非十六进制字符，请检查输入（只允许 0-9 a-f 和分隔符）。");
    }
    if (clean.size() % 2) {
      return fail("十六进制长度为奇数（" + std::to_string(clean.size()) + " 位），可能少了半字节。");
    }
    std::string bytes;
    bytes.reserve(clean.size() / 2);
    for (size_t i = 0; i + 1 < clean.size(); i += 2) {
      auto hv = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        return std::tolower((unsigned char)c) - 'a' + 10;
      };
      bytes += (char)((hv(clean[i]) << 4) | hv(clean[i + 1]));
    }
    int bad = 0;
    std::string text = utf8DecodeLossy(bytes, &bad);
    if (bad) {
      std::string b64 = util::base64Encode(bytes);
      if (b64.size() > 60) b64 = b64.substr(0, 60) + "…";
      text += "\n（含 " + std::to_string(bad) + " 个无法按 UTF-8 解码的字节，可能是二进制或 GBK 编码；原文另存为 base64：" +
              b64 + "）";
    }
    return ok(text, {{"bytes", (int)bytes.size()}, {"base64", util::base64Encode(bytes)}, {"utf8Errors", bad}});
  }
  return fail("mode 只能是 toHex 或 fromHex。");
}

namespace {

// ------------------------------ 6. color_convert ------------------------------
// tools-core.cjs:2591
struct Rgb { double r = 0, g = 0, b = 0, alpha = 1; };

std::string lowerTrim(const std::string& s) { return lowerAscii(util::trim(s)); }

bool parseColor(const std::string& input, Rgb* out) {
  std::string s = util::trim(input);
  if (s.empty()) return false;

  // #RGB / #RRGGBB（可省略 #）
  {
    std::string h = s;
    if (!h.empty() && h[0] == '#') h = h.substr(1);
    if (h.size() == 3 || h.size() == 6) {
      bool hexOnly = true;
      for (unsigned char c : h) if (!std::isxdigit(c)) { hexOnly = false; break; }
      if (hexOnly) {
        if (h.size() == 3) { std::string e; for (char c : h) { e += c; e += c; } h = e; }
        out->r = std::stoi(h.substr(0, 2), nullptr, 16);
        out->g = std::stoi(h.substr(2, 2), nullptr, 16);
        out->b = std::stoi(h.substr(4, 2), nullptr, 16);
        out->alpha = 1;
        return true;
      }
    }
  }

  std::string ls = lowerTrim(s);
  auto inside = [&](const char* fn) -> std::string {
    std::string pre = std::string(fn) + "(";
    if (ls.rfind(pre, 0) != 0) return "";
    size_t close = ls.rfind(')');
    if (close == std::string::npos || close < pre.size()) return "";
    return ls.substr(pre.size(), close - pre.size());
  };
  auto splitNums = [](const std::string& body) {
    std::vector<std::string> parts;
    std::string cur;
    for (char c : body) {
      if (c == ' ' || c == ',' || c == '/') { if (!cur.empty()) { parts.push_back(cur); cur.clear(); } }
      else cur += c;
    }
    if (!cur.empty()) parts.push_back(cur);
    return parts;
  };

  std::string body = inside("rgba");
  if (body.empty()) body = inside("rgb");
  if (!body.empty()) {
    auto p = splitNums(body);
    if (p.size() >= 3) {
      try {
        double r = std::stod(p[0]), g = std::stod(p[1]), b = std::stod(p[2]);
        double al = p.size() >= 4 ? std::stod(p[3]) : 1;
        *out = {r, g, b, al};
        return true;
      } catch (...) { return false; }
    }
    return false;
  }

  body = inside("hsla");
  if (body.empty()) body = inside("hsl");
  if (!body.empty()) {
    auto p = splitNums(body);
    if (p.size() >= 3) {
      try {
        double h = std::stod(p[0]);
        double sat = std::stod(p[1]) / 100.0;
        double li = std::stod(p[2]) / 100.0;
        double al = p.size() >= 4 ? std::stod(p[3]) : 1;
        auto k = [&](double n) { return std::fmod(n + h / 30.0, 12.0); };
        double a = sat * std::min(li, 1 - li);
        auto f = [&](double n) {
          double kk = k(n);
          return li - a * std::max(-1.0, std::min(kk - 3, std::min(9 - kk, 1.0)));
        };
        out->r = std::round(f(0) * 255);
        out->g = std::round(f(8) * 255);
        out->b = std::round(f(4) * 255);
        out->alpha = al;
        return true;
      } catch (...) { return false; }
    }
    return false;
  }

  static const std::map<std::string, std::string> NAMED = {
      {"red", "#f00"},     {"green", "#008000"}, {"blue", "#00f"},   {"black", "#000"},
      {"white", "#fff"},   {"gray", "#808080"},  {"grey", "#808080"}, {"orange", "#ffa500"},
      {"yellow", "#ff0"},  {"purple", "#800080"}, {"pink", "#ffc0cb"}};
  auto it = NAMED.find(ls);
  if (it != NAMED.end()) return parseColor(it->second, out);
  return false;
}

int clamp255(double v) { return (int)std::max(0.0, std::min(255.0, std::round(v))); }

std::string hexOf(const Rgb& c) {
  static const char* T = "0123456789ABCDEF";
  int v[3] = {clamp255(c.r), clamp255(c.g), clamp255(c.b)};
  std::string out = "#";
  for (int i = 0; i < 3; i++) { out += T[(v[i] >> 4) & 15]; out += T[v[i] & 15]; }
  return out;
}

double luminance(const Rgb& c) {
  auto f = [](double v) {
    double x = v / 255.0;
    return x <= 0.03928 ? x / 12.92 : std::pow((x + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contrastRatio(const Rgb& a, const Rgb& b) {
  double l1 = luminance(a), l2 = luminance(b);
  return (std::max(l1, l2) + 0.05) / (std::min(l1, l2) + 0.05);
}

}  // namespace

ToolResult colorConvert(const json& a) {
  Rgb c;
  if (!parseColor(sarg(a, "color"), &c)) {
    return fail("无法识别颜色。支持 #RGB、#RRGGBB、rgb(r,g,b)、hsl(h,s%,l%) 以及少量英文色名。");
  }
  double rr = c.r / 255.0, gg = c.g / 255.0, bb = c.b / 255.0;
  double mx = std::max({rr, gg, bb}), mn = std::min({rr, gg, bb});
  double d = mx - mn;
  double hh = 0;
  if (d != 0) {
    if (mx == rr) hh = (gg - bb) / d + (gg < bb ? 6 : 0);
    else if (mx == gg) hh = (bb - rr) / d + 2;
    else hh = (rr - gg) / d + 4;
    hh /= 6;
  }
  double l = (mx + mn) / 2;
  double sat = 0;
  if (mx != mn) sat = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  int hHsl = (int)std::lround(hh * 360), hSat = (int)std::lround(sat * 100), hL = (int)std::lround(l * 100);

  int hHsv = (int)std::lround(hh * 360);
  int sHsv = (int)std::lround((mx == 0 ? 0 : d / mx) * 100);
  int vHsv = (int)std::lround(mx * 100);

  double L = luminance(c);
  Rgb white{255, 255, 255, 1}, black{0, 0, 0, 1};
  double cw = contrastRatio(c, white), cb = contrastRatio(c, black);
  double yiq = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / 255.0;

  std::string text;
  text += "HEX " + hexOf(c) + "\n";
  text += "RGB rgb(" + std::to_string(clamp255(c.r)) + ", " + std::to_string(clamp255(c.g)) + ", " +
          std::to_string(clamp255(c.b)) + ")\n";
  text += "HSL hsl(" + std::to_string(hHsl) + ", " + std::to_string(hSat) + "%, " + std::to_string(hL) + "%)\n";
  text += "HSV hsv(" + std::to_string(hHsv) + ", " + std::to_string(sHsv) + "%, " + std::to_string(vHsv) + "%)\n";
  text += "相对亮度 " + fx(L, 4) + "\n";
  text += "对比度 对白 " + fx(cw, 2) + ":1　对黑 " + fx(cb, 2) + ":1\n";
  text += "明度(YIQ) " + std::to_string((int)std::lround(yiq * 100)) + "%　当这个颜色做底色时，建议用" +
          (yiq > 0.5 ? "黑色" : "白色") + "文字\n";
  text += std::string("WCAG 正文(4.5:1) 把它当文字色：白底") + (cw >= 4.5 ? "通过" : "不通过") + " / 黑底" +
          (cb >= 4.5 ? "通过" : "不通过");

  json data = {
      {"hex", hexOf(c)},
      {"rgb", json::array({clamp255(c.r), clamp255(c.g), clamp255(c.b)})},
      {"hsl", {{"h", hHsl}, {"s", hSat}, {"l", hL}}},
      {"hsv", {{"h", hHsv}, {"s", sHsv}, {"v", vHsv}}},
      {"luminance", std::round(L * 10000) / 10000},
      {"contrastWhite", std::round(cw * 100) / 100},
      {"contrastBlack", std::round(cb * 100) / 100},
      {"isDark", yiq <= 0.5},
      {"suggestedTextColor", yiq > 0.5 ? "#000000" : "#FFFFFF"},
      {"yiq", (int)std::lround(yiq * 100)},
  };

  std::string bgArg = sarg(a, "background");
  if (!bgArg.empty()) {
    Rgb bg;
    if (!parseColor(bgArg, &bg)) return fail("背景色无法识别。");
    double cc = contrastRatio(c, bg);
    text += "\n与背景 " + hexOf(bg) + " 的对比度 " + fx(cc, 2) + ":1　正文 AA " + (cc >= 4.5 ? "通过" : "不通过") +
            "　AAA " + (cc >= 7 ? "通过" : "不通过");
    data["contrastWithBackground"] = std::round(cc * 100) / 100;
  }
  return ok(text, data);
}

namespace {

// ------------------------------ 7. text_kit ------------------------------
// tools-core.cjs:2693
bool isAsciiUpper(uint32_t c) { return c >= 'A' && c <= 'Z'; }
bool isAsciiLower(uint32_t c) { return c >= 'a' && c <= 'z'; }
bool isAsciiDigit(uint32_t c) { return c >= '0' && c <= '9'; }

// 对应 JS 的 ([A-Z]+)([A-Z][a-z]) + ([a-z0-9])([A-Z]) + [^\p{L}\p{N}]+ → 空格
std::vector<std::string> splitWords(const std::string& s) {
  std::vector<uint32_t> cps;
  for (size_t i = 0; i < s.size();) {
    uint32_t cp = 0; size_t adv = utf8Next(s, i, &cp);
    cps.push_back(cp);
    i += adv;
  }
  std::string t;
  for (size_t i = 0; i < cps.size(); i++) {
    uint32_t c = cps[i];
    bool word = c < 0x80 ? (std::isalnum((int)c) != 0) : !isCjkPunct(c);
    if (!word) { t += ' '; continue; }
    if (i > 0 && isAsciiUpper(c)) {
      uint32_t p = cps[i - 1];
      if (isAsciiUpper(p) && i + 1 < cps.size() && isAsciiLower(cps[i + 1])) t += ' ';
      else if (isAsciiLower(p) || isAsciiDigit(p)) t += ' ';
    }
    utf8Append(t, c);
  }
  std::vector<std::string> out;
  std::string cur;
  for (char c : t) {
    if (c == ' ' || c == '\t') { if (!cur.empty()) { out.push_back(cur); cur.clear(); } }
    else cur += c;
  }
  if (!cur.empty()) out.push_back(cur);
  return out;
}

std::string capFirst(std::string w) {
  if (!w.empty()) {
    unsigned char c = (unsigned char)w[0];
    if (c < 0x80) w[0] = (char)std::toupper(c);
  }
  return w;
}

std::string toUpperAscii(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::toupper(c); });
  return s;
}
std::string toLowerAscii(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
  return s;
}

bool numericValue(const std::string& raw, double* out) {
  std::string s = util::trim(raw);
  std::string clean;
  for (char c : s) if (c != ',') clean += c;
  if (clean.empty()) return false;
  try {
    size_t used = 0;
    double v = std::stod(clean, &used);
    if (used != clean.size()) return false;
    *out = v;
    return true;
  } catch (...) { return false; }
}

std::string collapseSpaces(const std::string& s) {
  std::string out;
  bool prevSpace = false;
  for (char c : s) {
    bool isSp = (c == ' ' || c == '\t');
    if (isSp) { if (!prevSpace) out += ' '; }
    else out += c;
    prevSpace = isSp;
  }
  return out;
}

std::string joinLines(const std::vector<std::string>& v) {
  std::string out;
  for (size_t i = 0; i < v.size(); i++) { if (i) out += '\n'; out += v[i]; }
  return out;
}

}  // namespace

ToolResult textKit(const json& a) {
  std::string action = lowerAscii(sarg(a, "action"));
  std::string text = sarg(a, "text");
  if (text.empty()) return fail("缺少 text 参数。");
  auto lines = splitLines(text);
  bool ic = barg(a, "ignore_case");

  if (action == "dedupe") {
    std::set<std::string> seen;
    std::vector<std::string> out;
    int nonEmpty = 0;
    for (const auto& line : lines) {
      std::string key = util::trim(line);
      if (key.empty()) continue;
      nonEmpty++;
      if (ic) key = toLowerAscii(key);
      if (!seen.insert(key).second) continue;
      out.push_back(line);
    }
    return ok(joinLines(out), {{"before", nonEmpty}, {"after", (int)out.size()},
                               {"removed", nonEmpty - (int)out.size()}});
  }

  if (action == "sort") {
    std::vector<std::string> rows;
    for (const auto& l : lines) if (!util::trim(l).empty()) rows.push_back(l);
    bool numeric = barg(a, "numeric");
    std::stable_sort(rows.begin(), rows.end(), [&](const std::string& x, const std::string& y) {
      if (numeric) {
        double nx = 0, ny = 0;
        bool okx = numericValue(x, &nx), oky = numericValue(y, &ny);
        if (okx && oky) return nx < ny;
        if (okx) return true;
        if (oky) return false;
      }
      std::string kx = ic ? toLowerAscii(x) : x;
      std::string ky = ic ? toLowerAscii(y) : y;
      return kx < ky;
    });
    if (barg(a, "desc")) std::reverse(rows.begin(), rows.end());
    return ok(joinLines(rows), {{"count", (int)rows.size()}});
  }

  if (action == "trim") {
    std::vector<std::string> out;
    for (const auto& l : lines) {
      std::string t = collapseSpaces(util::trim(l));
      if (!t.empty()) out.push_back(t);
    }
    return ok(joinLines(out), {{"before", (int)lines.size()}, {"after", (int)out.size()},
                               {"removed", (int)lines.size() - (int)out.size()}});
  }

  if (action == "wrap") {
    std::string pre = sarg(a, "prefix"), suf = sarg(a, "suffix");
    std::vector<std::string> out;
    for (const auto& l : lines) out.push_back(pre + l + suf);
    return ok(joinLines(out), {{"count", (int)out.size()}});
  }

  if (action == "split") {
    std::string d = sarg(a, "delimiter");
    std::vector<std::string> parts;
    if (d.empty()) {
      parts = lines;
    } else {
      size_t pos = 0;
      while (true) {
        size_t hit = text.find(d, pos);
        if (hit == std::string::npos) { parts.push_back(text.substr(pos)); break; }
        parts.push_back(text.substr(pos, hit - pos));
        pos = hit + d.size();
      }
    }
    std::vector<std::string> out;
    for (size_t i = 0; i < parts.size(); i++) {
      std::string t = util::trim(parts[i]);
      if (t.empty()) continue;
      out.push_back(std::to_string(i + 1) + ". " + t);
    }
    return ok(joinLines(out), {{"count", (int)out.size()}, {"delimiter", d.empty() ? "换行" : d}});
  }

  if (action == "case") {
    std::string type = lowerAscii(sarg(a, "case_type", "camel"));
    std::vector<std::string> out;
    for (const auto& l : lines) {
      std::string t = util::trim(l);
      if (t.empty()) { out.push_back(l); continue; }
      if (type == "upper") { out.push_back(toUpperAscii(t)); continue; }
      if (type == "lower") { out.push_back(toLowerAscii(t)); continue; }
      auto ws = splitWords(t);
      if (ws.empty()) { out.push_back(t); continue; }
      std::string r;
      if (type == "camel") {
        r = toLowerAscii(ws[0]);
        for (size_t i = 1; i < ws.size(); i++) r += capFirst(ws[i]);
      } else if (type == "pascal") {
        for (const auto& w : ws) r += capFirst(w);
      } else if (type == "snake") {
        for (size_t i = 0; i < ws.size(); i++) { if (i) r += '_'; r += toLowerAscii(ws[i]); }
      } else if (type == "kebab") {
        for (size_t i = 0; i < ws.size(); i++) { if (i) r += '-'; r += toLowerAscii(ws[i]); }
      } else if (type == "const") {
        for (size_t i = 0; i < ws.size(); i++) { if (i) r += '_'; r += toUpperAscii(ws[i]); }
      } else if (type == "title") {
        for (size_t i = 0; i < ws.size(); i++) { if (i) r += ' '; r += capFirst(ws[i]); }
      } else {
        r = t;
      }
      out.push_back(r);
    }
    return ok(joinLines(out), {{"type", type}, {"count", (int)out.size()}});
  }

  return fail("action 只支持 dedupe / sort / trim / wrap / split / case。");
}

}  // namespace texttools
}  // namespace ds
