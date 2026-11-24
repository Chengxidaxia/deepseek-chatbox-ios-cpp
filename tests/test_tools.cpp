#include "tools.hpp"
#include "qr-core.hpp"
#include "util.hpp"
#include <iostream>
#include <fstream>

using namespace ds;
static int failed = 0;
#define CHECK(cond, msg) do { if (!(cond)) { std::cerr << "FAIL: " << msg << " (line " << __LINE__ << ")\n"; failed++; } else { std::cout << "  ok: " << msg << "\n"; } } while(0)

int main() {
  std::cout.setf(std::ios::unitbuf);
  auto& eng = ToolEngine::instance();
  std::string err;
  CHECK(eng.loadDefinitions("tools/tool_defs.json", &err), "加载工具定义: " + err);
  CHECK(eng.names().size() == 40, "工具数=40: " + std::to_string(eng.names().size()));

  std::cout << "=== 编码/计算工具 ===\n";
  {
    auto r = eng.call("base64_codec", {{"mode","encode"},{"text","hello"}});
    CHECK(r.ok && r.text=="aGVsbG8=", "base64 编码: " + r.text);
    r = eng.call("base64_codec", {{"mode","decode"},{"text","aGVsbG8="}});
    CHECK(r.ok && r.text=="hello", "base64 解码");
    r = eng.call("calculator", {{"expression","1+2*3"}});
    CHECK(r.ok && r.text.find("7")!=std::string::npos, "计算器 1+2*3=" + r.text);
    r = eng.call("calculator", {{"expression","sqrt(16)+pow(2,3)"}});
    CHECK(r.ok && r.text.find("12")!=std::string::npos, "计算器 sqrt+pow=" + r.text);
    r = eng.call("hash_text", {{"text","abc"},{"algorithm","sha256"}});
    CHECK(r.ok && r.text.find("ba7816b")!=std::string::npos, "SHA256(abc)");
    r = eng.call("percentage", {{"mode","ratio"},{"a",25},{"b",100}});
    CHECK(r.ok && r.text.find("25%")!=std::string::npos, "百分比 25/100=" + r.text);
    r = eng.call("base_convert", {{"value","255"},{"from",10},{"to",16}});
    CHECK(r.ok && r.text.find("FF")!=std::string::npos, "进制转换 255→FF=" + r.text);
    r = eng.call("unit_convert", {{"value",1},{"from","km"},{"to","m"}});
    CHECK(r.ok && r.text.find("1000")!=std::string::npos, "单位转换 1km=" + r.text);
  }

  std::cout << "=== 文本/JSON 工具 ===\n";
  {
    auto r = eng.call("json_minify", {{"json","{ \"a\" : 1 }"}});
    CHECK(r.ok && r.text.find(" ")==std::string::npos, "JSON 压缩: " + r.text);
    r = eng.call("text_stats", {{"text","你好hello world"}});
    CHECK(r.ok && r.data["cjk"]==2, "文本统计中文汉字数");
    r = eng.call("uuid_gen", {{"count",3}});
    CHECK(r.ok && r.data["uuids"].size()==3, "UUID 生成 3 个");
    r = eng.call("diff_text", {{"a","a\nb"},{"b","a\nc"}});
    CHECK(r.ok && r.data["added"]==1 && r.data["removed"]==1, "文本 diff");
  }

  std::cout << "=== QR 算法（对照已验证的 Web 版）===\n";
  {
    // 用已知文本生成，检查矩阵尺寸/版本合理、PNG 有效
    auto q = qr::qrMatrix("HELLO WORLD", 'M');
    CHECK(q.version >= 1 && q.version <= 40, "QR 版本: " + std::to_string(q.version));
    CHECK(q.size == q.version*4+17, "QR 尺寸=" + std::to_string(q.size));
    CHECK(q.matrix.size()==(size_t)q.size && q.matrix[0].size()==(size_t)q.size, "QR 矩阵维度一致");
    CHECK(!qr::qrAscii(q).empty(), "QR ASCII 输出非空");

    auto png = qr::qrPng(q, 8, 4);
    CHECK(png.size() > 100, "QR PNG 字节数: " + std::to_string(png.size()));
    // PNG 签名
    bool sig = png[0]==137&&png[1]==80&&png[2]==78&&png[3]==71;
    CHECK(sig, "QR PNG 签名正确");

    // 大容量：v40 + L 应能装 2953 字节
    int cap = qr::qrCapacity(40, 'L');
    CHECK(cap >= 2900 && cap <= 2953, "QR v40/L 容量=" + std::to_string(cap));
    std::string big(2000, 'x');
    auto q2 = qr::qrMatrix(big, 'L');
    CHECK(q2.version > 10 && q2.version <= 40, "2000字节 QR 版本=" + std::to_string(q2.version));

    // 通过工具调用
    auto r = eng.call("qr_text", {{"text","测试二维码"},{"level","M"},{"scale",6}});
    CHECK(r.ok && r.data.contains("images") && r.data["images"].size()==1, "qr_text 工具生成 1 张");
    CHECK(!r.images.empty() && r.images[0].find("data:image/png;base64,")==0, "qr_text 返回 PNG dataURL");
  }

  std::cout << "=== 工具搜索 ===\n";
  {
    auto hits = eng.search("计算表达式", 3);
    CHECK(!hits.empty(), "搜索「计算表达式」有结果");
    bool hasCalc=false;
    for(auto& h:hits) if(h.first=="calculator") hasCalc=true;
    CHECK(hasCalc, "搜索命中 calculator");
  }

  if (failed) { std::cerr << "\n" << failed << " 项失败\n"; return 1; }
  std::cout << "\n工具引擎测试全部通过 ✓\n";
  return 0;
}
