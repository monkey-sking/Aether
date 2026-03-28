# Aether 文档索引

Aether 当前是一个以 macOS 为中心的本地交互产品。当前代码主轴集中在：

- 语音输入与语音控制
- HUD 状态反馈与输入态跟随
- 兼容耳机 / AirPods 头部姿态控制与头势
- 当前 App 快捷键面板与自定义 App 规则
- 权限引导、激活 / 试用、Sparkle 更新

当前不要把以下内容当成“已经落地的现状”：

- Vision Pro / iPad + Pencil / Apple Watch / HomePod / UWB / gPTP 多设备协同
- “Apple 全家桶分布式感知网络”类体验叙事
- DriverKit 键盘注入路径

当前额外边界：

- 文本注入当前不以 DriverKit 键盘路径为近期目标；现有文本输出继续按当前实现路径理解

补充边界：

- 当前主工作区根目录是 `/Volumes/SSD/Projects/Aether/Apps`
- 当前核心代码主要位于 `Apps/Apps/AetherCore`
- 例行开发与回归优先看 `Current` 文档，不要默认从 PRD 开始

## 文档状态

本目录按以下三个状态管理：

- `Current`：应与当前代码、当前验收口径和当前产品范围保持一致
- `Planned`：描述未来开发方向、待办和设计约束，不代表已经实现
- `Historical`：保留背景、审计或旧方案，不作为当前事实来源

如果某篇文档和代码冲突，处理顺序应是：

1. 以当前代码和当前验收结论为准
2. 回写最接近的 `Current` 文档
3. 把失真的旧文档降级为 `Historical` 或补充明确说明

## 推荐阅读顺序

1. `README.md`
2. `user_guide.md`
3. `PENDING_ACCEPTANCE.md`
4. `VOICE_LEXICON_RULES.md`
5. `PERMISSION_TROUBLESHOOTING.md`
6. `TESTING.md`

如果你在做未来功能，再继续看：

1. `Phase1.5_TODO.md`
2. `ACTIVATION_GATING_TODO.md`
3. `REFERRAL_MVP.md`
4. `Roadmap.md`

如果你在看跨仓库 / 跨项目推进状态，再补看工作区根目录的 `../TODO.md`。

## 当前优先文档

| 文档 | 状态 | 用途 |
| :--- | :--- | :--- |
| `user_guide.md` | `Current` | 当前产品使用说明，面向普通用户 |
| `PENDING_ACCEPTANCE.md` | `Current` | 当前待人工复验与已通过项的活清单；未勾选不等于源码未实现 |
| `VOICE_LEXICON_RULES.md` | `Current` | 语音词库、自定义 App 规则和未来 App 打开/切换的边界 |
| `PERMISSION_TROUBLESHOOTING.md` | `Current` | 权限、授权状态与诊断排障 |
| `TESTING.md` | `Current` | 本地开发验证与回归入口 |
| `Standards.md` | `Current` | 文档与贡献规范 |

## 规划文档

| 文档 | 状态 | 用途 |
| :--- | :--- | :--- |
| `Phase1.5_TODO.md` | `Planned` | 中期规划与明确功能缺口清单；不要把它和当前复验清单混读 |
| `ACTIVATION_GATING_TODO.md` | `Planned` | 激活门禁已落地基线 + 剩余验证/收口 |
| `REFERRAL_MVP.md` | `Planned` | 邀请码与邀请奖励 MVP 范围、API 草案与验收口径 |
| `WHISPER_BACKEND_IMPLEMENTATION_CHECKLIST.md` | `Planned` | Whisper 后端专项实施清单 |
| `Roadmap.md` | `Planned` | 中长期路线图，混合近期计划与远期愿景 |

## 历史与愿景文档

以下文档保留背景价值，但不要把它们当成当前产品说明：

- `PRD.md`
- `User_Concept.md`
- `Phase1_TODO.md`
- `ACCEPTANCE_CHECKLIST.md`
- `ACCEPTANCE_CHECKLIST_2026-02-14.md`
- `verification_checklist.md`
- `TESTFLIGHT_ANALYSIS.md`
- `code_audit_report.md`
- `project_audit_report_2026-03-15.md`

## 设计与专项资料

- `hud_specification_v2.md`
- `design/HUD_Architecture.md`
- `specs/`

这类文档更适合做设计参考或专项治理输入。使用前先对照当前代码，不要默认它们已经与实现同步。

## 维护要求

- 任何影响行为、范围、设置、命令语义或验收口径的改动，都应先更新最接近的 `Current` 或 `Planned` 文档
- 不要再默认“所有改动都先改 PRD / Roadmap”；只有范围与方向变化时才更新它们
- 新文档默认放在 `docs/`；如果只是保留背景，应明确标成 `Historical`
- 路径、命令和产物位置统一以 `/Volumes/SSD/Projects/Aether/Apps` 为基准，除非文档明确说明是 `Website/`
