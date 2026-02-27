# 需求文档：Project Aether 审核改进

## 简介

本文档定义了 Project Aether 全面审核后发现的关键问题和改进机会的需求。Project Aether 是一个基于 AirPods 头部追踪、语音识别和 DriverKit 虚拟 HID 驱动的 macOS 交互系统。审核发现了多个严重问题（影响核心功能）和可改进项（影响代码质量和可维护性）。

本需求文档按优先级组织，涵盖 P0（立即执行）、P1（短期执行）和 P2（中期执行）三个级别的改进任务。

## 术语表

- **System**: Project Aether 整体系统
- **HeadMotionManager**: 管理 AirPods 头部追踪的核心组件
- **DriverClient**: 与 DriverKit 虚拟 HID 驱动通信的客户端
- **DwellOverlay**: 停留点击功能的视觉反馈覆盖层
- **Connection_Lock**: 防止 AirPods 在追踪期间切换设备的机制
- **HUD**: 屏幕上的状态提示界面
- **Voice_Command**: 语音识别触发的系统指令
- **Head_Gesture**: 头部动作触发的系统指令
- **Tracking_State**: 头部追踪的当前状态（启动、运行、停止）
- **Bluetooth_Route**: AirPods 的蓝牙连接路由
- **HID_Event**: 发送到 DriverKit 驱动的人机接口设备事件
- **CI/CD_Pipeline**: 持续集成和持续部署流程
- **Test_Coverage**: 自动化测试覆盖的代码百分比
- **ADR**: 架构决策记录（Architecture Decision Record）

---

## P0 需求：立即执行（1-2周）

### 需求 1：实现滚动功能

**用户故事：** 作为用户，我希望通过语音指令和头部倾斜来滚动页面，以便在不使用鼠标的情况下浏览内容。

#### 验收标准

1. WHEN 用户说出"向上滚动"Voice_Command，THE System SHALL 向上滚动当前活动窗口
2. WHEN 用户说出"向下滚动"Voice_Command，THE System SHALL 向下滚动当前活动窗口
3. WHILE Tracking_State 为运行状态，WHEN 用户头部向前倾斜超过 15 度，THE System SHALL 向下滚动当前活动窗口
4. WHILE Tracking_State 为运行状态，WHEN 用户头部向后倾斜超过 15 度，THE System SHALL 向上滚动当前活动窗口
5. THE System SHALL 支持所有 7 种语言的滚动 Voice_Command
6. WHEN 滚动操作执行时，THE System SHALL 在 50ms 内发送 HID_Event 到 DriverClient
7. WHEN 滚动操作完成时，THE System SHALL 显示视觉反馈 HUD
8. FOR ALL 滚动操作，THE System SHALL 记录操作日志用于调试

### 需求 2：实现拖拽功能

**用户故事：** 作为用户，我希望通过语音指令来拖拽窗口和对象，以便重新排列界面元素。

#### 验收标准

1. WHEN 用户说出"开始拖拽"Voice_Command，THE System SHALL 在当前光标位置按下鼠标左键
2. WHEN 用户说出"结束拖拽"Voice_Command，THE System SHALL 在当前光标位置释放鼠标左键
3. WHILE 拖拽状态激活，THE System SHALL 在 HUD 上显示"拖拽中"指示器
4. WHEN 拖拽状态激活时，THE System SHALL 允许头部追踪移动光标
5. THE System SHALL 支持所有 7 种语言的拖拽 Voice_Command
6. WHEN 拖拽操作开始或结束时，THE System SHALL 在 50ms 内发送 HID_Event 到 DriverClient
7. IF 拖拽状态持续超过 30 秒，THEN THE System SHALL 自动释放鼠标按键并显示超时警告
8. FOR ALL 拖拽操作，THE System SHALL 记录开始和结束时间戳

### 需求 3：修复快捷键启动反馈

**用户故事：** 作为用户，当我按下快捷键启动追踪但 AirPods 未连接时，我希望看到明确的错误提示，以便了解系统状态。

#### 验收标准

1. WHEN 用户按下启动快捷键，IF AirPods 未连接，THEN THE System SHALL 显示"AirPods 未连接"错误 HUD
2. WHEN 用户按下启动快捷键，IF AirPods 已连接，THEN THE System SHALL 显示"启动追踪"成功 HUD
3. THE System SHALL 在快捷键按下后 100ms 内检测 AirPods 连接状态
4. WHEN 错误 HUD 显示时，THE System SHALL 在 3 秒后自动隐藏
5. THE System SHALL 在日志中记录快捷键触发和 AirPods 连接状态
6. WHEN AirPods 未连接时，THE System SHALL 阻止 HeadMotionManager 启动追踪
7. THE System SHALL 支持所有 7 种语言的错误消息

### 需求 4：添加基础单元测试

**用户故事：** 作为开发者，我希望有自动化单元测试覆盖核心功能，以便在修改代码时快速发现回归问题。

#### 验收标准

1. THE System SHALL 包含 HeadMotionManager 核心方法的单元测试
2. THE System SHALL 包含 DriverClient 核心方法的单元测试
3. THE System SHALL 包含 Voice_Command 解析逻辑的单元测试
4. THE System SHALL 包含坐标转换逻辑的单元测试
5. WHEN 单元测试运行时，THE System SHALL 在 30 秒内完成所有测试
6. THE System SHALL 达到至少 40% 的 Test_Coverage
7. WHEN 任何单元测试失败时，THE System SHALL 提供清晰的失败原因和堆栈跟踪
8. THE System SHALL 使用 XCTest 框架编写所有单元测试

---

## P1 需求：短期执行（2-4周）

### 需求 5：添加蓝牙断线监听

**用户故事：** 作为用户，当我的 AirPods 切换到其他设备时，我希望系统立即停止追踪并通知我，而不是等待超时。

#### 验收标准

1. THE System SHALL 监听 Bluetooth_Route 变化事件
2. WHEN Bluetooth_Route 从 AirPods 变更为其他设备，THE System SHALL 在 500ms 内停止追踪
3. WHEN 蓝牙断线检测到时，THE System SHALL 显示"AirPods 已断开"HUD
4. THE System SHALL 保留现有的 5 秒超时检测作为备用机制
5. WHEN 追踪停止时，THE System SHALL 释放 Connection_Lock
6. THE System SHALL 在日志中记录蓝牙断线事件和时间戳
7. WHEN AirPods 重新连接时，THE System SHALL 显示"AirPods 已连接"通知

### 需求 6：优化 Connection Lock

**用户故事：** 作为用户，我希望 Connection Lock 只在追踪激活时生效，以便在不使用系统时 AirPods 可以正常切换设备。

#### 验收标准

1. WHEN Tracking_State 变为运行状态，THE System SHALL 激活 Connection_Lock
2. WHEN Tracking_State 变为停止状态，THE System SHALL 在 1 秒内释放 Connection_Lock
3. WHILE Tracking_State 为停止状态，THE System SHALL 允许 AirPods 自由切换设备
4. THE System SHALL 在日志中记录 Connection_Lock 的激活和释放事件
5. IF Connection_Lock 激活失败，THEN THE System SHALL 记录警告但继续追踪
6. WHEN Connection_Lock 释放时，THE System SHALL 验证释放操作成功

### 需求 7：添加输入验证

**用户故事：** 作为开发者，我希望所有发送到 DriverKit 的输入都经过验证，以防止恶意输入导致驱动崩溃。

#### 验收标准

1. WHEN DriverClient 接收到 HID_Event，THE System SHALL 验证坐标在屏幕边界内
2. WHEN DriverClient 接收到 HID_Event，THE System SHALL 验证事件类型为有效值
3. IF HID_Event 验证失败，THEN THE System SHALL 拒绝事件并记录错误日志
4. THE System SHALL 限制 HID_Event 的 X 坐标在 0 到屏幕宽度之间
5. THE System SHALL 限制 HID_Event 的 Y 坐标在 0 到屏幕高度之间
6. WHEN 验证失败时，THE System SHALL 返回描述性错误消息
7. THE System SHALL 在验证逻辑中包含单元测试

### 需求 8：性能优化

**用户故事：** 作为用户，我希望系统响应流畅，UI 更新不会造成性能问题。

#### 验收标准

1. THE System SHALL 将 UI 更新频率限制为每秒 30 次
2. WHEN 头部追踪数据到达时，THE System SHALL 批量处理坐标更新
3. THE System SHALL 在后台线程处理坐标转换计算
4. WHEN DwellOverlay 需要创建时，THE System SHALL 在追踪启动前完成创建
5. THE System SHALL 使用防抖机制减少 HUD 更新频率
6. WHEN 系统空闲时，THE System SHALL 释放不必要的内存资源
7. THE System SHALL 在性能分析工具中显示 CPU 使用率低于 15%

---

## P2 需求：中期执行（1-2个月）

### 需求 9：引入依赖注入

**用户故事：** 作为开发者，我希望使用依赖注入替代单例模式，以便更容易编写单元测试和模拟依赖。

#### 验收标准

1. THE System SHALL 使用协议定义 HeadMotionManager 的公共接口
2. THE System SHALL 使用协议定义 DriverClient 的公共接口
3. THE System SHALL 通过构造函数注入依赖而非使用单例
4. THE System SHALL 提供依赖注入容器用于管理对象生命周期
5. WHEN 运行单元测试时，THE System SHALL 允许注入模拟对象
6. THE System SHALL 保持与现有代码的向后兼容性
7. THE System SHALL 在重构后通过所有现有测试

### 需求 10：状态机重构

**用户故事：** 作为开发者，我希望使用状态机模式管理追踪状态，以便减少布尔标志并提高代码可读性。

#### 验收标准

1. THE System SHALL 定义明确的 Tracking_State 枚举（未启动、启动中、运行中、暂停中、已停止、错误）
2. THE System SHALL 使用状态机管理 Tracking_State 转换
3. THE System SHALL 验证所有状态转换的合法性
4. IF 非法状态转换发生，THEN THE System SHALL 记录错误并保持当前状态
5. THE System SHALL 在日志中记录所有状态转换
6. THE System SHALL 为状态机提供单元测试覆盖
7. THE System SHALL 移除冗余的布尔标志（isTracking、isPaused 等）

### 需求 11：添加 CI/CD 流程

**用户故事：** 作为开发者，我希望有自动化的 CI/CD 流程，以便每次提交都自动运行测试和代码质量检查。

#### 验收标准

1. THE System SHALL 在每次 Git 提交时自动运行所有单元测试
2. THE System SHALL 在每次 Git 提交时运行代码格式检查
3. THE System SHALL 在每次 Git 提交时运行静态代码分析
4. WHEN 任何 CI 检查失败时，THE System SHALL 阻止代码合并
5. THE System SHALL 生成 Test_Coverage 报告并显示在 CI 界面
6. THE System SHALL 在 CI_Pipeline 中运行构建验证
7. THE System SHALL 在 15 分钟内完成完整的 CI_Pipeline

### 需求 12：完善测试覆盖

**用户故事：** 作为开发者，我希望达到 70% 的测试覆盖率，以便确保代码质量和减少回归风险。

#### 验收标准

1. THE System SHALL 达到至少 70% 的 Test_Coverage
2. THE System SHALL 包含集成测试覆盖核心用户流程
3. THE System SHALL 包含 UI 测试覆盖关键交互场景
4. THE System SHALL 为所有公共 API 提供单元测试
5. THE System SHALL 为错误处理路径提供测试用例
6. THE System SHALL 为边界条件提供测试用例
7. WHEN Test_Coverage 低于 70% 时，THE CI_Pipeline SHALL 发出警告
8. THE System SHALL 使用 XCTest 和 XCUITest 框架编写测试

### 需求 13：添加 API 文档

**用户故事：** 作为开发者，我希望所有公共 API 都有清晰的文档，以便理解如何使用和扩展系统。

#### 验收标准

1. THE System SHALL 为所有公共类提供 Swift 文档注释
2. THE System SHALL 为所有公共方法提供 Swift 文档注释
3. THE System SHALL 在文档中包含参数说明和返回值说明
4. THE System SHALL 在文档中包含使用示例
5. THE System SHALL 使用 Jazzy 或 DocC 生成 HTML 文档
6. THE System SHALL 在 CI_Pipeline 中验证文档完整性
7. THE System SHALL 在 README 中提供文档链接

### 需求 14：添加架构决策记录

**用户故事：** 作为开发者，我希望记录重要的架构决策，以便理解设计选择的原因和权衡。

#### 验收标准

1. THE System SHALL 在 docs/adr 目录中维护 ADR 文档
2. THE System SHALL 为每个重要架构决策创建独立的 ADR
3. THE System SHALL 在 ADR 中包含决策背景、选项、决策和后果
4. THE System SHALL 为 DriverKit 选择创建 ADR
5. THE System SHALL 为状态管理方案创建 ADR
6. THE System SHALL 为依赖注入方案创建 ADR
7. THE System SHALL 使用 Markdown 格式编写 ADR

### 需求 15：添加速率限制

**用户故事：** 作为开发者，我希望对 HID 事件发送添加速率限制，以防止过载 DriverKit 驱动。

#### 验收标准

1. THE System SHALL 限制 HID_Event 发送速率为每秒最多 120 次
2. WHEN HID_Event 发送速率超过限制时，THE System SHALL 丢弃多余事件
3. THE System SHALL 在日志中记录速率限制触发事件
4. THE System SHALL 使用令牌桶算法实现速率限制
5. THE System SHALL 为速率限制逻辑提供单元测试
6. WHEN 速率限制触发时，THE System SHALL 优先保留最新的 HID_Event
7. THE System SHALL 允许通过配置文件调整速率限制阈值

### 需求 16：改进 DriverKit 连接重试

**用户故事：** 作为用户，当 DriverKit 连接失败时，我希望系统智能重试，以便提高连接成功率。

#### 验收标准

1. WHEN DriverClient 连接失败时，THE System SHALL 使用指数退避算法重试
2. THE System SHALL 最多重试 5 次连接
3. THE System SHALL 在第 1 次重试前等待 1 秒
4. THE System SHALL 在第 2 次重试前等待 2 秒
5. THE System SHALL 在第 3 次重试前等待 4 秒
6. IF 所有重试失败，THEN THE System SHALL 显示"驱动连接失败"错误 HUD
7. THE System SHALL 在日志中记录每次重试尝试和结果

---

## 非功能性需求

### 需求 17：兼容性

**用户故事：** 作为开发者，我希望所有改进都保持与现有代码的兼容性，以便不破坏已完成的功能。

#### 验收标准

1. THE System SHALL 通过所有 Phase 1 的功能验收测试
2. THE System SHALL 保持与 macOS 13.0+ 的兼容性
3. THE System SHALL 保持与所有支持的 AirPods 型号的兼容性
4. THE System SHALL 保持所有 7 种语言的多语言支持
5. WHEN 重构代码时，THE System SHALL 保持公共 API 签名不变
6. THE System SHALL 遵循 Apple DriverKit 和 System Extension 规范
7. THE System SHALL 在重构后通过所有现有的手动测试用例

### 需求 18：代码质量

**用户故事：** 作为开发者，我希望代码质量评分从 7.5/10 提升到 9/10，以便提高可维护性。

#### 验收标准

1. THE System SHALL 在静态代码分析中获得至少 9/10 的评分
2. THE System SHALL 消除所有高优先级的代码异味
3. THE System SHALL 将代码重复率降低到 5% 以下
4. THE System SHALL 将平均方法复杂度降低到 10 以下
5. THE System SHALL 遵循 Swift 官方代码风格指南
6. THE System SHALL 在 SwiftLint 检查中无错误和警告
7. THE System SHALL 在代码审查中获得至少 2 个批准

---

## 成功标准

本项目的整体成功标准：

1. 所有 P0 需求在 2 周内完成实施和测试
2. 所有 P1 需求在 4 周内完成实施和测试
3. 所有 P2 需求在 8 周内完成实施和测试
4. Test_Coverage 达到 70% 或更高
5. 所有核心功能有自动化测试覆盖
6. CI_Pipeline 正常运行并在每次提交时执行
7. 代码质量评分从 7.5/10 提升到 9/10 或更高
8. 所有严重问题（P0）得到修复并验证
9. 用户可以正常使用滚动和拖拽功能
10. 系统在 AirPods 断线时提供即时反馈

---

## 附录：审核报告参考

本需求文档基于 Project Aether 全面审核报告，该报告识别了 16 个关键问题和改进机会。所有需求都可追溯到审核报告中的具体发现。

审核报告关键指标：
- 当前代码质量评分：7.5/10
- 当前测试覆盖率：0%
- 识别的严重问题：5 个
- 识别的可改进项：11 个
- 预计改进后评分：9/10
