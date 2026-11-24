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

| 项 | 状态 |
|---|---|
| 用户气泡（淡蓝、右对齐、圆角 18、78% 宽） | 已实现 |
| 助手无气泡、全宽左对齐 | 已实现 |
| 思考块（2px 竖线、14/24、可折叠） | 已实现 |
| 正文 16/28 | 已实现 |
| 会话列表时间分组 + 空态 | 已实现 |
| 输入区（+ / 圆角输入框 / 圆形发送钮） | 已实现 |
| 官方文案表 | 已落地 `DSStrings` |
| 工具卡片三态（搜索/浏览/查找） | **未做**（当前只有一行摘要） |
| Fragment 卡片化 | **未做** |
| 分支切换、引用来源、附件面板、语音输入 | **未做** |
| Lottie 动画接入 | **未做**（需引入 Lottie 依赖） |
| 毛玻璃 / 渐变组件 | **未做** |
