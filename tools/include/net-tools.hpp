#pragma once
// 网络 / 系统类工具：实现对照 Web 版 server/tools-core.cjs 的同名方法
// （Web 版跑在 Node 里，用 dns/net/os 模块；这里换成 BSD socket / getaddrinfo / getifaddrs）。
#include "tools.hpp"

namespace ds {
namespace nettools {

// dns_lookup   —— tools-core.cjs:1945
ToolResult dnsLookup(const json& a);
// port_check   —— tools-core.cjs:1959
ToolResult portCheck(const json& a);
// local_ip     —— tools-core.cjs:2029
ToolResult localIp(const json& a);

}  // namespace nettools
}  // namespace ds
