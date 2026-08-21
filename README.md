# Aether App

`App` 是 Aether 的 macOS 客户端仓库。这里放的是当前在维护的原生 App、构建脚本、文档和测试，而不是早期 README 里那种偏概念化的项目介绍。

这份 README 只按当前源码做导航，不再按历史阶段或提交摘要描述项目。

## Workspace（工作区总览）

Aether 项目根目录（如 `/Volumes/SSD/Projects/Aether`）按 surface 拆分为多个独立仓库：

- `App/` — 本仓库：macOS 客户端 + DriverKit 相关代码（Sparkle 更新流水线）
- `Website/` — 官网 aether.7caifei.com：定价 / 下载 / FAQ / Stable / Beta 页
- `Admin/` — Auth / entitlement 后端、计费集成说明、管理脚本（ProcessZero/Admin，独立维护）

商业模型：免费试用 → 月/年订阅；App 内 About 页邮箱 + 激活码；公开 Stable/Beta 更新通道；邀请奖励赠送时长。

跨项目发布清单见 `docs/Aether-TODO.md`；工作流接收队列见 `docs/WORKSTREAM_INBOX.md`。

## 仓库里现在有什么

```text
App/
├── Apps/
│   └── AetherCore/          # 主应用源码
├── AetherTests/             # 单元测试
├── Scripts/                 # 构建 / 安装 / 打包 / 签名脚本
├── Shared/                  # 共享头文件
├── Drivers/                 # 预留目录（当前只有空目录结构）
├── docs/                    # 产品、设计、测试、发布、审计文档
└── Aether.xcodeproj
```

当前能直接看的主代码基本都在 `Apps/AetherCore/`。

## 入口文件

- `Apps/AetherCore/AetherApp.swift`
  - `@main`
  - 定义 `AppState`
  - 管理语音开关、激活模式、权限状态、主窗口和菜单栏状态同步
- `Apps/AetherCore/AetherMainView.swift`
  - 主窗口
  - 当前侧栏页面是：
    - `Overview`
    - `Head Gestures`
    - `Shortcuts`
    - `Current App Controls`
    - `Voice Insights`
    - `Voice Lexicon`
    - `About`
- `Apps/AetherCore/MenuBar.swift`
  - 菜单栏入口
  - 包含主状态、权限入口、语音输入/控制开关、主窗口唤起

## 主要模块

### Head / Pointer

- `Apps/AetherCore/HeadMotionManager.swift`
  - 头部追踪主状态机
  - 跟踪启停
  - 校准 / 居中
  - 全局快捷键联动
  - 耳机单击 / 双击 / 三击动作
  - 头部动作与热区相关持久化配置

### Voice

- `Apps/AetherCore/SpeechManager.swift`
  - 语音总控
  - 麦克风设备选择
  - 语音识别会话
  - 输入/控制状态同步
- `Apps/AetherCore/Speech/RecognitionSession.swift`
- `Apps/AetherCore/Speech/AudioCaptureSession.swift`
- `Apps/AetherCore/Speech/WakeWordDetector.swift`
- `Apps/AetherCore/Speech/VoiceCommandRouter.swift`
- `Apps/AetherCore/Speech/DictationHandler.swift`
- `Apps/AetherCore/Speech/TextInjector.swift`
- `Apps/AetherCore/Speech/LLMProviders.swift`

从 `AppState` 的实际代码看，当前语音激活模式是：

- `pushToTalk`
- `wakeWord`
- `handsFree`

另外语音输入和语音控制是分开的两个开关：

- `isVoiceInputEnabled`
- `isVoiceControlEnabled`

### HUD

- `Apps/AetherCore/HUD/HUDManager.swift`
- `Apps/AetherCore/HUD/HUDState.swift`
- `Apps/AetherCore/HUD/HUDView.swift`
- `Apps/AetherCore/HUD/CaretDetector.swift`
- `Apps/AetherCore/HUD/InputMethodCaretBridge.swift`

### Settings / About

- `Apps/AetherCore/SettingsModules.swift`
  - Voice settings 页面
  - Head gesture / Hot zone 配置页面
  - Shortcuts 页面
  - Voice Insights 页面
- `Apps/AetherCore/AboutCenter.swift`
  - About 页面
  - License / Trial
  - Update channel / appcast 检查
  - 支持链接和设备列表

## 当前 UI 结构

按 `AetherMainView.swift` 和 `SettingsModules.swift`，现在这个 App 不是单页设置，也不是只做 AirPods 光标。

首页 `Overview` 里当前实际有这些卡片：

- Readiness / 权限与设备就绪状态
- Pointer Control
- Voice Basics
- Voice Input
- Voice Control

`Head Gestures` 页面里当前能看到的是：

- `Hot Zone Rules`
- `Head Gestures (Nod/Shake)`
- `Advanced & Diagnostics`

`Shortcuts` 页面目前主要承载 `HotkeySettingsSection()`。

## 构建与发布脚本

常用脚本都在 `Scripts/`：

- `Scripts/BuildRelease.sh`
- `Scripts/BuildAndInstall.sh`
- `Scripts/InstallToApplications.sh`
- `Scripts/CreateDMG.sh`
- `Scripts/ReleaseForUsers.sh`
- `Scripts/Notarize.sh`
- `Scripts/PrepareAppBundle.sh`
- `Scripts/configure_signing.py`
- `Scripts/PublishSparkleRelease.sh`

常用命令：

```bash
cd App

./Scripts/BuildRelease.sh Release
./Scripts/BuildRelease.sh Debug

./Scripts/InstallToApplications.sh .build/release/Aether.app

./Scripts/BuildAndInstall.sh

SKIP_NOTARIZE=1 ./Scripts/ReleaseForUsers.sh
NOTARY_PROFILE=YourNotaryProfile ./Scripts/ReleaseForUsers.sh
```

按脚本现状：

- `BuildRelease.sh` 默认拒绝静默回退到 unsigned
- `BuildAndInstall.sh` 会走发布链路后重装到 `/Applications/Aether.app`
- `ReleaseForUsers.sh` 会处理签名、DMG、ZIP 和可选公证
- `PublishSparkleRelease.sh` 会把 Sparkle 更新 ZIP 同步到 `Website/public/aether(-beta)/`，生成 appcast + delta，并把 enclosure URL 重写到 tracking gateway

## 测试

当前仓库里的测试文件很少，主要是：

- `AetherTests/AetherTests.swift`
- `AetherTests/VoiceCommandRouterTests.swift`

## 文档入口

当前更值得参考的是这些文档：

- `docs/TESTING.md`
- `docs/PERMISSION_TROUBLESHOOTING.md`
- `docs/RELEASE_DISTRIBUTION.md`
- `docs/user_guide.md`
- `docs/VOICE_LEXICON_RULES.md`
- `docs/project_audit_report_2026-03-15.md`
- `docs/design/HUD_Architecture.md`
- `docs/specs/README.md`

这些文档更偏历史背景，不适合直接当“当前实现说明”：

- `docs/PRD.md`
- `docs/Roadmap.md`
- `docs/Phase1_TODO.md`
- `docs/Phase1.5_TODO.md`

## 目前 README 的定位

这份 README 现在只做三件事：

- 说明仓库里哪些目录还在活跃使用
- 给出主入口文件和页面结构
- 给出本地开发最常用的脚本入口

如果后面还要继续补，应该补的是：

- 一份单独的 `docs/development.md`
- 环境变量、签名要求、哪些文档已过期
- 当前功能矩阵和对应源码位置
