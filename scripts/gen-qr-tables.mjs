// 从已验证的 qr-core.js 提取 QR_RS_BLOCK / QR_ALIGN 表，生成 C++ 头文件。
// 避免手抄 40 版本表格出错。qr-core.js 已与 qrcode-generator 逐模块比对通过。
import fs from 'node:fs';

const SRC = 'K:/WorkBuddyWorkspace/2026-11-22-20-37-13/deepseek-chatbox-ios/www/js/qr-core.js';
const src = fs.readFileSync(SRC, 'utf8');

function extractArray(name) {
  const re = new RegExp('const ' + name + ' = (\\[[\\s\\S]*?\\]);');
  const m = re.exec(src);
  if (!m) throw new Error('未找到 ' + name);
  // 去掉 JS 注释和尾随逗号（JS 允许，JSON 不允许）
  const clean = m[1].replace(/\/\/[^\n]*/g, '').replace(/,\s*\]/g, ']');
  return JSON.parse(clean);
}

const RS = extractArray('QR_RS_BLOCK');
const ALIGN = extractArray('QR_ALIGN');

function rsToCpp(rs) {
  // 每行是一个版本×纠错的块数组（扁平的 [count,total,data,...]）
  const rows = [];
  for (let i = 0; i < rs.length; i += 4) {
    rows.push(rs.slice(i, i + 4));
  }
  // QR_RS_BLOCK 实际是两个一维表拼一起？检查维度
  return rows;
}

let out = '// 自动生成：由 scripts/gen-qr-tables.mjs 从 qr-core.js 提取，勿手改。\n';
out += '#pragma once\n#include <vector>\nnamespace ds { namespace qr {\n\n';

// QR_RS_BLOCK 是 160 项（40版本 × 4纠错），每项是一个块数组
out += 'inline const std::vector<std::vector<int>> QR_RS_BLOCK = {\n';
for (let i = 0; i < RS.length; i++) {
  const row = RS[i];
  out += '  {' + row.join(', ') + '},' + (i % 4 === 3 ? ` // v${Math.floor(i/4)+1}\n` : '\n');
}
out += '};\n\n';

// QR_ALIGN 是 40 项，每项是版本对应的对齐点坐标数组
out += 'inline const std::vector<std::vector<int>> QR_ALIGN = {\n';
for (let i = 0; i < ALIGN.length; i++) {
  out += '  {' + ALIGN[i].join(', ') + '},' + ` // v${i+1}\n`;
}
out += '};\n\n';

out += '}}  // namespace ds::qr\n';

fs.writeFileSync('tools/include/qr-tables.hpp', out, 'utf8');
console.log('QR_RS_BLOCK:', RS.length, '项, QR_ALIGN:', ALIGN.length, '项');
console.log('生成 tools/include/qr-tables.hpp', fs.statSync('tools/include/qr-tables.hpp').size, '字节');
