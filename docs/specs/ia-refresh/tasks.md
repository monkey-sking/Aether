# IA Refresh — Tasks

按依赖顺序排列。每个 Phase 都有可独立验证的产物，不会让 App 进入半成品状态。

---

## Phase 0 — 共识与快照

**目标**：确保所有人同意改动范围，并给当前版本打一个 tag 方便回滚对比。

- [x] design.md 被 review 并同意（2026-04-19）
- [x] 给当前版本打一个 git tag `pre-ia-refresh`（2026-04-19，指向 `7723044`）
- [x] 设置定位矩阵 `settings_matrix.md`（2026-04-19 完成主体，未核对项见文档末尾）

**验收**：矩阵表写完；tag 打上。

**已丢弃**：原本有一项"录 before 视频"。评估后认为 settings_matrix.md + git tag + 用户日常自用已经足够覆盖回归验证，录视频纯属仪式，丢弃。

---

## Phase 1 — Panel 枚举重构（无 UI 变化）

**目标**：把新的 Panel/SettingsTab 枚举结构建起来，但侧栏仍然显示旧 14 项、UI 完全不变。纯重构。

- [x] `AetherMainView.swift` 里定义 `enum SettingsTab`（2026-04-19，7 case：permissions / lexicon / appRules / launchAliases / importExport / diagnostics / about）
- [x] 新 `Panel` 枚举加上 5 个新 case（home / voice / pointer / shortcuts / settings(SettingsTab)），旧 14 个 case **共存**，全部加 `@available(*, deprecated, message:)` 标记
- [x] `AppState.onboardingStep: OnboardingStep` 改名 `permissionStage: PermissionSetupStage`，`deriveOnboardingStep` 改 `derivePermissionStage`。原 enum 名字 `OnboardingStep` **空出给 Phase 5 新 Onboarding 流程**用
- [x] 全仓搜所有引用 `OnboardingStep` 和 `onboardingStep`，更新（实际只有 AetherApp.swift 5 处）
- [x] xcodebuild Debug 成功，0 error 0 新 warning（2026-04-19）
- [ ] **用户手动**运行 App，侧栏 14 项 + 每项功能和之前完全一致

**验收**：Diff 应该只有 rename 和新增，没有功能变化。Git 上能一眼看出纯重构。

---

## Phase 2 — Settings 容器

**目标**：建出 5 项新侧栏里的"设置"容器，把 7 个 tab 内容挂进去。此时**侧栏仍然是 14 项**，但点旧的 Permissions & Status / Advanced 子项 / Logs 子项时，路由到新 `SettingsContainerView` 并自动切到对应 tab。

- [x] `SettingsContainerView`（2026-04-19，放在 `AetherMainView.swift` 末尾）
  - [x] 左侧 7 行二级列表
  - [x] 右侧 `SettingsTabContent(tab:)` 切换
  - [x] 初始 tab 参数 `initialTab: AetherMainView.SettingsTab`
- [x] `SettingsTabSidebar`（2026-04-19）— 7 行 list，权限未就绪时右侧橙色 badge 显示缺失数
- [x] `DiagnosticsContainerView`（2026-04-19）
  - [x] 顶部 segmented control：语音使用 / 唤醒与激活 / 焦点诊断
  - [x] 三个 case 内嵌原 `InputSettingsView(section: .insights)` / `.wakeInsights)` / `FocusDiagnosticsSettingsView`
- [x] `AetherMainView.swift` detail switch 里 `.settings(let tab)` 从占位改路由到 `SettingsContainerView(initialTab: tab)`
- [x] xcodebuild Debug 成功，0 error（2026-04-19）
- [ ] **用户手动验证**：临时把 `selection` 初值从 `.overview` 改成 `.settings(.permissions)` 跑一次，看 tab 切换、badge 显示、内容正确（验完改回；**或者等 Phase 3 新侧栏上线后自然验证**）

**决策偏离 spec**：原 spec 说"新文件 `Settings/SettingsContainerView.swift`"等 3 个独立文件。实际做成**追加到 `AetherMainView.swift` 末尾**。原因：Xcode 项目是老式 pbxproj（不是 Xcode 16 synchronized groups），新 `.swift` 文件不会自动纳入 build target，手工编辑 pbxproj 风险高。Phase 9 清理时再拆分。

**验收**：老侧栏 14 项仍能正常访问；同时可以通过程序跳转到 `SettingsContainerView` 并落在指定 tab。

---

## Phase 3 — 新侧栏上线（但 Home 还没做）

**目标**：侧栏变 5 项，Home 先用"占位 Home"（保留旧 Overview 内容）避免半成品。其他 4 项（语音 / 指针 / 快捷键 / 设置）全部就位。

- [x] `AetherMainView.swift` 里 List 部分改成 5 项平铺（无 Section header）
- [x] 旧 14 个 Panel case 删除（同时删除 unused `sidebarHeader` / `sidebarHeaderText` 辅助）
- [x] `.home` 路由到 `LegacyOverviewDashboardView`（原 `OverviewDashboardView` 直接 rename）
- [x] `.voice` 路由到新 `VoiceSettingsCombinedView`（segmented control 切换 输入 / 文字优化，复用 `InputSettingsView(section:)`）
- [x] `.pointer` 直接用 `ControlsPointerHotZonesSettingsView`
- [x] `.shortcuts` 直接用 `ControlsShortcutsSettingsView`
- [x] `.settings(.permissions)` 默认进 `SettingsContainerView(initialTab: .permissions)`
- [x] `SidebarMetrics.preferredWidth()` 重算，按 5 项 title（默认 170-260pt）
- [x] 主窗口默认尺寸 1120×760 → 960×640（注：spec 写的 1080×720 是估错的旧值，实际原值是 1120×760）
- [x] Matrix 校对 14/14 旧页面新路径均可达（2026-04-19）
- [x] xcodebuild Debug 成功（2026-04-19）
- [ ] **用户手动验证**：跑起来看 5 项侧栏 + 每个页面内容正确

**决策偏离**：原 spec 里"`.voice` 路由到新 `VoiceSettingsCombinedView`：上下排版两个原 section，用 `ScrollView` + 两块 `SettingsPage`"。实际改成 **segmented control 切换**。原因：`InputSettingsView` 自带 `SettingsPage` chrome（title + subtitle），上下堆叠会出两个大 header，视觉很乱。改用 segmented control 和 `DiagnosticsContainerView` 同模式，UI 更一致。

**验收**：侧栏 5 项；所有老设置都找得到；App 行为没有变化，只是 IA 排布变了。

---

## Phase 4 — Menu bar 去冗余

**目标**：菜单栏瘦身。

- [ ] `MenuBar.swift` 删掉状态副标题行
- [ ] 3 个独立权限按钮 → 1 个"开始设置..."（仅未完成时显示，调用 `OnboardingCoordinator.present()`——Phase 5 才实现，先留空壳）
- [ ] Label 文案简化为 "Aether · ✓ 就绪" 或 "Aether · ⚠ 未完成设置"
- [ ] 图标颜色逻辑保持（灰/绿/橙）

**验收**：菜单栏项数从现在的 ~10 项降到 ~6 项；所有原操作入口仍可达（权限修复通过 onboarding）。

---

## Phase 5 — Onboarding 流程

**目标**：首次启动流程跑通。

- [ ] 新文件 `Onboarding/OnboardingCoordinator.swift`
  - [ ] `enum Step { case welcome, accessibility, microphone, speech, airpods, voiceTrial, done }`
  - [ ] `@Published var currentStep: Step`
  - [ ] `advance()` / `skip()`
  - [ ] 完成时设 `@AppStorage("AetherOnboardingCompleted") = true`
- [ ] 新文件 `Onboarding/OnboardingWindow.swift` — 独立 `NSWindow`，720×520，居中，非模态
- [ ] 新文件 `Onboarding/Steps/OnboardingWelcomeStep.swift`
- [ ] 新文件 `Onboarding/Steps/OnboardingPermissionStep.swift`（泛型，接 accessibility / microphone / speech 三种）
- [ ] 新文件 `Onboarding/Steps/OnboardingAirPodsStep.swift`
  - [ ] 检查 AirPods 连接
  - [ ] 未连：一句提示 + "稍后"
  - [ ] 已连：3 秒倒计时校准演示
- [ ] 新文件 `Onboarding/Steps/OnboardingVoiceTrialStep.swift`
  - [ ] 按住大按钮 → 直接 `SFSpeechRecognizer`（不经 `RecognitionSession`）
  - [ ] 显示识别文本
  - [ ] 松开显示结果
- [ ] 新文件 `Onboarding/Steps/OnboardingDoneStep.swift`
- [ ] `AetherApp.swift` 启动时检查 `AetherOnboardingCompleted`，false 则 `OnboardingWindow.present()`
- [ ] Menu bar 的"开始设置..."按钮接到 `OnboardingCoordinator.present()`
- [ ] 本地化文案三份（至少 zh-Hans / en，其他语言留 TODO）
- [ ] 手动测试：新设备首次启动 → 走完 7 步 → 打开主窗口

**验收**：全新电脑装上 App，90 秒内能跑通一次听写；任一步骤可跳过且能再从 menu bar 继续。

---

## Phase 6 — Home 页重写

**目标**：用新 Home 取代 LegacyOverview。

- [ ] 新文件 `Home/HomeView.swift` — 页面根，4 个 section 组合
- [ ] 新文件 `Home/HomeWelcomeHero.swift`
  - [ ] 仅在 `AetherOnboardingCompleted == false` 时显示
  - [ ] "开始使用" 按钮打开 OnboardingWindow
- [ ] 新文件 `Home/HomeBlockingBanner.swift`
  - [ ] 检测任一核心权限未就绪
  - [ ] 多项缺失时只显示一条"未完成设置"，点进 onboarding 继续
- [ ] 新文件 `Home/HomeNowSection.swift`
  - [ ] 3 行：指针 / 语音输入 / 语音控制
  - [ ] 每行带状态灯 + label + 快速开关
  - [ ] 订阅 `HeadMotionManager` / `AppState` 的 published
- [ ] 新文件 `Home/HomeTrySection.swift`
  - [ ] 3 条动态建议
  - [ ] 启发式规则定义：
    - 未校准过 → "戴上 AirPods 按 ⌘⌃Space 校准"
    - 未用过唤醒词 → "说 'Hey Aether，打开 Safari'"
    - 已完成上述 → "看 30 秒演示"（留 TODO，视频单独提供）
  - [ ] 判断数据源：用 `UserDefaults` 里已有的累计 key（具体 key 见实现时确认）
- [ ] 新文件 `Home/HomeRecentSection.swift`
  - [ ] 复用 `VoiceUsageInsightsCard` 数据源
  - [ ] 只取 3 行 summary：今天识别段数、App 数；指针累计时长、最长一次
  - [ ] "打开诊断 →" 跳 `.settings(.diagnostics)`
- [ ] `AetherMainView.swift` 里 `.home` 的路由从 `LegacyOverviewDashboardView` 改为 `HomeView`
- [ ] 保留 `LegacyOverviewDashboardView`，加环境变量 `AETHER_LEGACY_OVERVIEW=1` 启用的回退通路
- [ ] 手动 review 每个 section 的视觉密度，必要时调 padding

**验收**：Home 页正常显示 4 个 section；阻断横幅仅异常时出现；"试试" section 的 3 条建议根据当前状态变化。

---

## Phase 7 — What's New 气泡 + 迁移

**目标**：老用户升级后不懵。

- [ ] 新文件 `Home/WhatsNewBubble.swift`
  - [ ] `@AppStorage("AetherWhatsNewV5_Shown") var shown: Bool = false`
  - [ ] 未显示过且 `AetherOnboardingCompleted == true`（即老用户）时显示
  - [ ] 右上角气泡，4 行要点 + "15 秒快速了解 →" 按钮
  - [ ] 15 秒演示是一个简短 sheet，3 页说明新 IA
  - [ ] "知道了"或关闭 → 设 shown = true
- [ ] `HomeView` 里挂 `WhatsNewBubble`
- [ ] 手动模拟：删掉 `AetherWhatsNewV5_Shown` 和 `AetherOnboardingCompleted=true` 的组合启动，气泡应出现

**验收**：老用户第一次打开新版本时气泡出现一次；点过不再出；新用户不出。

---

## Phase 8 — 打磨与回归

**目标**：质量关。

- [ ] 走完 Phase 0 的设置定位矩阵，52 个控件 100% 能找到
- [ ] 4 种语言（en / zh-Hans / ja / ko）至少过一遍字符串长度（onboarding 窗 + Home 页）
- [ ] Home 页 light / dark mode 两遍
- [ ] 侧栏在窄宽度下折叠行为正常
- [ ] 测试 edge case：
  - [ ] 全部权限已开 + 从未用过 App 的新用户 Home 显示"试试"
  - [ ] 部分权限缺失用户 Home 显示阻断横幅 + "试试"
  - [ ] 完全没连过 AirPods 的用户"试试"第一条是 AirPods 提示
- [ ] 跑 `AetherTests` 现有测试套件，全绿
- [ ] 找 2-3 个老用户（内部/beta）试用，收集 what's new 气泡反馈

**验收**：本 spec §12 五条验收全部满足。

---

## Phase 9 — 清理

**目标**：下一个大版本再做，不在本次发版里。

- [ ] 删除 `LegacyOverviewDashboardView` 和 `AETHER_LEGACY_OVERVIEW` 回退通路
- [ ] 把 `SettingsModules.swift` 开工拆分（单独 spec）
- [ ] 术语改名（Lexicon 等）的讨论（单独 spec）

---

## 估时参考

| Phase | 估时（单人） |
|---|---|
| Phase 0 | 0.5 天 |
| Phase 1 | 0.5 天 |
| Phase 2 | 1-1.5 天 |
| Phase 3 | 1 天 |
| Phase 4 | 0.5 天 |
| Phase 5 | 4-5 天 |
| Phase 6 | 3-4 天 |
| Phase 7 | 1 天 |
| Phase 8 | 2-3 天 |
| Phase 9 | （跨版本，不计） |

总计：**约 14-17 天单人开发 + 内部 beta 验证 3-5 天**。

## 不要做的事（防 scope creep）

以下情况出现时**立即停下**，不要顺手改：

- 想改业务逻辑（重构 `SpeechManager` 的某个方法）
- 想改控件本身（觉得某个 Slider 应该换成 Stepper）
- 想拆 `SettingsModules.swift`
- 想重命名术语
- 想加新功能

遇到上面任何一条，记到 `WORKSTREAM_INBOX.md` 留给后续 spec，本次坚决不动。
