# IA Refresh — Progress

**这份文档是跨会话的真理源。每次 Claude 停下前必须更新。下次接手前必须先读这份。**

## 当前位置

- **当前 Phase**：Phase 1（Panel 枚举重构）→ 代码完成，等用户运行确认行为无回归
- **最后更新**：2026-04-19
- **最后会话做了什么**：Phase 0 全部完成（丢弃录视频任务）。Phase 1 完成：OnboardingStep 改名、加 SettingsTab enum、Panel 扩 5 个新 case 共存、xcodebuild Debug 成功
- **下一步要做什么**：见下方 "Resume from here" 区块

## Phase 状态总览

| Phase | 名称 | 状态 |
|---|---|---|
| 0 | 共识与快照 | ✅ 完成 |
| 1 | Panel 枚举重构（无 UI 变化） | 🟡 代码完成，等用户跑一遍 |
| 2 | Settings 容器 | ⚪ 未开始 |
| 3 | 新侧栏上线（Home 暂用 Legacy） | ⚪ 未开始 |
| 4 | Menu bar 去冗余 | ⚪ 未开始 |
| 5 | Onboarding 流程 | ⚪ 未开始 |
| 6 | Home 页重写 | ⚪ 未开始 |
| 7 | What's New 气泡 + 迁移 | ⚪ 未开始 |
| 8 | 打磨与回归 | ⚪ 未开始 |
| 9 | 清理（跨版本，不计本次） | ⚪ 未开始 |

图例：⚪ 未开始 · 🟡 进行中 · ✅ 完成 · 🔴 阻塞

## Phase 0 子任务（已完成）

- [x] design.md 被 review 并同意（2026-04-19）
- [x] 打 git tag `pre-ia-refresh`（2026-04-19，指向 commit `7723044`）
- [x] 列设置定位矩阵 `settings_matrix.md`（2026-04-19，主体完成，有 5 项未核对留到 Phase 3 前补）
- ~~录 before 视频~~（2026-04-19 丢弃，详见 tasks.md Phase 0 末尾说明）

## Phase 1 子任务

- [x] `OnboardingStep` → `PermissionSetupStage` 改名（2026-04-19）
- [x] `onboardingStep` → `permissionStage` 改名（2026-04-19）
- [x] `deriveOnboardingStep` → `derivePermissionStage` 改名（2026-04-19）
- [x] 加 `enum SettingsTab`（2026-04-19，7 case）
- [x] `Panel` 扩 5 个新 case 共存（2026-04-19，旧 14 case 保留 + `@available(*, deprecated)` 标记）
- [x] `detail:` switch / `panelTitle()` / `panelSymbol()` 三处 exhaustive 更新（2026-04-19）
- [x] xcodebuild Debug 成功，0 error 0 warning（2026-04-19）
- [ ] **用户手动**运行 App，侧栏 14 项 + 功能不变

## 修改的文件（Phase 1）

- `App/Apps/AetherCore/AetherApp.swift`（改名 5 处）
- `App/Apps/AetherCore/AetherMainView.swift`（加 SettingsTab、扩 Panel、更新 3 处 switch）

## Resume from here

**如果你是新会话接手，从这里开始读：**

### 本 initiative 背景
见 memory `project_ia_refresh.md`。核心：Mac 端信息架构重构，侧栏 14→5，新 Home 页，首次启动 onboarding。**不碰业务逻辑**。

### 当前待办（按优先级）

1. **用户验证 Phase 1 无回归**（等用户运行 App 后才能打勾）
   - 侧栏仍然 14 项
   - 每项功能和之前完全一致
   - 如果 OK，打 Phase 1 最后一个 ☐；如果不 OK，排查

2. **开始 Phase 2：Settings 容器**（Phase 1 验证后启动）
   - 参考 `tasks.md` Phase 2 清单
   - 核心动作：
     - 新建 `App/Apps/AetherCore/Settings/SettingsContainerView.swift`（左侧 7 行 list + 右侧 `SettingsTabContent(tab:)`）
     - 新建 `Settings/SettingsTabSidebar.swift`（7 行 list，权限缺失时 ⚠ 角标）
     - 新建 `Settings/DiagnosticsContainerView.swift`（segmented control：语音使用 / 唤醒与激活 / 焦点诊断 → 三个原 view）
     - `AetherMainView.swift` 的 detail switch 里 `.settings(let tab)` 从占位文本改路由到 `SettingsContainerView(initialTab: tab)`
     - **本阶段侧栏仍然是 14 项**，新路由只能通过程序跳转验证
   - 测试：手动跳 `.settings(.permissions)` / `.settings(.diagnostics)` 看 tab 切换正确

3. **Phase 3 及以后**
   - 看 `tasks.md`，每个 Phase 完成后更新这里和 tasks.md 的 checkbox

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
- Phase 0+1 的 **3 个 commit 已落**（在 `App/` 仓，branch `fix/wake-dictation-regression`）：
  - `1eb826e` — docs(specs): add ia-refresh and iphone-remote initiative specs
  - `c288beb` — refactor(AppState): rename OnboardingStep to PermissionSetupStage
  - `f3a3fde` — refactor(panel): add SettingsTab enum and new Panel cases

⚠️ **分支名不匹配**：这 3 个 commit 和 IA refresh 有关，但当前分支叫 `fix/wake-dictation-regression`。用户可能之后想把 IA refresh 搬到独立分支（`feat/ia-refresh`）或者就合并在一起——这个由用户决定，Claude 不要擅自做 `git reset / git branch -m` 这类操作。

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
