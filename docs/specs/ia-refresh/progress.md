# IA Refresh — Progress

**这份文档是跨会话的真理源。每次 Claude 停下前必须更新。下次接手前必须先读这份。**

## 当前位置

- **当前 Phase**：Phase 2（Settings 容器）→ 代码完成 + 已 commit，可直接进 Phase 3
- **最后更新**：2026-04-19
- **最后会话做了什么**：Phase 0 + Phase 1 + Phase 2 全部代码完成并 commit 到 `App/` 仓 `fix/wake-dictation-regression` 分支（4 个 commit）
- **下一步要做什么**：见下方 "Resume from here" 区块

## Phase 状态总览

| Phase | 名称 | 状态 |
|---|---|---|
| 0 | 共识与快照 | ✅ 完成 |
| 1 | Panel 枚举重构（无 UI 变化） | ✅ 完成（代码 + commit） |
| 2 | Settings 容器 | ✅ 完成（代码 + commit）|
| 3 | 新侧栏上线（Home 暂用 Legacy） | ⚪ 未开始（**下一步**） |
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
- ~~录 before 视频~~（2026-04-19 丢弃）

## Phase 1 子任务（已完成）

- [x] `OnboardingStep` → `PermissionSetupStage` 改名
- [x] 加 `enum SettingsTab`（7 case）
- [x] `Panel` 扩 5 个新 case 共存（旧 14 case + `@available(*, deprecated)`）
- [x] `detail:` switch / `panelTitle()` / `panelSymbol()` 三处 exhaustive 更新
- [x] xcodebuild Debug 成功

## Phase 2 子任务（已完成）

- [x] `SettingsContainerView`（左 sidebar + 右 content）
- [x] `SettingsTabSidebar`（7 行 list + 权限 badge）
- [x] `DiagnosticsContainerView`（segmented control 3 子页）
- [x] detail switch 里 `.settings(let tab)` 路由到容器
- [x] xcodebuild Debug 成功
- [ ] **用户可选验证**：临时改 `@State var selection: Panel? = .overview` 为 `.settings(.permissions)` 跑一次（或等 Phase 3 自然验证）

## Resume from here

**如果你是新会话接手，从这里开始读：**

### 本 initiative 背景
见 memory `project_ia_refresh.md`。核心：Mac 端信息架构重构，侧栏 14→5，新 Home 页，首次启动 onboarding。**不碰业务逻辑**。

### 当前待办（按优先级）

1. **用户抽空跑一遍 App**（累积回归检查，并行进行）
   - 构建并安装：`cd App && ./Scripts/BuildAndInstall.sh`
   - 确认：侧栏仍 14 项、所有功能正常、`OnboardingStep` 改名零副作用
   - OK 就在 tasks.md Phase 1 最后一项打勾；不 OK 排查

2. **Phase 2 的可选验证**（或跳过，等 Phase 3 自然验证）
   - 临时改 `AetherMainView.selection` 初值为 `.settings(.permissions)` 跑一次，看 SettingsContainerView 正常显示、7 tab 能切、权限 badge 有显示
   - 验完改回 `.overview`
   - 不验也行，Phase 3 之后侧栏会自然路由到 `.settings(...)`，到时验证

3. **开始 Phase 3：新侧栏上线**（重要分水岭，用户首次看到 UI 变化）
   - 参考 `tasks.md` Phase 3 清单
   - 核心动作：
     - `AetherMainView.swift` 的 `List` 从 6 个 Section + 14 项改成 5 项平铺
     - 旧 14 个 `Panel` case 全部**删除**（不再需要 deprecated 共存）
     - `.home` 暂时路由到 `LegacyOverviewDashboardView`（原 `OverviewDashboardView` 直接 rename）
     - `.voice` 路由到新 `VoiceSettingsCombinedView`（上下排 Voice Input + Text Cleanup）
     - `.pointer` / `.shortcuts` 直接路由到现有 `ControlsPointerHotZonesSettingsView` / `ControlsShortcutsSettingsView`
     - `.settings(.permissions)` 作为默认 settings tab
     - `SidebarMetrics.preferredWidth()` 按新 5 项 title 重算（预计 180pt）
     - 主窗口默认尺寸从 1080×720 改 960×640
   - 验收：侧栏 5 项；52 个控件按 `settings_matrix.md` 能一一找到
   - **这是最大的视觉变化点**，用户会立刻看出"啊变了"

4. **Phase 4 及以后**
   - Phase 4 menu bar 去冗余
   - Phase 5 Onboarding 流程（最大的一块，4-5 天）
   - Phase 6 Home 页重写
   - 按 tasks.md 顺序推进

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
- Phase 0+1+2 的 **4 个 commit 已落**（在 `App/` 仓，branch `fix/wake-dictation-regression`）：
  - `1eb826e` — docs(specs): add ia-refresh and iphone-remote initiative specs
  - `c288beb` — refactor(AppState): rename OnboardingStep to PermissionSetupStage
  - `f3a3fde` — refactor(panel): add SettingsTab enum and new Panel cases
  - `7489e77` — feat(settings): add settings container view and diagnostics wrapper

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
