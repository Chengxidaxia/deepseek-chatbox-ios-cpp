#pragma once
// 加密模块：对照 Web 版 secure-key.js
// PIN + PBKDF2(150000, SHA-256) 派生密钥 -> AES-256-GCM 加密 API Key。
// 密文格式（base64）：salt(16) | iv(12) | tag(16) | ciphertext
// iOS 端同样用 OpenSSL（vcpkg），保证两端一致。
#include <string>
#include <vector>
#include <openssl/evp.h>
#include <openssl/rand.h>

namespace ds {
namespace crypto {

struct Encrypted {
  std::string saltB64;
  std::string ivB64;
  std::string tagB64;
  std::string cipherB64;
  std::string serialize() const { return saltB64 + "." + ivB64 + "." + tagB64 + "." + cipherB64; }
  static Encrypted deserialize(const std::string& s) {
    Encrypted e;
    size_t p1 = s.find('.'), p2 = s.find('.', p1+1), p3 = s.find('.', p2+1);
    if (p1==std::string::npos||p2==std::string::npos||p3==std::string::npos) return e;
    e.saltB64 = s.substr(0,p1);
    e.ivB64 = s.substr(p1+1,p2-p1-1);
    e.tagB64 = s.substr(p2+1,p3-p2-1);
    e.cipherB64 = s.substr(p3+1);
    return e;
  }
};

inline std::string b64enc(const unsigned char* d, int n) {
  int len = 4 * ((n + 2) / 3);  // 不依赖 EVP_EncodeBlock(nullptr,...) 的长度探测
  std::string s((size_t)len, '\0');
  int written = EVP_EncodeBlock((unsigned char*)&s[0], d, n);
  s.resize(written > 0 ? (size_t)written : 0);
  return s;
}
inline std::vector<unsigned char> b64dec(const std::string& s) {
  std::vector<unsigned char> out(s.size()*3/4+4);
  int n = EVP_DecodeBlock(out.data(), (const unsigned char*)s.data(), (int)s.size());
  if (n < 0) n = 0;
  // EVP_DecodeBlock 会计入 '=' 的填充，需扣掉
  int pad = 0;
  for (int i=(int)s.size()-1; i>=0 && s[i]=='='; --i) pad++;
  out.resize(n - pad);
  return out;
}

/** PBKDF2-HMAC-SHA256 派生密钥（PKCS5_PBKDF2_HMAC 跨 OpenSSL 版本稳定） */
inline bool pbkdf2(const std::string& pin, const unsigned char* salt, int saltLen,
                   unsigned char* out, int outLen, int iter = 150000) {
  return PKCS5_PBKDF2_HMAC(pin.data(), (int)pin.size(), salt, saltLen, iter,
                           EVP_sha256(), outLen, out) == 1;
}

inline Encrypted encrypt(const std::string& plaintext, const std::string& pin, std::string* err = nullptr) {
  Encrypted e;
  unsigned char salt[16], iv[12];
  if (RAND_bytes(salt, sizeof(salt)) != 1 || RAND_bytes(iv, sizeof(iv)) != 1) {
    if (err) *err = "随机数生成失败";
    return e;
  }
  unsigned char key[32];
  if (!pbkdf2(pin, salt, sizeof(salt), key, sizeof(key))) {
    if (err) *err = "密钥派生失败";
    return e;
  }
  EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
  if (!ctx) { if (err) *err = "加密上下文创建失败"; return e; }
  if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) != 1 ||
      EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, sizeof(iv), nullptr) != 1 ||
      EVP_EncryptInit_ex(ctx, nullptr, nullptr, key, iv) != 1) {
    if (err) *err = "AES-GCM 初始化失败";
    EVP_CIPHER_CTX_free(ctx); return e;
  }
  std::vector<unsigned char> cipher(plaintext.size() + 32);
  int outLen = 0, total = 0;
  EVP_EncryptUpdate(ctx, cipher.data(), &outLen, (const unsigned char*)plaintext.data(), (int)plaintext.size());
  total = outLen;
  EVP_EncryptFinal_ex(ctx, cipher.data()+total, &outLen);
  total += outLen;
  unsigned char tag[16];
  EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, sizeof(tag), tag);
  EVP_CIPHER_CTX_free(ctx);
  e.saltB64 = b64enc(salt, sizeof(salt));
  e.ivB64 = b64enc(iv, sizeof(iv));
  e.tagB64 = b64enc(tag, sizeof(tag));
  e.cipherB64 = b64enc(cipher.data(), total);
  OPENSSL_cleanse(key, sizeof(key));
  return e;
}

inline std::string decrypt(const Encrypted& e, const std::string& pin, std::string* err = nullptr) {
  auto salt = b64dec(e.saltB64), iv = b64dec(e.ivB64), tag = b64dec(e.tagB64), cipher = b64dec(e.cipherB64);
  if (salt.size()!=16 || iv.size()!=12 || tag.size()!=16) {
    if (err) *err = "密文格式损坏";
    return "";
  }
  unsigned char key[32];
  if (!pbkdf2(pin, salt.data(), (int)salt.size(), key, sizeof(key))) {
    if (err) *err = "密钥派生失败";
    return "";
  }
  EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
  if (!ctx) { if (err) *err = "解密上下文创建失败"; return ""; }
  if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) != 1 ||
      EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)iv.size(), nullptr) != 1 ||
      EVP_DecryptInit_ex(ctx, nullptr, nullptr, key, iv.data()) != 1) {
    if (err) *err = "AES-GCM 初始化失败"; EVP_CIPHER_CTX_free(ctx); return "";
  }
  std::vector<unsigned char> plain(cipher.size()+32);
  int outLen=0, total=0;
  EVP_DecryptUpdate(ctx, plain.data(), &outLen, cipher.data(), (int)cipher.size());
  total = outLen;
  EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, (int)tag.size(), tag.data());
  int ok = EVP_DecryptFinal_ex(ctx, plain.data()+total, &outLen);
  EVP_CIPHER_CTX_free(ctx);
  OPENSSL_cleanse(key, sizeof(key));
  if (ok <= 0) { if (err) *err = "PIN 错误或密文被篡改"; return ""; }
  total += outLen;
  return std::string((char*)plain.data(), total);
}

/** SHA-256 hex，供 hash_text 工具用 */
inline std::string sha256hex(const std::string& data) {
  unsigned char out[EVP_MAX_MD_SIZE]; unsigned int len=0;
  EVP_Digest(data.data(), data.size(), out, &len, EVP_sha256(), nullptr);
  static const char* hex="0123456789abcdef";
  std::string s; s.reserve(len*2);
  for (unsigned int i=0;i<len;i++){ s+=hex[out[i]>>4]; s+=hex[out[i]&15]; }
  return s;
}

}  // namespace crypto
}  // namespace ds
