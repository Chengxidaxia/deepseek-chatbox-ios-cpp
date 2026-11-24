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
- [x] API 层直连（SSE / TTS / ASR）
- [x] 内置工具引擎移植（40 工具 + 二维码 QR v1–40）
- [x] P0 纯字符串工具补齐（`regex_test` / `csv_json` / `slugify` / `id_validator` / `hex_view` / `color_convert` / `text_kit`）
- [x] P1 `aes_crypto`（OpenSSL EVP，CBC/GCM/ECB，密文与 Web 版逐字节相同）
- [x] P2 联网六件（`dns_lookup` / `port_check` / `local_ip` + `http_request` / `fetch_url` / `web_search`，libcurl + 本地 HTML 正文提取）
- [x] iOS UIKit 界面（Fragment 序列渲染 / 工具卡片三态 / 分支切换 / 附件 / 语音输入）
- [x] 「继续生成」入口（以收尾正文为前缀续写，新内容拼回同一条消息）
- [x] 附件落盘为沙盒文件（`Documents/attachments/`，库里只存相对路径，老库自动迁移）
- [x] iOS 云编译出 IPA（GitHub Actions，Ad-Hoc）

## iOS 界面与官方的对齐

前端取值与结构来自 `DeepSeek-2.7.1.ipa` 的实测提取，详见 `docs/官方iOS前端参考.md`。要点：

- **一条回答 = 按顺序排列的 Fragment**，不是把所有工具调用合并成一组：
  `思考 → 该轮工具卡片 → 下一轮思考 → … → 正文 → 引用 → 用量`。
- **工具卡片三态**：`搜索中...` / `已搜索 “%@”` / `联网搜索暂不可用`（浏览、页内查找同理），
  卡片可展开看完整执行结果，尺寸取自 `app.css` 的 `.tool-card`（圆角 14 / 描边 1 / 头部 10×12 / 字号 13）。
- **多轮工具循环**在 `DSBoxService` 内完成（模型请求工具 → 本地执行 → 回灌 → 再请求，上限 10 轮，
  用满后关闭工具通道并提示模型收尾），与 Web 版行为一致。
- **分支切换**：同一提问的多次回答各自留存，底部显示「第 n 条消息（共 m 条）」，
  「再试一次」生成新分支而不是覆盖。
- **图标为自绘**：官方 `Assets.car` 在 Windows 上解不开，按官方 SVG 的几何特征用 UIBezierPath 重绘
  （20×20 视口 / 1.6pt 描边 / 圆头端点），见 `Supporting/DSIcon.m`。
- **Lottie 动画未引入运行时**：官方那 8 个 16×16 动画（闪电摆动、专家脉冲、朗读波形等）
  用 Core Animation 等价实现，视觉一致但不增加依赖，见 `DSVoiceOverlay` 的波形与工具卡片的脉冲点。
