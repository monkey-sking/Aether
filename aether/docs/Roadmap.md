# **Project "Aether" 实施路线图 (Roadmap)**

> **基于文档**：
> 1. `Project 'Aether' 全感知协同交互系统需求文档 (PRD).md` (技术基石)
> 2. `Project 'Aether' 用户体验白皮书 (User Concept).md` (体验目标)

本路线图旨在将 **PRD v1.2** 中的技术框架（DriverKit, UWB, gPTP）转化为 **用户体验白皮书** 中描述的“无感生活流”场景。我们将开发进程分为四个阶段，每个阶段对应一个核心体验里程碑。

---

## **Phase 1: 感知觉醒 (The Awakening)**
**目标**：打通 macOS 与基础外设的底层连接，实现“开盖即连”的基础体验。

*   **体验对标 (User Concept)**：
    *   *“机器仿佛和你一起‘醒来’了”* -> 基础设备发现与握手。
*   **技术实施 (PRD v1.2)**：
    *   **DriverKit 虚拟 HID 驱动**：开发 `com.apple.developer.driverkit.family.hid.virtual.device`，构建系统的“虚拟神经中枢”。
    *   **AirPods 头部指向 (基础)**：利用 `CMHeadphoneMotionManager` 实现简单的头部动作映射。
    *   **本地网络发现**：建立基于 Bonjour/Multipeer Connectivity 的设备心跳机制。
*   **交付物**：
    *   macOS 驱动程序 (Alpha)
    *   状态栏菜单：显示当前连接的 AirPods/iPhone。

---

## **Phase 2: 隐形输入 (The Invisible Input)**
**目标**：引入精细操作与距离感知，消除对物理鼠标/键盘的强依赖。

*   **体验对标 (User Concept)**：
    *   *“消失的鼠标”* -> 桌面敲击选中。
    *   *“心领神会的协作”* -> Pencil 旋转调节。
*   **技术实施 (PRD v1.2)**：
    *   **空间仲裁 (Nearby Interaction)**：集成 U1/U2 芯片数据，实现“距离最近设备接管光标”。
    *   **Pencil Pro 深度集成**：接入 `UIPencilInteraction`，实现 Squeeze（挤压）呼出菜单和 Barrel Roll（旋转）调节参数。
    *   **Watch 触觉反馈链路**：打通 Mac 到 Apple Watch 的 `CoreHaptics` 通道，为“桌面敲击”提供物理确认感。
*   **交付物**：
    *   “Aether-Touch” iPad 伴侣应用。
    *   支持 Pencil 旋转调音量的 Mac 演示 Demo。

---

## **Phase 3: 空间心流 (Seamless Flow)**
**目标**：引入视觉与听觉的空间维度，实现真正的“环境即计算”。

*   **体验对标 (User Concept)**：
    *   *“自然的关注”* -> 眼神控制光标。
    *   *“声音自动聚焦”* -> 声源定位。
*   **技术实施 (PRD v1.2)**：
    *   **gPTP 时间同步**：部署 IEEE 802.1AS 协议，确保 Vision Pro 手势与 Mac 响应在微秒级对齐。
    *   **环境声源定位 (SSL)**：利用 HomePod/Studio Display 麦克风阵列，计算用户方位 (TDOA)，实现“转头即切换音频焦点”。
    *   **Vision Pro 骨架流**：接收 26 点手部骨架数据，实现空中手势直接操控 Mac 窗口。
*   **交付物**：
    *   全屋音频跟随系统。
    *   Vision Pro "Air-Mouse" 插件。

---

## **Phase 4: 数字圣所 (Digital Sanctuary)**
**目标**：融合物理形态感知，完善隐私与安全机制。

*   **体验对标 (User Concept)**：
    *   *“极致隐私”* -> 合盖即断连。
    *   *“开盖即创作”* -> 角度触发模式。
*   **技术实施 (补充)**：
    *   **MacBook Lid Sensor (新增)**：读取 `0x0020` HID Page，精细识别屏幕开合角度（<30° / >110°）。
    *   **硬件隐私锁**：联动 Lid Angle 数据，物理级切断麦克风/摄像头权限。
    *   **无感鉴权**：结合 Watch 距离与 FaceID，实现“坐下即解锁，离座即锁屏”。
*   **交付物**：
    *   Aether 1.0 正式版。
    *   隐私安全白皮书。

---

## **总结 Roadmap Summary**

| 阶段 | 核心主题 | 关键技术 (PRD) | 核心体验 (Concept) |
| :--- | :--- | :--- | :--- |
| **P1** | **基础连接** | DriverKit, Local Net | 设备发现 |
| **P2** | **精准交互** | Pencil, UWB, Haptics | 旋转旋钮, 桌面敲击 |
| **P3** | **空间感知** | gPTP, Vision Pro, SSL | 眼神控制, 声随人动 |
| **P4** | **物理融合** | Lid Sensor, Privacy | 开合盖模式, 极致隐私 |
