# IA Refresh — Design

## 1. 背景

现状（对话里盘点过的硬数据）：

- 侧栏 **14 项 / 6 组**
- `SettingsModules.swift` **6619 行** / 约 **52 个控件**
- 权限重复显示 **3 处**（Overview / Menu bar / Permissions & Status）
- `OnboardingStep` enum 存在但**没有 UI**，首次启动就是 Overview 页
- Overview 实际是"权限卡 + 4 个开关"，没回答"这个 App 能帮我做什么"

## 2. 目标

1. 新用户第一次打开能**一眼看懂这个 App 是干嘛的**
2. 新用户能**不看文档跑通一次听写 / 一次头追**
3. 老用户要找的设置**不丢**（位置可能换，内容一个不少）
4. 叠加 iPhone Remote 时**不再让侧栏变长**

非目标：精简功能、改名术语、优化具体设置页的内容。

## 3. 侧栏映射

### 3.1 新侧栏（5 项，无分组）

```
Home             (新，Panel.home)
语音             (Panel.voice)
指针             (Panel.pointer)
快捷键           (Panel.shortcuts)
设置             (新容器，Panel.settings)
```

去掉现在的 6 个 Section header（Workspace / Voice / Controls / App / Advanced / Logs & Diagnostics）。5 项平铺，不分组。

### 3.2 14 项的去向

| 现有 Panel | 去向 |
|---|---|
| `overview` | **Home**（整页重写，不是搬运） |
| `voiceInput` | 语音（页内 section 1：输入） |
| `textCleanup` | 语音（页内 section 2：文字优化） |
| `controlsPointerHotZones` | **指针**（直接改名，内容不动） |
| `controlsShortcuts` | **快捷键**（直接改名，内容不动） |
| `permissionsStatus` | 设置 → tab "权限" |
| `advancedLexicon` | 设置 → tab "词库" |
| `advancedAppRules` | 设置 → tab "App 规则" |
| `advancedLaunchAliases` | 设置 → tab "启动别名" |
| `advancedImportExport` | 设置 → tab "导入导出" |
| `logsVoiceUsage` | 设置 → tab "诊断"（sub-section A） |
| `logsWakeActivation` | 设置 → tab "诊断"（sub-section B） |
| `logsFocusDiagnostics` | 设置 → tab "诊断"（sub-section C） |
| `about` | 设置 → tab "关于" |

"设置"内部 **7 个 tab**，用 `Picker(.segmented)` 或左侧二级导航实现（见 §6）。

### 3.3 Panel 枚举重做

```swift
enum Panel: Hashable {
    case home
    case voice
    case pointer
    case shortcuts
    case settings(SettingsTab)
}

enum SettingsTab: Hashable {
    case permissions
    case lexicon
    case appRules
    case launchAliases
    case importExport
    case diagnostics
    case about
}
```

旧的 14 个 case 全部删掉。Deep link（比如从 Menu bar 点"权限"）直接导航到 `.settings(.permissions)`。

## 4. Home 页设计

Home 回答三个问题，每个问题一个 section：

```
┌─────────────────────────────────────────┐
│ [Welcome hero，仅首次启动未完成 onboarding 时] │
│ 一句话介绍 Aether + "开始使用" 按钮          │
├─────────────────────────────────────────┤
│ ⚠ 阻断横幅（仅有阻断问题时出现）              │
│ 例："麦克风权限未开启，语音输入无法使用 [修复]"│
├─────────────────────────────────────────┤
│ 现在                                     │
│ ● 指针 · 已启动 · AirPods Pro              │
│ ○ 语音输入 · 未监听 · [开启]                │
│ ○ 语音控制 · 未监听 · [开启]                │
├─────────────────────────────────────────┤
│ 试试                                     │
│ · 戴上 AirPods，按 ⌘⌃Space 校准           │
│ · 说 "Hey Aether，打开 Safari"            │
│ · 看 30 秒演示 →                          │
├─────────────────────────────────────────┤
│ 最近                                     │
│ · 今天识别 24 段 · 7 个 App                │
│ · 指针累计 3 小时 · 最长一次 42 分钟         │
│ · [打开诊断 →]                            │
└─────────────────────────────────────────┘
```

### 4.1 section 行为

- **Welcome hero**：只在 `onboardingCompleted == false` 时显示；完成后永久隐藏
- **阻断横幅**：有任一核心权限缺失时显示一条；多个权限缺失只显示"未完成设置 [继续设置]"一条，点了进 onboarding 继续
- **现在**：3 行固定状态，各自带快速开关。**不再显示 4 张 GlassCard**（现在的 PointerControlTile / VoiceBasicsTile / VoiceInputTile / VoiceControlTile）
- **试试**：3 条建议，根据状态动态：未校准提示校准、未用过唤醒词提示唤醒词、已都用过就提示高级功能（热区、lexicon 等）
- **最近**：复用现有 `VoiceUsageInsightsCard` 的数据源，**只取 3 行 summary**，详情按钮跳到诊断 tab

### 4.2 Home 不做什么

- 不重复权限卡片（已经在阻断横幅里了）
- 不放 4 张功能开关卡（拆成"现在"的 3 行紧凑状态）
- 不放设置入口（所有设置都在侧栏"设置"里）

### 4.3 文件

- 新增 `Home/HomeView.swift` — 页面根
- 新增 `Home/HomeWelcomeHero.swift`
- 新增 `Home/HomeBlockingBanner.swift`
- 新增 `Home/HomeNowSection.swift`（"现在"三行）
- 新增 `Home/HomeTrySection.swift`
- 新增 `Home/HomeRecentSection.swift`
- 改 `AetherMainView.swift` — `selection` 默认 `.home`，`case .home: HomeView()`

现有 `OverviewDashboardView` 改名 `LegacyOverviewDashboardView`，保留**一个 release cycle** 以防回退（见 §8），之后删除。

## 5. Onboarding 设计

### 5.1 触发

`@AppStorage("AetherOnboardingCompleted") var onboardingCompleted: Bool = false`

- 首次启动 / `onboardingCompleted == false` → App 启动完直接弹 onboarding 窗
- 用户可以关闭窗口（`onboardingCompleted` 保持 false，Home 会继续显示 Welcome hero）
- 完成最后一步或点"跳过设置" → `onboardingCompleted = true`

### 5.2 步骤

```
Step 1: Welcome
  · "Aether 把头部动作变成光标，把语音变成文字"
  · 3 个图标+短句：指针 · 听写 · 快捷键
  · [开始] [跳过]

Step 2: 辅助功能权限
  · 说明 + [开启辅助功能] 按钮
  · 开启后自动推进；用户拒绝后显示 [已知晓，下一步]

Step 3: 麦克风权限
  · 同上

Step 4: 语音识别权限
  · 同上

Step 5: AirPods 校准（可选）
  · 检测是否已连上 AirPods
  · 未连：显示"稍后连上 AirPods 再来 Home 校准"，直接跳 Step 6
  · 已连：短动画 + "看屏幕正中" + 3 秒倒计时 → 完成

Step 6: 试说一句话（可选）
  · 按住大按钮说"你好 Aether"
  · 实时显示识别到的文字
  · 成功 → 绿色 checkmark + "完成"
  · 失败/跳过 → 直接"完成"

Step 7: 完成
  · "已就绪" + "要了解更多功能，随时在 Home 页看'试试'"
  · [打开 Aether]
```

### 5.3 文件

- 新增 `Onboarding/OnboardingCoordinator.swift` — 状态机
- 新增 `Onboarding/OnboardingWindow.swift` — 独立 `NSWindow`，居中 720×520
- 新增 `Onboarding/Steps/OnboardingWelcomeStep.swift` …… 7 个 step view
- `AetherApp.swift` — 启动时检查 `onboardingCompleted`，未完成就调 `OnboardingWindow.present()`

### 5.4 和现有 `OnboardingStep` enum 的关系

现在的 `OnboardingStep` 只是权限状态派生，名字冲突。改名 `PermissionSetupStage`，`AppState.onboardingStep` 改 `permissionStage`，避免和新的 Onboarding 流程混淆。

## 6. 设置页内部 tab

### 6.1 结构

```swift
struct SettingsContainerView: View {
    @State private var tab: SettingsTab = .permissions
    var body: some View {
        VSplit {
            SettingsTabSidebar(selection: $tab)  // 左侧 7 行竖列
            SettingsTabContent(tab: tab)          // 右侧内容
        }
    }
}
```

左侧二级列表（不是 segmented control——7 个 tab 放 segmented 太挤），7 行：

```
权限          ⚠ 2 项待开启
词库
App 规则
启动别名
导入导出
诊断
关于
```

### 6.2 tab 内容

每个 tab 的 content view 就是原来那个 view，**原样放进来**，不做任何修改：

| Tab | 内容 view |
|---|---|
| 权限 | `PermissionsStatusSettingsView`（现有） |
| 词库 | `InputSettingsView(section: .lexicon)` |
| App 规则 | `AppRulesSettingsView`（现有） |
| 启动别名 | `AppLaunchAliasesSettingsView`（现有） |
| 导入导出 | `ImportExportSettingsView`（现有） |
| 诊断 | 新 `DiagnosticsContainerView`，内嵌原 3 个 logs view 作 sub-section |
| 关于 | `AboutCenterView`（现有） |

### 6.3 诊断 tab 的 sub-section

3 个 logs view（`logsVoiceUsage` / `logsWakeActivation` / `logsFocusDiagnostics`）在"诊断"tab 里用 segmented control 切换：

```
[ 语音使用 | 唤醒与激活 | 焦点诊断 ]
```

这 3 个长度不至于挤，7 个才挤。

## 7. Menu bar 去冗余

### 7.1 现状

Menu bar 现在展示：

- 图标 + 状态 label（Ready / Pointer active / Needs setup）
- 状态副标题（权限缺失提示等）
- 3 个权限修复按钮（只在缺失时）
- 语音输入 toggle
- 语音控制 toggle
- 快捷键面板
- 检查更新
- 设置…
- 退出

### 7.2 新版

```
[图标 only，颜色表达状态：灰正常/绿运行中/橙需设置]
  ↓ 点开
Label: "Aether · ✓ 就绪" / "Aether · ⚠ 未完成设置"
----------------
(仅未完成时) "开始设置..."    → 启动 Onboarding
----------------
☐ 语音输入
☐ 语音控制
----------------
显示主窗口
快捷键面板
----------------
检查更新...
退出
```

3 个独立权限按钮 → 1 个"开始设置..."（进 onboarding 继续未完成的步骤）。
状态副标题行删掉（Home 页已经有完整状态）。

### 7.3 文件

改 `MenuBar.swift`，`body` 里删掉权限分支，加 `openOnboarding()`。

## 8. 迁移与老用户

### 8.1 不做 legacy sidebar 开关

理由（已达成共识）：老用户是重度用户，能接受 IA 变好；工程债不值得为 3 个月缓冲付。

### 8.2 What's New 气泡

升级后**第一次打开主窗口**时，Home 页右上角弹一个气泡：

```
┌─────────────────────────────┐
│ 界面有变化 🎨                 │
│ · 侧栏从 14 项简化成 5 项      │
│ · 高级设置都在"设置"里         │
│ · Home 页现在是主入口          │
│                              │
│ [知道了]  [15 秒快速了解 →]   │
└─────────────────────────────┘
```

实现：`@AppStorage("AetherWhatsNewV5_Shown") var shown: Bool = false`，未显示过且 `onboardingCompleted == true` 时显示。点过一次不再出。

### 8.3 设置迁移

所有 `UserDefaults` key 不动，所有 `@AppStorage` 绑定不动。因为我们**只搬 view，不改 model**。用户现有配置完整保留。

### 8.4 回退预案

`LegacyOverviewDashboardView` 保留一个 release cycle。如果 Home 页上线后收到严重 negative feedback，环境变量 `AETHER_LEGACY_OVERVIEW=1` 启动可切回旧 Overview（侧栏仍是新的，只是 Home 页替换）。下一个大版本前删掉。

## 9. View 渲染层实现要点

### 9.1 `AetherMainView.swift` 的变化

```swift
// 侧栏 List 里，以前是 6 个 Section 组
// 现在是平铺 5 行，不分 Section
List(selection: $selection) {
    sidebarItem(.home).tag(Panel.home)
    sidebarItem(.voice).tag(Panel.voice)
    sidebarItem(.pointer).tag(Panel.pointer)
    sidebarItem(.shortcuts).tag(Panel.shortcuts)
    sidebarItem(.settings(.permissions)).tag(Panel.settings(.permissions))
}
```

`.settings(.permissions)` 进入 `SettingsContainerView(initialTab: .permissions)`。

### 9.2 侧栏宽度

现在 `SidebarMetrics.preferredWidth()` 按 14 项最长 title 算。改成按新 5 项算，侧栏能窄不少（估计 180pt 就够）。

### 9.3 Window 默认尺寸

Home 页内容密度远低于现在的 Overview。主窗口默认尺寸可以从现在的 1080×720 缩小到 **960×640**，让 Home 看起来更紧凑。`AetherApp.swift` 里 `WindowGroup` 默认 frame 调整。

## 10. 不触碰清单

这些文件本次**一行不改**：

- `SpeechManager.swift`（10914 行）
- `HeadMotionManager.swift`（除了新 Home 页订阅它的 published property）
- `HUDManager.swift` / `HUDView.swift`
- `VoiceCommandRouter.swift`
- `DictationHandler.swift`
- `InputControlArbiter.swift`
- `WakeWordDetector.swift`
- `CaretDetector.swift`
- `SettingsModules.swift` **内部不改**——只是被新的 `SettingsContainerView` 包进 tab。留到 IA 稳定后单独做 spec 拆分。

这点非常重要：**本 spec 不碰业务逻辑**。如果过程中发现必须动，立即停下来拉新的 spec，不要顺手改。

## 11. 开放问题

- **Home 页"试试"section 的动态规则如何落地**：目前描述的是"未校准提示校准"等启发式。具体判断条件（什么算"用过唤醒词"、统计从哪来）没写死，实现时定。
- **Onboarding Step 6 的"试说一句话"用哪个识别**：一次性用系统 `SFSpeechRecognizer` 就行（不走现有 `RecognitionSession`），做完就释放。避免和主识别路径耦合。
- **What's New 气泡的版本号锁定**：以哪个版本号为界显示？用 Marketing Version（1.x.x）还是内部 build version？决策在发版时再定，spec 留一个 `AetherWhatsNewV5_Shown` 的 key 占位，`V5` 是占位。

## 12. 验收

改完之后回答这些问题如果都是 yes，就算过：

- 新电脑装上 App，第一次打开，**90 秒内**能跑通一次听写（onboarding 带进去）
- 侧栏**截图宽度 ≤ 180pt**，5 项完整显示
- 原来在 14 项任何一项里的设置，现在**都能在 5 项新侧栏里找到**（测试 matrix 由 tasks 列出）
- 老用户升级后第一次打开主窗口 **What's New 气泡出现一次**，之后不再出现
- `UserDefaults` 迁移**零变更**——老用户的 lexicon / 规则 / 配置全部原样保留

## 13. 参考索引

- `Apps/AetherCore/AetherMainView.swift` — 侧栏和 detail 路由，重点改造
- `Apps/AetherCore/AetherApp.swift` — `AppState`, `OnboardingStep`（要改名）, `AppStorage` 键
- `Apps/AetherCore/MenuBar.swift` — 去冗余
- `Apps/AetherCore/PermissionsManager.swift` — 被 onboarding 复用
- `Apps/AetherCore/SettingsModules.swift` — 提供被容器包进去的现有 view，内部不改
