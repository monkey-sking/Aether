# **Project "Aether" 全感知协同交互系统需求文档 (PRD) v1.2**

> 文档状态：`Historical`
> 说明：这是 Aether 的早期多设备愿景与研究型 PRD，保留背景价值，但不代表当前已实现范围。
> 当前现状请先看：`README.md`、`user_guide.md`、`PENDING_ACCEPTANCE.md`、`VOICE_LEXICON_RULES.md`。

## **1\. 项目愿景 (Vision)**

构建一个以 macOS 为核心的分布式感知计算网络。通过聚合 Apple 全家桶（iPhone, iPad, Watch, AirPods, Vision Pro, HomePod, Siri Remote）的底层传感器数据，利用端侧 AI 意图识别和微秒级同步协议，消除物理输入设备的界限，实现全场景无感交互。

## **2\. 核心硬件矩阵与感知能力**

系统应支持以下设备的传感器数据接入与功能映射：

| 核心设备 | 关键传感器/技术 | 交互功能映射 | 技术框架 |
| :---- | :---- | :---- | :---- |
| **Vision Pro** | 12x 摄像头、LiDAR、手部骨架追踪 | 毫米级 3D 空间手势、虚拟物件抓取 | ARKit / avp\_stream 1 |
| **iPad Pro \+ Pencil Pro** | 压力感应、挤压 (Squeeze)、桶形旋转 (Barrel Roll) | 高精度参数调节、径向菜单、模拟旋钮 | UIPencilInteraction |
| **Apple Watch** | IMU、抬腕检测、数码表冠、Taptic Engine | 虚拟点击确认、数值精微调节、触觉反馈回传 3 | CoreMotion / CoreHaptics 6 |
| **AirPods Pro/Max** | 6DoF IMU (加速度计/陀螺仪) | 头部指向光标、空间声场锚定 | CMHeadphoneMotionManager |
| **iPhone Pro** | LiDAR、TrueDepth、U1/U2 芯片 | 桌面虚拟键盘映射、设备间距离仲裁 8 | ARKit / NearbyInteraction |
| **HomePod** | 麦克风阵列、声源定位 (SSL) | 用户方位感知、免唤醒意图捕获 11 | SiriKit Cloud Media |
| **Siri Remote** | 加速度计、陀螺仪、触摸板 | 简易体感控制、媒体播放手势 | GameController |

## **3\. "Aether-Link" 通信与同步协议**

### **3.1 确定性时间同步 (gPTP)**

为了确保多个传感器（如 Vision Pro 的手部数据与 iPad 的触控数据）能够完美融合，系统必须建立统一的时间基准。

* **需求**：在本地网络启用 **gPTP (IEEE 802.1AS)** 协议 14。  
* **指标**：跨设备传感器时间戳偏差需控制在 ![][image1] 以内 17。  
* **计算公式**：通过四次握手计算时钟偏移 14：  
  ![][image2]

### **3.2 交互仲裁逻辑 (Nearby Interaction)**

当用户同时拥有多个控制器（如手拿 Pencil Pro 同时佩戴 Watch）时，系统需自动判断哪一个是“当前活跃意图源”。

* **仲裁准则**：  
  1. **距离优先**：利用 U1/U2 芯片测距，距离屏幕最近且面向屏幕的设备获胜 。  
  2. **显式操作优先**：检测到 Pencil Pro 的 Squeeze 或 Watch 的捏合动作时，自动将焦点移至该设备 。  
  3. **视线辅助**：若 Vision Pro 在线，以眼动追踪焦点作为最高权重的仲裁依据 20。

## **4\. 关键功能模块**

### **4.1 "Aether-Touch" (iPad \+ Pencil 专项)**

* **模拟滚轮 (Barrel Roll)**：将 Apple Pencil Pro 的轴向旋转映射为 macOS 的系统滚轮或音量旋钮 。  
* **压力反馈**：根据 Pencil 笔尖压力控制 macOS 窗口的缩放比例或滚动速度 22。  
* **Squeeze 快捷指令**：笔身挤压时，在 Mac 屏幕光标处弹出径向工具栏（Radial Menu） 。

### **4.2 "Aether-Vision" (Vision Pro 专项)**

* **骨架流传输**：将 26 个手部关节数据实时流式传输至 Mac 24。  
* **虚拟输入平面**：在 Mac 前方空间划定虚拟操作区，手部进入该区域即触发光标接管 。

### **4.3 优雅降级与故障接管 (Graceful Degradation)**

当某一关键感官设备断开时，系统应自动执行以下降级路径 ：

| 故障设备 | 受影响交互 | 接管路径 (Fallback) | 用户体感 |
| :---- | :---- | :---- | :---- |
| **AirPods** | 头部光标指向 | **Mac 摄像头 (Head Pointer)** | 需要保持在视野内 |
| **Apple Watch** | 虚拟点击确认 | **眼神停留 (Dwell) 或 语音确认** | 节奏略微变慢 |
| **iPhone LiDAR** | 物理桌面键盘 | **iPad 虚拟触控板 或 视觉 2D 键盘** | 失去触觉参考 |
| **Pencil Pro** | 精细数值调节 | **Watch 数码表冠 或 语音参数调整** | 精度降低 |

### **4.4 "Aether-Voice" (AirPods 语音专项)**

在不依赖额外外设的前提下，提供语音指令与语音听写能力，用于补齐“点击之外的输入”，并作为无障碍与低负担交互的核心入口。

* **语音指令 (Command)**：支持点击/右键/双击/滚动/暂停控制/开始控制/校准/开关 Dwell Click 等控制语义。
* **语音听写 (Dictation)**：将识别结果注入到当前输入焦点（最小可用版本可采用“剪贴板 + 粘贴”注入路径）。
* **可选大模型增强 (LLM, Optional)**：用于指令理解、口语纠错与自动标点等（支持 OpenAI-compatible endpoint，自定义 provider）。

## **5\. 系统级特性**

### **5.1 "Aether-Ghost" 虚拟 HID 与引导加载**

* **受限权限申请**：驱动需具备 com.apple.developer.driverkit.family.hid.virtual.device 。  
* **Pre-login 支持**：在 Apple Silicon Mac 上，通过 Auxiliary Kernel Collection 将驱动配置为引导级，确保在 FileVault 登录界面即可使用 AirPods 旋转选择用户图标 。

### **5.2 隐私与合规**

* **本地孤岛**：所有传感器数据流严禁出局域网 。  
* **透明审计**：macOS 菜单栏实时显示各传感器的置信度（Confidence Marker）和活动状态 。

### **5.3 首次使用引导与可控性 (Onboarding & Control)**

为降低无障碍用户的配置成本，系统需要提供“可解释、可回退”的首次使用引导与控制面板。

* **权限自检**：启动时检测并引导开启必要权限（Accessibility/Input Monitoring、Microphone、Speech Recognition）。
* **强可控开关**：提供状态栏/浮层中的一键 Start/Stop，以及全局 Emergency Stop 热键。
* **误触发防护**：常驻语音监听默认关闭；开启时必须通过唤醒词触发动作/听写。
* **低成本回退**：提供撤销（Undo）与“暂停控制”语音指令，避免误操作代价过高。

## **6\. 落地分阶段里程碑**

1. **Phase 1 (MVP)**：完成 DriverKit 虚拟驱动与 AirPods 基础指向，加入 Siri Remote 媒体键映射。  
2. **Phase 2 (协同升级)**：引入 Nearby Interaction UWB 仲裁，实现 iPhone/Watch 靠近 Mac 时自动接管光标。  
3. **Phase 3 (精细化操作)**：接入 iPad \+ Pencil Pro 的 Squeeze 与 Barrel Roll API，实现 3D 径向菜单。  
4. **Phase 4 (空间感知)**：集成 Vision Pro 骨架流与 HomePod SSL 声源定位，实现完全的环境智能交互。

---

**下一步建议**：

鉴于 iPad 和 Pencil Pro 的 API (UIPencilInteraction) 相对成熟且数据带宽要求较低，可以将其作为 Phase 2 的重点，优先解决“iPad 作为 Mac 全局参数调节旋钮”的需求。

#### **引用的著作**

1. Improbable-AI/VisionProTeleop: VisionOS App \+ Python ... \- GitHub, 访问时间为 一月 29, 2026， [https://github.com/Improbable-AI/VisionProTeleop](https://github.com/Improbable-AI/VisionProTeleop)  
2. Apple researching HomePod-style Spatial Audio for Apple AR \- AppleInsider, 访问时间为 一月 29, 2026， [https://appleinsider.com/articles/21/04/13/apple-researching-homepod-style-spatial-audio-for-apple-ar](https://appleinsider.com/articles/21/04/13/apple-researching-homepod-style-spatial-audio-for-apple-ar)  
3. I can track head position using AirPods. : r/iOSProgramming \- Reddit, 访问时间为 一月 29, 2026， [https://www.reddit.com/r/iOSProgramming/comments/1g6a17i/i\_can\_track\_head\_position\_using\_airpods/](https://www.reddit.com/r/iOSProgramming/comments/1g6a17i/i_can_track_head_position_using_airpods/)  
4. Haptics Explorer \- App Store \- Apple, 访问时间为 一月 29, 2026， [https://apps.apple.com/us/app/haptics-explorer/id1660403082](https://apps.apple.com/us/app/haptics-explorer/id1660403082)  
5. Handling Common State Transitions | Apple Developer Documentation, 访问时间为 一月 29, 2026， [https://developer.apple.com/documentation/watchkit/handling-common-state-transitions](https://developer.apple.com/documentation/watchkit/handling-common-state-transitions)  
6. Introducing Core Haptics \- WWDC19 \- Videos \- Apple Developer, 访问时间为 一月 29, 2026， [https://developer.apple.com/videos/play/wwdc2019/520/](https://developer.apple.com/videos/play/wwdc2019/520/)  
7. Introducing Core Haptics \- WWDC19 \- Videos \- Apple Developer, 访问时间为 一月 29, 2026， [https://developer.apple.com/la/videos/play/wwdc2019/520/](https://developer.apple.com/la/videos/play/wwdc2019/520/)  
8. ARKit 6 \- Augmented Reality \- Apple Developer, 访问时间为 一月 29, 2026， [https://developer.apple.com/augmented-reality/arkit/](https://developer.apple.com/augmented-reality/arkit/)  
9. Visualizing and interacting with a reconstructed scene | Apple Developer Documentation, 访问时间为 一月 29, 2026， [https://developer.apple.com/documentation/ARKit/visualizing-and-interacting-with-a-reconstructed-scene](https://developer.apple.com/documentation/ARKit/visualizing-and-interacting-with-a-reconstructed-scene)  
10. Extending advanced direction finding and ranging | Apple Developer Documentation, 访问时间为 一月 29, 2026， [https://developer.apple.com/documentation/nearbyinteraction/extending-advanced-direction-finding-and-ranging](https://developer.apple.com/documentation/nearbyinteraction/extending-advanced-direction-finding-and-ranging)  
11. Audio \- HomeKit Helper, 访问时间为 一月 29, 2026， [https://www.homekithelper.net/devices/audio](https://www.homekithelper.net/devices/audio)  
12. Guide to Implementing a Sound Source Localization and Tracking System Based on Respeaker 4-Mic Array \- Oreate AI Blog, 访问时间为 一月 29, 2026， [https://www.oreateai.com/blog/guide-to-implementing-a-sound-source-localization-and-tracking-system-based-on-respeaker-4mic-array/d74acfcfa10e6b04afed0039ef48495e](https://www.oreateai.com/blog/guide-to-implementing-a-sound-source-localization-and-tracking-system-based-on-respeaker-4mic-array/d74acfcfa10e6b04afed0039ef48495e)  
13. Precision Time Protocol (PTP) in Data Acquisition and Tes \- HBM, 访问时间为 一月 29, 2026， [https://www.hbm.com/5143/precision-time-protocol/?country=none](https://www.hbm.com/5143/precision-time-protocol/?country=none)  
14. Network Timing Technology: NTP vs. PTP \- Masterclock, 访问时间为 一月 29, 2026， [https://www.masterclock.com/network-timing-technology-ntp-vs-ptp.html](https://www.masterclock.com/network-timing-technology-ntp-vs-ptp.html)  
15. Sarcouncil Journal of Engineering and Computer Sciences Time Synchronization of Multi-Sensor Systems using Generalized Precision, 访问时间为 一月 29, 2026， [https://sarcouncil.com/download-article/SJECS-213-\_2025-647-654.pdf](https://sarcouncil.com/download-article/SJECS-213-_2025-647-654.pdf)  
16. User Experience with macOS Login Screens \- Kandji Support, 访问时间为 一月 29, 2026， [https://support.kandji.io/kb/user-experience-with-macos-login-screens](https://support.kandji.io/kb/user-experience-with-macos-login-screens)  
17. Enabling Precision Time Protocol (PTP) \- Fixposition Documentation, 访问时间为 一月 29, 2026， [https://docs.fixposition.com/fd/enabling-precision-time-protocol-ptp](https://docs.fixposition.com/fd/enabling-precision-time-protocol-ptp)  
18. Overview of IEEE 802.1AS Generalized Precision Time Protocol (gPTP), 访问时间为 一月 29, 2026， [https://eci.intel.com/docs/3.3/development/performance/tsnrefsw/tsn-overview.html](https://eci.intel.com/docs/3.3/development/performance/tsnrefsw/tsn-overview.html)  
19. DriverKit | Apple Developer Documentation, 访问时间为 一月 29, 2026， [https://developer.apple.com/documentation/driverkit](https://developer.apple.com/documentation/driverkit)  
20. Control app tracking permissions on Apple Vision Pro, 访问时间为 一月 29, 2026， [https://support.apple.com/guide/apple-vision-pro/control-app-tracking-permissions-tan4aa01341/visionos](https://support.apple.com/guide/apple-vision-pro/control-app-tracking-permissions-tan4aa01341/visionos)  
21. Legal \- Eyes, Hands & Privacy \- Apple, 访问时间为 一月 29, 2026， [https://www.apple.com/legal/privacy/data/en/eyes-hands/](https://www.apple.com/legal/privacy/data/en/eyes-hands/)  
22. Handling squeezes from Apple Pencil | Apple Developer ..., 访问时间为 一月 29, 2026， [https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil](https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil)  
23. Apple Pencil Pro "Squeeze" feature for customizable radial menu \- Shapr3D Community, 访问时间为 一月 29, 2026， [https://discourse.shapr3d.com/t/apple-pencil-pro-squeeze-feature-for-customizable-radial-menu/33183](https://discourse.shapr3d.com/t/apple-pencil-pro-squeeze-feature-for-customizable-radial-menu/33183)  
24. Tracking and visualizing hand movement | Apple Developer Documentation, 访问时间为 一月 29, 2026， [https://developer.apple.com/documentation/visionOS/tracking-and-visualizing-hand-movement](https://developer.apple.com/documentation/visionOS/tracking-and-visualizing-hand-movement)

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAB4AAAAYCAYAAADtaU2/AAABNklEQVR4Xu2UMUtCYRSGD5EEQrhIa//AwcmpOQlTaMmfUKkYCP6Fhmh3cHZocgl/QUs0VC7SFLVEW4vRUJ3Ddy73fK9fSoMXpPvAy+U87wdHP64SpfxHOpwjlMtiwPnkfGuO/ToZ0sXIOqeHkimhMDQ4fU4BC8uixdfkzlj2Ak7IkvObOg85O3HtIwdPUBqkvwX3oB754JyZWc6UzewhZROlQfpKwI3ACdGv5IKTg24GOdhCqdQo/M3Eha7wkOLlkhu/9pEDbZTKHc0urgccUqT4f+JXpDxFqUSf3PJo3MR4cVdm3lYXJE+uPMdCwcX7Ok91ftfnlro1nYUnCry0l5w3zgvnWZ+v5K4n4oDckrE+JbucDTPbRV3jvzhV0/2Je5pzVctEluLvNxGiq02UDMUvUMpq8QOZc1e7r2gBJQAAAABJRU5ErkJggg==>

[image2]: <data:image/png;base64,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>
