# 官方 iOS UI 结构（从 Mach-O 反编译得到）

> 数据来源：`DeepSeek Chat.app/DeepSeek Chat`（25,368,432 B，arm64 thin，**cryptid=0 未加密**）。
> 复现：`python scripts/dump-official-ui.py <主二进制>`、`python scripts/dump-const-usage.py <主二进制>`。
> 本页所有类名都是**官方原文**，不是我们编的。

## 0. 怎么拿到的（方法留档）

| 目标 | 段 | 方法 |
|---|---|---|
| 类清单 | `__TEXT,__objc_classname` | NUL 分隔串，2051 条；Swift 类是 `_TtC13DeepSeek_Chat<len><Name>` 的 mangled 形式 |
| 字段名 | `__TEXT,__swift5_reflstr` | 9965 条 NUL 分隔串，按类型顺序排 |
| 布局相关串 | `__TEXT,__cstring` | 771 条含 padding/inset/radius/font 等关键词 |
| 浮点常量 | `__TEXT,__const` / `__DATA_CONST,__const` / `__DATA,__data` | 8 字节对齐扫 double |
| 常量引用次数 | `__text` | 简易寄存器追踪 `adrp`+`add`+`ldr d,[x,#imm]` |

**关键判断：cryptid=0**。`LC_ENCRYPTION_INFO_64` 的 cryptid 是 0（cryptsize 只有 0x1000，是占位），
所以 `__text` 段 17.4 MB 代码是**明文**。这个包没被 FairPlay 加密，理论上可以完整反编译。

**技术栈结论（推翻了之前的猜测）**：

- **UIKit + FlexLayout（flexbox）**，不是手写 NSLayoutConstraint。
  证据：导入符号里 `_$s10FlexLayout0A0C10marginLeftyAC12CoreGraphics7CGFloatVF`、
  `paddingEnd`、`AlignItems`、`LayoutMode.adjustWidth/adjustHeight/fitContainer` 等一整套。
- **不是 SwiftUI**。`UIHostingController` 只在导入符号里出现一次，是某个边缘功能用的。
- 配套库：`SVGKit`（渲染 Assets.car 里的 SVG）、`WCDBSwift`（本地库）、`Alamofire`（网络）。

## 1. 官方完整视图树

缩进表示 Swift 嵌套类型（`InputAreaView.TextInputView.Layout` 这种）。

```
RootViewController
├── SidebarViewController
│   ├── MainDecorationView          ← 抽屉打开时主页面缩成圆角卡片的那层
│   ├── CornerReferenceView         ← 圆角转角的参考视图（算曲率用）
│   └── SessionListViewController
│       ├── SessionListSearchBarView
│       │   └── SearchFieldView
│       ├── SessionListCollectionView        ← 注意：CollectionView，不是 TableView
│       │   ├── Header
│       │   ├── Cell
│       │   │   └── TitleLabel
│       │   ├── VirtualRootCell              ← 虚拟根 cell（分组标题的容器）
│       │   ├── SkeletonRowsView             ← 骨架屏
│       │   ├── LoadMoreSkeletonCell
│       │   ├── LoadMoreFailedCell
│       │   ├── Footer
│       │   └── FooterHeightResolver
│       ├── SessionListSearchResultCell
│       │   └── SnippetView                  ← 搜索结果高亮片段
│       ├── SessionListMultiSelectBottomBar
│       │   └── ItemButton
│       └── FooterView
└── SessionViewController
    ├── Coordinator
    ├── MessageViewController
    │   ├── EmptyView                        ← 空态是独立视图，不是表格的一部分
    │   ├── BackToBottomButton
    │   ├── InputAreaContainerView
    │   │   ├── InputTopBannerWrapperView
    │   │   │   ├── InputTopBannerView
    │   │   │   └── InputTopBannerMaskView
    │   │   ├── InputAreaAndMuteView
    │   │   │   ├── ShareButtomView
    │   │   │   │   └── ShareActionButton
    │   │   │   └── InputAreaView
    │   │   │       ├── BannerView
    │   │   │       ├── EditingView / EditContext
    │   │   │       ├── TextInputView              ← 输入框本体
    │   │   │       │   ├── Layout                 ← 布局常量结构体（官方自己的命名）
    │   │   │       │   └── TextView
    │   │   │       ├── PromptInputView
    │   │   │       ├── ActionAreaView             ← 按钮区
    │   │   │       │   ├── ToggleButtonGroup
    │   │   │       │   │   └── ToggleButtonContainer
    │   │   │       │   │       └── ToggleButton   ← 深度思考 / 智能搜索
    │   │   │       │   ├── SearchOperationView    ← 搜索运行态
    │   │   │       │   ├── ReasoningOperationView ← 思考运行态
    │   │   │       │   ├── UploadButton
    │   │   │       │   ├── VoiceInputButton
    │   │   │       │   ├── SendButton
    │   │   │       │   └── TextButton
    │   │   │       ├── VoiceRecord / VoiceGesture / VoiceGestureContext / VoiceReportContext
    │   │   │       └── VoiceButton / ButtonContainerView
    │   │   └── MuteAlertView
    │   ├── MessageListView
    │   │   └── BottomLanding                ← 「底部着陆」，贴底检测
    │   ├── BaseMessageCell
    │   │   └── ContextMenuGestureDelegate
    │   ├── AgentMessageView
    │   │   ├── AvatarView
    │   │   └── InnerAvatarView
    │   ├── BaseAgentMessageView
    │   │   └── ViewMaker
    │   ├── BaseMessageOperationBar
    │   │   └── Coordinator
    │   └── ModelSelectorView
    │       └── ModelLongPress / ModelPan / ModelTap
    └── ProfileViewController                ← 设置页
        ├── InsetsGroupedCell / InsetsGroupedLayer
        ├── SectionHeader / SectionFooter
        ├── TableFooterView
        ├── ForwardChevron
        ├── ThemePicker
        └── AudioInputLanguagePicker
```

组件层（跨页面复用）：

```
DSButton                      ← 全站按钮的唯一实现
├── ImageConfig
├── TitleConfig
├── BorderConfig
├── IconTitleConfig
├── ScaledImageConfig
└── ConfigurationUpdateHandler

VariableBlurView              ← 可变强度模糊（顶栏/输入区渐隐）
├── ExclusionState
└── BackdropSegmentView

PromptSuggestionView
└── TemplateButton            ← 空态里的建议问题

HeaderTextView
└── TailMaskView

GlassRimBorderView
├── EDRWhiteView
└── GradientView

TextSelectionMenuView
├── ItemControl
└── HighlightView

CitationView
└── BrandBadgeContentView

FeedbackBadView
├── TagView
└── TagsView

DSAnimation                   ← 动画统一入口
```

## 2. 提炼出的官方设计常量

### 2.1 尺寸表（`__DATA,__data`，成组存放，可信度高）

| 地址 | 值 | 推断含义 |
|---|---|---|
| `0x1650090` | `20 64 56 44 28 24 24` | 图标 20 / 头像 64 / 行高 56 / **触控区 44** / 小图标 28 / 图标 24 / 图标 24 |
| `0x164ffd0` | `16 × 7` | 7 个组件共用间距 16 |
| `0x1650030` | `20 × 7` | 7 个组件共用 20 |
| `0x16207b0` | `0.5 1 2 3 4 5 6 7 8 9 10` | 刻度序列（非布局） |
| `0x1656e98` | `2.5 5 10 20` | 进度/缩放档位 |

**`44` 与 `16` / `20` 是最硬的三个数**：44 是 Apple 触控区下限，16/20 各被 7 处共用。

### 2.2 字号表（`__TEXT,__const`，递增序列）

```
0x12112b8: 20 13 14 15 16 18 20 22 26 32 38 43 51   22 23 24 25 26 28 32 36 43 50 56 64
0x120d2c0: 14 15 16 17 19 21 23 28 33 40 47 53      23 24 25 26 27 29 33 38 44 52 60 66
0x120da10: 12 13 17 19 21 24 30 36 41 48            21 23 26 27 33 35 41 47 53 61 12 16
0x120e000: 15 17 19 23 27 33 38 44                  21 22 24 26 37 44 50 57
```

四组都是**单调递增**，且起点是 12~20、跨度到 50~66 —— 这是 Dynamic Type 的字号缩放表
（每个 text style 在各 content size category 下的字号），**不是布局间距**。
可用的信息：正文基准字号落在 **15/16/17** 三档，小字 **12/13/14**，标题 **20/22**。

### 2.3 圆角与间距（零散，可信度中）

`0x120d170: 32 40 24 84 24 40`、`0x120e9b0: 44 4 20 15 23 29`、`0x1232f70: 13 16 11 16 11.5 12`

`11.5` 这个值出现得很有意思（不是整数，通常是有意为之的视觉修正）。

### 2.4 拿不到的（必须说清楚）

**「哪个视图用哪个数值」拿不到。** 原因：

1. 官方布局走 FlexLayout，`padding(16)` 这种 CGFloat 字面量，**能编成立即数的就编进指令**
   （`fmov d0, #16.0`），不能编的才进常量池。而 20/22/44 这类恰好是 `fmov` 编不出来的，
   却又被大量内联 —— 扫描常量池只能捞到 27 个 UI 值，且全是角度（300/360）和色值（255/180）。
2. 要把数值归因到视图，必须知道函数边界 + 做完整数据流分析。本机装不上 capstone
   （`pip install` 被沙箱拦），只能手写单条指令解码，做到「统计常量被引用几次」为止。

**要拿到精确归因，需要**：capstone/objdump 反汇编 + Swift 符号恢复（`_$s` mangled 名 →
demangle），把每个函数和类对上。这是一项独立的、更大的工作。

## 3. 我们 vs 官方：差异表

| 项 | 官方 | 我们（build 121） | 影响 |
|---|---|---|---|
| 根容器 | `RootViewController` | `DSRootViewController` ✅ | 已对齐 |
| 抽屉 | `SidebarViewController` | 自绘 drawer ✅ | 已对齐 |
| **抽屉打开时主页面缩放圆角** | `MainDecorationView` + `CornerReferenceView` | **无** | 观感差异明显 |
| 会话列表 | **UICollectionView** + 骨架屏 + 加载更多 | UITableView | 中等 |
| 会话搜索 | `SessionListSearchBarView.SearchFieldView` | 自绘 UITextField | 小 |
| 空态 | `MessageViewController.EmptyView` 独立视图 | 内嵌 label | 小 |
| 输入区 | `TextInputView` → `ActionAreaView` → `ToggleButtonGroup` 三层 | 单层 stack | **大** |
| chips 容器 | `ToggleButtonGroup` + `ToggleButtonContainer` | 直接塞 stack | 中等 |
| 搜索/思考运行态 | `SearchOperationView` / `ReasoningOperationView` 独立视图 | 无（只改 chip 颜色） | **大** |
| 回到底部 | `BackToBottomButton` | 无 | 中等 |
| 按钮 | **统一 `DSButton`** + 5 种 Config | 各处手写 UIButton | **大（这是「不像」的深层原因）** |
| 顶栏渐隐 | `VariableBlurView` | 无 | 小 |
| 设置页 | `ProfileViewController` + `InsetsGroupedCell` | 手写 tableView | 中等 |
| 布局方式 | **FlexLayout（flexbox）** | NSLayoutConstraint 手写 | 结构性差异 |

**最该先补的三件事**（按观感收益排序）：

1. **`DSButton` 统一按钮** —— 官方所有按钮同源，我们各处手写，这才是「看着不像」的根因，
   比任何单个数值都重要。
2. **输入区三层结构** + `ToggleButtonGroup` —— 输入区是用户停留时间最长的区域。
3. **`MainDecorationView`**（抽屉打开时主页面缩放成圆角卡片）—— 一眼就能看出是官方的那一手。
