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
