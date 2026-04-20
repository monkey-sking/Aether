# Aether for Mac — UI Redesign

> **关系位置**：本 spec 取代 `../ia-refresh/`（已暂缓）。诊断和迁移矩阵沿用 ia-refresh 的结论（`ia-refresh/settings_matrix.md` 仍是迁移核对表），但**实施路径完全重拟**——吸取 Phase 3 翻车教训，每 Phase 只改一件事。

## 产品定位

**Aether 是 macOS 的输入扩展，不是独立 App**。用户不"打开 Aether"——他们在用 Mac，Aether 在后台把语音/头动路由到当前前台 App。

## 关键决策（已锁定）

| 维度 | 决策 | 否决的方案 |
|---|---|---|
| 侧栏项数 | 14 → **5**：首页 / 语音 / 指针 / 快捷键 / 设置 | 分组 Section header（信息密度仍太高） |
| 页内切换 | **Form + Section 垂直排列** | segmented control（Phase 3 翻车）、子侧栏（结构大改） |
| Home 页 | **重写**，不是改 Overview | 优化 Overview（根问题是没叙事） |
| Onboarding | 独立 `NSWindow`，7 步，每步可跳 | Sheet（模态感太强）、inline（新用户没注意到） |
| 设置聚合 | 7 个 tab 放进"设置"容器 | 新增独立侧栏项 |
| Menu bar | 去权限重复，只留状态 + 快速入口 | 状态副标题与 Home 冗余 |
| 老用户迁移 | **不做 sidebar 回退开关**；老用户升级后看 What's New 气泡（一次） | 灰度开关（工程债不划算） |
| 视觉方向 | Apple HIG 原生 + 克制留白 + 一等品 polish（参考 Final Cut / Logic / Keynote） | Linear/Raycast、Arc、Notion、自建设计系统 |
| 终端术语 | **不改**（Lexicon / Wake / Dictation 保留） | 重命名（用户学习成本） |
| 业务逻辑 | **零改动**，全部当黑盒 | 顺手重构 |

## 诊断（今天到底哪里乱）

| 指标 | 现状 | 目标 |
|---|---|---|
| 侧栏项数 | 14 项 / 6 Section header | 5 项 / 无 Section |
| `SettingsModules.swift` | 6619 行 / ~52 控件 | **不拆**（本 spec 不解决），但入口从 10 个 Panel 压到 1 个容器 |
| 权限展示 | Overview / Menu bar / Permissions & Status 共 3 处 | 1 处（设置 → 权限），Home 仅在有异常时显示一条横幅 |
| Onboarding | enum 存在但无 UI，新用户直接进 Overview | 首次启动 7 步引导，走完才进主窗 |
| Overview 页定位 | "权限卡 + 4 个顶层开关"，无叙事 | 被 Home 页替换，叙事"Aether 正在为我做什么" |

## 做

- 侧栏 IA 14→5（**不分 Section**）
- Home 页重写
- 首次启动 onboarding
- 设置容器 + 7 tab 结构（**每个 tab 内容原样放入**，不拆控件）
- Menu bar 去冗余
- What's New 气泡（老用户一次性提醒）
- 为 iPhone Remote 预留"指针"页的 pointer-source 钩子

## 不做

- 业务逻辑改动（SpeechManager / HeadMotionManager / HUDManager / VoiceCommandRouter / DictationHandler / WakeWordDetector / CaretDetector **一行不碰**）
- 拆 `SettingsModules.swift`（6619 行留到下一次 spec）
- 改 `@AppStorage` key / `UserDefaults` key（老用户配置完整保留）
- 术语重命名
- 新功能（含 Rewrite Context、iPhone Remote 的 UI）

## 相关文档

- [design.md](design.md) — 具体设计（IA、Home、视觉语言、页面 layout、onboarding）
- [tasks.md](tasks.md) — 分阶段实施计划
- [`../ia-refresh/settings_matrix.md`](../ia-refresh/settings_matrix.md) — 14 项旧页面迁移核对表（沿用）
- [`../iphone-remote/`](../iphone-remote/) — iPhone Remote（独立 initiative，UI 钩子见 design.md §9）
