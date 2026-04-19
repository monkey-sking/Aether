# IA Refresh Spec

重排 Aether for Mac 的信息架构（IA）和首次启动体验。目标：降低上手门槛，同时为后续 iPhone Remote 等新能力铺路。

## 文档结构

- **[design.md](design.md)** — 架构设计：侧栏映射、Home 页、onboarding 流程、Settings 聚合
- **[tasks.md](tasks.md)** — 分阶段任务清单

## 核心决策（已锁定）

| 维度 | 决策 |
|---|---|
| 侧栏项数 | **14 → 5**（Home / 语音 / 指针 / 快捷键 / 设置） |
| Home 页 | **完全重写**，不是优化 Overview。答三个问题：现在什么状态、能做什么、有没有问题 |
| Onboarding | 首次启动 Welcome + 权限三连 + AirPods 校准演示 + PTT 试用。每步可跳过 |
| 设置聚合 | 原 Advanced / Logs / Permissions / About 全部收进"设置"内部 tab，不是新侧栏项 |
| Menu bar | 去掉和 Home 重复的状态，只留快速开关 + 打开主窗口 |
| 老用户迁移 | **不做 legacy sidebar 开关**。首次重打开时给一个 15 秒的 What's New 气泡，然后就结束 |
| 术语改名 | **不做**（Lexicon 叫不叫 Lexicon 留到下次讨论） |
| 功能改动 | **零**。本次只动 IA / 排版 / 引导，不动任何业务逻辑 |

## 为什么做这次

现状盘点（对话中已确认）：

- 侧栏 **14 项** / 6 组，新用户要扫一遍才知道去哪
- `SettingsModules.swift` **6619 行**，约 **52 个** Toggle/Slider/Picker/Stepper/TextField
- 权限**在 3 处重复展示**：Overview / Menu bar / Permissions & Status
- `OnboardingStep` enum 存在但**没有对应 UI 流程**，首次启动直接进 Overview
- Overview 页**名不副实**，实际是"权限卡 + 4 个顶层开关"，没有"App 能做什么"的叙事

根问题不是"设置太多"而是"App 没有故事"——用户打开后不知道这 14 项侧栏凑起来能做成什么。

## 范围

**做**：

- 侧栏 IA 重排（14 → 5）
- Home 页重写
- 首次启动 onboarding 流程
- "设置"页内部 tab 结构（纯搬运现有 view）
- Menu bar 去冗余
- What's New 迁移气泡

**不做**（明确排除）：

- 任何业务逻辑改动（`SpeechManager` / `HeadMotionManager` / `HUDManager` 一行不碰）
- 拆 `SettingsModules.swift`（6619 行先留着，等这次 IA 稳定再拆）
- 术语重命名
- 新功能（含 iPhone Remote，它在自己的 spec 里等着）

## 相关 spec

- [`../iphone-remote/`](../iphone-remote/) — 已标记 paused，等本 spec 完成
