# iPhone Remote Spec

> **状态：PAUSED（2026-04-19）**
>
> 本 spec 依赖 Mac 端信息架构重构（见 [`../ia-refresh/`](../ia-refresh/)）。在 ia-refresh 的侧栏收拢 + Home 页 + onboarding 完成前**不开工**，否则 iPhone Remote 的 UI 会被做两遍（一次挂在旧 14 项侧栏下，一次搬到新 IA 里）。
>
> ia-refresh 完成后本 spec 需要做的调整（不在此刻动，只记一下）：
> - "iPhone Remote" 不是新增侧栏项，而是**指针**页下的一个 pointer source 选项（AirPods 头追 / iPhone 激光笔）
> - 配对 + 校准作为首次启动 onboarding 的可选延伸，不强制
> - 所有原 spec 里"新增 SettingsModules iPhone Remote 页"的描述要改写

---

为 Aether for Mac 增加一个 iOS 配套 App，作为**激光笔式指针**和**文本语音输入终端**。

## 文档结构

- **[design.md](design.md)** — 架构设计、协议定义、文件级改动
- **[tasks.md](tasks.md)** — 分阶段任务清单，按依赖顺序排列

## 核心决策（已锁定）

| 维度 | 决策 |
|---|---|
| 指针形态 | 激光笔式绝对指向（不是相对增量鼠标） |
| 位姿方案 | ARKit 6DOF + 四角校准，**屏上无任何常驻标记** |
| 多屏支持 | 每块屏独立四角校准，射线-矩形求交决定目标屏 |
| 重锚定 | 每次 iOS App 启动指屏中心一次（~5 秒） |
| 校准期交互 | 蒙屏独占，其他输入被拦截 |
| 语音输入 | iPhone 端 STT，**只发文本**到 Mac，不推音频 |
| 唤醒词 | 保留在 Mac 侧，与 iPhone 流无关 |
| 传输 | Multipeer Connectivity（MPC），Codable 包 |
| iOS App 定位 | 免费、上 App Store、**哑终端**（本地不做 license 校验） |

## 范围

**做**：

- 手持 iPhone 指屏移动光标（激光笔）
- PTT 按钮触发语音识别，结果以文本回传
- 可选：iOS 侧 `UITextView` 键盘模式，任意第三方 IME 的语音输入都能用
- 首次四角校准流程
- 每次启动的中心点重锚定
- 配对（6 位码或 QR）
- 与 Mac 现有激活状态集成（未激活拒绝连接）

**不做**（明确排除）：

- iPhone 端头戴模式 / 头追替代
- iPhone 麦克风音频流（Continuity Camera 那条路也不主动用）
- iOS 侧完整设置 UI（Aether 的所有设置仍然在 Mac 主 App 里）
- iOS 侧唤醒词监听
- iOS 侧独立付费/订阅

## 开始实施

按 [tasks.md](tasks.md) 的阶段顺序推进。每个阶段 Mac 端都能独立验证，不必等 iOS App 就位。
