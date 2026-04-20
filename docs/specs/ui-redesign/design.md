# Aether UI Redesign — Design

## §1 新 IA

### 侧栏（5 项，平铺，无 Section header）

```
  首页      Home
  语音      Voice
  指针      Pointer
  快捷键    Shortcuts
  设置      Settings
```

HIG 依据：macOS Sidebar 建议 5–10 项顶层，超过需要分组。Aether 的 14 项是"分组也救不了"的量级，先压到 5。每项用 SF Symbol + 粗体 16pt 文字（和当前 sidebarItem 一致）。

**侧栏组件选型**：`NavigationSplitView` + `List(selection:)`，和现在一致，不改结构。

**默认窗口尺寸**：保持 1120×760（不改，避免和侧栏压缩一起变——Phase 3 翻车的一条原因是同时改了两个）。

### 每个侧栏项的内部布局原则

| 侧栏项 | 内部布局 | 为什么 |
|---|---|---|
| 首页 | 单页 `ScrollView`，纵向 Section | 首页是摘要，没有子 tab 语义 |
| 语音 | 单页 `Form` 纵向展开两个 `Section`（输入 / 文字优化） | **不用 segmented control**。HIG: System Settings 用 scrolling Form + Section |
| 指针 | 单页 `Form` | 只有一组设置 |
| 快捷键 | 单页 `Form` | 同上 |
| 设置 | 左 7 行 List + 右 content（类 System Settings 风格） | 设置是"容器"，有多个平行分类 |

**关键反 pattern**：**不用 TabView 也不用 Picker segmented** 来分"等价的两半"。Phase 3 的 VoiceSettingsCombinedView 就是这么翻车的——SwiftUI 在两个分支都是同一 struct 时 view identity 不切换，Picker 点了看起来没反应。一页滚动就能解决，视觉和 HIG 都更干净。

## §2 首页（Home）

### 目标叙事

回答一个问题：**"Aether 正在为我做什么？"**

不是"设置清单"，不是"权限卡"，是**状态 + 建议 + 摘要**的叙事。

### 布局（从上到下）

```
┌────────────────────────────────────────────┐
│ [可选] 欢迎卡片（首次启动才显示）            │  ← Welcome hero
├────────────────────────────────────────────┤
│ [可选] 阻断横幅（有未就绪权限才显示）        │  ← Blocking banner
├────────────────────────────────────────────┤
│ 现在                                         │  ← Section "现在"
│ ● 头控：已开启      [开关] [进入指针页]     │     3 行状态 + 快速开关
│ ● 语音输入：已开启  [开关] [进入语音页]     │
│ ● 语音控制：已开启  [开关] [进入语音页]     │
├────────────────────────────────────────────┤
│ 试试（可选）                                 │  ← Section "试试"
│ 动态建议（未校准/未试用/未配 iPhone Remote） │     2-3 卡片
├────────────────────────────────────────────┤
│ 最近（可选）                                 │  ← Section "最近"
│ 最近 3 条 VoiceUsage 摘要                    │
└────────────────────────────────────────────┘
```

### 数据绑定

- **Welcome 卡片**：`@AppStorage("AetherHomeWelcomeDismissed")` 为 false 时显示，点"开始使用"写 true
- **阻断横幅**：`appState.missingPermissionCount > 0` 时显示，点"去修复"跳 `.settings(.permissions)`
- **头控行**：`appState.isHeadTrackingEnabled`（和 Pointer 页的开关同 binding）
- **语音输入行**：`appState.isVoiceInputEnabled`
- **语音控制行**：`appState.isVoiceControlEnabled`
- **"试试"卡片**：动态列表，由 `HomeSuggestionEngine`（新增 struct）计算。首版规则：没做过 AirPods 校准 → 显示"试试 AirPods 头追校准"；没试过唤醒 → "说一句 '你好 Aether'"
- **"最近"**：复用 `VoiceUsageInsights` 的数据源（**不复用 UI**），只取最近 3 条

### 不做

- **不把权限卡搬进 Home**。权限在"设置 → 权限"tab，Home 只在有异常时显示一条横幅（链接过去）
- **不把 Overview 的 4 个顶层开关直接搬过来**。"现在"section 的 3 行虽然也是开关，但是**新写的轻量行**（状态文字 + 小开关 + 跳链），不是把 `OverviewDashboardView` 复制过来

### 反 Phase 3 要点

- 不用 segmented control 组织 Home 内容（Phase 3 的教训）
- 不把 Home 做成"上下两半平行"——是**纵向摘要**，不是双栏
- 新 `HomeView` 是纯新增 SwiftUI struct，不 rename 旧 `OverviewDashboardView`（保留作为 fallback，用环境变量 `AETHER_LEGACY_OVERVIEW=1` 可切回，应急用；下一版 spec 彻底删）

## §3 设置容器

### 进入点

侧栏的"设置"项路由到 `SettingsContainerView(initialTab:)`。默认 tab `.permissions`。

### 内部结构（左 List + 右 content）

```
┌─────────────┬──────────────────────────┐
│ 权限         │ (对应 tab 的 content)     │
│ 词库         │                           │
│ App 规则     │                           │
│ 启动别名     │                           │
│ 导入导出     │                           │
│ 诊断         │                           │
│ 关于         │                           │
└─────────────┴──────────────────────────┘
```

**7 个 tab** 每个对应原 14 项里的 1 项：

| 设置 tab | 原 14 项 | content |
|---|---|---|
| 权限 | 6. Permissions & Status | `PermissionsStatusSettingsView` 原样 |
| 词库 | 7. Lexicon | `InputSettingsView(section: .lexicon)` 原样 |
| App 规则 | 8. App Rules | `AppRulesSettingsView` 原样 |
| 启动别名 | 9. Launch Aliases | `AppLaunchAliasesSettingsView` 原样 |
| 导入导出 | 10. Import & Export | `ImportExportSettingsView` 原样 |
| 诊断 | 11-13. Voice Usage / Wake / Focus | `DiagnosticsContainerView` 内部 segmented control 3 子页（**这里 segmented 可以用**，3 个 case 是不同 struct，没有 Phase 3 的 identity 问题） |
| 关于 | 14. About | `AboutCenterView` 原样 |

### 权限 tab 右上角 badge

`SettingsTabSidebar` 的"权限"行如果 `appState.missingPermissionCount > 0`，右侧显示橙色数字 badge（`Circle().fill(.orange).frame(20×20)` + 白字）。

## §4 Onboarding

### 触发条件

`@AppStorage("AetherOnboardingCompleted") == false` 时，App 启动后弹出独立 `NSWindow`。主窗先不显示，等 onboarding 完成或跳过后才显示。

### 窗口

- 尺寸 720×520，`styleMask = [.titled, .closable]`（不可 resize）
- Title："欢迎使用 Aether"
- 7 个 step 横向切换（progress dots 在底部）

### 7 步

1. **Welcome** — Aether 是什么，一句话定位 + 一张 hero 图（可选）
2. **麦克风权限** — "请求权限" 按钮 + "稍后"
3. **语音识别权限** — 同上
4. **辅助功能权限** — 同上，附"打开系统设置"按钮
5. **AirPods 校准演示**（可跳）— 有 AirPods 连接时显示演示；无则直接跳过
6. **说一句话试试**（可跳）— "说 '你好 Aether'"，检测到唤醒后显示 checkmark
7. **完成** — "开始使用" 按钮，写 `AetherOnboardingCompleted = true`，关闭此窗，显示主窗

### 持久化状态

- `AetherOnboardingCompleted: Bool` — 全局完成标记
- `AetherOnboardingStepCompleted.<step>: Bool`（7 个）— 单步状态；重启后从最后一个未完成步骤恢复

### 反 pattern

- 不阻止用户关闭 onboarding 窗（关了等于"稍后再做"，主窗弹出，Home 的阻断横幅提醒未完成设置）
- 不在 onboarding 里改业务逻辑。权限请求按钮调用**已存在**的 `AppState.requestMicPermission()` 等方法

## §5 Menu bar 重设计

### 现状

Menu bar Label："Aether · [详细状态副标题]"。菜单项 ~10 个，含 3 个独立的权限"修复"按钮。

### 新设计

- **Label 简化**："Aether · ✓ 就绪" / "Aether · ⚠ 未完成" / "Aether · ✕ 未激活"
- **菜单项 ~6 个**：主窗 / HUD 开关 / 快速暂停 / 分隔 / 开始设置（只在未就绪时出现，一个按钮跳 `.settings(.permissions)`）/ 退出
- **去状态副标题**（和 Home 重复）
- **3 个权限按钮 → 1 个"开始设置…"**（Phase 5 onboarding 实现后改成跳 onboarding；之前先跳到设置 → 权限）

## §6 视觉语言

### Typography（全部用 HIG 语义字体，不写数字）

| 用途 | SwiftUI API | 对应 pt |
|---|---|---|
| 页面大标题 | `.largeTitle` (`.bold`) | 26 |
| 卡片标题 | `.headline` | 13 bold |
| 正文 | `.body` | 13 |
| 次要说明 | `.caption` | 11 |
| 辅助文字 | `.caption2` | 10 |

不用自定义字号。HIG 依据：语义字体跟随系统字号设置（辅助功能用户会放大，写死 16pt 会破坏）。

### Spacing

| 用途 | 值 |
|---|---|
| 卡片之间纵向间距 | 12 |
| 卡片内部 padding | 20（继承现 GlassCard） |
| Form Section 间距 | 24 |
| Section 标题与内容间距 | 8 |
| 按钮/开关 trailing 边距 | 12 |

### Color tokens（全部 semantic）

| 用途 | Token |
|---|---|
| 主强调色 | `Color.accentColor` |
| 主文字 | `.primary` |
| 次要文字 | `.secondary` |
| 容器背景 | `Color(nsColor: .controlBackgroundColor)` |
| 窗口背景 | `Color(nsColor: .windowBackgroundColor)` |
| 成功 | `.green` |
| 警告 | `.orange`（橙，不红） |
| 错误 | `.red` |

**严禁**自定义 hex 颜色。HIG 依据：用户的 Accent Color / Accessibility Contrast 设置能正确继承。

### 组件选型规则

| 场景 | 首选 | 次选 | 什么时候用 GlassCard |
|---|---|---|---|
| 设置页（Voice / Pointer / Shortcuts） | `Form` + `Section` | — | 不用 |
| 首页 Home | `ScrollView` + `GroupBox` | — | "现在" section 每行可用 GlassCard |
| Home 的 hero / welcome 大卡 | `GlassCard` | — | ✓（视觉 accent） |
| Settings 容器右侧 | `Form` | `ScrollView` + `GroupBox` | 不用 |
| Onboarding step | `VStack` 纵向 + 留白 | — | 不用（太重） |

**GlassCard 用法守则**：只在需要视觉 accent 的地方用（Home 的 hero、"现在"的快速开关行）。Settings 页**全部用 Form**，不要套 GlassCard——Settings 是低频、密度高、阅读导向的面板，Form 的原生外观更合适。

## §7 各页面详细 Layout

### 7.1 首页

见 §2。

### 7.2 语音

```
Form {
    Section("输入") {
        LabeledContent("麦克风") { microphonePicker }
        LabeledContent("识别语言") { speechLanguagePicker }
        Toggle("启用语音输入", isOn: …)
        … (原 InputSettingsView(.basics) 的所有 card)
    }

    Section("文字优化") {
        … (原 InputSettingsView(.textCleanup) 的所有 card，含 LLMRewriteSettingsCard)
    }
}
```

**空状态**：没有可用麦克风时 `ContentUnavailableView("无可用麦克风", systemImage: "mic.slash")` 替换"输入"section。

**迁移**：原 `InputSettingsView(section: .basics)` 和 `InputSettingsView(section: .textCleanup)` 的内部 VStack+GlassCard 直接搬进来，外层包 `Section`。不动内部 card 结构。

### 7.3 指针

```
Form {
    Section("指针源") {
        Picker("当前使用", selection: $pointerSource) {
            Text("AirPods 头追").tag(PointerSourceID.airpodsHead)
            // Text("iPhone 激光笔").tag(...)  // iPhone Remote 就绪后 uncomment
        }
    }

    Section("头追") {
        … (原 PointerSettingsCardContent)
    }

    Section("热区") {
        … (原 HeadGestureSettingsContent 的 body，hide diagnostics)
    }
}
```

**iPhone Remote 钩子**：见 §9。

### 7.4 快捷键

```
Form {
    Section { HotkeySettingsSection() }
}
```

原样包一层 Form。

### 7.5 设置（容器）

见 §3。

### 7.6 关于

原 `AboutCenterView` 作为"设置 → 关于" tab 的 content，不改。

## §8 What's New 气泡

老用户从 b141+ 升到新 UI 版本时，首次打开主窗，Home 页右上角显示一次性气泡：

```
┌─────────────────────┐
│ 新界面 ✨            │
│ 侧栏精简到 5 项，    │
│ 设置页合并了。        │
│             [我知道了] │
└─────────────────────┘
```

`@AppStorage("AetherWhatsNewV5_Shown")` 控制，点"我知道了"或 10 秒后自动消失，写 true。

## §9 iPhone Remote 钩子

iPhone Remote spec（`../iphone-remote/`）的 Phase 4 Mac UI 接入位置：**"指针"页的"指针源" Picker**（§7.3）。当 iPhone 已配对且连上，picker 多一项"iPhone 激光笔"。未配对时多一个 footer 链接"配对 iPhone…"跳到一个配对 sheet。

**本 spec 只预留 Picker 的位置和 `PointerSourceID` 占位 enum**，实际 iPhone Remote 的 `RemoteService` / 配对 flow 不在本 spec 范围。

## §10 非目标（明确不做）

- **不拆 `SettingsModules.swift`**。6619 行继续是一个文件，只是被各 tab 引用。下一版 spec 专门处理。
- **不改 HUD**。`HUDManager` 是黑盒。
- **不改 Menu bar 图标**。只改 Label 文案和菜单项。
- **不做灰度开关 / legacy sidebar toggle**。工程债不划算。
- **不做国际化补充**（现有 zh/en 原样沿用）。
- **不改 `@AppStorage` / `UserDefaults` key**。
- **不引入新依赖**（不加 Pointfree 的 ComposableArchitecture / SwiftData 等）。
