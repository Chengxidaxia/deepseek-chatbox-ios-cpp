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
    CURL::libcurl OpenSSL::SSL OpenSSL::Crypto SQLite::SQLite3
  )
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
    target_link_libraries(${name} PRIVATE dsbox_core)
    add_test(NAME ${name} COMMAND ${name})
  endforeach()
endif()
