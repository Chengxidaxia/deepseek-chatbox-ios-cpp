# DeepSeek Chatbox — iOS (C++ 原生重写)

把现有 Web 版 Chatbox 用 C++ 重写为 iOS 原生应用。核心逻辑跨平台 C++，UI 层 Objective-C++ / UIKit，直连 DeepSeek 官方 API，数据全部存手机本地，不依赖任何服务器。

## 架构

```
┌─────────────────────────────────────┐
│  iOS UI (Objective-C++ / UIKit)     │  ← ios/ChatboxIOS
│  会话列表 · 聊天气泡 · 输入 · 设置   │
└──────────────┬──────────────────────┘
               │ ObjC++ 桥接 (Service 单例)
┌──────────────▼──────────────────────┐
│  C++ Core (跨平台)                  │  ← core/ + tools/
│  ├ model      数据模型              │
│  ├ store      SQLite 本地存储        │
│  ├ crypto     PIN+PBKDF2+AES-GCM     │
│  ├ api        libcurl 直连官方+SSE   │
│  └ tools      40 个内置工具引擎       │
└──────────────┬──────────────────────┘
               │ HTTPS
        api.deepseek.com
```

## 设计原则

- **数据存本地**：SQLite 落 iOS `Documents/`，不上传任何服务器
- **Key 加密**：PIN → PBKDF2(150000) → AES-256-GCM，密文存 SQLite，PIN 不落盘
- **直连官方**：C++ 层直接请求 `api.deepseek.com`，Bearer Key 在端上注入（已实测官方放行 CORS/直连）
- **对齐全功能**：40 内置工具、TTS/ASR、思考强度、上下文用量等尽量对齐 Web 版
- **本机可验证**：core 库用 MinGW/CMake 本机编译跑测试；iOS 包走 GitHub Actions 云编译

## 依赖

| 库 | 用途 | 本机来源 | iOS 来源 |
|---|---|---|---|
| nlohmann/json 3.11.3 | JSON | `vendor/json.hpp`（已内置） | 同左 |
| libcurl | HTTPS 请求 | MinGW 系统库 | vcpkg |
| OpenSSL 3.x | AES-GCM / PBKDF2 | MinGW 系统库 | vcpkg |
| SQLite3 | 本地存储 | MinGW 系统库 | iOS 系统 framework |

## 本机构建与测试（Windows / MinGW）

```bash
export PATH="/k/Programs/msys64/mingw64/bin:$PATH"
cmake -S . -B .build/native -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build .build/native
./.build/native/test_core.exe
```

## 目录

- `core/include` / `core/src` — 跨平台核心库
- `tools/` — 内置工具引擎 + 工具定义
- `tests/` — 本机验证程序
- `ios/` — iOS App 工程（UIKit + ObjC++ 桥接）
- `cmake/` — iOS toolchain / 签名配置
- `scripts/` — 打包 / 发布脚本

## 进度

- [x] C++ 核心骨架 + CMake + 依赖
- [x] 数据模型 / SQLite 存储 / 加密（本机测试全绿）
- [ ] API 层直连（SSE / TTS / ASR）
- [ ] 内置工具引擎移植
- [ ] iOS UIKit 界面
- [ ] iOS 云编译出 IPA
