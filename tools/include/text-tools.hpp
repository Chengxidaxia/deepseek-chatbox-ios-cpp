#pragma once
// P0 纯字符串类工具：实现对照 Web 版 server/tools-core.cjs（行号见各函数注释）。
// 与 tools.cpp 分开编译，callImpl() 只做分发。
#include "tools.hpp"

namespace ds {
namespace texttools {

ToolResult regexTest(const json& a);      // tools-core.cjs:2131
ToolResult csvJson(const json& a);        // tools-core.cjs:2182
ToolResult slugify(const json& a);        // tools-core.cjs:2238
ToolResult idValidator(const json& a);    // tools-core.cjs:2288
ToolResult hexView(const json& a);        // tools-core.cjs:2561
ToolResult colorConvert(const json& a);   // tools-core.cjs:2591
ToolResult textKit(const json& a);        // tools-core.cjs:2693

}  // namespace texttools
}  // namespace ds
