#include "tools.hpp"
#include "qr-core.hpp"
#include "util.hpp"
#include <iostream>
#include <fstream>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

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

  std::cout << "=== P0 纯字符串工具 ===\n";
  {
    // regex_test：\d+ 从 a1b22 抽到 1、22
    auto r = eng.call("regex_test", {{"pattern","\\d+"},{"text","a1b22"}});
    CHECK(r.ok && r.data["count"]==2, "regex 匹配 2 条: " + r.text);
    CHECK(r.ok && r.data["matches"][0]["match"]=="1" && r.data["matches"][1]["match"]=="22", "regex 捕获 1/22");
    // 命名组降级：std::regex 不认 (?<name>)，实现里转普通组并记名
    r = eng.call("regex_test", {{"pattern","(?<year>\\d{4})-(?<month>\\d{2})"},{"text","2026-11"}});
    CHECK(r.ok && r.data["matches"][0]["groups"]["year"]=="2026", "regex 命名组 year: " + r.text);
    r = eng.call("regex_test", {{"pattern","("},{"text","x"}});
    CHECK(!r.ok && r.text.find("正则表达式错误")!=std::string::npos, "regex 非法模式报错: " + r.text);
    r = eng.call("regex_test", {{"pattern","z+"},{"text","abc"}});
    CHECK(r.ok && r.data["count"]==0, "regex 无匹配 count=0");

    // csv_json：引号内含逗号 / "" 转义，往返不变
    r = eng.call("csv_json", {{"mode","toJson"},{"text","name,note\nalice,\"a,b\"\nbob,\"say \"\"hi\"\"\""}});
    CHECK(r.ok && r.data["rows"]==2, "csv toJson 行数: " + r.text);
    CHECK(r.ok && r.text.find("\"a,b\"")!=std::string::npos, "csv toJson 保留引号内逗号");
    std::string csvBack = r.text;
    r = eng.call("csv_json", {{"mode","toCsv"},{"text",csvBack}});
    CHECK(r.ok && r.text.find("\"a,b\"")!=std::string::npos, "csv toCsv 重新加引号: " + r.text);
    r = eng.call("csv_json", {{"mode","toCsv"},{"text","[]"}});
    CHECK(!r.ok, "csv toCsv 空数组报错");

    // slugify
    r = eng.call("slugify", {{"text","Hello, World!"}});
    CHECK(r.ok && r.text=="hello-world", "slugify Hello, World! → " + r.text);
    r = eng.call("slugify", {{"text","  你好，世界  "}});
    CHECK(r.ok && r.text.find("你好")!=std::string::npos && r.text.find("，")==std::string::npos,
          "slugify 保留中文、去掉全角标点: " + r.text);
    r = eng.call("slugify", {{"text","A  B---C"},{"separator","_"}});
    CHECK(r.ok && r.text=="a_b_c", "slugify 自定义连接符: " + r.text);

    // id_validator
    r = eng.call("id_validator", {{"type","idcard"},{"value","11010519491231002X"}});
    CHECK(r.ok && r.data["valid"]==true, "身份证合法: " + r.text);
    r = eng.call("id_validator", {{"type","idcard"},{"value","110105194912310021"}});
    CHECK(r.ok && r.data["valid"]==false, "身份证改末位不合法: " + r.text);
    r = eng.call("id_validator", {{"type","idcard"},{"value","110105194902310021"}});
    CHECK(r.ok && r.data["valid"]==false && r.text.find("出生日期无效")!=std::string::npos, "身份证 2 月 31 日被拦");
    r = eng.call("id_validator", {{"type","email"},{"value","a@b.co"}});
    CHECK(r.ok && r.data["valid"]==true, "邮箱合法");
    r = eng.call("id_validator", {{"type","phone"},{"value","13800138000"}});
    CHECK(r.ok && r.data["valid"]==true, "手机号合法");
    r = eng.call("id_validator", {{"type","ipv4"},{"value","256.1.1.1"}});
    CHECK(r.ok && r.data["valid"]==false, "IPv4 越界被拦");
    r = eng.call("id_validator", {{"type","uuid"},{"value","3f2504e0-4f89-11d3-9a0c-0305e82c3301"}});
    CHECK(r.ok && r.data["valid"]==true, "UUID 合法");

    // hex_view：ASCII 往返 + UTF-8 中文按字节
    r = eng.call("hex_view", {{"mode","toHex"},{"text","abc"}});
    CHECK(r.ok && r.text.find("61 62 63")!=std::string::npos, "hex toHex: " + r.text);
    CHECK(r.ok && r.data["hex"]=="616263", "hex 原始串");
    r = eng.call("hex_view", {{"mode","fromHex"},{"text","0x61, 62 63"}});
    CHECK(r.ok && r.text=="abc", "hex fromHex 多分隔符: " + r.text);
    r = eng.call("hex_view", {{"mode","toHex"},{"text","中文"}});
    std::string zhHex = r.data["hex"].get<std::string>();
    r = eng.call("hex_view", {{"mode","fromHex"},{"text",zhHex}});
    CHECK(r.ok && r.text=="中文", "hex UTF-8 中文往返: " + r.text);
    r = eng.call("hex_view", {{"mode","fromHex"},{"text","61626"}});
    CHECK(!r.ok, "hex 奇数长度报错");

    // color_convert
    r = eng.call("color_convert", {{"color","#3964FE"},{"background","#FFFFFF"}});
    CHECK(r.ok && r.data["hex"]=="#3964FE", "color hex 规范化: " + r.text);
    double bgContrast = r.data["contrastWithBackground"].get<double>();
    CHECK(bgContrast > 4.5 && bgContrast < 5.0, "color 对白对比度 ≈4.74: " + std::to_string(bgContrast));
    r = eng.call("color_convert", {{"color","rgb(30,144,255)"}});
    CHECK(r.ok && r.data["hex"]=="#1E90FF", "color rgb() 解析: " + r.text);
    r = eng.call("color_convert", {{"color","hsl(210,100%,56%)"}});
    CHECK(r.ok, "color hsl() 解析: " + r.text);
    r = eng.call("color_convert", {{"color","red"}});
    CHECK(r.ok && r.data["hex"]=="#FF0000", "color 色名解析");
    r = eng.call("color_convert", {{"color","不是颜色"}});
    CHECK(!r.ok, "color 非法输入报错");

    // text_kit：6 个 action 各一条
    r = eng.call("text_kit", {{"action","dedupe"},{"text","a\nb\na\n\nA"}});
    CHECK(r.ok && r.data["after"]==3, "text_kit dedupe: " + r.text);
    r = eng.call("text_kit", {{"action","dedupe"},{"text","a\nA"},{"ignore_case",true}});
    CHECK(r.ok && r.data["after"]==1, "text_kit dedupe 忽略大小写");
    r = eng.call("text_kit", {{"action","sort"},{"text","10\n9\n100"},{"numeric",true}});
    CHECK(r.ok && r.text=="9\n10\n100", "text_kit sort numeric: " + r.text);
    r = eng.call("text_kit", {{"action","trim"},{"text","  a   b  \n\n c "}});
    CHECK(r.ok && r.text=="a b\nc", "text_kit trim: " + r.text);
    r = eng.call("text_kit", {{"action","wrap"},{"text","a\nb"},{"prefix","- "}});
    CHECK(r.ok && r.text=="- a\n- b", "text_kit wrap: " + r.text);
    r = eng.call("text_kit", {{"action","split"},{"text","a, b ,, c"},{"delimiter",","}});
    // 编号沿用原始下标（与 Web 版一致），空段被过滤但序号不重排
    CHECK(r.ok && r.text=="1. a\n2. b\n4. c", "text_kit split: " + r.text);
    r = eng.call("text_kit", {{"action","case"},{"text","userName"},{"case_type","snake"}});
    CHECK(r.ok && r.text=="user_name", "text_kit case snake: " + r.text);
    r = eng.call("text_kit", {{"action","case"},{"text","HTTPResponse"},{"case_type","kebab"}});
    CHECK(r.ok && r.text=="http-response", "text_kit case kebab: " + r.text);
    r = eng.call("text_kit", {{"action","case"},{"text","hello world"},{"case_type","camel"}});
    CHECK(r.ok && r.text=="helloWorld", "text_kit case camel: " + r.text);
    r = eng.call("text_kit", {{"action","nope"},{"text","x"}});
    CHECK(!r.ok, "text_kit 未知 action 报错");
  }

  std::cout << "=== AES 加解密（对照 Web 版 / Node crypto 的黄金向量）===\n";
  {
    // 期望值全部由 `node -e` 用 crypto.createCipheriv 现算得出（Web 版跑的就是 Node crypto），
    // 所以这些断言等价于「与 Web 版对同一明文/key/iv 逐字节相同」。
    const std::string K128 = "0123456789abcdef";
    const std::string K192 = "0123456789abcdef01234567";
    const std::string K256 = "0123456789abcdef0123456789abcdef";
    const std::string IV16 = "abcdef9876543210";
    // IV16 的 hex：标签里放的是「输入编码名」，值固定 hex（Web 版如此）
    const std::string IV16_HEX = "61626364656639383736353433323130";

    // 取 data 里的字符串字段，缺失时返回占位符（失败用例的消息里不会因为缺字段而抛异常）
    auto js = [](const ToolResult& t, const char* k) -> std::string {
      if (t.data.is_object() && t.data.contains(k) && t.data[k].is_string())
        return t.data[k].get<std::string>();
      return "<none>";
    };
    auto encHex = [&](const std::string& key, const std::string& iv, const std::string& pt,
                      const std::string& mode) {
      json args = {{"action","encrypt"},{"text",pt},{"key",key},{"mode",mode},
                   {"output_encoding","hex"}};
      if (!iv.empty()) args["iv"] = iv;
      return eng.call("aes_crypto", args);
    };

    // ---- CBC：128 / 192 / 256 位，11 字节明文 → PKCS#7 补到 16 字节 ----
    auto r = encHex(K128, IV16, "hello world", "cbc");
    CHECK(r.ok && js(r,"ciphertext")=="4dc2f2b42aab28100de8f7e16a71291b",
          "AES-128-CBC 密文逐字节相同: " + js(r,"ciphertext"));
    CHECK(r.text.find("模式 AES-128-CBC")!=std::string::npos, "CBC 文案模式名大写: " + r.text);
    CHECK(r.text.find("iv(utf8) "+IV16_HEX)!=std::string::npos,
          "CBC 文案 iv 行标签用输入编码、值用 hex");

    r = encHex(K192, IV16, "hello world", "cbc");
    CHECK(r.ok && js(r,"ciphertext")=="7bee3dec735db46ead387639925070fb", "AES-192-CBC 密文相同: " + js(r,"ciphertext"));
    r = encHex(K256, IV16, "hello world", "cbc");
    CHECK(r.ok && js(r,"ciphertext")=="e21532781397a447fe75577402519b54", "AES-256-CBC 密文相同: " + js(r,"ciphertext"));

    // ---- ECB：无 iv ----
    r = encHex(K128, "", "hello world", "ecb");
    CHECK(r.ok && js(r,"ciphertext")=="8169bed4ef49a8874559c5b200daade7", "AES-128-ECB 密文相同: " + js(r,"ciphertext"));
    CHECK(r.data.is_object() && r.data["iv"].is_null(), "ECB 不返回 iv");
    r = encHex(K256, "", "hello world", "ecb");
    CHECK(r.ok && js(r,"ciphertext")=="29ab5c74f8bbebab1840f68ef86e645c", "AES-256-ECB 密文相同: " + js(r,"ciphertext"));

    // ---- 多块 CBC：32 字节明文 → 3 块 48 字节 ----
    r = encHex(K128, IV16, "0123456789abcdef0123456789abcdef", "cbc");
    CHECK(r.ok && r.data.contains("bytes") && r.data["bytes"]==48,
          "多块 CBC 密文 48 字节: " + js(r,"ciphertext"));
    CHECK(js(r,"ciphertext")=="2b6b52583127176effa0dd59361f7e157c31ec3f7330e4a856c6b8234e92edde797950d1913eb35f6d81351847393a3f",
          "多块 CBC 密文相同");

    // ---- UTF-8 中文明文（验证按字节而非字符喂给 EVP）----
    r = encHex(K128, IV16, "你好，世界", "cbc");
    CHECK(r.ok && js(r,"ciphertext")=="beb92ac1030044fc60fc7f85c57d15b7", "中文明文 CBC 密文相同: " + js(r,"ciphertext"));

    // ---- 默认输出 base64 ----
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","hello world"},{"key",K128},
                               {"iv",IV16},{"mode","cbc"}});
    CHECK(r.ok && js(r,"ciphertext")=="TcLytCqrKBAN6PfhanEpGw==", "CBC 默认输出 base64: " + js(r,"ciphertext"));
    CHECK(r.text.find("密文(base64) TcLytCqrKBAN6PfhanEpGw==")!=std::string::npos, "CBC 文案 base64 密文行");

    // ---- key / iv 的 hex 与 base64 编码应得到同一密文 ----
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","hello world"},
                               {"key","30313233343536373839616263646566"},{"key_encoding","hex"},
                               {"iv",IV16_HEX},{"iv_encoding","hex"},
                               {"mode","cbc"},{"output_encoding","hex"}});
    CHECK(r.ok && js(r,"ciphertext")=="4dc2f2b42aab28100de8f7e16a71291b", "hex 编码的 key/iv 结果相同: " + js(r,"ciphertext"));
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","hello world"},
                               {"key","MDEyMzQ1Njc4OWFiY2RlZg=="},{"key_encoding","base64"},
                               {"iv",IV16},{"mode","cbc"},{"output_encoding","hex"}});
    CHECK(r.ok && js(r,"ciphertext")=="4dc2f2b42aab28100de8f7e16a71291b", "base64 编码的 key 结果相同: " + js(r,"ciphertext"));

    // ---- 解密往返 ----
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text","4dc2f2b42aab28100de8f7e16a71291b"},
                               {"input_encoding","hex"},{"key",K128},{"iv",IV16},{"mode","cbc"}});
    CHECK(r.ok && r.text=="hello world", "CBC 解密往返(hex 进): " + r.text);
    CHECK(js(r,"hex")=="68656c6c6f20776f726c64", "解密返回明文 hex: " + js(r,"hex"));
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text","TcLytCqrKBAN6PfhanEpGw=="},
                               {"key",K128},{"iv",IV16},{"mode","cbc"}});
    CHECK(r.ok && r.text=="hello world", "CBC 解密往返(base64 进): " + r.text);
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text","8169bed4ef49a8874559c5b200daade7"},
                               {"input_encoding","hex"},{"key",K128},{"mode","ecb"}});
    CHECK(r.ok && r.text=="hello world", "ECB 解密往返: " + r.text);

    // ---- GCM 用例 2（全零 key / iv / 16 字节全零明文，McGrew-Viega）----
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text",std::string(16,'\0')},
                               {"key",std::string(16,'\0')},{"iv",std::string(12,'\0')},
                               {"mode","gcm"},{"output_encoding","hex"}});
    CHECK(r.ok && js(r,"ciphertext")=="0388dace60b6a392f328c2b971b2fe78", "GCM 用例2 密文相同: " + js(r,"ciphertext"));
    CHECK(js(r,"tag")=="q25H1CzsE731OmeyEle93w==",
          "GCM 用例2 tag 相同（base64 of ab6e47d4…bddf）: " + js(r,"tag"));
    CHECK(r.text.find("tag(base64) ")!=std::string::npos, "GCM 文案带 tag 行");

    // ---- GCM：hello world，key 16 字节 / iv 12 字节 ----
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","hello world"},{"key",K128},
                               {"iv","abcdef987654"},{"mode","gcm"},{"output_encoding","hex"}});
    CHECK(r.ok && js(r,"ciphertext")=="0b8bd522fb8d72557a93b2", "GCM 密文相同: " + js(r,"ciphertext"));
    CHECK(js(r,"tag")=="5svflvibIrc56cVV3FJFYw==", "GCM tag 相同: " + js(r,"tag"));
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text","0b8bd522fb8d72557a93b2"},
                               {"input_encoding","hex"},{"key",K128},{"iv","abcdef987654"},
                               {"mode","gcm"},{"tag","5svflvibIrc56cVV3FJFYw=="}});
    CHECK(r.ok && r.text=="hello world", "GCM 解密往返: " + r.text);

    // ---- GCM 多块：60 字节明文（4 块），key/iv 走 hex 编码 ----
    // 工具的 text 参数是 UTF-8 明文字符串（没有 text_encoding），所以这里用 60 个 ASCII 字符，
    // 期望值同样由 node 现算。
    const std::string PT60 = "012345678901234567890123456789012345678901234567890123456789";
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text",PT60},
                               {"key","feffe9928665731c6d6a8f9467308308"},{"key_encoding","hex"},
                               {"iv","cafebabefacedbaddecaf888"},{"iv_encoding","hex"},
                               {"mode","gcm"},{"output_encoding","hex"}});
    CHECK(r.ok && js(r,"ciphertext")==
          "ab831ed4edc644f6d61218431916c633533ab045090761092fb878299ba41b6d"
          "0fda2c12f739a2766271564dd117291792f0d6fdf2347ef5b10ca391",
          "GCM 多块密文相同: " + js(r,"ciphertext"));
    CHECK(js(r,"tag")=="8xrLRebsi1PTHAMwAnFeOQ==", "GCM 多块 tag 相同: " + js(r,"tag"));
    // 密文是 hex、tag 是 base64 的混合编码也要能自洽解开（tag 兜底按 base64 重解）
    r = eng.call("aes_crypto", {{"action","decrypt"},
                               {"text","53df8b7da098330d30c6e6ef7cdc59389ecf0a09dbb58617ad2dac0c17205bf6"
                                        "b89e0f8d851eceaaa0eedf9ba9c91eeee6baeeaee0726421444c6239"},
                               {"input_encoding","hex"},{"key",K128},{"iv","abcdef987654"},
                               {"mode","gcm"},{"tag","aKNO173xaZbwollMsm0pmg=="}});
    CHECK(r.ok && r.text==PT60, "GCM 解密往返（密文 hex + tag base64）: " + r.text);

    // ---- 256 位 GCM ----
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","hello world"},{"key",K256},
                               {"iv","abcdef987654"},{"mode","gcm"},{"output_encoding","hex"}});
    CHECK(r.ok && js(r,"ciphertext")=="b78c4d78a839c17a203941", "AES-256-GCM 密文相同: " + js(r,"ciphertext"));

    // ---- 错误分支 ----
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","x"},{"key","too-short-key"},
                               {"iv",IV16},{"mode","cbc"}});
    CHECK(!r.ok && r.text.find("16/24/32")!=std::string::npos, "key 长度非法报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","x"},{"key",K128},{"mode","cbc"}});
    CHECK(!r.ok && r.text.find("需要 iv")!=std::string::npos, "CBC 缺 iv 报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","x"},{"key",K128},{"iv","short"},{"mode","cbc"}});
    CHECK(!r.ok && r.text.find("16 字节")!=std::string::npos, "CBC iv 长度非法报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text","0b8bd522fb8d72557a93b2"},
                               {"input_encoding","hex"},{"key",K128},{"iv","abcdef987654"},{"mode","gcm"}});
    CHECK(!r.ok && r.text.find("需要 tag")!=std::string::npos, "GCM 解密缺 tag 报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text","0b8bd522fb8d72557a93b2"},
                               {"input_encoding","hex"},{"key",K128},{"iv","abcdef987654"},
                               {"mode","gcm"},{"tag","e6cbdf96f89b22b739e9c555dc524562"}});
    CHECK(!r.ok && r.text.find("解密失败")!=std::string::npos, "GCM tag 被改报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text","4dc2f2b42aab28100de8f7e16a71291c"},
                               {"input_encoding","hex"},{"key",K128},{"iv",IV16},{"mode","cbc"}});
    CHECK(!r.ok && r.text.find("解密失败")!=std::string::npos, "CBC 密文被改报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","x"},{"key",K128},{"iv",IV16},{"mode","xts"}});
    CHECK(!r.ok && r.text.find("cbc / gcm / ecb")!=std::string::npos, "mode 非法报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","sign"},{"text","x"},{"key",K128}});
    CHECK(!r.ok && r.text.find("encrypt 或 decrypt")!=std::string::npos, "action 非法报错: " + r.text);
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text","x"},{"key","zzzzzzzzzzzzzzzz"},
                               {"key_encoding","hex"},{"iv",IV16},{"mode","cbc"}});
    CHECK(!r.ok, "key 含非法 hex 报错: " + r.text);

    // ---- 解密出非 UTF-8 字节时要给提示 ----
    r = eng.call("aes_crypto", {{"action","encrypt"},{"text",std::string("\xff\xfe\xfd\xfc",4)},
                               {"key",K128},{"iv",IV16},{"mode","cbc"},{"output_encoding","hex"}});
    CHECK(r.ok, "二进制明文可加密: " + r.text);
    r = eng.call("aes_crypto", {{"action","decrypt"},{"text",js(r,"ciphertext")},
                               {"input_encoding","hex"},{"key",K128},{"iv",IV16},{"mode","cbc"}});
    CHECK(r.ok && r.text.find("不是合法 UTF-8")!=std::string::npos, "非法 UTF-8 明文有提示: " + r.text);
  }
  std::cout << "=== 网络 / 系统类工具 ===\n";
  {
    auto js = [](const ToolResult& t, const char* k) -> std::string {
      if (t.data.is_object() && t.data.contains(k) && t.data[k].is_string())
        return t.data[k].get<std::string>();
      return "<none>";
    };

    // dns_lookup：localhost 一定在 hosts 里，不依赖外网
    auto r = eng.call("dns_lookup", {{"hostname","localhost"}});
    CHECK(r.ok && r.data.contains("addresses") && r.data["addresses"].is_array() && !r.data["addresses"].empty(),
          "dns_lookup localhost 有结果: " + r.text);
    CHECK(r.text.find("IPv4")!=std::string::npos, "dns_lookup 输出含 IPv4 行");
    r = eng.call("dns_lookup", {{"hostname","localhost"},{"family",4}});
    CHECK(r.ok, "dns_lookup family=4: " + r.text);
    {
      bool onlyV4 = true;
      for (auto& e : r.data["addresses"]) if (e["family"] != 4) onlyV4 = false;
      CHECK(onlyV4, "family=4 只返回 IPv4");
    }
    r = eng.call("dns_lookup", {{"hostname",""}});
    CHECK(!r.ok && r.text.find("hostname")!=std::string::npos, "dns_lookup 缺 hostname 报错");
    r = eng.call("dns_lookup", {{"hostname","this-host-should-not-exist.invalid"}});
    CHECK(!r.ok && r.text.find("失败")!=std::string::npos, "dns_lookup 不存在的域名报错: " + r.text);

    // port_check：先自己开一个监听端口，验证「可连通」这条分支
#if defined(_WIN32)
    WSADATA wsa; WSAStartup(MAKEWORD(2,2), &wsa);
#endif
    int lfd = (int)::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    int listenPort = 0;
    if (lfd >= 0) {
      sockaddr_in sa;
      std::memset(&sa, 0, sizeof(sa));
      sa.sin_family = AF_INET;
      sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      sa.sin_port = 0;  // 让系统分配
      if (::bind(lfd, (sockaddr*)&sa, sizeof(sa)) == 0 && ::listen(lfd, 8) == 0) {
        sockaddr_in got;
        socklen_t gl = sizeof(got);
        if (::getsockname(lfd, (sockaddr*)&got, &gl) == 0) listenPort = ntohs(got.sin_port);
      }
    }
    if (listenPort > 0) {
      r = eng.call("port_check", {{"host","127.0.0.1"},{"port",listenPort},{"timeout_ms",2000}});
      CHECK(r.ok && r.data["reachable"]==true, "port_check 连上监听端口: " + r.text);
      CHECK(r.text.find("可连通")!=std::string::npos, "port_check 可连通文案");
#if defined(_WIN32)
      ::closesocket(lfd);
#else
      ::close(lfd);
#endif
      // 端口关掉后再探一次，应报不可达（连接被拒绝）
      r = eng.call("port_check", {{"host","127.0.0.1"},{"port",listenPort},{"timeout_ms",2000}});
      CHECK(r.ok && r.data["reachable"]==false, "port_check 端口关闭后不可达: " + r.text);
    } else {
      std::cout << "  skip: 本机无法开监听端口，跳过 port_check 正向用例\n";
    }
    r = eng.call("port_check", {{"host","127.0.0.1"},{"port",0}});
    CHECK(!r.ok && r.text.find("1-65535")!=std::string::npos, "port_check 非法端口报错");
    r = eng.call("port_check", {{"port",80}});
    CHECK(!r.ok && r.text.find("host")!=std::string::npos, "port_check 缺 host 报错");

    // local_ip：正常机器至少有回环
    r = eng.call("local_ip", {{}});
    CHECK(r.ok, "local_ip 返回成功");
    CHECK(r.data.contains("interfaces") && r.data["interfaces"].is_array(), "local_ip 返回接口数组");
    CHECK(r.text.find("127.0.0.1")!=std::string::npos, "local_ip 至少列出回环: " + r.text);
    {
      bool hasInternalFlag = false;
      for (auto& e : r.data["interfaces"]) if (e.contains("internal")) hasInternalFlag = true;
      CHECK(hasInternalFlag, "local_ip 每条带 internal 标记");
    }
    (void)js;
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
