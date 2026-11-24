cmake_minimum_required(VERSION 3.20)
project(dsbox_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# 依赖策略：curl / OpenSSL / SQLite 用系统库（本机 MinGW + iOS vcpkg 均提供）。
# nlohmann/json 用仓库内 vendor 单头文件（两端一致，无需包管理器）。
# iOS 平台由 toolchain 注入 CMAKE_SYSTEM_NAME=iOS，届时切换 framework。
# ---------------------------------------------------------------------------
if(NOT IOS)
  find_package(CURL REQUIRED)
  find_package(OpenSSL REQUIRED)
  find_package(SQLite3 REQUIRED)
  find_package(ZLIB REQUIRED)
  find_package(Iconv)
endif()

# ---------------------------------------------------------------------------
# core 静态库
# ---------------------------------------------------------------------------
file(GLOB CORE_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/core/src/*.cpp)
add_library(dsbox_core STATIC ${CORE_SOURCES})
target_include_directories(dsbox_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/core/include
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor
)

if(NOT IOS)
  target_link_libraries(dsbox_core PUBLIC
    CURL::libcurl OpenSSL::SSL OpenSSL::Crypto SQLite3::SQLite3 ZLIB::ZLIB
  )
endif()

# ---------------------------------------------------------------------------
# tools 静态库（内置工具引擎 + QR），依赖 core 的模型/util/crypto
# ---------------------------------------------------------------------------
file(GLOB TOOL_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/tools/src/*.cpp)
add_library(dsbox_tools STATIC ${TOOL_SOURCES})
target_include_directories(dsbox_tools PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/tools/include
  ${CMAKE_CURRENT_SOURCE_DIR}/core/include
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor
)
target_link_libraries(dsbox_tools PUBLIC dsbox_core)

# net-tools.cpp 直接用 socket API：iOS 用系统 BSD socket，Windows 本机要额外链 ws2_32 / iphlpapi
if(WIN32)
  target_link_libraries(dsbox_tools PUBLIC ws2_32 iphlpapi)
endif()

# web-tools.cpp 用 libcurl 抓网页 + iconv 转 GBK/Big5 正文
if(NOT IOS)
  target_link_libraries(dsbox_tools PUBLIC CURL::libcurl)
  if(Iconv_FOUND)
    target_link_libraries(dsbox_tools PUBLIC Iconv::Iconv)
  endif()
endif()

# ---------------------------------------------------------------------------
# 测试程序（本机验证用）
# ---------------------------------------------------------------------------
option(DSBOX_BUILD_TESTS "Build native tests" ON)
if(DSBOX_BUILD_TESTS AND NOT IOS)
  enable_testing()
  file(GLOB TEST_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/tests/*.cpp)
  foreach(src ${TEST_SOURCES})
    get_filename_component(name ${src} NAME_WE)
    add_executable(${name} ${src})
    target_link_libraries(${name} PRIVATE dsbox_core dsbox_tools)
    add_test(NAME ${name} COMMAND ${name})
    # 测试用相对路径读 tools/tool_defs.json，工作目录固定为仓库根
    set_tests_properties(${name} PROPERTIES WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
  endforeach()
endif()

# ---------------------------------------------------------------------------
# 构建计数：口径是「编译一次算一次」，所以每次 cmake --build（含增量）都 +1。
# 用 ALL 目标而不是 POST_BUILD：POST_BUILD 只在 target 真的重建时才触发，
# 改个测试文件就不会记，那就不叫「编译了一次」了。
# ---------------------------------------------------------------------------
find_package(Python3 COMPONENTS Interpreter QUIET)
if(Python3_Interpreter_FOUND AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/scripts/bump-build.py")
  add_custom_target(build_count ALL
    COMMAND ${Python3_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/scripts/bump-build.py"
            --source local --note "cmake --build"
    COMMENT "记录构建次数"
    VERBATIM)
endif()
