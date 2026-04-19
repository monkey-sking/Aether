# Settings Migration Matrix

> **用途**：IA refresh 改完后，对着这份表手动逐条核对，每一行原有内容都必须在新 IA 里找得到。
>
> **粒度**：页面 + 主要卡片/section。不枚举单控件（每个 GlassCard 内部的 Toggle/Slider 会跟着卡片整体迁移，不单独追踪）。
>
> **符号**：🟢 已验证 · 🟡 待验证 · 🔴 丢失

## 枚举现状（2026-04-19 盘点）

14 项侧栏对应的 top-level view：

| # | 旧 Panel | view 名 | 文件:行 |
|---|---|---|---|
| 1 | Overview | `OverviewDashboardView` | `AetherMainView.swift:539` |
| 2 | Voice Input | `InputSettingsView(section: .basics)` | `SettingsModules.swift:93` |
| 3 | Text Cleanup | `InputSettingsView(section: .textCleanup)` | `SettingsModules.swift:93` |
| 4 | Pointer & Hot Zones | `ControlsPointerHotZonesSettingsView` | `SettingsModules.swift:6103` |
| 5 | Shortcuts | `ControlsShortcutsSettingsView` | `SettingsModules.swift:6124` |
| 6 | Permissions & Status | `PermissionsStatusSettingsView` | `AetherMainView.swift:717` |
| 7 | Lexicon | `InputSettingsView(section: .lexicon)` | `SettingsModules.swift:93` |
| 8 | App Rules | `AppRulesSettingsView` | `SettingsModules.swift:6141` |
| 9 | Launch Aliases | `AppLaunchAliasesSettingsView` | `SettingsModules.swift:6216` |
| 10 | Import & Export | `ImportExportSettingsView` | `SettingsModules.swift:6300` |
| 11 | Voice Usage | `InputSettingsView(section: .insights)` | `SettingsModules.swift:93` |
| 12 | Wake & Activation | `InputSettingsView(section: .wakeInsights)` | `SettingsModules.swift:93` |
| 13 | Focus & Input Diagnostics | `FocusDiagnosticsSettingsView` | `SettingsModules.swift:6503` |
| 14 | About | `AboutCenterView` | `AboutCenter.swift` |

## 控件总量

`SettingsModules.swift` grep 出 **52 个** Toggle/Slider/Picker/Stepper/TextField。
Overview / Permissions / About 在其他文件，不计入这 52。

## 旧 → 新迁移映射

### 1. Overview（`OverviewDashboardView`）

旧内容（5 个组件）：
- Readiness summary card（权限状态 + 展开详情）
- Pointer Control tile（头追开/关、自动启动、Posture Guide 开关）
- Voice Basics tile（激活模式三选一 picker）
- Voice Input tile（语音输入 on/off 等）
- Voice Control tile（语音控制 on/off 等）

**新位置**：整页由 **Home 页** 替换。

具体去向：
| 旧组件 | 新位置 |
|---|---|
| Readiness summary card | Home 页"阻断横幅"——只在有未就绪项时显示一条"未完成设置" |
| Pointer Control tile | Home 页"现在" section 第 1 行（状态 + 快速开关） |
| Voice Basics tile（激活模式） | Home 页"现在" section 各行 hover/点击展开，或并入快速开关 |
| Voice Input tile | Home 页"现在" section 第 2 行 |
| Voice Control tile | Home 页"现在" section 第 3 行 |
| 权限详情全部 | 折叠进"设置" → 权限 tab |

状态 🟡（待 Home 页实现后验证）

### 2. Voice Input（`InputSettingsView(.basics)`）

旧 GlassCard 结构（`SettingsModules.swift:376-608` 范围内）：
- 麦克风设备选择 + 语音语言（single / bilingual 模式切换）
- 语音激活总开关 + 激活模式
- （其他开关，具体以代码为准）

**新位置**：**语音** 页上半部分（page 内 section "输入"）。
内容原样放入，不拆不改。

状态 🟡

### 3. Text Cleanup（`InputSettingsView(.textCleanup)`）

旧 GlassCard 结构：
- Term corrections（术语修正）
- Text cleanup rewrite card（全文优化，含 LLM 相关设置，line 610+）
- `LLMRewriteSettingsCard` 独立 struct（line 1177）

**新位置**：**语音** 页下半部分（page 内 section "文字优化"）。

状态 🟡

### 4. Pointer & Hot Zones（`ControlsPointerHotZonesSettingsView`）

旧内容：
- `PointerSettingsCardContent`（GlassCard 包装，line 5845）
- `HeadGestureSettingsContent(showsDiagnostics: false)`（line 5945）

**新位置**：**指针** 页（直接改名，内容 0 改动）。

状态 🟢（纯改名，无内容变动，风险最低）

### 5. Shortcuts（`ControlsShortcutsSettingsView`）

旧内容：
- `HotkeySettingsSection()`（一个独立 section）

**新位置**：**快捷键** 页（直接改名，内容 0 改动）。

状态 🟢

### 6. Permissions & Status（`PermissionsStatusSettingsView`）

旧内容（在 `AetherMainView.swift:717-?`）：
- Readiness summary（重复 Overview 的那份）
- 辅助功能权限卡 + 修复按钮
- 麦克风权限卡 + 修复按钮
- 语音识别权限卡 + 修复按钮
- 开机启动开关（`LaunchAtLoginManager`）
- 鼠标 idle 暂停分钟数 stepper

**新位置**：**设置** 页 → **权限** tab。整页原样放入，无内部改动。

注意：Home 页"阻断横幅"会复用这里的权限状态检测逻辑（但不复用 UI）。

状态 🟡

### 7. Lexicon（`InputSettingsView(.lexicon)`）

旧 GlassCard 结构（line 733+）：
- `showsLexiconTools` 区块
- `VoiceLexiconEditorRow`（line 5056）
- `VoiceLexiconSectionChip`（line 2364）
- `VoiceLexiconSectionHeader`（line 2388）
- `SpeechTermGroupCard`（line 5207）
- `SpeechTermGroupEditorSheet`（line 5245）

**新位置**：**设置** 页 → **词库** tab。原样放入。

状态 🟡

### 8. App Rules（`AppRulesSettingsView`）

旧内容：
- `CustomAppShortcutRulesCard`（line 2757）
- `CustomAppShortcutRuleEditorSheet`（line 2933，sheet 弹窗）

**新位置**：**设置** 页 → **App 规则** tab。

状态 🟡

### 9. Launch Aliases（`AppLaunchAliasesSettingsView`）

旧内容：
- `CustomAppLaunchAliasesCard`（line 5507）
- `CustomAppLaunchAliasRuleEditorSheet`（line 5651，sheet 弹窗）

**新位置**：**设置** 页 → **启动别名** tab。

状态 🟡

### 10. Import & Export（`ImportExportSettingsView`）

旧内容：
- Lexicon 导入/导出/剪贴板导入/导出按钮
- App Rules 导入/导出/复制 AI 提示按钮
- Launch Aliases 导入/导出按钮
（大致三组按钮，每组 3-4 个操作）

**新位置**：**设置** 页 → **导入导出** tab。

状态 🟡

### 11. Voice Usage（`InputSettingsView(.insights)`）

旧内容（line 3069+）：
- `VoiceUsageInsightsCard`
- `VoiceUsageStatusChip`
- `VoiceUsageTopAppRow`
- `VoiceUsageEventRow` 等多个 row 组件
- `VoiceUsageAllRecentEventsPopover`
- `VoiceUsageAllAppsPopover`
- `VoiceUsageSummaryBadge`
- `VoiceUsageAppSummaryRow`

**新位置**：**设置** 页 → **诊断** tab → segmented control 第 1 项 "语音使用"。

**注意**：Home 页"最近" section **复用这个数据源**（不是复用 UI），只取 3 行 summary 显示。

状态 🟡

### 12. Wake & Activation（`InputSettingsView(.wakeInsights)`）

旧内容（line 3709+）：
- `WakeActivationInsightsCard`
- `WakePhrasePill`
- `WakePhraseDistributionRow`
- `WakePhraseMetricChip`

**新位置**：**设置** 页 → **诊断** tab → segmented control 第 2 项 "唤醒与激活"。

状态 🟡

### 13. Focus & Input Diagnostics（`FocusDiagnosticsSettingsView`）

旧内容：
- 焦点窗口追踪诊断
- 输入注入诊断
- CaretDetector 相关
（需实现时读具体代码确认）

**新位置**：**设置** 页 → **诊断** tab → segmented control 第 3 项 "焦点诊断"。

状态 🟡

### 14. About（`AboutCenterView`）

旧内容（在 `AboutCenter.swift`）：
- 版本 / Build
- License / Trial 状态
- Update channel（stable / beta）
- appcast 检查按钮
- 支持链接
- 设备列表

**新位置**：**设置** 页 → **关于** tab。原样放入。

状态 🟡

## 不在矩阵里但相关的

- `HeadGestureSettingsContent`（`SettingsModules.swift:5945`）被 Pointer & Hot Zones 内嵌使用，不是独立页
- `HotkeySettingsSection`（在 `HotkeyManager.swift` 附近）被 Shortcuts 内嵌
- `VoiceLexiconDefaults`（`Speech/VoiceLexiconDefaults.swift`）是数据层，不在 IA 考量
- Menu bar 的快速入口不在矩阵里（单独见 design.md §7）

## 未核对项（留给实现阶段）

- [ ] Permissions & Status 页内的具体控件清单（读 `AetherMainView.swift:717+` 补全）
- [ ] Text Cleanup 页的 LLM 子设置具体有哪些控件
- [ ] Lexicon 页各 sub-section 的结构（`basicLexiconSectionExpanded` 展开/收起行为）
- [ ] FocusDiagnosticsSettingsView 具体内容
- [ ] AboutCenter 页的 support link 列表

这些留到 Phase 3（新侧栏上线）之前补充；迁移工作**不会**因为这几项缺失而停滞（反正这几页都是原样放入）。

## 验收清单（改完后逐项手动核对）

Phase 8 验收用：

- [ ] 打开新版 App，进 Home，确认 4 个 section 都按 design.md §4 显示
- [ ] 进 "语音" 页，确认原 Voice Input + Text Cleanup 所有卡片都在
- [ ] 进 "指针"，确认 `PointerSettingsCardContent` 和 `HeadGestureSettingsContent` 都在
- [ ] 进 "快捷键"，确认 `HotkeySettingsSection` 所有快捷键项都在
- [ ] 进 "设置" → "权限"，确认 3 个权限卡 + 登录启动 + idle 暂停
- [ ] 进 "设置" → "词库"，词库条目完整保留
- [ ] 进 "设置" → "App 规则"，自定义规则条目完整保留
- [ ] 进 "设置" → "启动别名"，别名条目完整保留
- [ ] 进 "设置" → "导入导出"，3 组导入导出按钮都在
- [ ] 进 "设置" → "诊断"，segmented control 3 项（语音使用 / 唤醒与激活 / 焦点诊断）都能切，内容保留
- [ ] 进 "设置" → "关于"，版本/License/更新/支持链接都在
- [ ] 老用户 `UserDefaults`：lexicon / 规则 / 别名 / 快捷键配置完整保留
- [ ] 所有原 14 项里的入口都能在新 5 项里找到
