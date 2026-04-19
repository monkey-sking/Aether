# IA Refresh — Progress

**这份文档是跨会话的真理源。每次 Claude 停下前必须更新。下次接手前必须先读这份。**

## 当前位置

- **当前 Phase**：Phase 3（新侧栏上线）→ 代码完成 + 已 commit，**用户运行时会立刻看到 UI 变化**
- **最后更新**：2026-04-19
- **最后会话做了什么**：Phase 3 完成——侧栏 14 项变 5 项、VoiceSettingsCombinedView 用 segmented control、主窗默认 960×640、matrix 回归 14/14 可达
- **下一步要做什么**：见下方 "Resume from here" 区块

## Phase 状态总览

| Phase | 名称 | 状态 |
|---|---|---|
| 0 | 共识与快照 | ✅ 完成 |
| 1 | Panel 枚举重构（无 UI 变化） | ✅ 完成（代码 + commit） |
| 2 | Settings 容器 | ✅ 完成（代码 + commit）|
| 3 | 新侧栏上线（Home 暂用 Legacy） | ✅ 完成（代码 + commit，**用户首次可见变化**） |
| 4 | Menu bar 去冗余 | ⚪ 未开始（**下一步**） |
| 5 | Onboarding 流程 | ⚪ 未开始 |
| 6 | Home 页重写 | ⚪ 未开始 |
| 7 | What's New 气泡 + 迁移 | ⚪ 未开始 |
| 8 | 打磨与回归 | ⚪ 未开始 |
| 9 | 清理（跨版本，不计本次） | ⚪ 未开始 |

图例：⚪ 未开始 · 🟡 进行中 · ✅ 完成 · 🔴 阻塞

## Phase 0 子任务（已完成）

- [x] design.md 被 review 并同意（2026-04-19）
- [x] 打 git tag `pre-ia-refresh`（2026-04-19，指向 commit `7723044`）
- [x] 列设置定位矩阵 `settings_matrix.md`（2026-04-19）
- ~~录 before 视频~~（2026-04-19 丢弃）

## Phase 1 子任务（已完成）

- [x] `OnboardingStep` → `PermissionSetupStage` 改名
- [x] 加 `enum SettingsTab`（7 case）
- [x] `Panel` 扩 5 个新 case 共存
- [x] xcodebuild Debug 成功

## Phase 2 子任务（已完成）

- [x] `SettingsContainerView`（左 sidebar + 右 content）
- [x] `SettingsTabSidebar`（7 行 list + 权限 badge）
- [x] `DiagnosticsContainerView`（segmented control 3 子页）
- [x] xcodebuild Debug 成功

## Phase 3 子任务（已完成）

- [x] `OverviewDashboardView` → `LegacyOverviewDashboardView` 改名
- [x] `VoiceSettingsCombinedView`（segmented control，和 DiagnosticsContainerView 同模式）
- [x] 删 14 个 legacy Panel case，删 unused sidebar header helpers
- [x] 侧栏 List 改 5 项平铺（ForEach 驱动）
- [x] detail switch / panelTitle / panelSymbol 精简成 5 case
- [x] `SidebarMetrics.preferredWidth()` 新 5 项重算（170-260pt）
- [x] 主窗默认尺寸 1120×760 → 960×640
- [x] 14/14 旧页面新路径回归验证
- [x] xcodebuild Debug 成功
- [ ] **用户手动验证**：跑 App 看侧栏 5 项、每个入口内容正确

## Resume from here

**如果你是新会话接手，从这里开始读：**

### 本 initiative 背景
见 memory `project_ia_refresh.md`。核心：Mac 端信息架构重构，侧栏 14→5，新 Home 页，首次启动 onboarding。**不碰业务逻辑**。

### 当前待办（按优先级）

1. **用户跑一遍 App 验证 Phase 3**（**这是第一次能看到 UI 变化**）
   - `cd /Volumes/SSD/Projects/Aether/App && ./Scripts/BuildRelease.sh Debug && open .build/release/Aether.app`
   - 验收：
     - 侧栏 **5 项**（首页 / 语音 / 指针 / 快捷键 / 设置），无 Section header
     - 点"首页"显示原 Overview 内容（LegacyOverviewDashboardView）
     - 点"语音"有 segmented control 切 输入/文字优化
     - 点"指针"显示原头控热区、点"快捷键"显示 HotkeySettingsSection
     - 点"设置"显示 7 tab 容器，默认权限 tab，权限未就绪时右侧橙色 badge
     - 诊断 tab 内 segmented 切 语音使用/唤醒与激活/焦点诊断
     - 主窗启动后尺寸 960×640
     - AirPods 头追、语音输入、HUD、快捷键全部正常
   - 通过后把 tasks.md Phase 3 最后一项打勾

2. **开始 Phase 4：Menu bar 去冗余**（0.5 天）
   - `MenuBar.swift` 删状态副标题行
   - 3 个独立权限按钮 → 1 个"开始设置..."（Phase 5 实现真流程前，先跳到 `.settings(.permissions)` 占位）
   - Label 文案简化 "Aether · ✓ 就绪" / "Aether · ⚠ 未完成设置"
   - 菜单项数 ~10 → ~6

3. **Phase 5 是大块头**：Onboarding 流程（4-5 天，本 initiative 最大单 Phase）

4. **Phase 6 Home 页重写**：把占位 LegacyOverviewDashboardView 换成真 Home
5. **Phase 7 What's New 气泡**：老用户升级后提醒
6. **Phase 8 打磨与回归**：收尾

### 严格不做

遇到以下情况**立即停手**，把想法记到 `WORKSTREAM_INBOX.md`，本次 ia-refresh initiative 不做：

- 改业务逻辑（`SpeechManager` / `HeadMotionManager` 等）
- 拆 `SettingsModules.swift`
- 改控件本身（比如把 Slider 换 Stepper）
- 重命名术语（Lexicon 等）
- 加新功能（含 iPhone Remote）

### Git 状态要点

- **仓库结构提醒**：`/Volumes/SSD/Projects/Aether/` 和 `/Volumes/SSD/Projects/Aether/App/` 是**两个独立的 git 仓库**（不是 submodule），本 initiative 的所有代码 + spec 改动都在 `App/` 仓里
- 分支（在 `App/` 仓）：`fix/wake-dictation-regression`
- 主分支：`main`
- 已打 tag：`pre-ia-refresh` → `7723044`（Phase 0 基线，在 `App/` 仓里）
- Phase 0+1+2+3 的 **6 个 commit 已落**（在 `App/` 仓，branch `fix/wake-dictation-regression`）：
  - `1eb826e` — docs(specs): add ia-refresh and iphone-remote initiative specs
  - `c288beb` — refactor(AppState): rename OnboardingStep to PermissionSetupStage
  - `f3a3fde` — refactor(panel): add SettingsTab enum and new Panel cases
  - `7489e77` — feat(settings): add settings container view and diagnostics wrapper
  - `8cfdd76` — docs(ia-refresh): update progress after Phase 2 complete
  - `ca3716b` — feat(sidebar): collapse sidebar to 5 items and route through new IA

⚠️ **分支名不匹配**：这 4 个 commit 和 IA refresh 有关，但当前分支叫 `fix/wake-dictation-regression`。用户可能之后想把 IA refresh 搬到独立分支（`feat/ia-refresh`）或者就合并在一起——这个由用户决定，Claude 不要擅自做 `git reset / git branch -m` 这类操作。

### 建议的 commit 拆分（下次可以做）

按风险/类型分 4 个 commit：

1. `docs: add ia-refresh and iphone-remote specs` — 两份 spec 文档
2. `refactor(panel): rename OnboardingStep to PermissionSetupStage` — AetherApp.swift 改名
3. `refactor(panel): introduce SettingsTab and new Panel cases` — AetherMainView.swift 扩容
4. 用户自己的零散改动（`.gitignore / README.md / TODO.md / v2ex_draft.md` 等）交给用户决定

## 决策日志

追加新决策时加日期。

- **2026-04-19** 选择方向 B（侧栏 14→5 + Home 重写 + onboarding），暂停 iPhone Remote 直到 ia-refresh 落地
- **2026-04-19** 不做 legacy sidebar 回退开关，但保留 `LegacyOverviewDashboardView` + 环境变量 `AETHER_LEGACY_OVERVIEW=1` 作为应急
- **2026-04-19** 设置页用"左侧二级列表 + 右侧内容"结构，不用 segmented control（7 个 tab 放 segmented 太挤）
- **2026-04-19** 诊断 tab 内部用 segmented control（3 个子 section 放 segmented 合适）
- **2026-04-19** 设置矩阵粒度：**页面 + 主要卡片/section 级**，不枚举单控件（GlassCard 内部的 Toggle/Slider 跟卡片整体迁移，不单独追踪）。52 个控件的总量作为 sanity check，不做个体映射
- **2026-04-19** **Phase 2+ 新代码先放到 `AetherMainView.swift` 末尾**，不新建单独文件。原因：Xcode 项目是老式 pbxproj（不是 Xcode 16 synchronized groups），新 `.swift` 文件不会自动纳入 target，手工编辑 pbxproj 风险高。`AetherMainView.swift` 已经托管 `OverviewDashboardView` / `LaunchAtLoginManager` 等多个类型，新增 `SettingsContainerView` 等在一致性上 OK。Phase 9 清理时再拆分单独文件（到那时可能顺便把项目升到 synchronized groups）

## 阻塞与待决问题

（空）

## 给下次会话的移交清单

写在 `## 当前位置` 里，每次停下前更新。
