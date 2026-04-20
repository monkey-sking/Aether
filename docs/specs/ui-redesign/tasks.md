# Aether UI Redesign — Tasks

按依赖顺序排列。**每 Phase 只改一件事**，要么是**用户可见变化**要么是**零风险基础设施**——不混。每 Phase 都能 revert 为单 commit、用一个页面或一条流程手动验证。

## Phase 0 — 快照 + 基线

**目标**：锁定基线，打 tag，不动代码。

- [ ] 确认当前 App 仓 `main` 的 head commit
- [ ] 打 git tag `pre-ui-redesign`
- [ ] 确认 settings_matrix.md 仍然准确（ia-refresh 的矩阵沿用）
- [ ] 在本 tasks.md 的"决策日志"section 确认本次 spec 的起点

**产出**：tag + 本 spec 三份 markdown。无代码改动。

**验收**：`git tag | grep pre-ui-redesign` 有返回。

**Revert**：N/A（没改代码）。

**估时**：0.5 天。

---

## Phase 1 — 新 Panel / SettingsTab enum 共存（零风险基础设施）

**目标**：把 Phase 2 要用的 `enum SettingsTab` 和新 `Panel` case 加上，**侧栏仍 14 项**。纯新增，不 wire 进 UI，用户完全无感。

- [ ] `AetherMainView.swift` 加 `enum SettingsTab`（7 case：permissions / lexicon / appRules / launchAliases / importExport / diagnostics / about）
- [ ] `Panel` enum 扩 5 个新 case（home / voice / pointer / shortcuts / settings(SettingsTab)），旧 14 个 case **共存**，全部加 `@available(*, deprecated)`
- [ ] `AppState` 的 `onboardingStep: OnboardingStep` 改名 `permissionStage: PermissionSetupStage`（腾出 `OnboardingStep` 给 Phase 7 用）
- [ ] `xcodebuild Debug` 成功，无新 warning

**产出**：2 个 commit，纯重构，`git diff` 应只有 rename + 新增。

**验收**：用户运行 App，14 项侧栏**每一项表现与之前一致**（包括所有子页、快捷键、状态）。

**Revert**：`git revert` 这两个 commit 即可。

**估时**：1 天。

---

## Phase 2 — Settings 容器（不 wire，纯新增）

**目标**：写 `SettingsContainerView` + `DiagnosticsContainerView`，放在 `AetherMainView.swift` 末尾。**不 wire 进侧栏**。

- [ ] `SettingsContainerView(initialTab:)`（左 7 行 `List` + 右 `content`）
- [ ] `SettingsTabSidebar`（7 行，权限未就绪时右侧橙色 badge）
- [ ] `DiagnosticsContainerView`（顶部 segmented control 3 子页 — 此处 segmented OK，3 个 case 是不同 struct，无 Phase 3 identity 问题）
- [ ] 每个 tab 的 content 用原 view：`PermissionsStatusSettingsView` / `InputSettingsView(.lexicon)` / `AppRulesSettingsView` / `AppLaunchAliasesSettingsView` / `ImportExportSettingsView` / `DiagnosticsContainerView` / `AboutCenterView`
- [ ] `xcodebuild Debug` 成功

**产出**：1 个 commit，只新增代码。

**验收**：用户运行 App，**侧栏和页面没变化**。开发者可临时把 `@State selection: Panel? = .overview` 改成 `.settings(.permissions)` 跑一次人工验证 tab 切换、badge 显示、诊断子页可切。

**Revert**：`git revert` 这 1 个 commit。

**估时**：1–1.5 天。

---

## Phase 3 — 新 Home 页写好（不 wire）

**目标**：新写 `HomeView`（不 rename `OverviewDashboardView`，让它继续作为 fallback）。放在 `AetherMainView.swift` 末尾。**不 wire 进侧栏**。

- [ ] `HomeView` struct，布局见 design.md §2
- [ ] `HomeSuggestionEngine`（struct，计算"试试" section 的建议）
- [ ] Welcome hero 卡（`@AppStorage("AetherHomeWelcomeDismissed")`）
- [ ] 阻断横幅（`appState.missingPermissionCount > 0` 时显示）
- [ ] "现在" section 3 行（3 个状态行 + 快速开关）
- [ ] "最近" section 复用 VoiceUsageInsights 数据源
- [ ] `xcodebuild Debug` 成功

**产出**：1 个 commit，只新增。

**验收**：开发者临时改 `selection = .home` 跑一次看 Home 完整显示。

**Revert**：`git revert` 1 commit。

**估时**：2–3 天。

---

## Phase 4 — 侧栏 14 → 5（**唯一一次用户可见侧栏变化**）

**目标**：侧栏切到 5 项，路由到 Phase 2/3 写好的 view。**此 Phase 不改 Home/Settings 内部、不改默认窗口尺寸、不 rename 类**——只改"侧栏结构 + detail 路由"。

- [ ] `AetherMainView.swift` 的 List 改 5 项平铺（`ForEach(sidebarPanels)`）
- [ ] `sidebarPanels: [Panel]` 定义 5 项
- [ ] detail 的 switch 5 case：
  - `.home` → `HomeView()`
  - `.voice` → `VoicePageView()`（**新建**，见下）
  - `.pointer` → `ControlsPointerHotZonesSettingsView`（直接复用，原样）
  - `.shortcuts` → `ControlsShortcutsSettingsView`（原样）
  - `.settings(let tab)` → `SettingsContainerView(initialTab: tab)`
- [ ] `VoicePageView`：一个 `Form`，里面两个 `Section("输入") { … }` / `Section("文字优化") { … }`，**不是** segmented control（design.md §7.2）
- [ ] `SidebarMetrics.preferredWidth()` 按 5 项 title 重算（170–260pt）
- [ ] 旧 14 个 Panel case **保留**（不删，防 Phase 5 万一要回退）
- [ ] `xcodebuild Debug` 成功

**产出**：1 个 commit。**用户可见变化**。

**验收**：
- 侧栏 5 项无 Section header
- 每项 content 正确（首页 = HomeView / 语音 = Form 两 Section / 指针 / 快捷键 / 设置 = 容器 + 7 tab）
- **滚动语音页**看到两个 Section（**不需要点任何 tab / segmented**）
- AirPods 头追、语音输入、HUD、快捷键全部正常（业务逻辑无改动）
- 跑 `../ia-refresh/settings_matrix.md` 的 14/14 验收清单全过

**Revert**：`git revert` 1 commit，侧栏秒回 14 项（因为旧 case 保留，老 selection.home fallback 到 `.overview`——需要改回默认 selection）。

**估时**：1–1.5 天。

---

## Phase 5 — 删 legacy Panel case + Menu bar 去冗余

**目标**：确认 Phase 4 稳定一周 + 无用户反馈后，删 deprecated Panel case、简化 Menu bar。

- [ ] 删 14 个 deprecated Panel case
- [ ] 删 `sidebarHeader` / `sidebarHeaderText` helpers（Phase 4 后已无人用）
- [ ] `MenuBar.swift`：删状态副标题行、3 个权限按钮合并成"开始设置…"、菜单项精简到 ~6
- [ ] Label 文案改"Aether · ✓ 就绪" / "Aether · ⚠ 未完成" / "Aether · ✕ 未激活"
- [ ] 默认窗口尺寸保持 1120×760（**本 Phase 不改**）
- [ ] `xcodebuild Debug` 成功

**产出**：1–2 个 commit。用户可见变化（Menu bar），但属小调整。

**验收**：Menu bar 文案 + 6 菜单项，删 legacy Panel 后侧栏行为不变。

**Revert**：`git revert` 对应 commit。legacy Panel case 删掉之后如果还要回 14 项，**得 revert 到 Phase 4 之前**（所以 Phase 5 是个分水岭，之后要回退成本高）。

**估时**：1 天。

---

## Phase 6 — 默认窗口尺寸调整（独立一步）

**目标**：把主窗默认尺寸改成 960×640（现在 1120×760）。独立一步，方便 A/B revert。

- [ ] `StandardWindowConfigurator` 或 window 初始化处改默认尺寸
- [ ] 老用户的 saved frame 不动（`NSWindow.setFrameAutosaveName` 会保留他们最后一次 resize）
- [ ] `xcodebuild Debug` 成功

**产出**：1 个 commit。

**验收**：新用户首次开 App 窗口 960×640；老用户保留他们的 frame。

**Revert**：1 commit。

**估时**：0.5 天。

---

## Phase 7 — Onboarding 流程（本 initiative 最大单 Phase）

**目标**：首次启动独立窗口 7 步引导。

- [ ] 新 file（或追加到 `AetherMainView.swift`）`OnboardingWindow` + 7 个 step view
- [ ] `OnboardingCoordinator` ObservableObject 管理当前 step / 持久化
- [ ] `@AppStorage("AetherOnboardingCompleted")` + 单步标记
- [ ] App 启动时判断未完成则弹 onboarding 窗、delay 主窗
- [ ] 7 步文案（中英）
- [ ] 每步可跳（Welcome 和"完成"外）
- [ ] `xcodebuild Debug` 成功

**产出**：2–3 个 commit。

**验收**：新建 user（清 UserDefaults）启动 App，onboarding 独立窗弹出；完成或跳过后主窗出现；重启 App 不再弹。

**Revert**：revert 对应 commit 或手动 `defaults write com.7fei.Aether AetherOnboardingCompleted -bool YES`。

**估时**：4–5 天（最大 Phase，留 buffer）。

---

## Phase 8 — What's New 气泡 + 老用户迁移

**目标**：老用户首次打开新版显示一次 "What's New"。

- [ ] `HomeView` 右上角 `.overlay` 一个 Popover，`@AppStorage("AetherWhatsNewV5_Shown")` 控制
- [ ] 文案："侧栏精简到 5 项，设置合并了"
- [ ] 点"我知道了"或 10 秒自动消失
- [ ] 首次启动过 onboarding 的新用户**不显示**（`AetherOnboardingCompleted` 在 V5 版本内被设 true 的不显示气泡）
- [ ] `xcodebuild Debug` 成功

**产出**：1 commit。

**验收**：从 b154（老 UI）升到新版 App，Home 页弹一次气泡。关掉重开不再弹。

**Revert**：1 commit。

**估时**：0.5 天。

---

## Phase 9 — 打磨与回归

**目标**：发 beta，按 settings_matrix.md 验收清单 14 行全过。

- [ ] 14 项验收清单（见 `../ia-refresh/settings_matrix.md` §验收清单）
- [ ] 老用户 UserDefaults 保留验证（lexicon / 规则 / 别名 / 快捷键）
- [ ] 所有空状态（无麦克风 / 无 AirPods / 无权限）都有合理 fallback
- [ ] 跑 Debug + Release 构建
- [ ] 发 beta 一个版本，`PUBLISH_SPARKLE=1 SPARKLE_CHANNEL=beta`
- [ ] 等 1 周无反馈再决定是否 PR 到 stable

**产出**：若干 polish commit + beta 发布。

**验收**：matrix 14 行全绿，用户自用 3 天无退回需求。

**估时**：3–5 天。

---

## 总估时

Phase 0–9 累计 **13–18 天**。Phase 7 onboarding 是大头，其他都是小 Phase。

## 与 iPhone Remote 的交叉

iPhone Remote 的 Mac 端 UI（其 Phase 4）要挂在**本 spec 的 Phase 4** 完成后：指针页的"指针源" Picker 多一项"iPhone 激光笔"。iPhone Remote 的 Phase 0–3（Shared Protocol、MPC、校准数学）和本 spec **无交叉**，可独立并行。

## 决策日志

追加新决策时加日期。

- **2026-04-20** 立项。吸收 ia-refresh 诊断，但拒绝其 Phase 3 方案（segmented control 合并 Voice Input / Text Cleanup）
- **2026-04-20** "语音"页用 `Form` + 两个 `Section` 垂直排列，不用 segmented control / tab 切换
- **2026-04-20** 不做灰度开关。老 `OverviewDashboardView` 保留作 env-var fallback（`AETHER_LEGACY_OVERVIEW=1`），下一版 spec 再删
- **2026-04-20** Phase 4（侧栏 14→5）独立，Phase 5（删 legacy + Menu bar）独立，Phase 6（窗口尺寸）独立——教训：Phase 3 翻车就是因为这三件事挤在一起
- **2026-04-20** 设置容器沿用 ia-refresh Phase 2 的 `SettingsContainerView` + `DiagnosticsContainerView` 设计（那部分代码当时没问题，回退时也保留作 dead code）

## 阻塞与待决

（空）
