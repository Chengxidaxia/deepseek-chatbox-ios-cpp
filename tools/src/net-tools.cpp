// 网络 / 系统类工具：dns_lookup / port_check / local_ip。
// 对照 Web 版 server/tools-core.cjs:1945 / 1959 / 2029。
// 三个工具都不依赖 libcurl：DNS 用 getaddrinfo，端口探测用非阻塞 connect + select，
// 网卡信息用 getifaddrs（Windows 走 GetAdaptersAddresses）。
#include "net-tools.hpp"
#include "util.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
using socklen_type = int;
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
using socklen_type = socklen_t;
#endif

namespace ds {
namespace nettools {
namespace {

using json = nlohmann::json;

std::string sarg(const json& a, const char* k, const std::string& def = "") {
  if (!a.contains(k) || a[k].is_null()) return def;
  if (a[k].is_string()) return a[k].get<std::string>();
  return a[k].dump();
}
ToolResult fail(const std::string& msg) { ToolResult r; r.ok = false; r.text = msg; return r; }
ToolResult ok(const std::string& text, json data = json::object()) {
  ToolResult r; r.ok = true; r.text = text; r.data = data.is_null() ? json::object() : data; return r;
}
long long iarg(const json& a, const char* k, long long def) {
  if (!a.contains(k) || a[k].is_null()) return def;
  if (a[k].is_number()) return a[k].get<long long>();
  if (a[k].is_string()) { try { return std::stoll(a[k].get<std::string>()); } catch (...) { return def; } }
  return def;
}

// ---- 平台初始化 / 清理 ----
#if defined(_WIN32)
using sock_t = SOCKET;
constexpr sock_t kInvalidSock = INVALID_SOCKET;
// WSAStartup 必须在使用任何 socket API 前调用；用局部静态对象做一次，进程退出时清理。
struct WsaGuard {
  WsaGuard() { WSADATA d; started_ = (WSAStartup(MAKEWORD(2, 2), &d) == 0); }
  ~WsaGuard() { if (started_) WSACleanup(); }
  bool started_ = false;
};
bool ensureNetInit() { static WsaGuard g; return g.started_; }
void closeSock(sock_t fd) { ::closesocket(fd); }
#else
using sock_t = int;
constexpr sock_t kInvalidSock = -1;
bool ensureNetInit() { return true; }
void closeSock(sock_t fd) { ::close(fd); }
#endif

bool setNonBlocking(sock_t fd) {
#if defined(_WIN32)
  u_long mode = 1;
  return ioctlsocket(fd, FIONBIO, &mode) == 0;
#else
  int flags = ::fcntl((int)fd, F_GETFL, 0);
  if (flags < 0) return false;
  return ::fcntl((int)fd, F_SETFL, flags | O_NONBLOCK) == 0;
#endif
}

int lastNetError() {
#if defined(_WIN32)
  return WSAGetLastError();
#else
  return errno;
#endif
}

// 非阻塞 connect「还没完成」的判定，Windows 与 POSIX 的错误码不同
bool inProgress(int e) {
#if defined(_WIN32)
  return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS || e == WSAEINVAL;
#else
  return e == EINPROGRESS || e == EWOULDBLOCK || e == EALREADY;
#endif
}

std::string netErrText(int e) {
#if defined(_WIN32)
  switch (e) {
    case WSAECONNREFUSED: return "ECONNREFUSED（连接被拒绝，端口未监听）";
    case WSAETIMEDOUT: return "ETIMEDOUT（连接超时）";
    case WSAEHOSTUNREACH: return "EHOSTUNREACH（主机不可达）";
    case WSAENETUNREACH: return "ENETUNREACH（网络不可达）";
    case WSAHOST_NOT_FOUND: return "ENOTFOUND（域名不存在）";
    default: return "错误码 " + std::to_string(e);
  }
#else
  return std::string(std::strerror(e));
#endif
}

// 把 sockaddr 里的地址转成可读字符串
std::string addrToText(const sockaddr* sa, char* buf, size_t buflen) {
  buf[0] = '\0';
  if (sa->sa_family == AF_INET) {
    const auto* v4 = reinterpret_cast<const sockaddr_in*>(sa);
    inet_ntop(AF_INET, &v4->sin_addr, buf, (socklen_t)buflen);
  } else if (sa->sa_family == AF_INET6) {
    const auto* v6 = reinterpret_cast<const sockaddr_in6*>(sa);
    inet_ntop(AF_INET6, &v6->sin6_addr, buf, (socklen_t)buflen);
  }
  return std::string(buf);
}

int familyOf(const sockaddr* sa) { return sa->sa_family == AF_INET6 ? 6 : 4; }

#if defined(_WIN32)
// Windows 的接口名是 UTF-16（中文系统上会出现「以太网」「WLAN」），这里转成 UTF-8，
// 否则中文名全变成 '?'。
std::string wideToUtf8(const wchar_t* w) {
  std::string out;
  for (; w && *w; ++w) {
    unsigned cp = (unsigned)*w;
    if (cp >= 0xD800 && cp <= 0xDBFF && w[1] >= 0xDC00 && w[1] <= 0xDFFF) {
      cp = 0x10000 + ((cp - 0xD800) << 10) + ((unsigned)w[1] - 0xDC00);
      ++w;
    }
    if (cp < 0x80) {
      out += (char)cp;
    } else if (cp < 0x800) {
      out += (char)(0xC0 | (cp >> 6));
      out += (char)(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      out += (char)(0xE0 | (cp >> 12));
      out += (char)(0x80 | ((cp >> 6) & 0x3F));
      out += (char)(0x80 | (cp & 0x3F));
    } else {
      out += (char)(0xF0 | (cp >> 18));
      out += (char)(0x80 | ((cp >> 12) & 0x3F));
      out += (char)(0x80 | ((cp >> 6) & 0x3F));
      out += (char)(0x80 | (cp & 0x3F));
    }
  }
  return out;
}
#endif

}  // namespace

// ---------------------------------------------------------------------------
// dns_lookup
// ---------------------------------------------------------------------------
ToolResult dnsLookup(const json& a) {
  const std::string host = util::trim(sarg(a, "hostname"));
  if (host.empty()) return fail("缺少 hostname 参数。");
  const long long famArg = iarg(a, "family", 0);
  const int family = (famArg == 4 || famArg == 6) ? (int)famArg : 0;
  if (!ensureNetInit()) return fail("网络栈初始化失败。");

  addrinfo hints;
  std::memset(&hints, 0, sizeof(hints));
  hints.ai_family = family == 4 ? AF_INET : family == 6 ? AF_INET6 : AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;

  addrinfo* res = nullptr;
  const int rc = ::getaddrinfo(host.c_str(), nullptr, &hints, &res);
  if (rc != 0) {
#if defined(_WIN32)
    return fail("解析 " + host + " 失败：" + netErrText(rc));
#else
    return fail("解析 " + host + " 失败：" + std::string(gai_strerror(rc)));
#endif
  }

  // 去重但保持系统返回顺序（等价于 Node 的 verbatim: true）
  std::vector<std::string> seen;
  json addresses = json::array();
  std::string lines;
  int count = 0;
  char buf[INET6_ADDRSTRLEN];
  for (addrinfo* p = res; p; p = p->ai_next) {
    if (!p->ai_addr) continue;
    if (p->ai_family != AF_INET && p->ai_family != AF_INET6) continue;
    const std::string ip = addrToText(p->ai_addr, buf, sizeof(buf));
    if (ip.empty()) continue;
    if (std::find(seen.begin(), seen.end(), ip) != seen.end()) continue;
    seen.push_back(ip);
    const int fam = familyOf(p->ai_addr);
    addresses.push_back({{"address", ip}, {"family", fam}});
    lines += std::string(fam == 6 ? "IPv6" : "IPv4") + "  " + ip + "\n";
    count++;
  }
  ::freeaddrinfo(res);

  if (!count) return fail(host + " 没有解析到地址。");
  if (!lines.empty() && lines.back() == '\n') lines.pop_back();
  return ok(host + " 解析结果（" + std::to_string(count) + " 条）：\n" + lines,
            {{"hostname", host}, {"addresses", addresses}});
}

// ---------------------------------------------------------------------------
// port_check
// ---------------------------------------------------------------------------
ToolResult portCheck(const json& a) {
  const std::string host = util::trim(sarg(a, "host"));
  const long long port = iarg(a, "port", 0);
  if (host.empty()) return fail("缺少 host 参数。");
  if (port < 1 || port > 65535) return fail("port 必须是 1-65535 的整数。");
  // iOS 上局域网扫描要尽量短，默认 3s、上限 15s（与 Web 版一致）
  long long timeout = iarg(a, "timeout_ms", 3000);
  timeout = std::min<long long>(15000, std::max<long long>(300, timeout));
  if (!ensureNetInit()) return fail("网络栈初始化失败。");

  const auto started = std::chrono::steady_clock::now();
  auto elapsedMs = [&started]() {
    return (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now() - started).count();
  };

  addrinfo hints;
  std::memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* res = nullptr;
  const int rc = ::getaddrinfo(host.c_str(), nullptr, &hints, &res);
  if (rc != 0) {
#if defined(_WIN32)
    return fail(host + ":" + std::to_string(port) + " 不可达：" + netErrText(rc));
#else
    return fail(host + ":" + std::to_string(port) + " 不可达：" + std::string(gai_strerror(rc)));
#endif
  }

  const std::string label = host + ":" + std::to_string(port);
  std::string lastErr = "没有可用地址";
  bool anyTried = false;

  for (addrinfo* p = res; p; p = p->ai_next) {
    if (p->ai_family != AF_INET && p->ai_family != AF_INET6) continue;
    const long long remain = timeout - elapsedMs();
    if (remain <= 0) { lastErr = "ETIMEDOUT（总超时 " + std::to_string(timeout) + "ms）"; break; }
    anyTried = true;

    sockaddr_storage addr;
    std::memset(&addr, 0, sizeof(addr));
    std::memcpy(&addr, p->ai_addr, p->ai_addrlen);
    if (addr.ss_family == AF_INET)
      reinterpret_cast<sockaddr_in*>(&addr)->sin_port = htons((unsigned short)port);
    else
      reinterpret_cast<sockaddr_in6*>(&addr)->sin6_port = htons((unsigned short)port);

    sock_t fd = ::socket(p->ai_family, SOCK_STREAM, IPPROTO_TCP);
    if (fd == kInvalidSock) { lastErr = netErrText(lastNetError()); continue; }
    if (!setNonBlocking(fd)) { closeSock(fd); lastErr = "无法设置非阻塞模式"; continue; }

    bool connected = false;
    const int cr = ::connect(fd, reinterpret_cast<sockaddr*>(&addr), (socklen_type)p->ai_addrlen);
    if (cr == 0) {
      connected = true;
    } else {
      const int ce = lastNetError();
      if (!inProgress(ce)) {
        lastErr = netErrText(ce);
      } else {
        // 等可写（连上）或出错，最多等到总截止时间
        const long long left = std::max<long long>(1, timeout - elapsedMs());
        fd_set wfds, efds;
        FD_ZERO(&wfds); FD_ZERO(&efds);
        FD_SET(fd, &wfds);
        FD_SET(fd, &efds);
        timeval tv;
        tv.tv_sec = (long)(left / 1000);
        tv.tv_usec = (long)((left % 1000) * 1000);
#if defined(_WIN32)
        const int sr = ::select(0, nullptr, &wfds, &efds, &tv);
#else
        const int sr = ::select((int)fd + 1, nullptr, &wfds, &efds, &tv);
#endif
        if (sr == 0) {
          lastErr = "ETIMEDOUT（" + std::to_string(timeout) + "ms 内没有连上，可能被防火墙拦截或端口未开放）";
        } else if (sr < 0) {
          lastErr = netErrText(lastNetError());
        } else {
          int soErr = 0;
          socklen_type len = sizeof(soErr);
          if (::getsockopt(fd, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&soErr), &len) == 0 && soErr == 0)
            connected = true;
          else
            lastErr = netErrText(soErr ? soErr : lastNetError());
        }
      }
    }
    closeSock(fd);

    if (connected) {
      ::freeaddrinfo(res);
      const long long ms = elapsedMs();
      return ok(label + " 可连通（" + std::to_string(ms) + "ms）",
                {{"host", host}, {"port", (int)port}, {"reachable", true}, {"ms", ms}});
    }
  }
  ::freeaddrinfo(res);
  if (!anyTried) return fail(label + " 不可达：" + lastErr);
  return ok(label + " 不可达：" + lastErr,
            {{"host", host}, {"port", (int)port}, {"reachable", false}, {"ms", elapsedMs()}});
}

// ---------------------------------------------------------------------------
// local_ip
// ---------------------------------------------------------------------------
#if defined(_WIN32)
ToolResult localIp(const json&) {
  if (!ensureNetInit()) return fail("网络栈初始化失败。");
  ULONG size = 16 * 1024;
  std::vector<unsigned char> buf(size);
  auto* aa = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data());
  ULONG rc = ::GetAdaptersAddresses(AF_UNSPEC,
                                    GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
                                    nullptr, aa, &size);
  if (rc == ERROR_BUFFER_OVERFLOW) {
    buf.assign(size, 0);
    aa = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data());
    rc = ::GetAdaptersAddresses(AF_UNSPEC,
                                GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
                                nullptr, aa, &size);
  }
  if (rc != NO_ERROR) return fail("枚举网络接口失败（错误码 " + std::to_string((int)rc) + "）。");

  json list = json::array();
  std::string lines;
  char host[INET6_ADDRSTRLEN];
  for (auto* p = aa; p; p = p->Next) {
    std::string name = wideToUtf8(p->FriendlyName);
    if (name.empty()) name = "if" + std::to_string(p->IfIndex);
    for (auto* ua = p->FirstUnicastAddress; ua; ua = ua->Next) {
      if (!ua->Address.lpSockaddr) continue;
      const int fam = familyOf(ua->Address.lpSockaddr);
      const std::string ip = addrToText(ua->Address.lpSockaddr, host, sizeof(host));
      if (ip.empty()) continue;
      // 与 Web 版一致：回环只保留 IPv4
      const bool loopback = (fam == 4) ? (ip.rfind("127.", 0) == 0) : (ip == "::1");
      if (loopback && fam != 4) continue;
      // 前缀长度转掩码
      std::string mask;
      if (ua->OnLinkPrefixLength > 0 && ua->OnLinkPrefixLength <= (fam == 4 ? 32u : 128u)) {
        const unsigned bits = ua->OnLinkPrefixLength;
        if (fam == 4) {
          unsigned m = bits ? (0xFFFFFFFFu << (32 - bits)) : 0u;
          mask = std::to_string((m >> 24) & 255) + "." + std::to_string((m >> 16) & 255) + "." +
                 std::to_string((m >> 8) & 255) + "." + std::to_string(m & 255);
        } else {
          mask = "/" + std::to_string(bits);
        }
      }
      lines += name + "  " + (fam == 6 ? "IPv6" : "IPv4") + "  " + ip;
      if (!mask.empty()) lines += "  掩码 " + mask;
      if (loopback) lines += "  (回环)";
      lines += "\n";
      list.push_back({{"name", name}, {"family", fam == 6 ? "IPv6" : "IPv4"}, {"address", ip},
                      {"netmask", mask}, {"internal", loopback}});
    }
  }
  if (!lines.empty() && lines.back() == '\n') lines.pop_back();
  return ok(lines.empty() ? "（没有探测到网络接口）" : lines, {{"interfaces", list}});
}
#else
ToolResult localIp(const json&) {
  ifaddrs* ifs = nullptr;
  if (::getifaddrs(&ifs) != 0) return fail("枚举网络接口失败：" + netErrText(lastNetError()) + "。");

  json list = json::array();
  std::string lines;
  char host[INET6_ADDRSTRLEN];
  char mask[INET6_ADDRSTRLEN];
  for (ifaddrs* p = ifs; p; p = p->ifa_next) {
    if (!p->ifa_addr) continue;
    const int fam = p->ifa_addr->sa_family;
    if (fam != AF_INET && fam != AF_INET6) continue;
    const std::string ip = addrToText(p->ifa_addr, host, sizeof(host));
    if (ip.empty()) continue;
    const bool loopback = (p->ifa_flags & IFF_LOOPBACK) != 0;
    // 与 Web 版一致：回环只保留 IPv4
    if (loopback && fam != AF_INET) continue;
    std::string maskText;
    if (p->ifa_netmask) maskText = addrToText(p->ifa_netmask, mask, sizeof(mask));
    const std::string name = p->ifa_name ? p->ifa_name : "?";
    const char* famText = fam == AF_INET6 ? "IPv6" : "IPv4";
    lines += name + "  " + famText + "  " + ip;
    if (!maskText.empty()) lines += "  掩码 " + maskText;
    if (loopback) lines += "  (回环)";
    lines += "\n";
    list.push_back({{"name", name}, {"family", famText}, {"address", ip},
                    {"netmask", maskText}, {"internal", loopback}});
  }
  ::freeifaddrs(ifs);
  if (!lines.empty() && lines.back() == '\n') lines.pop_back();
  return ok(lines.empty() ? "（没有探测到网络接口）" : lines, {{"interfaces", list}});
}
#endif

}  // namespace nettools
}  // namespace ds
