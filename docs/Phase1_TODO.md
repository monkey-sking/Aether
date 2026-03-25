# **Project "Aether" Phase 1 实施清单 (TODO)**

> 文档状态：`Historical`
> 说明：这是早期 Phase 1 清单，保留项目起始阶段的实现背景，不再作为当前主待办。
> 当前近期规划请先看 `Phase1.5_TODO.md`。

**里程碑目标**：感知觉醒 (The Awakening) - 建立 macOS 虚拟 HID 通路与 AirPods 基础姿态控制。

## **1. 工程脚手架搭建 (Foundation) [100%]**
- [x] **创建 Xcode Workspace**
    - [x] `Aether.xcworkspace`
    - [x] 主 App Target: `AetherCore` (macOS App, SwiftUI)
    - [x] 辅助 Target: `AetherDriver` (DriverKit Extension)
- [x] **配置 Entitlements & Info.plist**
    - [x] 申请/配置 `com.apple.developer.driverkit` 权限
    - [x] 配置 `com.apple.developer.driverkit.family.hid.virtual.device`
    - [x] 配置 System Extension 权限 (`system-extension` entitlement)
    - [x] 配置 `NSMotionUsageDescription` (AirPods 数据读取权限)
- [x] **代码签名与身份稳定 (Stable Identity)**
    - [x] **主 App**：配置为 `Personal Team` 自动签名 (解决 TCC 权限重置)
    - [x] **驱动器**：配置为 DriverKit 自动签名 + Provisioning Profile (可正常构建与 codesign)

## **2. 交互控制与控制逻辑 (Control & Logic) [100%]**
- [x] **系统级热键 (Global Hotkey)**
    - [x] 实现基于 `CGEventTap` 的 `Control + Option + S` 全局开关
    - [x] 支持在任何 App 背景下激活/停止追踪
- [x] **AirPods 物理按键 (Super-Control)**
    - [x] **单捏 (1x)** -> 鼠标左键点击
    - [x] **双捏 (2x)** -> 鼠标右键点击 (Context Menu)
    - [x] **三捏 (3x)** -> 鼠标双击
- [x] **悬停点击优化 (Dwell Logic)**
    - [x] 实现圆形倒计时进度条 UI
    - [x] 优化停留半径 (15px) 与触发延迟 (0.8s, 无起步延迟)

## **3. AirPods 姿态追踪 (Head Pointer) [100%]**
- [x] **CMHeadphoneMotionManager 集成**
    - [x] 初始化 Manager 并检查设备可用性
    - [x] `startDeviceMotionUpdates` 开启实时姿态回调
- [x] **姿态解算与映射**
    - [x] 读取 Pitch/Yaw 数据并映射到屏幕绝对坐标
    - [x] 实现死亡区 (Deadzone) 过滤细微抖动
- [x] **中心校准 (Calibration)**
    - [x] 实现自动校准与姿态重置逻辑

## **4. 驱动与基础架构 (Infrastructure) [90%]**
- [ ] **DriverKit 全流程接入（代码已闭环，待真机安装验证）**
    - [x] 实现 `OSSystemExtensionRequest` 激活逻辑 (含 Needs User Approval UI 引导)
    - [x] 实现 `IOUserClient` 数据通道 (IPC)：App -> Driver 发送 `AetherHIDEvent`
    - [x] 驱动侧：把 `AetherHIDEvent` 转为虚拟 HID（相对鼠标移动 + 左键点击 MVP）
    - [ ] 安装验证：DriverKit 扩展安装/启用后，指针移动与点击确实经由虚拟 HID 生效（非 CGEvent fallback）
- [x] **模拟点击方案 (Alternative)**
    - [x] 实现基于 `CoreGraphics` 的底层事件模拟 (作为驱动未激活时的可靠替代)
    - [x] 增加权限门禁：Accessibility 未授权时不安装全局热键 Event Tap

## **5. 状态管理与发现 (State & UI) [80%]**
- [x] **状态栏控制 (Menu Bar)**
    - [x] 显示连接状态与开关切换
- [ ] **AirPods 连接管理**
    - [ ] 监听蓝牙路由变化，实现断开自动暂停
- [ ] **多设备预研 (MCP)**
    - [ ] Multipeer Connectivity 基础架构初始化
- [ ] **语音输入 (Voice)**
    - [x] 语音指令：点击/右键/双击/暂停(Stop)/开始/校准/开关悬停点击
    - [x] 语音听写：把识别文本注入到当前输入焦点 (MVP: clipboard + Cmd+V)
    - [x] 可选大模型增强：口语纠错/加标点 (OpenAI-compatible endpoint, behind toggle)
    - [x] Push-to-talk 热键：`Control + Option + V` (按住说，松开执行)
    - [x] 常驻监听：默认关闭；开启后需用唤醒词 `Aether ...` 才会触发动作/听写
- [x] **首次使用引导 (Onboarding)**
    - [x] 权限自检：Accessibility/Input Monitoring、Microphone、Speech Recognition
    - [x] 一键跳转：打开系统设置对应隐私面板
- [x] **低成本回退 (Safety)**
    - [x] 撤销听写：语音 `撤销/undo` -> `Cmd+Z` (仅在近期注入后生效)

## **6. 集成收口 (MVP Closure) [80%]**
- [x] **事件输出抽象 (Output Abstraction)**
    - [x] 定义输出层，并保留 `CoreGraphics` 作为 fallback
    - [x] HeadMotion / Speech 注入统一走输出层（为 DriverKit 输出做准备）
- [x] **DriverKit -> 代码闭环**
    - [x] App 侧实现 `DriverClient`（连接/发消息/重连/错误可观测）
    - [x] Driver 侧实现 `IOUserClient` + 外部方法：`PostHIDEvent(dx,dy,buttons)`
- [ ] **DriverKit -> 体验闭环（需要安装验证）**
    - [ ] 最小闭环：AirPods 指针移动 + 左键点击经由虚拟 HID 输出（不是 CGEvent 模拟）

---

**验证标准 (Definition of Done):**
1. [x] **身份识别**：App 签名在重新编译后不丢失“辅助功能”权限。
2. [x] **精准追踪**：佩戴 AirPods 转头，光标可以精准覆盖屏幕元素。
3. [x] **全能点击**：支持 AirPods 物理按捏、悬停点击两种模式。
4. [x] **一键掌控**：`Option + S` 随时切断/恢复控制。
