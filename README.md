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
bash scripts/build-local.sh          # 配置 + 编译 + ctest，并记一次构建
bash scripts/build-local.sh --no-test # 只编译
```

手动等价流程：

```bash
cmake -S . -B .build/native -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build .build/native
ctest --test-dir .build/native --output-on-failure
```

## 构建计数

口径：**只要发起过一次编译，就算一次构建**，成功失败都算。本机编译和云编译**各算各的**——
同一天里本机编了 1 次、云端编了 1 次，那就是 +2。

| 触发点 | 怎么记 |
|---|---|
| 本机 `cmake --build`（含增量、什么都没变也算） | CMake 的 `build_count` 目标自动追加一行 `local` |
| 本机 `ctest` | `build-local.sh` 追加一行 `test` |
| 云编译（Actions 每次 run） | workflow 追加一行 `ci`；分支构建号 = 追加后那行的号 |
| tag 构建 | 号直接取 tag 名里的 `.buildN`，只编译不回写（tag 是快照） |

### 为什么是「流水账」而不是一个数字

早先是 `build-count.json` 里一个 `build`，本机和 CI 各自读出来 +1 再写回。
两边同时推进时 git 合并只能二选一，**两次编译只剩一次，号被吃掉**，还每次 push 都冲突。

现在拆成两个文件：

| 文件 | 作用 | 合并行为 |
|---|---|---|
| `build-count.json` | `base`（1~110 的汇总数，之后不再变）+ 口径说明 + 冻结的旧明细 | 不再被写，所以不冲突 |
| `build-events.jsonl` | 一次编译一行，只追加、不改写 | `.gitattributes` 里 `merge=union`，两边的行都保留 |

`build = base + build-events.jsonl 的行数`。所以本机 1 行 + 云端 1 行 = 号 +2，
既不会互相覆盖，也不会再产生冲突块。

| 字段 | 含义 |
|---|---|
| `base` | 开始按事件留档之前的次数汇总；`Info.plist` 里 `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`、`CFBundleShortVersionString = $(MARKETING_VERSION)`，CI 编译时注入 |
| `legacy_history` | 旧格式的明细，冻结保留，不再追加 |

```bash
python scripts/bump-build.py --show          # 看当前号 + 最近几条
python scripts/bump-build.py --next          # 只算下一次的号（CI 取号用）
python scripts/bump-build.py --source local --note "..."   # 一般用不到，CMake 已自动记
```

云编译由 workflow 的 `Record build count` 步骤自动追加并回写 master；tag 构建是 detached HEAD，
只写进 run summary 不回写。

> **坑**：GitHub 对 `[skip ci]` 是**全文匹配**，不只看标题行。提交正文里只要出现这个字样
> （哪怕是在解释它），整次 push 的 workflow 都会被跳过。写提交信息时别在正文里提这个词。

## 目录

- `core/include` / `core/src` — 跨平台核心库
- `tools/` — 内置工具引擎 + 工具定义
- `tests/` — 本机验证程序
- `ios/` — iOS App 工程（UIKit + ObjC++ 桥接）
- `cmake/` — iOS toolchain / 签名配置
- `scripts/` — 打包 / 发布脚本

## 安装（iOS）

产物是 **Ad-Hoc 签名**的 ipa，不能直接装，要用 Sideloadly / AltStore 这类工具重签后安装
（免费证书 7 天过期）。版本信息、安装步骤、逐项真机验证清单见
[`docs/安装与真机验证.md`](docs/安装与真机验证.md)。

## 进度

- [x] C++ 核心骨架 + CMake + 依赖
- [x] 数据模型 / SQLite 存储 / 加密（本机测试全绿）
- [x] API 层直连（SSE / TTS / ASR）
- [x] 内置工具引擎移植（40 工具 + 二维码 QR v1–40）
- [x] P0 纯字符串工具补齐（`regex_test` / `csv_json` / `slugify` / `id_validator` / `hex_view` / `color_convert` / `text_kit`）
- [x] P1 `aes_crypto`（OpenSSL EVP，CBC/GCM/ECB，密文与 Web 版逐字节相同）
- [x] P2 联网六件（`dns_lookup` / `port_check` / `local_ip` + `http_request` / `fetch_url` / `web_search`，libcurl + 本地 HTML 正文提取）
- [x] P3 `token_count` 接真分词器（自实现 byte-level BPE，词表 3.91 MB 二进制，与 Web 版逐 token 一致）
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
