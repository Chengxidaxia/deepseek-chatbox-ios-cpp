// aes_crypto：AES-128/192/256 的 CBC / GCM / ECB，OpenSSL EVP 实现。
// 对照 Web 版 tools-core.cjs:2783（Web 走 Web Crypto），参数名与输出文案保持一致。
#include "crypto-tools.hpp"
#include "util.hpp"

#include <openssl/evp.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

namespace ds {
namespace cryptotools {
namespace {

using json = nlohmann::json;

// ------------------------------ 参数 / 结果 ------------------------------
std::string sarg(const json& a, const char* k, const std::string& def = "") {
  if (!a.contains(k) || a[k].is_null()) return def;
  if (a[k].is_string()) return a[k].get<std::string>();
  return a[k].dump();
}
ToolResult fail(const std::string& msg) { ToolResult r; r.ok = false; r.text = msg; return r; }
ToolResult ok(const std::string& text, json data = json::object()) {
  ToolResult r; r.ok = true; r.text = text; r.data = data.is_null() ? json::object() : data; return r;
}
std::string lowerAscii(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
  return s;
}

// ------------------------------ 编码 ------------------------------
int hexVal(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  return std::tolower((unsigned char)c) - 'a' + 10;
}

bool decodeBytes(const std::string& raw, const std::string& enc,
                 std::vector<unsigned char>* out, std::string* err) {
  out->clear();
  if (enc == "hex") {
    // 与 Web 版一致：先去掉 0x 前缀、空白和冒号
    std::string clean;
    for (size_t i = 0; i < raw.size();) {
      char c = raw[i];
      if (c == '0' && i + 1 < raw.size() && (raw[i + 1] == 'x' || raw[i + 1] == 'X')) { i += 2; continue; }
      if (std::isspace((unsigned char)c) || c == ':') { i++; continue; }
      clean += c; i++;
    }
    // 比 Web 版多一道校验：Node 的 Buffer.from(s,'hex') 遇到奇数长度/非法字符会静默截断，
    // 这里直接报错，避免用户拿到半截密钥却看不出问题。
    if (clean.size() % 2) { *err = "hex 长度为奇数（" + std::to_string(clean.size()) + " 位）"; return false; }
    for (unsigned char c : clean)
      if (!std::isxdigit(c)) { *err = "hex 含非法字符"; return false; }
    for (size_t i = 0; i + 1 < clean.size(); i += 2)
      out->push_back((unsigned char)((hexVal(clean[i]) << 4) | hexVal(clean[i + 1])));
    return true;
  }
  if (enc == "base64") {
    std::string clean;
    for (char c : raw) if (!std::isspace((unsigned char)c)) clean += c;
    if (clean.empty()) return true;
    for (unsigned char c : clean) {
      bool legal = std::isalnum(c) || c == '+' || c == '/' || c == '=';
      if (!legal) { *err = "base64 含非法字符"; return false; }
    }
    std::string dec = util::base64Decode(clean);
    out->assign(dec.begin(), dec.end());
    return true;
  }
  out->assign(raw.begin(), raw.end());  // utf8
  return true;
}

std::string toHex(const std::vector<unsigned char>& bytes) {
  static const char* T = "0123456789abcdef";
  std::string out;
  out.reserve(bytes.size() * 2);
  for (unsigned char b : bytes) { out += T[(b >> 4) & 15]; out += T[b & 15]; }
  return out;
}

std::string encodeBytes(const std::vector<unsigned char>& bytes, const std::string& enc) {
  if (enc == "hex") return toHex(bytes);
  return util::base64Encode(std::string(bytes.begin(), bytes.end()));
}

// ------------------------------ 密码套件 ------------------------------
const EVP_CIPHER* pickCipher(size_t keyLen, const std::string& mode) {
  const bool k128 = keyLen == 16, k192 = keyLen == 24;
  if (mode == "cbc") return k128 ? EVP_aes_128_cbc() : k192 ? EVP_aes_192_cbc() : EVP_aes_256_cbc();
  if (mode == "ecb") return k128 ? EVP_aes_128_ecb() : k192 ? EVP_aes_192_ecb() : EVP_aes_256_ecb();
  if (mode == "gcm") return k128 ? EVP_aes_128_gcm() : k192 ? EVP_aes_192_gcm() : EVP_aes_256_gcm();
  return nullptr;
}

// GCM 的 auth tag 固定 16 字节
constexpr int kGcmTagLen = 16;

// 按 WHATWG UTF-8 解码规则数「替换字符」个数，与 Web 版
// `plain.toString('utf8').match(/\ufffd/g)` 的口径一致：
// 一段非法序列只产生一个 U+FFFD（而非按字节计数），被截断的尾巴也只算一个。
int countReplacementChars(const std::vector<unsigned char>& b) {
  const size_t n = b.size();
  int bad = 0;
  size_t i = 0;
  while (i < n) {
    const unsigned char c = b[i];
    if (c < 0x80) { i++; continue; }
    int need = 0;
    unsigned char lo = 0x80, hi = 0xBF;  // 首字节后第一个续字节的合法区间
    if (c >= 0xC2 && c <= 0xDF) need = 1;
    else if (c == 0xE0) { need = 2; lo = 0xA0; }
    else if (c >= 0xE1 && c <= 0xEC) need = 2;
    else if (c == 0xED) { need = 2; hi = 0x9F; }
    else if (c >= 0xEE && c <= 0xEF) need = 2;
    else if (c == 0xF0) { need = 3; lo = 0x90; }
    else if (c >= 0xF1 && c <= 0xF3) need = 3;
    else if (c == 0xF4) { need = 3; hi = 0x8F; }
    else { bad++; i++; continue; }  // 80..C1 / F5..FF：孤立续字节或超范围首字节

    size_t j = i + 1;
    bool broken = false;
    for (int k = 0; k < need; k++, j++) {
      const unsigned char lb = (k == 0) ? lo : 0x80;
      const unsigned char hb = (k == 0) ? hi : 0xBF;
      if (j >= n || b[j] < lb || b[j] > hb) { broken = true; break; }
    }
    if (broken) { bad++; i = (j > i) ? j : i + 1; continue; }  // 只吞到出错字节之前
    i = j;
  }
  return bad;
}

}  // namespace

ToolResult aesCrypto(const json& a) {
  const std::string action = lowerAscii(sarg(a, "action"));
  const std::string mode = lowerAscii(sarg(a, "mode", "cbc"));
  if (action != "encrypt" && action != "decrypt") return fail("action 只能是 encrypt 或 decrypt。");
  if (mode != "cbc" && mode != "gcm" && mode != "ecb") return fail("mode 只能是 cbc / gcm / ecb。");

  auto normEnc = [](const std::string& v, const char* fallback) -> std::string {
    std::string e = lowerAscii(util::trim(v));
    if (e == "utf8" || e == "hex" || e == "base64") return e;
    return fallback;
  };
  const std::string keyEnc = normEnc(sarg(a, "key_encoding"), "utf8");
  const std::string ivEnc = normEnc(sarg(a, "iv_encoding"), "utf8");
  const std::string inEnc = normEnc(sarg(a, "input_encoding"), "base64");
  const std::string outEnc = normEnc(sarg(a, "output_encoding"), "base64");

  std::string err;
  std::vector<unsigned char> key;
  if (!decodeBytes(sarg(a, "key"), keyEnc, &key, &err))
    return fail("key 解析失败（" + keyEnc + "）：" + err + "。");
  if (key.size() != 16 && key.size() != 24 && key.size() != 32) {
    return fail("key 长度是 " + std::to_string(key.size()) +
                " 字节，必须是 16/24/32 字节（128/192/256 位）。如果 key 是十六进制串，请把 key_encoding 设为 hex。");
  }

  const EVP_CIPHER* cipher = pickCipher(key.size(), mode);
  if (!cipher) return fail("不支持的算法组合。");
  const std::string alg = "aes-" + std::to_string(key.size() * 8) + "-" + mode;

  // iv：ECB 不需要；CBC 必须 16 字节；GCM 一般 12 字节，其他长度也允许（会显式设 IVLEN）
  std::vector<unsigned char> iv;
  if (mode != "ecb") {
    if (!decodeBytes(sarg(a, "iv"), ivEnc, &iv, &err))
      return fail("iv 解析失败（" + ivEnc + "）：" + err + "。");
    if (iv.empty()) return fail("CBC / GCM 需要 iv 参数。");
    if (mode == "cbc" && iv.size() != 16)
      return fail("CBC 的 iv 必须是 16 字节，当前 " + std::to_string(iv.size()) + " 字节。");
  }

  // Web 版对空明文不报错（会得到一个纯填充块），这里保持一致；空密文才拦。
  const std::string text = sarg(a, "text");

  EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
  if (!ctx) return fail("加解密上下文创建失败。");

  if (action == "encrypt") {
    std::vector<unsigned char> plain(text.begin(), text.end());
    std::vector<unsigned char> outBytes(plain.size() + 32, 0);
    unsigned char tag[kGcmTagLen] = {0};
    int len1 = 0, len2 = 0;
    bool okAll = false;
    do {
      if (EVP_EncryptInit_ex(ctx, cipher, nullptr, nullptr, nullptr) != 1) break;
      if (mode == "gcm" && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)iv.size(), nullptr) != 1) break;
      if (EVP_EncryptInit_ex(ctx, nullptr, nullptr, key.data(), iv.empty() ? nullptr : iv.data()) != 1) break;
      if (!plain.empty() &&
          EVP_EncryptUpdate(ctx, outBytes.data(), &len1, plain.data(), (int)plain.size()) != 1) break;
      if (EVP_EncryptFinal_ex(ctx, outBytes.data() + len1, &len2) != 1) break;
      okAll = true;
    } while (false);
    if (okAll && mode == "gcm" &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, kGcmTagLen, tag) != 1) okAll = false;
    EVP_CIPHER_CTX_free(ctx);
    if (!okAll) return fail("加密失败（算法 " + alg + "）。");

    outBytes.resize((size_t)len1 + (size_t)len2);
    const std::string cipherText = encodeBytes(outBytes, outEnc);
    const std::string tagB64 = util::base64Encode(
        std::string(reinterpret_cast<const char*>(tag), (size_t)kGcmTagLen));

    // 文案与 Web 版逐字对齐：模式名大写；iv 行的括号里放的是「输入的编码」，
    // 值却固定是 hex（Web 版如此，保持可对比性）；tag 恒为 base64。
    std::string algUpper = alg;
    std::transform(algUpper.begin(), algUpper.end(), algUpper.begin(),
                   [](unsigned char c) { return (char)std::toupper(c); });
    std::string body = "模式 " + algUpper + "\n";
    body += "密文(" + outEnc + ") " + cipherText;
    if (!iv.empty()) body += "\niv(" + ivEnc + ") " + toHex(iv);
    if (mode == "gcm") body += "\ntag(base64) " + tagB64;

    json data = {
        {"mode", alg},
        {"ciphertext", cipherText},
        {"iv", iv.empty() ? json(nullptr) : json(toHex(iv))},
        {"tag", mode == "gcm" ? json(tagB64) : json(nullptr)},
        {"outputEncoding", outEnc},
        {"bytes", (int)outBytes.size()},
    };
    return ok(body, data);
  }

  // ---- decrypt ----
  std::vector<unsigned char> cipherBytes;
  if (!decodeBytes(text, inEnc, &cipherBytes, &err))
    return fail("密文解析失败（" + inEnc + "）：" + err + "。");
  if (cipherBytes.empty()) return fail("密文为空，无法解密。");

  std::vector<unsigned char> tagBytes;
  if (mode == "gcm") {
    const std::string tagArg = util::trim(sarg(a, "tag"));
    if (tagArg.empty()) return fail("GCM 解密需要 tag（auth tag）参数。");
    // 先按 input_encoding 解；解不出来或长度不对时再按 base64 兜一次。
    // 原因：加密侧固定把 tag 输出成 base64（与 Web 版一致），当 output_encoding=hex 时
    // 「密文是 hex、tag 是 base64」，若解密侧严格按 input_encoding 走就会解不开自己刚生成的 tag。
    // tag 必定是 16 字节，用「长度是否等于 16」来消歧足够安全。
    if (!decodeBytes(tagArg, inEnc, &tagBytes, &err) || (int)tagBytes.size() != kGcmTagLen) {
      std::vector<unsigned char> asB64;
      std::string err2;
      if (decodeBytes(tagArg, "base64", &asB64, &err2) && (int)asB64.size() == kGcmTagLen)
        tagBytes = asB64;
      else if (tagBytes.empty())
        return fail("tag 解析失败（" + inEnc + "）：" + err + "。");
    }
    if ((int)tagBytes.size() != kGcmTagLen)
      return fail("GCM 的 tag 必须是 16 字节，当前 " + std::to_string(tagBytes.size()) + " 字节。");
  }

  std::vector<unsigned char> plain(cipherBytes.size() + 32, 0);
  int len1 = 0, len2 = 0;
  bool okAll = false;
  do {
    if (EVP_DecryptInit_ex(ctx, cipher, nullptr, nullptr, nullptr) != 1) break;
    if (mode == "gcm" && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)iv.size(), nullptr) != 1) break;
    if (EVP_DecryptInit_ex(ctx, nullptr, nullptr, key.data(), iv.empty() ? nullptr : iv.data()) != 1) break;
    if (EVP_DecryptUpdate(ctx, plain.data(), &len1, cipherBytes.data(), (int)cipherBytes.size()) != 1) break;
    if (mode == "gcm" &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, kGcmTagLen, tagBytes.data()) != 1) break;
    if (EVP_DecryptFinal_ex(ctx, plain.data() + len1, &len2) != 1) break;
    okAll = true;
  } while (false);
  EVP_CIPHER_CTX_free(ctx);
  if (!okAll) {
    if (mode == "gcm") return fail("解密失败：key / iv / 密文 / 编码方式不匹配，或密文被截断（GCM 校验未通过）。");
    return fail("解密失败：key / iv / 密文 / 编码方式不匹配，或密文被截断（PKCS#7 填充非法）。");
  }

  plain.resize((size_t)len1 + (size_t)len2);
  std::string asText(plain.begin(), plain.end());
  const int bad = countReplacementChars(plain);

  std::string body = asText;
  if (bad) {
    std::string hex = toHex(plain);
    if (hex.size() > 120) hex = hex.substr(0, 120);
    body += "\n\n（有 " + std::to_string(bad) + " 个字节不是合法 UTF-8，原文 hex：" + hex + "）";
  }
  return ok(body, {{"mode", alg}, {"bytes", (int)plain.size()},
                   {"plaintext", asText}, {"hex", toHex(plain)}});
}

}  // namespace cryptotools
}  // namespace ds
