#pragma once
// AES 对称加解密：实现对照 Web 版 server/tools-core.cjs 的 aes_crypto（Web 走 Web Crypto，
// 这里换 OpenSSL EVP）。参数语义与输出文案保持一致。
#include "tools.hpp"

namespace ds {
namespace cryptotools {

ToolResult aesCrypto(const json& a);

}  // namespace cryptotools
}  // namespace ds
