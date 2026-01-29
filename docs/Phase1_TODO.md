# **Project "Aether" Phase 1 实施清单 (TODO)**

**里程碑目标**：感知觉醒 (The Awakening) - 建立 macOS 虚拟 HID 通路与 AirPods 基础姿态控制。

## **1. 工程脚手架搭建 (Foundation)**
- [ ] **创建 Xcode Workspace**
    - [ ] `Aether.xcworkspace`
    - [ ] 主 App Target: `AetherCore` (macOS App, SwiftUI)
    - [ ] 辅助 Target: `AetherDriver` (DriverKit Extension)
- [ ] **配置 Entitlements & Info.plist**
    - [ ] 申请/配置 `com.apple.developer.driverkit` 权限
    - [ ] 配置 `com.apple.developer.driverkit.family.hid.virtual.device`
    - [ ] 配置 System Extension 权限 (`system-extension` entitlement)
    - [ ] 配置 `NSMotionUsageDescription` (AirPods 数据读取权限)

## **2. 虚拟 HID 驱动开发 (DriverKit)**
> 核心任务：欺骗 macOS，让它以为有一个物理鼠标连接了。
- [ ] **驱动生命周期管理**
    - [ ] 在主 App 中实现 `OSSystemExtensionRequest` 激活逻辑
    - [ ] 处理用户授权回调 (System Settings > Privacy & Security)
- [ ] **HID 描述符构建 (Report Descriptor)**
    - [ ] 定义相对坐标鼠标描述符 (Generic Desktop / Mouse)
    - [ ] 定义绝对坐标触控板描述符 (Digitizer) [可选]
- [ ] **数据管道通信**
    - [ ] 实现 `IOUserClient`，建立 App 与 Driver 的 IPC 通信通道
    - [ ] 定义共享内存结构体 `AetherHIDEvent` (包含 dx, dy, buttons)

## **3. AirPods 姿态追踪 (Head Pointer)**
> 核心任务：读取头部转动数据。
- [ ] **CMHeadphoneMotionManager 集成**
    - [ ] 初始化 Manager 并检查 `deviceMotionAvailable`
    - [ ] `startDeviceMotionUpdates` 开启高频回调 (60Hz+)
- [ ] **姿态解算**
    - [ ] 读取 `motion.attitude` (Pitch, Yaw, Roll)
    - [ ] **映射算法**：将 Yaw (左右摇头) 映射为 X 轴位移，Pitch (抬头低头) 映射为 Y 轴位移
    - [ ] **防抖与平滑**：实现卡尔曼滤波或简单的低通滤波，消除头部微颤
- [ ] **中心校准 (Reset Origin)**
    - [ ] 设定快捷键或动作（如“保持静止2秒”）重置光标中心点

## **4. 交互胶水层 (Integration)**
- [ ] **数据流桥接**
    - [ ] 将 AirPods 解算后的 (dx, dy) 通过 IPC 发送给 DriverKit
    - [ ] DriverKit 构造 `IOHIDElementValue` 并提交 `dispatchReport`
- [ ] **状态栏菜单 (Menu Bar Extra)**
    - [ ] 显示连接状态图标
    - [ ] 增加“启用/暂停”开关
    - [ ] 增加“灵敏度”调节滑块

## **5. 本地网络发现 (Local Net)**
> 为 Phase 2 的多设备互联做准备。
- [ ] **Multipeer Connectivity 初始化**
    - [ ] 定义 Service Type (`_aether-link._tcp`)
    - [ ] 实现 `MCNearbyServiceAdvertiser` (Mac 端广播)
    - [ ] 实现基础的心跳包 (Heartbeat) 发送

---

**验证标准 (Definition of Done):**
1.  App 启动后，系统设置中出现 Aether 扩展请求。
2.  佩戴 AirPods 转头，Mac 屏幕光标随之移动。
3.  状态栏能显示当前 AirPods 连接状态。
