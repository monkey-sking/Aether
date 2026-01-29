# Project Aether

**全感知协同交互系统 (All-Sensing Collaborative Interaction System)**

> "环境即计算，设备即感官。"

Project Aether 是一个构建在 macOS 生态上的分布式感知网络。它聚合了 LiDAR、麦克风阵列、IMU 和其他底层传感器，通过微秒级同步协议 (gPTP) 和端侧 AI，实现无缝的“隐形”交互。

## 📁 项目结构 (Directory Structure)

```
Aether/
├── Apps/
│   └── AetherCore/   # 主 App (macOS / SwiftUI) - 大脑
├── Drivers/
│   └── AetherDriver/ # DriverKit Extension - 虚拟神经中枢 (Virtual HID)
├── Shared/           # 共享数据模型与协议 (IPC / XPC)
├── docs/             # 项目文档 (PRD, Roadmap, User Concept)
└── .agent/           # Agentic Workflows & Skills
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

### 初始化
```bash
# 查看相关 Agent 技能
cat .agent/skills/setup_driverkit.md
```

## 🤝 贡献 (Contributing)
请遵循 `docs/Standards.md` 中的文档编写规范与 Git 提交规范。
