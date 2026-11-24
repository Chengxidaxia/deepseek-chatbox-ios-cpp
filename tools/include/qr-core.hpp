#pragma once
// QR 算法：对照 qr-core.js（byte 模式，v1-40，纠错 L/M/Q/H，已逐模块验证）。
#include <string>
#include <vector>
#include <cstdint>

namespace ds {
namespace qr {

struct QrMatrix {
  int version = 0;
  int size = 0;
  int mask = 0;
  std::vector<std::vector<bool>> matrix;
};

inline const int QR_MAX_VERSION = 40;
inline const int QR_INPUT_MAX = 16384;

int ecIndex(char level);
QrMatrix qrMatrix(const std::string& text, char level = 'M');
int qrCapacity(int version, char level);
std::string qrAscii(const QrMatrix& m);
// 生成 PNG（返回二进制字节），用内置极简 PNG 编码器，无第三方图像库
std::vector<unsigned char> qrPng(const QrMatrix& m, int scale = 8, int border = 4);

}  // namespace qr
}  // namespace ds
