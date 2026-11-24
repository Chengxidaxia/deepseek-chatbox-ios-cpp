#pragma once
// 联网类工具：http_request / fetch_url / web_search。
// 对照 Web 版 server/tools-core.cjs:1983 / 1791 / 1751（Web 版用 fetch，这里换 libcurl）。
//
// 按用户要求，web_search / fetch_url 全部本地实现，**不接**官方
// POST /v1/tools/search 与 /v1/tools/fetch。
#include "tools.hpp"

namespace ds {
namespace webtools {

ToolResult httpRequest(const json& a);
ToolResult fetchUrl(const json& a);
ToolResult webSearch(const json& a);

}  // namespace webtools
}  // namespace ds
