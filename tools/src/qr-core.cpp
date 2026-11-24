// QR 算法 C++ 实现：逐行对照 qr-core.js（byte 模式，v1-40）。
#include "qr-core.hpp"
#include "qr-tables.hpp"
#include <algorithm>
#include <cmath>
#include <zlib.h>

namespace ds {
namespace qr {

// Galois Field 表
static int QR_EXP[512], QR_LOG[256];
static bool gfInit() {
  static bool done = false;
  if (done) return true;
  int x = 1;
  for (int i = 0; i < 255; i++) { QR_EXP[i] = x; QR_LOG[x] = i; x <<= 1; if (x & 0x100) x ^= 0x11d; }
  for (int i = 255; i < 512; i++) QR_EXP[i] = QR_EXP[i - 255];
  done = true;
  return true;
}
static int qrMul(int a, int b) { return (a == 0 || b == 0) ? 0 : QR_EXP[QR_LOG[a] + QR_LOG[b]]; }

int ecIndex(char level) {
  switch (level) {
    case 'L': return 0; case 'M': return 1; case 'Q': return 2; case 'H': return 3;
    default: return 1;
  }
}
static int ecBits(char level) {
  switch (level) {
    case 'L': return 1; case 'M': return 0; case 'Q': return 3; case 'H': return 2;
    default: return 0;
  }
}

struct Block { int total, data, ec; };
static std::vector<Block> qrBlocks(int version, char level) {
  gfInit();
  const auto& raw = QR_RS_BLOCK[(version - 1) * 4 + ecIndex(level)];
  std::vector<Block> out;
  for (size_t i = 0; i < raw.size(); i += 3)
    for (int k = 0; k < raw[i]; k++)
      out.push_back({raw[i+1], raw[i+2], raw[i+1] - raw[i+2]});
  return out;
}

static std::vector<int> qrGenPoly(int n) {
  std::vector<int> poly = {1};
  for (int i = 0; i < n; i++) {
    std::vector<int> next(poly.size() + 1, 0);
    for (size_t j = 0; j < poly.size(); j++) {
      next[j] ^= poly[j];
      next[j+1] ^= qrMul(poly[j], QR_EXP[i]);
    }
    poly = next;
  }
  return poly;
}

static std::vector<int> qrReedSolomon(const std::vector<int>& data, int ecLen) {
  auto gen = qrGenPoly(ecLen);
  std::vector<int> res(ecLen, 0);
  for (int byte : data) {
    int factor = byte ^ res[0];
    res.erase(res.begin()); res.push_back(0);
    if (factor != 0) for (int i = 0; i < ecLen; i++) res[i] ^= qrMul(gen[i+1], factor);
  }
  return res;
}

static std::vector<int> qrCodewords(const std::vector<uint8_t>& bytes, int version, char level) {
  auto blocks = qrBlocks(version, level);
  int totalData = 0;
  for (auto& b : blocks) totalData += b.data;
  std::vector<int> bits;
  auto push = [&](int val, int len) { for (int i = len - 1; i >= 0; i--) bits.push_back((val >> i) & 1); };
  push(0b0100, 4);
  push((int)bytes.size(), version <= 9 ? 8 : 16);
  for (uint8_t b : bytes) push(b, 8);
  int cap = totalData * 8;
  for (int i = 0; i < 4 && (int)bits.size() < cap; i++) bits.push_back(0);
  while (bits.size() % 8) bits.push_back(0);
  std::vector<int> words;
  for (size_t i = 0; i < bits.size(); i += 8) {
    int v = 0;
    for (int j = 0; j < 8; j++) v = (v << 1) | bits[i+j];
    words.push_back(v);
  }
  const int PAD[] = {0xec, 0x11};
  for (int i = 0; (int)words.size() < totalData; i++) words.push_back(PAD[i % 2]);
  std::vector<std::vector<int>> dataBlocks, ecBlocks;
  size_t p = 0;
  for (auto& b : blocks) {
    std::vector<int> d(words.begin() + p, words.begin() + p + b.data);
    p += b.data;
    dataBlocks.push_back(d);
    ecBlocks.push_back(qrReedSolomon(d, b.ec));
  }
  std::vector<int> out;
  int maxData = 0, maxEc = 0;
  for (auto& b : blocks) { maxData = std::max(maxData, b.data); maxEc = std::max(maxEc, b.ec); }
  for (int i = 0; i < maxData; i++) for (auto& d : dataBlocks) if (i < (int)d.size()) out.push_back(d[i]);
  for (int i = 0; i < maxEc; i++) for (auto& e : ecBlocks) if (i < (int)e.size()) out.push_back(e[i]);
  return out;
}

static bool maskFn(int mask, int r, int c) {
  switch (mask) {
    case 0: return (r + c) % 2 == 0;
    case 1: return r % 2 == 0;
    case 2: return c % 3 == 0;
    case 3: return (r + c) % 3 == 0;
    case 4: return (r/2 + c/3) % 2 == 0;
    case 5: return ((r*c)%2) + ((r*c)%3) == 0;
    case 6: return (((r*c)%2) + ((r*c)%3)) % 2 == 0;
    case 7: return (((r*c)%3) + ((r+c)%2)) % 2 == 0;
    default: return false;
  }
}

static const int QR_G15 = (1<<10)|(1<<8)|(1<<5)|(1<<4)|(1<<2)|(1<<1)|1;
static const int QR_G18 = (1<<12)|(1<<11)|(1<<10)|(1<<9)|(1<<8)|(1<<5)|(1<<2)|1;
static const int QR_G15_MASK = (1<<14)|(1<<12)|(1<<10)|(1<<4)|(1<<1);
static int bitLen(int d) { int n = 0; while (d != 0) { n++; d = (int)((unsigned)d >> 1); } return n; }
static int qrBchInfo(int data) {
  int d = data << 10;
  while (bitLen(d) - bitLen(QR_G15) >= 0) d ^= QR_G15 << (bitLen(d) - bitLen(QR_G15));
  return ((data << 10) | d) ^ QR_G15_MASK;
}
static int qrBchVersion(int data) {
  int d = data << 12;
  while (bitLen(d) - bitLen(QR_G18) >= 0) d ^= QR_G18 << (bitLen(d) - bitLen(QR_G18));
  return (data << 12) | d;
}

struct BuildResult { std::vector<std::vector<bool>> matrix; int size; };
static BuildResult qrBuildMatrix(int version, const std::vector<int>& codewords, char level, int mask, bool writeMeta) {
  int size = version * 4 + 17;
  std::vector<std::vector<bool>> m(size, std::vector<bool>(size, false));
  std::vector<std::vector<bool>> reserved(size, std::vector<bool>(size, false));
  std::vector<std::vector<bool>> setFlag(size, std::vector<bool>(size, false));
  auto set = [&](int r, int c, bool v) {
    if (r < 0 || c < 0 || r >= size || c >= size) return;
    m[r][c] = v; setFlag[r][c] = true;
  };
  auto finder = [&](int r0, int c0) {
    for (int r = -1; r <= 7; r++) for (int c = -1; c <= 7; c++) {
      int rr = r0 + r, cc = c0 + c;
      if (rr < 0 || cc < 0 || rr >= size || cc >= size) continue;
      bool dark = (r >= 0 && r <= 6 && (c == 0 || c == 6))
               || (c >= 0 && c <= 6 && (r == 0 || r == 6))
               || (r >= 2 && r <= 4 && c >= 2 && c <= 4);
      set(rr, cc, dark);
    }
  };
  finder(0, 0); finder(0, size - 7); finder(size - 7, 0);
  for (int i = 8; i < size - 8; i++) { set(6, i, i % 2 == 0); set(i, 6, i % 2 == 0); }
  const auto& pos = QR_ALIGN[version - 1];
  auto inFinder = [&](int r, int c) { return (r <= 8 && c <= 8) || (r <= 8 && c >= size - 8) || (r >= size - 8 && c <= 8); };
  for (int r0 : pos) for (int c0 : pos) {
    if (inFinder(r0, c0)) continue;
    for (int r = -2; r <= 2; r++) for (int c = -2; c <= 2; c++)
      set(r0 + r, c0 + c, std::max(std::abs(r), std::abs(c)) != 1);
  }
  int bits = writeMeta ? qrBchInfo((ecBits(level) << 3) | mask) : 0;
  for (int i = 0; i < 15; i++) {
    bool bit = writeMeta && (((bits >> i) & 1) == 1);
    int r = i < 6 ? i : (i < 8 ? i + 1 : size - 15 + i);
    set(r, 8, bit);
    int c = i < 8 ? size - i - 1 : (i < 9 ? 15 - i : 14 - i);
    set(8, c, bit);
  }
  set(size - 8, 8, writeMeta);
  if (version >= 7) {
    int vbits = writeMeta ? qrBchVersion(version) : 0;
    for (int i = 0; i < 18; i++) {
      bool bit = writeMeta && (((vbits >> i) & 1) == 1);
      set(i / 3, (i % 3) + size - 11, bit);
      set((i % 3) + size - 11, i / 3, bit);
    }
  }
  // 标记功能图形区域（不再写数据）
  for (int r = 0; r < size; r++) for (int c = 0; c < size; c++) if (setFlag[r][c]) reserved[r][c] = true;

  int totalBits = (int)codewords.size() * 8;
  int idx = 0, dir = -1, row = size - 1;
  for (int col = size - 1; col > 0; col -= 2) {
    if (col == 6) col--;
    while (true) {
      for (int k = 0; k < 2; k++) {
        int cc = col - k;
        if (!reserved[row][cc]) {
          int bit = 0;
          if (idx < totalBits) { bit = (codewords[idx >> 3] >> (7 - (idx & 7))) & 1; idx++; }
          m[row][cc] = bit == 1;
          reserved[row][cc] = true;
        }
      }
      row += dir;
      if (row < 0 || row >= size) { row -= dir; dir = -dir; break; }
    }
  }
  for (int r = 0; r < size; r++) for (int c = 0; c < size; c++)
    if (!setFlag[r][c] && maskFn(mask, r, c)) m[r][c] = !m[r][c];
  return {m, size};
}

static int qrLostPoint(const std::vector<std::vector<bool>>& m, int size) {
  auto dark = [&](int r, int c) { return m[r][c]; };
  int lost = 0;
  for (int r = 0; r < size; r++) for (int c = 0; c < size; c++) {
    int same = 0;
    for (int dr = -1; dr <= 1; dr++) for (int dc = -1; dc <= 1; dc++) {
      if (dr == 0 && dc == 0) continue;
      int rr = r + dr, cc = c + dc;
      if (rr < 0 || cc < 0 || rr >= size || cc >= size) continue;
      if (dark(r, c) == dark(rr, cc)) same++;
    }
    if (same > 5) lost += 3 + same - 5;
  }
  for (int r = 0; r < size - 1; r++) for (int c = 0; c < size - 1; c++) {
    int n = (int)dark(r,c) + (int)dark(r+1,c) + (int)dark(r,c+1) + (int)dark(r+1,c+1);
    if (n == 0 || n == 4) lost += 3;
  }
  for (int r = 0; r < size; r++) for (int c = 0; c < size - 6; c++)
    if (dark(r,c)&&!dark(r,c+1)&&dark(r,c+2)&&dark(r,c+3)&&dark(r,c+4)&&!dark(r,c+5)&&dark(r,c+6)) lost += 40;
  for (int c = 0; c < size; c++) for (int r = 0; r < size - 6; r++)
    if (dark(r,c)&&!dark(r+1,c)&&dark(r+2,c)&&dark(r+3,c)&&dark(r+4,c)&&!dark(r+5,c)&&dark(r+6,c)) lost += 40;
  int darkCount = 0;
  for (int r = 0; r < size; r++) for (int c = 0; c < size; c++) if (dark(r,c)) darkCount++;
  lost += (int)((std::abs((100.0 * darkCount) / size / size - 50) / 5) * 10);
  return lost;
}

int qrCapacity(int version, char level) {
  auto blocks = qrBlocks(version, level);
  int totalData = 0;
  for (auto& b : blocks) totalData += b.data;
  return (totalData * 8 - 4 - (version <= 9 ? 8 : 16)) / 8;
}

QrMatrix qrMatrix(const std::string& text, char level) {
  gfInit();
  std::vector<uint8_t> bytes(text.begin(), text.end());
  int version = 0;
  for (version = 1; version <= QR_MAX_VERSION; version++) {
    auto blocks = qrBlocks(version, level);
    int totalData = 0;
    for (auto& b : blocks) totalData += b.data;
    if (4 + (version <= 9 ? 8 : 16) + (int)bytes.size() * 8 <= totalData * 8) break;
  }
  QrMatrix result;
  if (version > QR_MAX_VERSION) return result;  // 空矩阵表示过长
  auto cw = qrCodewords(bytes, version, level);
  int bestMask = 0, bestScore = -1;
  for (int mask = 0; mask < 8; mask++) {
    auto probe = qrBuildMatrix(version, cw, level, mask, false);
    int score = qrLostPoint(probe.matrix, probe.size);
    if (bestScore < 0 || score < bestScore) { bestScore = score; bestMask = mask; }
  }
  auto final = qrBuildMatrix(version, cw, level, bestMask, true);
  result.version = version; result.mask = bestMask; result.size = final.size; result.matrix = final.matrix;
  return result;
}

std::string qrAscii(const QrMatrix& q) {
  std::string out;
  int n = q.size;
  for (int r = 0; r < n; r++) {
    for (int c = 0; c < n; c++) out += q.matrix[r][c] ? "██" : "  ";
    out += '\n';
  }
  return out;
}

// ------------------------------ 极简 PNG 编码（zlib + CRC32）------------------------------
static void appendU32BE(std::vector<unsigned char>& v, uint32_t x) {
  v.push_back((x >> 24) & 255); v.push_back((x >> 16) & 255);
  v.push_back((x >> 8) & 255); v.push_back(x & 255);
}
static void appendChunk(std::vector<unsigned char>& png, const char* type, const std::vector<unsigned char>& data) {
  appendU32BE(png, (uint32_t)data.size());
  size_t off = png.size();
  png.insert(png.end(), type, type + 4);
  png.insert(png.end(), data.begin(), data.end());
  uint32_t crc = (uint32_t)crc32(0, png.data() + off, (uInt)(4 + data.size()));
  appendU32BE(png, crc);
}

std::vector<unsigned char> qrPng(const QrMatrix& q, int scale, int border) {
  int n = q.size;
  int dim = (n + border * 2) * scale;
  // 灰度 8bit：每行 filter byte(0) + dim 字节
  std::vector<unsigned char> raw;
  raw.reserve((dim + 1) * dim);
  for (int y = 0; y < dim; y++) {
    raw.push_back(0);  // filter none
    int mr = y / scale - border;
    for (int x = 0; x < dim; x++) {
      int mc = x / scale - border;
      bool dark = (mr >= 0 && mc >= 0 && mr < n && mc < n) && q.matrix[mr][mc];
      raw.push_back(dark ? 0 : 255);
    }
  }
  uLongf zlen = compressBound(raw.size());
  std::vector<unsigned char> zdata(zlen);
  compress2(zdata.data(), &zlen, raw.data(), raw.size(), Z_DEFAULT_COMPRESSION);
  zdata.resize(zlen);

  std::vector<unsigned char> png = {137,80,78,71,13,10,26,10};
  // IHDR
  std::vector<unsigned char> ihdr;
  appendU32BE(ihdr, dim); appendU32BE(ihdr, dim);
  ihdr.push_back(8);   // bit depth
  ihdr.push_back(0);   // color type: grayscale
  ihdr.push_back(0); ihdr.push_back(0); ihdr.push_back(0);
  appendChunk(png, "IHDR", ihdr);
  appendChunk(png, "IDAT", zdata);
  appendChunk(png, "IEND", {});
  return png;
}

}  // namespace qr
}  // namespace ds
