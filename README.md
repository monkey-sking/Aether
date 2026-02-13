# Project Aether

**全感知协同交互系统 (All-Sensing Collaborative Interaction System)**

> "环境即计算，设备即感官。"

Project Aether 是一个构建在 macOS 生态上的分布式感知网络。它聚合了 AirPods 的 **头部追踪 (Head Tracking)**、麦克风阵列、IMU 和端侧 AI，通过自研的 DriverKit 虚拟驱动，实现无缝的“隐形”交互。

## 🌟 核心特性 (Core Features)

*   **⚡️ 头部光标 (Head Pointer)**
    *   利用 AirPods 陀螺仪实现微秒级光标控制，支持平滑滤波 (Smoothing) 与边缘停靠 (Dwell Click)。
    *   **手势**: 支持 Tilt Scroll (点头/仰头滚动) 与 Shake Stop (摇头停止)。
*   **🗣 语音中枢 (Voice Core)**
    *   支持 "Wake Word" 唤醒与上下文敏感指令，完全摆脱对物理键盘的依赖。
    *   **智能交互**: 实现了 PTT (Push-to-Talk) 与 Continuous Mode (持续监听) 的无缝切换。
*   **🔌 虚拟驱动 (Virtual HID)**
    *   基于 Apple DriverKit (`com.apple.developer.driverkit`)，模拟底层硬件输入，绕过系统级限制。
    *   **完全兼容**: 系统将此设备识别为原生鼠标/键盘，无需特殊 API 适配。
*   **📍 智能 HUD (Context-Aware HUD)**
    *   **零延迟响应**: 基于 Combine 的反应式状态管理，毫秒级切换显示内容。
    *   **智能定位**: 自动识别输入框 (Text Field) 与非输入区域，动态切换跟随策略 (Caret vs Mouse)。
    *   **抗干扰**: 针对各类无边框应用 (Electron/Arc) 的坐标系修正与容错处理 (Role-Based Fallback)。
*   **⌨️ 隐形输入法 (AetherIME)**
    *   **精准光标感知**: 作为一个“隐形”输入法存在，利用 `NSTextInputClient` 协议直接从应用内部获取精准的光标坐标。
    *   **系统级补盲**: 解决 Accessibility API 在某些应用 (如终端、旧版编辑器) 中无法获取光标或延迟过高的问题。

## 📁 项目结构 (Directory Structure)

```
Aether/
├── Apps/
│   └── AetherCore/           # 主 App (macOS / SwiftUI) - 大脑
│       ├── HeadMotionManager.swift   # 运动引擎 & 姿态解算
│       ├── VoiceService.swift        # 语音意图识别 & PTT 逻辑
│       └── HotkeyFeedbackHUD.swift   # 智能反馈与其定位逻辑 (Core Logic)
├── Drivers/
│   └── AetherDriver/         # DriverKit Extension - 虚拟神经中枢 (Virtual HID)
│       ├── AetherDriver.cpp          # 驱动逻辑入口
│       └── AetherUserClient.cpp      # App 与 Driver 通信层
├── InputMethod/              # 隐形输入法 (AetherIME)
│   └── AetherIME/            # 用于获取精准光标位置的辅助 IME
├── Shared/                   # 共享数据模型与协议 (IPC / XPC)
├── Scripts/                  # 自动化构建脚手架 (Build, Sign, Package)
├── docs/                     # 项目文档 (PRD, Roadmap, User Concept)
└── .agent/                   # Agentic Workflows & Skills
```

## 📚 文档索引 (Documentation)

*   [**产品需求文档 (PRD v3.0)**](docs/PRD.md): 系统的技术蓝图与完整规格说明。
*   [**用户体验白皮书 (User Concept)**](docs/User_Concept.md): 场景化描述与体验设计愿景。
*   [**实施路线图 (Roadmap)**](docs/Roadmap.md): 分阶段开发计划 (P1 - P4)。
*   [**Phase 1 实施清单 (TODO)**](docs/Phase1_TODO.md): 当前阶段的具体开发任务。
*   [**开发规范 (Standards)**](docs/Standards.md): 文档与代码贡献指南。

## 🚀 快速开始 (Getting Started)

### 环境要求
*   macOS 15.0+ (Sequoia)
*   Xcode 16.0+
*   Entitlements: 需申请 `com.apple.developer.driverkit` 权限。

### 构建与安装
项目包含完整的自动化构建脚本：

```bash
# 1. 编译 App 与 Driver (自动处理代码签名)
./Scripts/BuildRelease.sh Release

# 2. 生成发布级安装包 (DMG)
./Scripts/CreateDMG.sh
```

## 🗓️ 最新动态 (Latest Updates - v0.1.0 RC)
*   **Coordinate Normalization**: 修复了多显示器与屏幕旋转下的坐标系转换问题。
*   **Role-Based Fallback**: 优化了 HUD 在非输入模式下的跟随逻辑，杜绝在该模式下吸附于按钮或背景的问题。
*   **Chromium Defense**: 针对 Electron 应用的坐标异常 (0,0) 增加了严格的窗口校验机制。
*   **Build Automation**: 实现了全自动化的 `CreateDMG` 脚本，支持自定义背景与图标布局。

## 🤝 贡献 (Contributing)
请遵循 `docs/Standards.md` 中的文档编写规范与 Git 提交规范。
