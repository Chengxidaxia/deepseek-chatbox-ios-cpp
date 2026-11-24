#pragma once
// 通用工具：对照 Web 版 public/js/util.js
#include <string>
#include <cstdint>
#include <random>
#include <sstream>
#include <iomanip>
#include <chrono>

namespace ds {
namespace util {

inline std::string nowIso() {
  auto t = std::chrono::system_clock::now();
  std::time_t tt = std::chrono::system_clock::to_time_t(t);
  std::tm tm{};
#ifdef _WIN32
  gmtime_s(&tm, &tt);
#else
  gmtime_r(&tt, &tm);
#endif
  std::ostringstream os;
  os << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
  return os.str();
}

inline int64_t nowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
    std::chrono::system_clock::now().time_since_epoch()).count();
}

/** UUID v4，对照 util.js 的 uuid()（crypto.randomUUID 带 fallback） */
inline std::string uuid() {
  static thread_local std::mt19937_64 rng(std::random_device{}());
  uint64_t a = rng(), b = rng();
  // 设置 version=4, variant=10xx
  a = (a & 0xFFFFFFFFFFFF0FFFULL) | 0x0000000000004000ULL;
  b = (b & 0x3FFFFFFFFFFFFFFFULL) | 0x8000000000000000ULL;
  char buf[37];
  snprintf(buf, sizeof(buf),
    "%08llx-%04llx-%04llx-%04llx-%012llx",
    (unsigned long long)(a >> 32),
    (unsigned long long)((a >> 16) & 0xFFFF),
    (unsigned long long)(a & 0xFFFF),
    (unsigned long long)(b >> 48),
    (unsigned long long)(b & 0xFFFFFFFFFFFFULL));
  return std::string(buf);
}

/** 短 id：对照 store.js 的 'c_' + Date.now().toString(36) + random */
inline std::string shortId(const std::string& prefix = "m") {
  static thread_local std::mt19937_64 rng(std::random_device{}());
  std::ostringstream os;
  os << prefix << '_' << std::hex << nowMs() << (rng() % 0xFFFFFF);
  return os.str();
}

/** token 粗估：对照 util.js estimateTokens —— CJK 1 token/字，其余 3.2 字符/token */
inline int estimateTokens(const std::string& text) {
  int tokens = 0;
  size_t i = 0;
  while (i < text.size()) {
    unsigned char c = (unsigned char)text[i];
    if (c < 0x80) { i += 1; tokens += 1; }
    else if ((c & 0xE0) == 0xC0) { i += 2; tokens += 1; }  // 2字节：多为 CJK 兼容区，按 1
    else if ((c & 0xF0) == 0xE0) { i += 3; tokens += 1; }  // 3字节：CJK 主体，1 token/字
    else { i += 4; tokens += 1; }
  }
  // 非 CJK 部分按 3.2 字符/token 修正：这里用近似——ASCII 占比高时压缩
  size_t ascii = 0;
  for (unsigned char c : text) if (c < 0x80) ascii++;
  int cjkTokens = tokens - (int)(ascii / 3.2 > 0 ? 0 : 0); // 占位，下面统一算
  (void)cjkTokens;
  // 精确重算：CJK 字符 1 token，ASCII 每 3.2 字符 1 token
  int cjk = 0;
  i = 0;
  while (i < text.size()) {
    unsigned char c = (unsigned char)text[i];
    if (c < 0x80) i += 1;
    else if ((c & 0xE0) == 0xC0) { i += 2; cjk++; }
    else if ((c & 0xF0) == 0xE0) { i += 3; cjk++; }
    else { i += 4; cjk++; }
  }
  ascii = 0;
  for (unsigned char c : text) if (c < 0x80) ascii++;
  return cjk + (int)(ascii / 3.2);
}

inline std::string base64Encode(const std::string& in) {
  static const char* tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  out.reserve((in.size() + 2) / 3 * 4);
  size_t i = 0;
  while (i + 3 <= in.size()) {
    uint32_t v = ((uint32_t)(unsigned char)in[i] << 16) | ((uint32_t)(unsigned char)in[i+1] << 8) | (unsigned char)in[i+2];
    out += tbl[(v >> 18) & 63]; out += tbl[(v >> 12) & 63];
    out += tbl[(v >> 6) & 63]; out += tbl[v & 63];
    i += 3;
  }
  size_t rem = in.size() - i;
  if (rem == 1) {
    uint32_t v = (uint32_t)(unsigned char)in[i] << 16;
    out += tbl[(v >> 18) & 63]; out += tbl[(v >> 12) & 63]; out += "==";
  } else if (rem == 2) {
    uint32_t v = ((uint32_t)(unsigned char)in[i] << 16) | ((uint32_t)(unsigned char)in[i+1] << 8);
    out += tbl[(v >> 18) & 63]; out += tbl[(v >> 12) & 63]; out += tbl[(v >> 6) & 63]; out += '=';
  }
  return out;
}

inline std::string base64Decode(const std::string& in) {
  auto val = [](char c) -> int {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
  };
  std::string out;
  size_t i = 0;
  while (i < in.size()) {
    int a = val(in[i]), b = (i+1 < in.size()) ? val(in[i+1]) : -1;
    int c = (i+2 < in.size()) ? val(in[i+2]) : -1, d = (i+3 < in.size()) ? val(in[i+3]) : -1;
    if (a < 0 || b < 0) break;
    out += (char)((a << 2) | (b >> 4));
    if (c >= 0) out += (char)((b << 4) | (c >> 2));
    if (d >= 0) out += (char)((c << 6) | d);
    i += 4;
  }
  return out;
}

inline std::string urlEncode(const std::string& s) {
  std::string out;
  static const char* hex = "0123456789ABCDEF";
  for (unsigned char c : s) {
    if (isalnum(c) || c=='-' || c=='_' || c=='.' || c=='~') out += c;
    else { out += '%'; out += hex[(c >> 4) & 15]; out += hex[c & 15]; }
  }
  return out;
}

inline std::string maskKey(const std::string& key) {
  if (key.size() <= 8) return "****";
  return key.substr(0, 4) + "****" + key.substr(key.size() - 4);
}

inline std::string trim(const std::string& s) {
  size_t a = s.find_first_not_of(" \t\r\n");
  if (a == std::string::npos) return "";
  size_t b = s.find_last_not_of(" \t\r\n");
  return s.substr(a, b - a + 1);
}

}  // namespace util
}  // namespace ds
