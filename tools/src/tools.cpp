// 内置工具引擎实现：对照 Web 版 tools-browser.js。
#include "tools.hpp"
#include "crypto-tools.hpp"
#include "qr-core.hpp"
#include "text-tools.hpp"
#include "util.hpp"
#include "crypto.hpp"   // sha256hex
#include <cmath>
#include <sstream>
#include <iomanip>
#include <regex>
#include <algorithm>
#include <random>
#include <fstream>
#include <cctype>
#include <unordered_map>

namespace ds {

ToolEngine& ToolEngine::instance() { static ToolEngine e; return e; }

bool ToolEngine::loadDefinitions(const std::string& path, std::string* err) {
  std::ifstream f(path, std::ios::binary);
  if (!f) { if (err) *err = "无法打开工具定义: " + path; return false; }
  try {
    f >> defs_;
  } catch (const std::exception& ex) { if (err) *err = std::string("工具定义解析失败: ") + ex.what(); return false; }
  return true;
}

std::vector<std::string> ToolEngine::names() const {
  std::vector<std::string> out;
  for (const auto& d : defs_)
    if (d.contains("function") && d["function"].contains("name"))
      out.push_back(d["function"]["name"].get<std::string>());
  return out;
}

// 工具检索关键词（对照 Web 版 server/tools-core.cjs 的 FIND_TOOL_KEYS）
static const std::unordered_map<std::string, std::vector<std::string>>& toolKeys() {
  static const std::unordered_map<std::string, std::vector<std::string>> K = {
    {"get_balance", {"余额","充值","欠费","账户余额","还有多少钱"}},
    {"list_models", {"模型列表","有哪些模型","可用模型","模型版本"}},
    {"current_time", {"几点","现在时间","今天几号","星期几","时区"}},
    {"search_history", {"历史对话","之前聊过","以前问过","找对话"}},
    {"usage_stats", {"用量统计","消耗token","总共用了","累计token"}},
    {"web_search", {"搜索","联网","新闻","最新消息","查一下","天气","实时"}},
    {"fetch_url", {"打开网址","抓取网页","读网页","这个链接","读取网页"}},
    {"calculator", {"计算","算一下","帮我算","等于多少","表达式","算账","运算"}},
    {"hash_text", {"哈希","md5","sha1","sha256","sha512","摘要","校验值"}},
    {"base64_codec", {"base64","编码","解码"}},
    {"url_codec", {"url编码","url解码","转义","百分号"}},
    {"json_format", {"json格式","格式化json","美化json","解析json"}},
    {"text_stats", {"字数","多少字","字符数","行数","统计文本"}},
    {"uuid_gen", {"uuid","唯一id","guid","随机id"}},
    {"random_pick", {"随机","抽签","抽取","抽奖","掷骰子"}},
    {"dns_lookup", {"dns","解析域名","域名解析","查ip"}},
    {"port_check", {"端口","端口通不通","能否连接","服务在线"}},
    {"http_request", {"调接口","发请求","http请求","get请求","post请求","状态码"}},
    {"local_ip", {"本机ip","我的ip","网卡地址","局域网ip"}},
    {"base_convert", {"进制转换","二进制","十六进制","八进制","十进制转"}},
    {"percentage", {"百分比","打几折","折扣","增长率","占比"}},
    {"date_diff", {"相差多少天","倒计时","日期差","过去多久"}},
    {"unit_convert", {"单位换算","公里换","英里","公斤","摄氏度","温度换算"}},
    {"regex_test", {"正则","regex","正则表达式","匹配提取"}},
    {"diff_text", {"对比差异","文本对比","比较区别","改了什么","diff"}},
    {"csv_json", {"csv","表格转","csv转json","表格数据"}},
    {"slugify", {"slug","生成别名","友好url","标题转链接"}},
    {"password_gen", {"生成密码","随机密码","强密码","password"}},
    {"id_validator", {"验证身份证","校验身份证","手机号合法","邮箱合法"}},
    {"timestamp_convert", {"时间戳","timestamp","unix时间","毫秒转","秒转日期"}},
    {"json_minify", {"压缩json","json压缩","json一行"}},
    {"token_count", {"多少token","token数","分词","计费token","token消耗"}},
    {"qr_text", {"二维码","qr","扫码","生成二维码","二维码图片"}},
    {"stat_calc", {"统计","平均值","均值","中位数","标准差","方差","分位数","异常值","算一下平均"}},
    {"hex_view", {"十六进制","hex","hexdump","字节查看","二进制查看","xxd","转hex"}},
    {"color_convert", {"颜色转换","色值","hex颜色","rgb转","hsl","对比度","配色","颜色代码"}},
    {"text_kit", {"去重","排序","清洗文本","清理空行","加前缀","拆列","命名风格","驼峰","下划线命名","case转换"}},
    {"aes_crypto", {"aes","加解密","对称加密","encrypt","decrypt","cbc","gcm","加密参数","解密密文"}},
    {"cmd_run", {"执行命令","cmd","运行命令","本机命令"}},
  };
  return K;
}

std::vector<std::pair<std::string, json>> ToolEngine::search(const std::string& query, int topK) {
  std::string q = util::trim(query);
  std::transform(q.begin(), q.end(), q.begin(), [](unsigned char c){ return std::tolower(c); });
  // 去掉标点，保留中英文数字（用于 2-gram 模糊命中）
  std::string qChars;
  for (unsigned char c : q) if (std::isalnum(c) || c >= 0x80) qChars += (char)c;
  std::vector<std::pair<double, std::pair<std::string, json>>> scored;
  for (const auto& d : defs_) {
    if (!d.contains("function")) continue;
    const auto& fn = d["function"];
    std::string name = fn.value("name", "");
    std::string desc = fn.value("description", "");
    std::string hay = name + " " + desc;
    std::transform(hay.begin(), hay.end(), hay.begin(), [](unsigned char c){ return std::tolower(c); });
    double score = 0;
    // 整词/子串命中（对照 Web 版 strongHit）
    if (hay.find(q) != std::string::npos && !q.empty()) score += q.size() >= 4 ? 12 : 8;
    // 关键词表命中 + 中文 2-gram 容忍口语变体
    auto itk = toolKeys().find(name);
    if (itk != toolKeys().end()) {
      for (const auto& kwRaw : itk->second) {
        std::string kw = kwRaw;
        std::transform(kw.begin(), kw.end(), kw.begin(), [](unsigned char c){ return std::tolower(c); });
        if (q.find(kw) != std::string::npos) { score += kw.size() >= 4 ? 12 : 8; continue; }
        // 中文关键词长度>=3：拆成 2-gram，命中多数即算部分匹配
        if (kw.size() >= 3 && (kw[0] & 0x80)) {
          int grams = 0, hit = 0;
          for (size_t i = 0; i + 1 < kw.size(); i += (kw[i] & 0x80) ? 3 : 1) {
            if (i + 1 >= kw.size()) break;
            std::string g = kw.substr(i, (kw[i] & 0x80) ? 6 : 2);
            grams++;
            if (qChars.find(g) != std::string::npos || q.find(g) != std::string::npos) hit++;
          }
          if (grams > 0 && hit >= std::max(2, grams - 1)) score += 5;
        }
      }
    }
    // 弱匹配：查询词片段命中描述
    std::istringstream iss(q); std::string word;
    while (iss >> word) if (word.size() >= 2 && hay.find(word) != std::string::npos) score += 1;
    // 工具名被完整提及强命中
    if (!name.empty() && q.find(name) != std::string::npos) score += 10;
    if (score > 0) scored.push_back({score, {name, fn}});
  }
  std::sort(scored.begin(), scored.end(), [](const auto& a, const auto& b){ return a.first > b.first; });
  std::vector<std::pair<std::string, json>> out;
  for (int i = 0; i < topK && i < (int)scored.size(); i++) out.push_back(scored[i].second);
  return out;
}

// ------------------------------ 辅助 ------------------------------
static std::string sarg(const json& a, const char* k, const std::string& def = "") {
  if (!a.contains(k)) return def;
  if (a[k].is_string()) return a[k].get<std::string>();
  if (a[k].is_null()) return def;
  return a[k].dump();
}
static double darg(const json& a, const char* k, double def = 0) {
  if (!a.contains(k)) return def;
  if (a[k].is_number()) return a[k].get<double>();
  if (a[k].is_string()) { try { return std::stod(a[k].get<std::string>()); } catch (...) { return def; } }
  return def;
}
static int iarg(const json& a, const char* k, int def = 0) { return (int)darg(a, k, def); }
static bool barg(const json& a, const char* k, bool def = false) {
  if (!a.contains(k)) return def;
  if (a[k].is_boolean()) return a[k].get<bool>();
  return def;
}
static ToolResult fail(const std::string& msg) { ToolResult r; r.ok=false; r.text=msg; return r; }
static ToolResult ok(const std::string& text, json data = json::object()) {
  ToolResult r; r.ok=true; r.text=text; r.data=data.empty()?json::object():data; return r;
}
static std::string fmtNum(double v, int prec = 6) {
  if (!std::isfinite(v)) return "NaN";
  std::ostringstream os; os << std::setprecision(prec) << v;
  return os.str();
}

// 安全的表达式求值（对照 evalArithmetic：数字/四则/括号/常见函数）
static double evalExpr(const std::string& raw) {
  // 极简递归下降解析器，避免用 new Function（C++ 没有）
  std::string s;
  for (char c : raw) if (!std::isspace((unsigned char)c)) s += c;
  size_t pos = 0;
  // 用函数对象递归
  struct Parser {
    const std::string& s; size_t& pos;
    double primary() {
      if (pos >= s.size()) throw std::runtime_error("表达式不完整");
      char c = s[pos];
      if (c == '(') { pos++; double v = expr(0); if (pos >= s.size() || s[pos] != ')') throw std::runtime_error("括号不匹配"); pos++; return v; }
      if (c == '-') { pos++; return -primary(); }
      if (c == '+') { pos++; return primary(); }
      size_t start = pos;
      while (pos < s.size() && (std::isalnum((unsigned char)s[pos]) || s[pos]=='.')) pos++;
      std::string tok = s.substr(start, pos - start);
      // 函数调用（支持逗号分隔的多参数：pow/min/max）
      if (pos < s.size() && s[pos] == '(') {
        pos++;
        std::vector<double> args;
        if (pos < s.size() && s[pos] != ')') {
          while (true) {
            args.push_back(expr(0));
            if (pos < s.size() && s[pos] == ',') { pos++; continue; }
            break;
          }
        }
        if (pos >= s.size() || s[pos] != ')') throw std::runtime_error("函数括号不匹配");
        pos++;
        auto a0 = [&]() -> double { return args.empty() ? 0 : args[0]; };
        if (tok=="sqrt") return std::sqrt(a0());
        if (tok=="abs") return std::abs(a0());
        if (tok=="sin") return std::sin(a0());
        if (tok=="cos") return std::cos(a0());
        if (tok=="tan") return std::tan(a0());
        if (tok=="log") return std::log(a0());
        if (tok=="log10") return std::log10(a0());
        if (tok=="exp") return std::exp(a0());
        if (tok=="round") return std::round(a0());
        if (tok=="floor") return std::floor(a0());
        if (tok=="ceil") return std::ceil(a0());
        if (tok=="factorial") { double r=1; for (int i=2;i<=a0();i++) r*=i; return r; }
        if (tok=="pow") { if (args.size()<2) throw std::runtime_error("pow 需要 2 个参数"); return std::pow(args[0],args[1]); }
        if (tok=="min") { if (args.empty()) throw std::runtime_error("min 缺少参数"); double r=args[0]; for (double v:args) r=std::min(r,v); return r; }
        if (tok=="max") { if (args.empty()) throw std::runtime_error("max 缺少参数"); double r=args[0]; for (double v:args) r=std::max(r,v); return r; }
        throw std::runtime_error("未知函数: " + tok);
      }
      if (tok == "PI" || tok == "pi") return M_PI;
      if (tok == "E") return M_E;
      try { size_t used=0; double v=std::stod(tok, &used); if (used==tok.size()) return v; } catch (...) {}
      throw std::runtime_error("无法解析: " + tok);
    }
    static int prec(char op) { if (op=='+'||op=='-') return 1; if (op=='*'||op=='/'||op=='%') return 2; if (op=='^') return 3; return -1; }
    double expr(int minPrec) {
      double lhs = primary();
      while (pos < s.size()) {
        char op = s[pos]; int p = prec(op);
        if (p < minPrec || p < 0) break;
        pos++;
        double rhs = (op == '^') ? expr(p) : expr(p + 1);
        switch (op) {
          case '+': lhs += rhs; break;
          case '-': lhs -= rhs; break;
          case '*': lhs *= rhs; break;
          case '/': if (rhs == 0) throw std::runtime_error("除数不能为 0"); lhs /= rhs; break;
          case '%': if ((int)rhs == 0) throw std::runtime_error("模数不能为 0"); lhs = (int)lhs % (int)rhs; break;
          case '^': lhs = std::pow(lhs, rhs); break;
        }
      }
      return lhs;
    }
  };
  Parser p{s, pos};
  double v = p.expr(0);
  if (pos != s.size()) throw std::runtime_error("表达式含无法解析的部分: " + s.substr(pos));
  return v;
}

// ------------------------------ 工具实现 ------------------------------
static ToolResult callImpl(const std::string& name, const json& a, const ToolContext& ctx) {
  // --- 需要 API 的工具 ---
  if (name == "get_balance") {
    if (!ctx.getBalance) return fail("余额查询不可用");
    std::string err; Balance b = ctx.getBalance(ctx.apiKey, &err);
    if (!err.empty() && b.raw.empty()) return fail("查询失败：" + err);
    std::string text = "账户可用：" + std::string(b.available ? "是" : "否（余额不足或账号受限）");
    if (b.raw.contains("balance_infos") && b.raw["balance_infos"].is_array())
      for (const auto& bi : b.raw["balance_infos"])
        text += "\n" + bi.value("currency","") + " 总余额 " + bi.value("total_balance","") +
                "（赠金 " + bi.value("granted_balance","") + "，充值 " + bi.value("topped_up_balance","") + "）";
    return ok(text, b.raw);
  }
  if (name == "list_models") {
    if (!ctx.listModels) return fail("模型列表不可用");
    std::string err; auto models = ctx.listModels(ctx.apiKey, &err);
    std::string text;
    for (const auto& m : models) {
      std::string ctxn = m.contextWindow ? (std::to_string(m.contextWindow / 1024) + "K") : "未知";
      text += "- " + m.id + "（" + m.name + "）：上下文 " + ctxn + "\n";
    }
    json arr = json::array(); for (auto& m : models) arr.push_back(m.toJson());
    return ok(text, {{"models", arr}});
  }

  // --- 本地数据工具 ---
  if (name == "current_time") {
    std::time_t t = std::time(nullptr);
    std::tm lt{};
#ifdef _WIN32
    localtime_s(&lt, &t);
#else
    localtime_r(&t, &lt);
#endif
    char buf[64]; std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", &lt);
    static const char* WD[] = {"星期日","星期一","星期二","星期三","星期四","星期五","星期六"};
    std::string iso = buf;
    std::string text = iso + "（" + WD[lt.tm_wday] + "，本机时间）";
    return ok(text, {{"iso", iso}, {"weekday", WD[lt.tm_wday]}});
  }
  if (name == "search_history") {
    std::string q = sarg(a, "query");
    if (q.empty()) return fail("缺少 query 参数。");
    int limit = std::min(20, std::max(1, iarg(a, "limit", 5)));
    std::string lower = q; std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c){return std::tolower(c);});
    json hits = json::array();
    if (ctx.conversations) {
      for (auto& c : ctx.conversations()) {
        std::string title = c.title;
        std::string lowTitle = title; std::transform(lowTitle.begin(), lowTitle.end(), lowTitle.begin(), [](unsigned char x){return std::tolower(x);});
        std::string snippet;
        for (auto& m : c.messages) {
          std::string lc = m.content; std::transform(lc.begin(), lc.end(), lc.begin(), [](unsigned char x){return std::tolower(x);});
          size_t idx = lc.find(lower);
          if (idx != std::string::npos) {
            size_t b = idx > 40 ? idx - 40 : 0;
            snippet = m.content.substr(b, 120);
            break;
          }
        }
        if (lowTitle.find(lower) != std::string::npos || !snippet.empty()) {
          hits.push_back({{"id",c.id},{"title",title.empty()?"(无标题)":title},{"updatedAt",c.updatedAt},{"snippet",snippet}});
        }
        if ((int)hits.size() >= limit) break;
      }
    }
    if (hits.empty()) return ok("没有找到包含「" + q + "」的历史对话。", json::array());
    std::string text;
    for (size_t i = 0; i < hits.size(); i++)
      text += std::to_string(i+1) + ". [" + hits[i]["title"].get<std::string>() + "]" +
              (hits[i]["snippet"].get<std::string>().empty() ? "" : "\n   …" + hits[i]["snippet"].get<std::string>() + "…") + "\n";
    return ok(text, hits);
  }
  if (name == "usage_stats") {
    int convs=0, msgs=0; int64_t prompt=0, completion=0;
    if (ctx.conversations) for (auto& c : ctx.conversations()) {
      convs++;
      for (auto& m : c.messages) {
        msgs++;
        if (m.promptTokens) prompt += *m.promptTokens;
        if (m.completionTokens) completion += *m.completionTokens;
      }
    }
    std::string text = "对话 " + std::to_string(convs) + " 个，消息 " + std::to_string(msgs) + " 条\n累计输入 " +
                       std::to_string(prompt) + " tokens，输出 " + std::to_string(completion) + " tokens";
    return ok(text, {{"conversations",convs},{"messages",msgs},{"prompt",prompt},{"completion",completion}});
  }

  // --- 计算/编码工具 ---
  if (name == "calculator") {
    std::string expr = util::trim(sarg(a, "expression"));
    if (expr.empty()) return fail("缺少 expression 参数。");
    int prec = std::min(12, std::max(0, iarg(a, "precision", 0)));
    try {
      double value = evalExpr(expr);
      std::ostringstream os; os << std::fixed << std::setprecision(prec) << value;
      std::string result = os.str();
      // 去掉尾随 0
      if (result.find('.') != std::string::npos) {
        while (!result.empty() && result.back()=='0') result.pop_back();
        if (!result.empty() && result.back()=='.') result.pop_back();
      }
      return ok(expr + " = " + result, {{"expression",expr},{"value",value}});
    } catch (const std::exception& e) { return fail(std::string("计算失败：") + e.what() + "。表达式 " + expr); }
  }
  if (name == "hash_text") {
    std::string text = sarg(a, "text");
    if (text.empty()) return fail("缺少 text 参数。");
    std::string alg = sarg(a, "algorithm", "sha256");
    std::transform(alg.begin(), alg.end(), alg.begin(), [](unsigned char c){return std::tolower(c);});
    if (alg != "sha256") return fail("C++ 版目前支持 sha256（" + alg + " 暂不支持）。");
    // 用 crypto::sha256hex
    std::string digest = ds::crypto::sha256hex(text);
    return ok(alg + "（" + std::to_string(text.size()) + " 字符）：" + digest, {{"algorithm",alg},{"digest",digest}});
  }
  if (name == "base64_codec") {
    std::string text = sarg(a, "text");
    if (text.empty()) return fail("缺少 text 参数。");
    std::string mode = sarg(a, "mode", "encode");
    if (mode == "encode") {
      std::string out = util::base64Encode(text);
      return ok(out, {{"mode",mode},{"result",out}});
    }
    if (mode == "decode") {
      std::string out = util::base64Decode(text);
      if (out.empty()) return fail("解码结果为空，请确认输入是合法的 Base64。");
      return ok(out, {{"mode",mode},{"result",out}});
    }
    return fail("mode 只能是 encode 或 decode。");
  }
  if (name == "url_codec") {
    std::string text = sarg(a, "text");
    if (text.empty()) return fail("缺少 text 参数。");
    std::string mode = sarg(a, "mode", "encode");
    // decode 需要 URL 解码（简单实现）
    std::string out;
    if (mode == "decode") {
      for (size_t i = 0; i < text.size(); i++) {
        if (text[i]=='%' && i+2 < text.size()) {
          auto hx=[](char c){ return c>='0'&&c<='9'?c-'0':(c>='a'&&c<='f'?c-'a'+10:(c>='A'&&c<='F'?c-'A'+10:0)); };
          out += (char)(hx(text[i+1])*16 + hx(text[i+2])); i += 2;
        } else if (text[i]=='+') out += ' ';
        else out += text[i];
      }
    } else out = util::urlEncode(text);
    return ok(out, {{"mode",mode},{"result",out}});
  }
  if (name == "json_format" || name == "json_minify") {
    std::string raw = util::trim(sarg(a, name=="json_minify"?"json":"json"));
    if (raw.empty()) return fail("缺少 json 参数。");
    try {
      json obj = json::parse(raw);
      if (name == "json_minify") {
        std::string out = obj.dump();
        return ok(out, {{"before",(int)raw.size()},{"after",(int)out.size()},{"saved",(int)raw.size()-(int)out.size()}});
      }
      std::string path = util::trim(sarg(a,"path"));
      json target = obj;
      if (!path.empty()) {
        std::istringstream iss(path); std::string key;
        while (std::getline(iss, key, '.')) {
          if (!target.contains(key)) return fail("路径 " + path + " 不存在（在「" + key + "」处断开）。");
          target = target[key];
        }
      }
      int indent = std::min(8, std::max(0, iarg(a,"indent",2)));
      std::string out = target.is_string() ? target.get<std::string>() : target.dump(indent);
      return ok(out, {{"valid",true}});
    } catch (const std::exception& e) { return fail(std::string("JSON 解析失败：") + e.what()); }
  }
  if (name == "text_stats") {
    std::string text = sarg(a, "text");
    if (text.empty()) return fail("缺少 text 参数。");
    int chars=0, cjk=0, words=0, lines=1;
    bool inWord = false;
    for (size_t i=0;i<text.size();) {
      unsigned char c=(unsigned char)text[i];
      if (c=='\n') { lines++; i++; continue; }
      if (c<0x80) { chars++; if (std::isalnum(c)) { if(!inWord){words++;inWord=true;} } else inWord=false; i++; }
      else if ((c&0xF0)==0xE0) { chars++; cjk++; inWord=false; i+=3; }
      else { chars++; inWord=false; i+=2; }
    }
    std::string t = "字符 " + std::to_string(chars) + "，行数 " + std::to_string(lines) +
                    "，中文汉字 " + std::to_string(cjk) + "，英文/数字词 " + std::to_string(words);
    return ok(t, {{"chars",chars},{"lines",lines},{"cjk",cjk},{"words",words}});
  }
  if (name == "uuid_gen") {
    int count = std::min(50, std::max(1, iarg(a,"count",1)));
    json arr = json::array(); std::string text;
    for (int i=0;i<count;i++) { std::string u=util::uuid(); arr.push_back(u); text += u + "\n"; }
    if (!text.empty()) text.pop_back();
    return ok(text, {{"uuids",arr}});
  }
  if (name == "random_pick") {
    int count = std::min(50, std::max(1, iarg(a,"count",1)));
    static thread_local std::mt19937 rng(std::random_device{}());
    json picks = json::array(); std::string text;
    if (a.contains("items") && a["items"].is_array() && !a["items"].empty()) {
      auto items = a["items"]; int n=(int)items.size(); bool unique=barg(a,"unique");
      if (unique && count > n) return fail("unique=true 时数量不能超过候选数（" + std::to_string(n) + "）。");
      std::vector<int> idx(n); for(int i=0;i<n;i++)idx[i]=i;
      for (int k=0;k<count;k++) {
        int pick = unique ? (std::uniform_int_distribution<int>(0,(int)idx.size()-1)(rng)) : (std::uniform_int_distribution<int>(0,n-1)(rng));
        std::string v = items[unique?idx[pick]:pick].get<std::string>();
        if (unique) idx.erase(idx.begin()+pick);
        picks.push_back(v); text += v + "\n";
      }
    } else {
      int mn=(int)darg(a,"min",1), mx=(int)darg(a,"max",100);
      if (mx < mn) return fail("max 不能小于 min。");
      if (mx - mn > 1e9) return fail("随机范围过大（上限 1e9）。");
      for (int k=0;k<count;k++) { int v=std::uniform_int_distribution<int>(mn,mx)(rng); picks.push_back(v); text+=std::to_string(v)+"\n"; }
    }
    if (!text.empty()) text.pop_back();
    return ok(text, {{"picks",picks}});
  }
  if (name == "base_convert") {
    std::string raw=util::trim(sarg(a,"value"));
    if (raw.empty()) return fail("缺少 value 参数。");
    int from=iarg(a,"from",10), to=iarg(a,"to",16);
    if ((from!=2&&from!=8&&from!=10&&from!=16)||(to!=2&&to!=8&&to!=10&&to!=16)) return fail("进制只能是 2 / 8 / 10 / 16。");
    try {
      long long v=std::stoll(raw,nullptr,from);
      std::string out;
      if (to==10) out=std::to_string(v);
      else { std::ostringstream os; os << std::uppercase << std::setbase(to) << v; out=os.str(); }
      return ok(raw+"（"+std::to_string(from)+" 进制）= "+out+"（"+std::to_string(to)+" 进制）", {{"decimal",v},{"value",out}});
    } catch (...) { return fail("「"+raw+"」不是合法的 "+std::to_string(from)+" 进制数字。"); }
  }
  if (name == "percentage") {
    std::string mode=sarg(a,"mode"); double A=darg(a,"a"), B=darg(a,"b");
    std::string text; double value=0;
    if (mode=="ratio") { if(B==0) return fail("分母 b 不能为 0。"); value=A/B*100; text=fmtNum(A)+" 占 "+fmtNum(B)+" 的 "+fmtNum(value)+"%"; }
    else if (mode=="growth") { if(A==0) return fail("原值 a 不能为 0。"); value=(B-A)/A*100; text="从 "+fmtNum(A)+" 到 "+fmtNum(B)+"，"+(value>=0?"增长 ":"下降 ")+fmtNum(std::abs(value))+"%"; }
    else if (mode=="discount") { if(B<0||B>100) return fail("折扣 b 应在 0-100 之间。"); value=A*B/100; text="原价 "+fmtNum(A)+" 打 "+fmtNum(B/10)+" 折 = "+fmtNum(value); }
    else if (mode=="increase") { value=A*(1+B/100); text=fmtNum(A)+" 增加 "+fmtNum(B)+"% = "+fmtNum(value); }
    else return fail("mode 只能是 ratio / growth / discount / increase。");
    return ok(text, {{"mode",mode},{"value",value}});
  }
  if (name == "unit_convert") {
    double value=darg(a,"value"); std::string from=sarg(a,"from"), to=sarg(a,"to");
    std::transform(from.begin(),from.end(),from.begin(),[](unsigned char c){return std::tolower(c);});
    std::transform(to.begin(),to.end(),to.begin(),[](unsigned char c){return std::tolower(c);});
    struct U { const char* name; double factor; };
    static const std::vector<std::vector<U>> GROUPS = {
      {{"km",1000},{"m",1},{"cm",0.01},{"mm",0.001},{"inch",0.0254},{"ft",0.3048},{"mile",1609.344}},
      {{"kg",1},{"g",0.001},{"mg",0.000001},{"lb",0.45359237},{"oz",0.028349523125}},
      {{"b",1},{"byte",1},{"kb",1024},{"mb",1048576},{"gb",1073741824},{"tb",1099511627776}},
      {{"s",1},{"sec",1},{"min",60},{"h",3600},{"hour",3600},{"d",86400},{"day",86400}},
    };
    for (const auto& g : GROUPS) {
      double ff=NAN, tf=NAN;
      for (const auto& u : g) { if (from==u.name) ff=u.factor; if (to==u.name) tf=u.factor; }
      if (std::isfinite(ff) && std::isfinite(tf)) {
        double out=value*ff/tf;
        return ok(fmtNum(value)+" "+from+" = "+fmtNum(out)+" "+to, {{"value",out}});
      }
    }
    return fail("不支持的单位组合 " + from + " → " + to + "。");
  }
  if (name == "token_count") {
    std::string text=sarg(a,"text");
    if (text.empty()) return fail("缺少 text 参数。");
    int tokens=util::estimateTokens(text);
    return ok("字符数："+std::to_string(text.size())+"\n估算 Token 数："+std::to_string(tokens)+"（字符估算，非官方分词器）", {{"tokens",tokens},{"estimated",true}});
  }
  if (name == "find_tool") {
    std::string query=sarg(a,"query"), action=sarg(a,"action");
    bool isList = action=="list" || barg(a,"list");
    if (isList) {
      auto ns = ToolEngine::instance().names(); std::string text="可用工具共 "+std::to_string(ns.size())+" 个：\n\n";
      for (auto& n : ns) text += "- " + n + "\n";
      return ok(text, {{"action","list"},{"count",(int)ns.size()}});
    }
    if (query.empty()) return fail("缺少 query 参数。想列出全部工具请传 action=\"list\"。");
    int topK=std::min(10,std::max(1,iarg(a,"top_k",5)));
    auto hits=ToolEngine::instance().search(query,topK);
    if (hits.empty()) return fail("没有找到与「"+query+"」相关的工具。");
    std::string text; json arr=json::array();
    for (auto& hit : hits) {
      text += "### " + hit.first + "\n" + hit.second.value("description","") + "\n\n";
      arr.push_back(hit.first);
    }
    return ok("找到 "+std::to_string(hits.size())+" 个相关工具：\n\n"+text, {{"names",arr}});
  }
  if (name == "password_gen") {
    int length=std::min(128,std::max(4,iarg(a,"length",16))), count=std::min(20,std::max(1,iarg(a,"count",1)));
    std::string pool;
    if (barg(a,"upper",true)) pool += "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    if (barg(a,"lower",true)) pool += "abcdefghijklmnopqrstuvwxyz";
    if (barg(a,"digits",true)) pool += "0123456789";
    if (barg(a,"symbols",true)) pool += "!@#$%^&*()-_=+[]{};:,.?/";
    if (pool.empty()) return fail("至少启用一种字符集。");
    static thread_local std::mt19937 rng(std::random_device{}());
    json arr=json::array(); std::string text;
    for (int n=0;n<count;n++) {
      std::string pw;
      for (int i=0;i<length;i++) pw += pool[std::uniform_int_distribution<size_t>(0,pool.size()-1)(rng)];
      arr.push_back(pw); text += pw + "\n";
    }
    if(!text.empty())text.pop_back();
    int entropy=(int)std::round(length*std::log2(pool.size()));
    return ok(text+"\n\n估算熵 "+std::to_string(entropy)+" bit", {{"passwords",arr},{"entropyBits",entropy}});
  }
  if (name == "stat_calc") {
    std::string raw=sarg(a,"numbers");
    if (raw.empty()) return fail("缺少 numbers 参数。");
    std::vector<double> nums;
    // 用正则按分隔符切分
    std::regex sep(R"([\s,;，；、|]+)");
    std::sregex_token_iterator it(raw.begin(), raw.end(), sep, -1), end;
    for (; it != end; ++it) {
      std::string t=it->str(); if(t.empty())continue;
      // 去掉货币符号和百分号
      std::string clean; for(char c:t) if(c!='$'&&c!=','&&c!='%'&&c!=':') clean+=c;
      try { nums.push_back(std::stod(clean)); } catch(...) { return fail("「"+t+"」不是有效数字。"); }
    }
    if (nums.empty()) return fail("没有解析到数字。");
    int n=(int)nums.size(), prec=std::min(10,std::max(0,iarg(a,"precision",4)));
    std::vector<double> sorted=nums; std::sort(sorted.begin(),sorted.end());
    double sum=0; for(double v:nums)sum+=v; double mean=sum/n;
    auto medianOf=[&](const std::vector<double>& v){ int m=(int)v.size(); if(m%2)return v[(m-1)/2]; return (v[m/2-1]+v[m/2])/2; };
    double median=medianOf(sorted), half=n/2;
    double q1=medianOf(std::vector<double>(sorted.begin(),sorted.begin()+half));
    double q3=medianOf(std::vector<double>(sorted.begin()+(n%2?half+1:half),sorted.end()));
    double ss=0; for(double v:nums)ss+=(v-mean)*(v-mean);
    std::string text="个数 "+std::to_string(n)+"\n总和 "+fmtNum(sum,prec)+"\n均值 "+fmtNum(mean,prec)+
                     "\n中位数 "+fmtNum(median,prec)+"\n最小 "+fmtNum(sorted.front(),prec)+"\n最大 "+fmtNum(sorted.back(),prec)+
                     "\n方差(样本) "+fmtNum(n>1?ss/(n-1):0,prec)+"\n标准差(样本) "+fmtNum(n>1?std::sqrt(ss/(n-1)):0,prec)+
                     "\nQ1 "+fmtNum(q1,prec)+"\nQ3 "+fmtNum(q3,prec)+"\nIQR "+fmtNum(q3-q1,prec);
    return ok(text, {{"count",n},{"sum",sum},{"mean",mean},{"median",median}});
  }
  if (name == "date_diff") {
    // 用 time_t 解析 YYYY-MM-DD 或 Unix 秒
    auto parse=[&](const std::string& s)->std::time_t{
      if(s.empty())return std::time(nullptr);
      try { return (std::time_t)std::stoll(s); } catch(...){}
      std::tm tm{};
      if(sscanf(s.c_str(),"%d-%d-%d",&tm.tm_year,&tm.tm_mon,&tm.tm_mday)>=3){tm.tm_year-=1900;tm.tm_mon-=1;return std::mktime(&tm);}
      return std::time(nullptr);
    };
    std::time_t fromT=parse(sarg(a,"from")), toT=parse(sarg(a,"to"));
    double secs=std::difftime(toT,fromT); int64_t ms=(int64_t)secs*1000;
    int64_t absms=ms<0?-ms:ms;
    int64_t days=absms/86400000, hours=(absms%86400000)/3600000, minutes=(absms%3600000)/60000;
    std::string text="相差 "+std::to_string(days)+" 天 "+std::to_string(hours)+" 小时 "+std::to_string(minutes)+" 分钟（"+(ms>=0?"正向":"倒退")+" "+std::to_string((int64_t)(absms/1000))+" 秒）";
    return ok(text, {{"ms",ms},{"days",days},{"hours",hours},{"minutes",minutes}});
  }
  if (name == "timestamp_convert") {
    std::string raw=sarg(a,"value");
    if (raw.empty()) return fail("缺少 value 参数。");
    int64_t ms;
    try {
      if (std::all_of(raw.begin(),raw.end(),[](unsigned char c){return std::isdigit(c);})) {
        long long n=std::stoll(raw); std::string unit=sarg(a,"unit");
        ms = unit=="s" ? n*1000 : (unit=="ms" ? n : (raw.size()<=10 ? n*1000 : n));
      } else return fail("无法解析时间（C++ 版支持 Unix 时间戳）。");
    } catch(...) { return fail("无法解析时间「"+raw+"」。"); }
    std::time_t t=(std::time_t)(ms/1000); std::tm lt{};
#ifdef _WIN32
    localtime_s(&lt,&t);
#else
    localtime_r(&t,&lt);
#endif
    char buf[64]; std::strftime(buf,sizeof(buf),"%Y-%m-%d %H:%M:%S",&lt);
    std::string text="本地："+std::string(buf)+"\nUnix 秒："+std::to_string(ms/1000)+"\nUnix 毫秒："+std::to_string(ms);
    return ok(text, {{"seconds",ms/1000},{"ms",ms}});
  }
  if (name == "diff_text") {
    std::string A=sarg(a,"a"), B=sarg(a,"b");
    // 按行 LCS
    std::vector<std::string> la, lb;
    std::istringstream ia(A), ib(B); std::string line;
    while(std::getline(ia,line))la.push_back(line);
    while(std::getline(ib,line))lb.push_back(line);
    size_t n=la.size(),m=lb.size();
    if(n*m>4000000)return fail("文本行数过多，请先截取。");
    std::vector<std::vector<int>> dp(n+1,std::vector<int>(m+1,0));
    for(int i=(int)n-1;i>=0;i--)for(int j=(int)m-1;j>=0;j--)
      dp[i][j]=la[i]==lb[j]?dp[i+1][j+1]+1:std::max(dp[i+1][j],dp[i][j+1]);
    std::vector<std::string> rows; int same=0,added=0,removed=0; size_t i=0,j=0;
    while(i<n&&j<m){
      if(la[i]==lb[j]){rows.push_back("  "+la[i]);same++;i++;j++;}
      else if(dp[i+1][j]>=dp[i][j+1]){rows.push_back("- "+la[i]);removed++;i++;}
      else{rows.push_back("+ "+lb[j]);added++;j++;}
    }
    while(i<n){rows.push_back("- "+la[i]);removed++;i++;}
    while(j<m){rows.push_back("+ "+lb[j]);added++;j++;}
    bool context=barg(a,"context");
    std::string text="相同 "+std::to_string(same)+" 行，新增 "+std::to_string(added)+" 行，删除 "+std::to_string(removed)+" 行\n\n";
    for(auto& r:rows) if(context||r.rfind("  ",0)!=0) text+=r+"\n";
    return ok(text, {{"same",same},{"added",added},{"removed",removed}});
  }
  if (name == "json_minify") { /* 上面已处理 */ }
  // --- P0 纯字符串类（实现见 tools/src/text-tools.cpp）---
  if (name == "regex_test")    return texttools::regexTest(a);
  if (name == "csv_json")      return texttools::csvJson(a);
  if (name == "slugify")       return texttools::slugify(a);
  if (name == "id_validator")  return texttools::idValidator(a);
  if (name == "hex_view")      return texttools::hexView(a);
  if (name == "color_convert") return texttools::colorConvert(a);
  if (name == "text_kit")      return texttools::textKit(a);
  // --- P1 加解密（实现见 tools/src/crypto-tools.cpp）---
  if (name == "aes_crypto")    return cryptotools::aesCrypto(a);
  if (name == "qr_text") {
    std::string text=util::trim(sarg(a,"text"));
    if(text.empty())return fail("缺少 text 参数。");
    std::string lv=sarg(a,"level","M"); char level=std::toupper(lv[0]);
    if(level!='L'&&level!='M'&&level!='Q'&&level!='H')level='M';
    int scale=std::min(20,std::max(2,iarg(a,"scale",8)));
    if((int)text.size()>qr::QR_INPUT_MAX)return fail("内容 "+std::to_string(text.size())+" 字节，超过上限 "+std::to_string(qr::QR_INPUT_MAX)+" 字节。");
    // 单张：超过容量则按 #i/N 切分
    int cap=qr::qrCapacity(qr::QR_MAX_VERSION,level);
    std::vector<std::string> chunks;
    if((int)text.size()<=cap)chunks.push_back(text);
    else {
      int step=std::max(64,cap-12);
      for(size_t start=0;start<text.size();start+=step)
        chunks.push_back(text.substr(start,step));
    }
    int total=(int)chunks.size(); json images=json::array(); std::string ascii; int version=0,sizeN=0,maskN=0;
    for(int i=0;i<total;i++){
      std::string payload = total>1 ? ("#"+std::to_string(i+1)+"/"+std::to_string(total)+"\n"+chunks[i]) : chunks[i];
      auto q=qr::qrMatrix(payload,level);
      if(q.version==0)return fail("二维码生成失败：内容过长。");
      if(i==0){version=q.version;sizeN=q.size;maskN=q.mask;ascii=qr::qrAscii(q);}
      auto png=qr::qrPng(q,scale,4);
      images.push_back("data:image/png;base64,"+util::base64Encode(std::string(png.begin(),png.end())));
    }
    ToolResult r=ok((total>1?"内容切成 "+std::to_string(total)+" 张二维码（按 #i/N 顺序扫码）：\n":"二维码已生成\n")+
      "规格：版本 "+std::to_string(version)+"，"+std::to_string(sizeN)+"×"+std::to_string(sizeN)+" 模块，纠错 "+level+"级",
      {{"images",images},{"parts",total},{"bytes",(int)text.size()},{"version",version},{"size",sizeN},{"level",std::string(1,level)},{"ascii",ascii}});
    for(auto& im:images)r.images.push_back(im.get<std::string>());
    return r;
  }
  if (name == "web_search" || name == "fetch_url" || name == "http_request" ||
      name == "dns_lookup" || name == "port_check" || name == "local_ip" || name == "cmd_run") {
    return fail("工具「"+name+"」在手机端不可用（联网/系统能力限制）。");
  }
  return fail("未知工具：" + name + "（手机端不可用或已移除）");
}

ToolResult ToolEngine::call(const std::string& name, const json& args, const ToolContext& ctx) {
  try { return callImpl(name, args, ctx); }
  catch (const std::exception& e) { return fail(std::string("工具执行失败：") + e.what()); }
  catch (...) { return fail("工具执行失败：未知错误"); }
}

}  // namespace ds
