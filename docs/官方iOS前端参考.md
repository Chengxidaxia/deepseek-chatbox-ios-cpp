# 官方 iOS 前端参考（DeepSeek 2.7.1）

本文件记录从官方 App（`DeepSeek-2.7.1.ipa`）中**实测提取**的前端信息，作为 iOS/Rust 各端界面的对齐依据。
所有结论都标注了提取方式；没有取到的项明确写「未提取」，不做推测。

## 1. 提取方法

| 信息 | 方法 | 产出 |
|---|---|---|
| 技术栈 | 解包看 `Frameworks/` | 原生 Swift + SnapKit/FlexLayout（纯代码布局，无 storyboard） |
| 界面类名 | 二进制里还原 `_TtC13DeepSeek_Chat…` 长度前缀编码 | 466 个类名，其中 287 个 UI 相关 |
| 中文文案 | `zh-Hans.lproj/Localizable.strings` 二进制 plist 解析 | 806 条，导出为 JSON |
| 图标 | `Assets.car` 内嵌 SVG 文本 | 部分（多数为 CoreUI 分块压缩，未完整解出） |
| 动画 | App 根目录 Lottie JSON | 8 个文件，可直接复用 |
| 颜色 | 二进制的 hex 常量 + 已有 `tokens.css`（取自官方站点 main.css）交叉验证 | 主文字 `#0F0F0F` 与 `--label-primary #0F1115` 接近 |

> `Assets.car` 的位图/Rendition 是 BOM 分块 + CoreUI 压缩格式，Windows 上未找到可用解包工具，**未完整提取**。
> 需要图标时优先从官方站点 CSS/SVG 取。

## 2. 界面架构（类名 → 职责）

官方用「页面 Controller + 消息 View/Cell + Fragment 子视图」三层，**一条回答由多个 Fragment 按顺序组成**。

### 页面

| 类名 | 职责 |
|---|---|
| `RootViewController` | 根容器 |
| `SidebarViewController` | 侧边栏抽屉 |
| `SessionListViewController` | 会话列表 |
| `SessionViewController` / `MessageViewController` | 单个会话 / 消息区 |
| `WelcomeViewController` | 空态欢迎页 |
| `ProfileViewController` | 设置（`profileTitle` = 设置） |
| `PersonalizationViewController` | 个性化 |
| `FontSizeViewController` | 字体大小 |
| `DataConfigViewController` | 数据管理 |

### 会话列表

`SessionListSearchBarView`、`SessionListEmptyView`、`SessionListSearchResultsView`、
`SessionListMultiSelectController` + `SessionListMultiSelectTopBar/BottomBar`（多选删除/置顶）。

### 消息区

| 类名 | 职责 |
|---|---|
| `MessageListView` | 消息容器 |
| `BaseMessageCell` → `UserMessageCell` / `AgentMessageCell` | 用户/助手两条渲染链 |
| `UserBubbleView` / `UserRequestBubbleView` | 用户气泡 |
| `AgentFragmentsView` / `FragmentsContainerView` / `AgentGroupView` | **助手消息的 Fragment 容器** |
| `BaseMessageOperationBar` → `UserMessageOperationBar` / `AgentMessageOperationBar` | 操作栏 |
| `BranchChooseView` | 分支切换 |
| `CitationView` / `CiteIconsView` / `SearchSummaryView` | 引用来源 |

### Fragment（助手回答的组成单元）

| 类名 | 对应内容 |
|---|---|
| `ThinkFragmentView` | 思考过程 |
| `ToolSearchFragmentView` | 联网搜索 |
| `ToolOpenFragmentView` | 浏览页面 |
| `ToolFindFragmentView` | 页内查找 |
| `ToolLoadingFragmentView` / `ToolCallLoadingDotView` | 工具加载态 |
| `RequestFragmentView` / `ResponseFragmentView` | 工具请求/返回 |
| `SingleSearchFragmentView` | 单条搜索结果 |
| `CautionTipFragmentView` / `InfoTipFragmentView` / `WarningTipFragmentView` | 提示条 |

→ **结论**：官方不是「所有工具合并成一个组」，而是「思考 → 该轮工具 → 下一轮思考 → 工具 → 正文」顺序排布的 Fragment 序列。这与 Web 版 v1.12.4 修正后的顺序渲染一致。

### 输入区

`InputAreaView`、`InputViewModel`、`DSFixedLineHeightTextView`、
`FileInputContainerView` / `InputFileCell` / `FileImageCell`、`UploadPanelView`（相册/拍照/文件）、
`VoiceInputMaskView` / `SpectrumView`（按住说话的遮罩与频谱）、`PromptSuggestionView`（推荐提示词）。

### 视觉组件

`Typography`（统一字号）、`DSGlassButton` / `DSGlassEffectView` / `VariableBlurView`（毛玻璃）、
`DSGradientView`、`ShadowView`、`ThemeAwareLottieView`（Lottie 跟随主题）、
`TTSButtonView` / `TTSVoiceFluidBlobView`（朗读流体球）、`ToolCallLoadingDotView`（工具加载圆点）、
`TouchIntentionAwareTableView`（滚动中不触发点击）。

## 3. 视觉取值（实测）

来自 `deepseek-chatbox/public/css/tokens.css` 与 `app.css`（该文件注释声明取自 chat.deepseek.com 的 main.css，值未调整）。

| 项 | 浅色 | 深色 |
|---|---|---|
| 页面底 `--bg-base` | `#FFFFFF` | `#151517` |
| 主文字 `--label-primary` | `#0F1115` | `#F9FAFB` |
| 次文字 `--label-secondary` | `#61666B` | `#CFD3D6` |
| 三级文字 `--label-tertiary` | `#81858C` | `#ADB2B8` |
| 描边 `--border-l2` | `rgba(0,0,0,.10)` | `rgba(255,255,255,.12)` |
| 品牌 `--brand-primary` | `#3964FE` | `#5686FE` |
| 用户气泡 `--bubble` | `#EDF3FE` | `#2C2C2E` |

尺寸：

| 项 | 值 | 出处 |
|---|---|---|
| 正文 | 16px / 行高 28px | `.md` |
| 思考正文 | 14px / 行高 24px | `.think` |
| 思考头部 | 13px | `.think-head` |
| 用户气泡 | 圆角 18、内边距 10×14、最大宽 78% | `.msg.user .bubble` |
| 思考竖线 | 2px、间距 12px | `.think` 的 `border-left` + `padding-left` |
| 消息列表左右留白 | 桌面 36px / 移动端 20px | `--message-list-padding-horizontal` |
| 图标描边 | 1.6px（20×20 关闭图标） | 官方 SVG 实测 |

## 4. 文案体系

官方 806 条文案已导出，key 原样保留。已落地到 `ios/ChatboxIOS/Supporting/DSStrings.m`，常用项示例：

| key | 中文 |
|---|---|
| `sessionInitTitle` | 新对话 |
| `sessionListEmptyTitle` / `sessionListEmptyDescription` | 暂无对话 / 你与 DeepSeek 的对话将展示在这里 |
| `chatInputPlaceholderChat` | 发消息 |
| `thinking` | 正在思考 |
| `thinkingAutoFold` / `thinkingAutoFoldDesc` | 思考内容自动折叠 / 开启后，思考结束后将自动折叠思考内容 |
| `regenerateNormal` | 再试一次 |
| `regenerateEnableSearch` / `regenerateDisableSearch` | 搜索网页 / 关闭搜索 |
| `regenerateVerbosityHigh` / `regenerateVerbosityLow` | 更加详细 / 更加简洁 |
| `toolSearchWip` / `toolSearchingWithQuery` / `toolSearchFinished` | 搜索中... / 搜索 %@ / 已搜索 %@ |
| `toolOpen` / `toolOpenSearchResult` / `toolOpenFailed` | 浏览 / 浏览搜索结果 / 浏览失败 |
| `toolFindWip` / `toolFindFinished` / `toolFindNoResult` | 正在查找“%@” / 已查找到“%@” / 未查找到“%@” |
| `mergeToolSearchResults` / `mergeToolOpenResults` | 已搜索到 %d 个网页 / 已浏览 %d 个页面 |
| `defaultModelName` / `expertModelName` / `visionModelName` | 快速模式 / 专家模式 / 识图模式 |
| `branch_switcher_description` | 第 %d 条消息（共 %d 条） |
| `sessionHistoryTimelineLabel*` | 今天 / 昨天 / 7 天内 / 30 天内 |

> 官方没有的概念（本地 API Key、思考强度、上下文限制、温度、系统提示词）在 `DSStrings.m` 里标注为「自创」。

## 5. 可直接复用的动画资源

官方根目录下 8 个 Lottie JSON，均为 16×16 矢量动画：

| 文件 | 用途 |
|---|---|
| `model_default.json` | 快速模式图标（闪电摆动） |
| `model_expert.json` | 专家模式图标（缩放脉冲） |
| `model_vision.json` | 识图模式图标（相册） |
| `toggle_think.json` | 深度思考开关 |
| `toggle_search.json` | 联网搜索开关 |
| `tts_auto_play_on.json` / `tts_auto_play_off.json` | 自动朗读开关 |
| `tts_playing_wave.json` | 朗读播放中波形 |

已复制到工作区 `.ref/ds-assets/`（未入库，版权归官方，仅作对照）。

## 6. 当前对齐情况

| 项 | 状态 | 落点 |
|---|---|---|
| 用户气泡（淡蓝、右对齐、圆角 18、78% 宽） | 已实现 | `DSMessageCell` + `DSTheme` || 用户气泡内附件预览（图片缩略图 / 文件 chip） | 已实现 | `DSMessageCell renderUserAttachments:` |
| 助手无气泡、全宽左对齐 | 已实现 | `DSMessageCell` |
| 思考块（2px 竖线、14/24、可折叠） | 已实现 | `DSMessageCell thinkBoxForRound:` |
| 正文 16/28 | 已实现 | `DSTheme bodyText:color:` |
| 会话列表时间分组 + 空态 | 已实现 | `DSConversationListController` |
| 输入区（+ / 圆角输入框 / 圆形发送钮） | 已实现 | `DSChatViewController buildComposer` |
| 输入区毛玻璃底 + 开关 chips（深度思考 / 联网搜索 / 模型） | 已实现 | `UIVisualEffectView` + `chipButtonWithTitle:` |
| 官方文案表 | 已落地 | `DSStrings`（含 40 个工具的中文名映射） |
| 工具卡片三态（搜索 / 浏览 / 查找 / 本地工具） | 已实现 | `DSToolCardView` |
| 多轮工具循环 + 轮次用尽收尾提示 | 已实现 | `DSBoxService runAgentLoopWithHistory:` |
| Fragment 卡片化（思考/工具/正文按发生顺序） | 已实现 | `DSMessageCell rebuildAssistant:` + `DSTurn` |
| 联网搜索结果卡片（已搜索到 N 个网页） | 已实现 | `DSSearchResultCardView` |
| 分支切换（第 n 条 / 共 m 条） | 已实现 | `DSBranchBar` + `DSTurn.branches` |
| 引用来源（编号 + 标题 + 域名，可点开） | 已实现 | `DSCitationListView` |
| 附件面板（相册 / 拍照 / 文件） | 已实现 | `DSAttachmentPanel` + PHPicker / UIImagePicker / UIDocumentPicker |
| 语音输入（按住说话 + 波形 + 上滑取消 + ASR 回填） | 已实现 | `DSVoiceRecorder` + `DSVoiceOverlay` |
| 识图（图片附件按 OpenAI 多模态 content 发送） | 已实现 | `core/src/api.cpp toApiMessages` |
| Lottie 动画 | **改为等价自绘** | 官方 JSON 为 16×16 微动画，用 Core Animation 复刻（`DSVoiceOverlay` 波形、工具卡脉冲点、`DSIcon` 线性图标），不引入运行时依赖 |
| 毛玻璃 / 渐变组件 | 已实现（毛玻璃） | 输入区 `UIBlurEffect` + 语音遮罩卡片；渐变未使用（官方仅 Tab 图标用渐变） |

### 已知差异（非视觉，能力层面）

| 差异 | 原因 |
|---|---|
| 「继续生成」未做 | 需要 beta 接口的 `prefix` 续写，当前 core 的 `buildPayload` 已支持 `continuePrefix`，但 UI 未挂入口 |
| 按住说话直接转文字、不边录边识别 | 官方为流式 ASR；这里用 `/v1/tools/asr` 一次性上传，松手后才出文字 |
| 图片不落盘为独立文件 | 存 SQLite blob，随会话导出；官方存沙盒文件目录 |
| 无侧边栏抽屉 | 会话列表用导航栈 push，官方是 Sidebar 抽屉 |

## 6.1 2026-11-24 这一轮的对齐改动（真机反馈「界面没对齐」）

真机反馈「快速/专家/识图没了」「界面没对齐」「点联网搜索闪退」后，重新解包 2.7.1 的
`zh-Hans.lproj/Localizable.strings`（`plistlib` 解析，806 条）逐条核对文案，并据此改了界面：

| 项 | 改动 | 依据 |
|---|---|---|
| 联网搜索开关 | 文案改为 **智能搜索** | 官方 key `messageSearchButton = 智能搜索`（原来的「联网搜索」是我们自造的叫法） |
| 深度思考开关 | 保持「深度思考」 | 官方 key `messageR1Button = 深度思考` |
| 输入区结构 | 改为**一个圆角容器上下两行**：正文在上，工具行在下（左起 chips，右侧 `+` / 语音 / 发送） | 类名 `InputAreaView` / `InputFileCell` / `PromptSuggestionView` 的组织方式 + 官方截图形态；**未取到帧数据，布局是推断的** |
| 输入框长高 | 跟内容长到最多 120pt，超出转内部滚动 | 官方输入框可多行；上限为我们自定 |
| 语音 / 发送互斥 | 有文字显示发送钮，空文本显示麦克风 | 官方输入区右下角是同一位置的两种态 |
| 空态 | 居中「开启对话」+「回答由 AI 生成，仅供参考」 | 官方 key `startChat = 开启对话`、`inputAIAlert = 回答由 AI 生成，仅供参考` |
| 思考头部 | 结束后显示 **已思考（用时 N 秒）** | 官方 key `messageThinkDuration = 已思考（用时 %1$d 秒）`；N 由首个 reasoning 增量到首个正文增量计时 |
| 模型 chip | 不再映射「快速/专家/识图」，直接显示 `/models` 返回的展示名 | 官方已取消三档；我们的版本按用户要求保留切换菜单 |

> 未做：Sidebar 抽屉（官方是 `SidebarViewController` 抽屉，我们是导航栈 push）。
> 官方欢迎页那句问候语**不在** 806 条 Localizable 里，二进制里也搜不到中文，
> 推测由服务端下发，所以没有硬编一个假文案，空态只用可验证的官方 key。

## 6.2 从 `Assets.car` 的资源名反推界面结构（2026-11-24 第二次对齐）

`Assets.car` 的位图解不开，但**资源名是明文**：直接扫可打印串就能拿到 200 多个路径。
这比看类名更接近「哪块 UI 有什么」：

| 资源名 | 说明 |
|---|---|
| `Ic_menu_outline_24.svg` | 顶栏左侧的三横线 → **官方是抽屉/列表入口，不是返回箭头** |
| `chat/top_bar/modelChoose` + `modelChooseCheckmark` | **模型选择在顶栏**，点开是带勾的列表 |
| `chat/top_bar/sessionRefresh`、`chat/top_bar/closeShare` | 顶栏还有刷新/关闭分享 |
| `chat/bottom_bar/{add,voice,send,stop,deep_think,searching,text,pencil,promptSuggestionArrow}` | 底部工具条：加号、语音、发送、停止、深度思考、搜索、推荐提示词 |
| `chat/file_upload_menu/{paperclip,photo,camera,folder24}` | 加号展开的是相册/拍照/文件 |
| `chat/model_icon/{quick,expert,vision}` + `_fill` | 三个模型图标仍在资源里（但 UI 已不再用「快速/专家/识图」这套叫法） |
| `chat/message/{copyAction,likeAction,dislikeAction,regenerateAction,shareAction,tts_play,tts_stop,referenceListV2,editAction,moreAction}` | 消息操作栏：复制、赞/踩、重试、分享、朗读、引用列表、编辑、更多 |
| `chat/think/{arrow,thinkCollapse}` | 思考块的箭头与折叠 |
| `chat/fragment/{search,open,find}` + `_failed` | 三类工具 Fragment 的图标与失败态 |
| `chat/button/chat_continue` | 「继续生成」 |
| `settings/{moon,sun,fontSize*,letter,phone,microphone,data_config,...}` | 设置页条目 |

据此这一轮改的：

| 项 | 改动 |
|---|---|
| 顶栏 | 左 ☰（`DSIconMenu`，点开回到会话列表）、**中间模型选择**（模型名 + ⌄，点开是带勾列表）、右 ＋ |
| 底部工具条 | 去掉模型 chip（它属于顶栏），只留 深度思考 / 智能搜索 / ＋ / 语音 / 发送（停止） |
| 智能搜索开关 | 以前 `search`/`readUrl` 只是存了个值，`buildPayload` 根本没用 —— 现在关掉就**真的不把 `web_search`/`fetch_url`/`http_request` 发给模型** |
| 工具定义装载 | 以前只在「设置里看工具列表」时才 `loadDefinitions`，没进过那页的话 `defs_` 是空的，智能搜索一个工具都带不上去；现在 `DSBoxService -init` 里一次性装载 |

> 上一版这里写着「只有拿到官方运行截图才能抠」。**其实不用截图** —— 官方图标的原始
> 矢量就在包里，见 6.3。

## 6.3 把官方图标原矢量从 `Assets.car` 里抠出来（2026-11-24 第三次对齐）

没有实物截图，也不靠「按几何特征重绘」。官方包本身就是最权威的参考，只是数据藏在
`Assets.car` 里，需要自己解。完整链路：

### ① `Assets.car` = BOMStore 容器

```
0    'BOMStore'
8    version = 1
12   blockCount
16   indexOffset    ← 块表
20   indexLength
24   varsOffset
28   varsLength
```

块表按 8 字节一条（`address, length`）索引整包 2600 多个数据块。**但不需要用块表**：
每个 rendition 的 `ISTC` 头就紧挨在它自己的数据前面，所以「从数据块往前找最近的
`ISTC`」就能拿到它的资源名。

### ② `ISTC` 头（**小端**）

| 偏移 | 字段 | 例（`iconFile.svg`） |
|---|---|---|
| 0 | `ISTC` | |
| 4 | version | 1 |
| 8 | flags | 0x00000104 |
| 12 | width（像素） | 0 |
| 16 | height | 0 |
| 20 | scale × 100 | 0（矢量原生，无栅格化倍率） |
| 24 | 像素格式 | ` GVS` → 反过来读是 **`SVG `** |
| 40 | 资源名（NUL 结尾） | `iconFile.svg` |

> 踩坑：这几个整数是**小端**。按大端读会得到 `version = 16777216`，一个头都匹配不上。

### ③ 载荷是 LZVN 压缩的（`bvxn`）

`bvxn` 不是 LZFSE v2，是它的快速变体 **LZVN**，没有 FSE/Huffman，自己写 60 行就能解：

```
块头：'bvxn' | u32 n_raw | u32 n_payload        （都小端）
opcode：
  0xE0         大字面量：长度 = 次字节 + 16
  0xE1-0xEF    小字面量：长度 = opc & 0x0F
  0xF0         大 match：长度 = 次字节 + 16，沿用上次距离
  0xF1-0xFF    小 match：长度 = opc & 0x0F，沿用上次距离
  LLMMMDDD + 1 字节      sml_d：L=高2位, M=中3位+3, D=低3位<<8|次字节
  LLMMM111 + 2 字节      lrg_d：同上，D = 16 位
  101LLMMM + 2 字节      med_d：L=bit3-4, M=5 位+3, D=14 位
  LLMMM110               pre_d：同上，沿用上次距离
  0x06 = eos（占 8 字节）  0x0E/0x16 = nop
```

实测校验：解出字节数 **恰好等于** 头里的 `n_raw`，且首个块开头的 `18 0c` 正好解出
`="28" `（回溯 12 字节复制 6 字节）—— 对得上就说明码表没读错。

### ④ 结果

624 个 rendition 里 **182 个是 SVG**，全部解出，`<svg`/`viewBox` 各 184 处、
零位图（`PNG` 计数为 0，栅格 rendition 是裸 BGRA/GA8 像素）。

落地成仓库里的东西：

| 产物 | 说明 |
|---|---|
| `ios/ChatboxIOS/Resources/OfficialIcons/*.svg` | 58 个官方图标**原样**保留，便于日后逐字核对 |
| `scripts/gen-icon-assets.py` | 打成 C 表 `DSIconAssets.h/.m`；`--check` 供 CI 校验是否最新 |
| `ios/ChatboxIOS/Supporting/DSSVGIcon.m` | 自带 SVG 解析器：path 全命令（含弧线转三次贝塞尔）、rect/circle/ellipse/line、fill/stroke/stroke-width/linecap/linejoin/fill-rule、transform |
| `ios/ChatboxIOS/Supporting/DSIcon.m` | 枚举 → 官方资源名，删掉全部手绘近似几何 |

### ⑤ 顺带拿到的官方配色（57 个 SVG 的 fill 统计）

| 色值 | 次数 | 用途 |
|---|---|---|
| `#0F0F0F` | 130 | 主文字 / 主图标 |
| `white` | 58 | 反白（发送箭头、停止方块） |
| `#7D7F85` | 52 | 次要用色（搜索、加号） |
| `#18181B` | 26 | 深一档的文字 |
| `#426EFE` / `#4E77FF` / `#3E5FFE` | 11 | 品牌强调蓝 |
| `#EF4444` | 3 | 危险 |
| `#22C55E` / `#00D158` | 4 | 成功 |
| `#6D93FF → #5A71F0` | — | 品牌渐变（`ic_link_outline` 的 linearGradient） |

`DSTheme` 的 `labelPrimary` / `labelSecondary` / `labelTertiary` / `brand` / `danger`
已按上表校准（`#0F0F0F` / `#7D7F85` / `#8E9094` / `#426EFE` / `#EF4444`）。

### ⑥ 尺寸口径

官方图标只有 **16 / 20 / 24** 三种画布，且文件名自带：
`ic_*_16` 用于输入条开关、`ic_*_20` 用于列表与操作、`ic_*_24` 用于顶栏。
`DSIconPointSizeInline/Action/Nav` 三个常量就是这三个值，调用点一律用它们，
不再各处写 17/21/22 这种手调数字。

> 仍然没有的：**布局数值**（间距、字号、圆角半径）。这些不在 `Assets.car` 里，
> 在 Swift 代码的常量里；要继续抠得反编译 `DeepSeek Chat` 主二进制。

## 6.4 整个应用的骨架重排（2026-11-24 第四次对齐）

前几轮只对齐了图标、配色、文案这些「局部」，骨架还是我们自己的：导航栈 + 系统导航栏。
官方是 **RootViewController + Sidebar 抽屉 + 自绘顶栏**。这一轮把骨架换掉。

### 官方 → 我们 的对照

| 官方类 | 我们的实现 | 说明 |
|---|---|---|
| `RootViewController` | `DSRootViewController` | 聊天页常驻，抽屉盖在上面 |
| `SidebarViewController` | 同上（容器内） | 左侧滑出、遮罩可点关闭、左缘右滑打开 |
| `SessionListViewController` | `DSConversationListController`（`drawerMode`） | 自带「开启新对话 / 搜索 / 列表 / 设置」四段 |
| `SessionListSearchBarView` | 自绘 `UITextField` + 放大镜 | 抽屉里没有导航栏，`UISearchController` 挂不上去 |
| `chat/top_bar/*` | `DSTopBarView` | **自绘 44pt 顶栏**，不再用 `UINavigationBar` |
| `SessionViewController` | `DSChatViewController` | 改成根容器的子控制器，不再叠导航栈 |
| `ProfileViewController` | `DSSettingsViewController` | 从抽屉模态弹出（官方也是从侧栏进） |

### 结构变化带来的行为变化

| 之前 | 现在 |
|---|---|
| ☰ 回到/推入会话列表页 | ☰ 滑出抽屉 |
| 点会话 = push 一个新聊天页 | 点会话 = 换掉根容器的子控制器（栈不增长） |
| ＋ 新对话 = push 又一页 | ＋ 新对话 = 新建会话并换页 |
| 顶栏 = `UINavigationBar` + `navigationItem` | 顶栏 = `DSTopBarView`（☰ / 模型名⌄ / ＋） |
| 输入区毛玻璃 + 分割线 | 页面同色、无分割线 |

### 顺带修掉的静默 bug

「智能搜索点了没反应」的根因不在 UI，在桥接：

```
strcmp([n objCType], @encode(BOOL))   // arm64 上 BOOL 是 C++ bool → "B"
                                      // 而 @(YES) 是 __NSCFBoolean → "c"
```

比不出来 → 当成数字发成 `1` → C++ 侧 `j.value<bool>()` 抛 `type_error.302`
→ `Store::saveSettings` 整体失败、被 catch 掉 → **开关静默无效**。
影响面不只是智能搜索：深度思考、设置页的所有开关都是同一条路径。

修法：改用 `CFBooleanGetTypeID()` 判定；`Settings/UIState::fromJson` 对 0/1 容忍；
补三条回归用例；开关改成即时上色 + 回读校验日志（存不进去会留日志）。

## 7. 构建状态

| 项 | 值 |
|---|---|
| 版本 | `1.12.4.build87`（`CFBundleShortVersionString` 1.12.4 / `CFBundleVersion` 87） |
| Bundle ID | `com.dsbox.chatbox` |
| 架构 / 最低系统 | arm64 / iOS 16.0 |
| 云编译 | GitHub Actions `iOS Build`（macos-latest），最近一次 run `45335475373` **success** |
| 编译警告 | 本工程代码 0 条（仅剩 runner 侧 actions Node20 提示） |
| 产物 | `ChatboxIOS-adhoc.ipa`，2.94 MB，`codesign -s -` ad-hoc 签名 |
| 装真机 | 需 Sideloadly / AltStore / TrollStore 重签（无开发者证书） |
