# Overlay triplet：把 iOS 依赖库的最低版本对齐工程的 IPHONEOS_DEPLOYMENT_TARGET(16.0)。
# 官方 arm64-ios triplet 用当前 SDK 版本(26.5)编译，链接到 16.0 工程会刷一堆
# "built for newer 'iOS' version" 警告，旧系统上还可能缺符号。
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphoneos)
set(VCPKG_OSX_DEPLOYMENT_TARGET 16.0)
