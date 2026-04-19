# iPhone Remote — Design

> **PAUSED**：见 [README.md](README.md) 顶部说明。本文档是初稿，等 ia-refresh 落地后会按新 IA 修订 §5（Mac 端改动清单）中关于 `SettingsModules.swift` 新增页的部分。

## 1. 背景

Aether for Mac 目前用两个输入源：

- **头追**：`HeadMotionManager` + `CMHeadphoneMotionManager`，只认 AirPods 类 MFi 耳机
- **麦克风**：`SpeechManager` + `AVAudioEngine`，走 Mac 本机输入设备

新增 iPhone 配套 App 的目的是在上述两者之外提供：

- 手持 iPhone 做**激光笔式**指针（不是相对增量）
- 利用 iPhone 的 STT 和第三方 IME，提供**文本级**语音输入

## 2. 为什么不用的几种方案

| 方案 | 否决原因 |
|---|---|
| 纯陀螺仪相对增量 | 用户要求激光笔式，不是增量鼠标 |
| 屏幕 image anchor | 屏上要常驻可见标记，体验侵入性 |
| LiDAR / 深度相机 | 只有 Pro 机型；LiDAR 看玻璃屏反光差 |
| UWB | Mac 不作为 UWB anchor 暴露给第三方 |
| Mac 摄像头反向追 iPhone | Mac webcam FOV 窄、单目深度不可靠 |
| Continuity Camera 做麦 | 用户在远离 Mac 时不适用；**不如 iOS 端本地 STT** |
| 音频流到 Mac 再识别 | 带宽、延迟、编解码都是负担；iOS 端 STT 更快更省 |

## 3. 架构总览

```
┌─────────────────────── iPhone (AetherRemote.app) ──────────────────────┐
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────────┐  │
│  │  ARKit 6DOF  │  │  PTT button  │  │  Text input (UITextView)     │  │
│  │  CMMotion    │  │              │  │  SFSpeechRecognizer / IME    │  │
│  └──────┬───────┘  └──────┬───────┘  └───────────────┬──────────────┘  │
│         │                 │                           │                 │
│         └────────┬────────┴───────────────────────────┘                 │
│                  │                                                       │
│           ┌──────▼──────┐                                                │
│           │ RemoteClient│ MCSession (client)                             │
│           └──────┬──────┘                                                │
└──────────────────┼───────────────────────────────────────────────────────┘
                   │ MPC over BT + Wi-Fi
┌──────────────────┼───────────────────────────────────────────────────────┐
│                  ▼                                                       │
│           ┌─────────────┐                                                │
│           │RemoteService│ MCSession (advertiser)                         │
│           └──────┬──────┘                                                │
│                  │                                                       │
│    ┌─────────────┼────────────────┬──────────────────┐                  │
│    ▼             ▼                ▼                  ▼                  │
│ ┌────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│ │Calib.  │ │iPhoneLaser   │ │Text ingress  │ │PTT ingress   │           │
│ │Coord.  │ │PointerSource │ │→ Dictation   │ │→ Notification│           │
│ └────┬───┘ └──────┬───────┘ │  Handler     │ │  (现有)      │           │
│      │            │         └──────────────┘ └──────────────┘           │
│      ▼            ▼                                                     │
│ ┌──────────────────────┐  ┌──────────────────────────────────────────┐  │
│ │ Pointer Coordinator  │◄─│ AirPodsHeadPointerSource (从现有抽出)     │  │
│ └──────────┬───────────┘  └──────────────────────────────────────────┘  │
│            │                                                             │
│            ▼                                                             │
│  CGEvent / cursor                                        Mac (AetherCore)│
└─────────────────────────────────────────────────────────────────────────┘
```

## 4. 仓库结构

```
App/
├── Apps/
│   ├── AetherCore/                  （现有 Mac app）
│   └── AetherRemote/                （新增 iOS app）
│       ├── AetherRemote.xcodeproj
│       └── Sources/
│           ├── AetherRemoteApp.swift
│           ├── Remote/
│           │   ├── RemoteClient.swift
│           │   └── PairingStore.swift
│           ├── Motion/
│           │   └── MotionStreamer.swift
│           ├── Input/
│           │   └── TextStreamer.swift
│           ├── Views/
│           │   ├── MainView.swift
│           │   ├── PairingView.swift
│           │   └── CalibrationAssistView.swift
│           └── Resources/
│               ├── Info.plist
│               └── AetherRemote.entitlements
└── Shared/
    ├── AetherShared.h               （现有）
    └── RemoteProtocol/              （新增 Swift package）
        ├── Package.swift
        └── Sources/RemoteProtocol/
            ├── Packet.swift
            ├── Payloads.swift
            └── ProtocolVersion.swift
```

Mac target (`AetherCore.xcodeproj`) 和 iOS target (`AetherRemote.xcodeproj`) 都通过 Swift Package Manager 本地路径引用 `Shared/RemoteProtocol/`。

## 5. Mac 端改动清单

### 5.1 新增（9 个文件）

| 文件 | 职责 |
|---|---|
| `Pointer/PointerSource.swift` | 协议抽象：输入源产出 `PointerFrame` / `ButtonEvent` |
| `Pointer/PointerCoordinator.swift` | 持有 active source，把 `PointerFrame` 转 `CGEvent` |
| `Pointer/AirPodsHeadPointerSource.swift` | 从 `HeadMotionManager` 抽出的光标映射逻辑 |
| `Pointer/ScreenCalibration.swift` | 四角最小二乘、射线-矩形求交、持久化 |
| `Pointer/CalibrationCoordinator.swift` | 校准状态机：首次四角、每次重锚定 |
| `Pointer/CalibrationOverlayWindow.swift` | 全屏独占窗（`level = .screenSaver + 1`） |
| `Remote/RemoteService.swift` | `MCNearbyServiceAdvertiser` + `MCSession`，配对、心跳、keychain |
| `Remote/RemoteSessionState.swift` | 连接/配对/版本协商状态 |
| `Remote/iPhoneLaserPointerSource.swift` | 消费 motion frame → `ScreenCalibration` → `PointerFrame` |

### 5.2 修改（5 个文件）

| 文件 | 改动 |
|---|---|
| `HeadMotionManager.swift` | 抽出"姿态 → 光标"部分到 `AirPodsHeadPointerSource`；本类专注数据采集 + 按键 + 手势 |
| `SpeechManager.swift` | 新增 "text ingress" 入口：从 `RemoteService` 收到文本，直接灌给 `DictationHandler` / `VoiceCommandRouter`，不经 `RecognitionSession` |
| `AetherApp.swift` | `AppState` 注册 `PointerCoordinator` 和 `RemoteService` |
| `SettingsModules.swift` | 新增 "iPhone Remote" 页：配对状态、重新校准、source 切换、灵敏度 |
| `Info.plist` | 加 `NSLocalNetworkUsageDescription`、`NSBonjourServices = ["_aether-remote._tcp"]` |

### 5.3 不改

- `VoiceCommandRouter.swift`——本来就吃文本，iPhone 路径无感
- `DictationHandler.swift`——`onPartial` / `onFinal` 接口和本地 STT 完全对称
- `TextInjector.swift`、HUD 全家——下游无感
- Headset 按键、手势识别、手势历史——和 iPhone 源无关

## 6. iOS 端（新 target）

### 6.1 Xcode 配置

- Bundle ID：`com.aether.remote`（待定，对齐 Mac 端 `com.aether.core`）
- 最低系统：iOS 16（ARKit world tracking 稳定，`UITextView` 现代 API）
- 依赖：`Shared/RemoteProtocol`（SPM 本地路径）

### 6.2 Info.plist usage descriptions

```
NSCameraUsageDescription
   "Aether Remote 需要相机用 ARKit 计算手机相对 Mac 屏幕的位置，以实现激光笔级精度的指针。"
NSMotionUsageDescription
   "Aether Remote 使用运动传感器实时追踪手机朝向。"
NSLocalNetworkUsageDescription
   "Aether Remote 需要本地网络发现并连接到你的 Mac。"
NSBluetoothAlwaysUsageDescription
   "Aether Remote 使用蓝牙与你的 Mac 做低延迟配对通讯。"
NSSpeechRecognitionUsageDescription
   "Aether Remote 在设备本地把你的语音转成文本，发送给 Mac。"
```

### 6.3 组件职责

**`AetherRemoteApp.swift`** — `@main`。启动时 `UIApplication.shared.isIdleTimerDisabled = true` 避免锁屏。

**`RemoteClient.swift`** — `MCNearbyServiceBrowser` + `MCSession`。暴露：
- `connect(to peerID:)`, `disconnect()`
- `send(_ packet: Packet, reliable: Bool)`
- `@Published var status: Status`（`.idle / .browsing / .connecting / .connected / .paired`）
- incoming packet 的 `PassthroughSubject<Packet, Never>`

**`PairingStore.swift`** — Keychain 存 `peerID` + `sharedSecret`。

**`MotionStreamer.swift`** — `ARSession` + `CMMotionManager` 双路径：
- 优先 ARKit (`ARWorldTrackingConfiguration`, `worldAlignment = .gravity`)
- ARKit 跟踪丢失时回落到 `CMMotionManager` 纯陀螺（加 packet 里 `trackingState = .limited`）
- `ARSessionDelegate.session(_:didUpdate:)` 每帧产 `MotionFrame`，丢给 `RemoteClient.send(_:reliable: false)`

**`TextStreamer.swift`** — 
- 持一个 `UITextView`（在 `MainView` 里展示）
- `textViewDidChange` → 计算 diff → 发 `textPartial` 包
- "提交" 按钮 → 发 `textFinal` 包 → 清空
- iOS 端不主动调 `SFSpeechRecognizer`；让用户按键盘上的麦按钮（系统 STT 或 IME 自带 STT）

**`MainView.swift`** — 单页：
- 顶部：连接状态 + Mac 名称
- 中央：大 PTT 圆按钮（按下触发 `buttonEvent(.pttDown)`，松开 `.pttUp`）
- 底部：`UITextView` + "提交" 按钮（键盘模式）
- 右上：跟踪质量指示灯（绿/黄/红）
- 右下：齿轮 → 灵敏度、断开连接

**`PairingView.swift`** — 首次：扫描 / 列表 Mac peer → 选中 → 显示 Mac 上的 6 位码输入框 → 发 `hello(pairingCode:)` → 等 `helloAck`。

**`CalibrationAssistView.swift`** — 校准期显示："请指向 Mac 屏上的亮点，按 PTT 确认"，附 ARKit 跟踪质量实时条。

## 7. Wire Protocol

### 7.1 协议版本

`ProtocolVersion = 1`。breaking change 时 `+1`。Mac 端 `RemoteService` 在 `Hello` 时对比版本，不匹配返回 `.error(.incompatibleVersion)` 并拒连。

### 7.2 Packet 定义

```swift
// Shared/RemoteProtocol/Sources/RemoteProtocol/Packet.swift

public enum Packet: Codable, Sendable {
    case hello(Hello)
    case helloAck(HelloAck)
    case motion(MotionFrame)
    case button(ButtonEvent)
    case textPartial(TextPayload)
    case textFinal(TextPayload)
    case calibrationCue(CalibrationCue)
    case calibrationSample(CalibrationSample)
    case heartbeat(Heartbeat)
    case error(ErrorPayload)
}

public struct Hello: Codable, Sendable {
    public let protocolVersion: UInt16
    public let appVersion: String
    public let deviceName: String
    public let pairingCode: String?         // 只在首次配对时带
    public let capabilities: Set<Capability>
}

public enum Capability: String, Codable, Sendable {
    case arWorldTracking
    case gyroFallback
    case textInput
    case pttButton
}

public struct HelloAck: Codable, Sendable {
    public let protocolVersion: UInt16
    public let macLicenseStatus: LicenseStatus   // .active / .trial / .expired
    public let displays: [DisplayInfo]           // 当前已知的屏信息
}

public struct DisplayInfo: Codable, Sendable {
    public let displayID: UInt32                 // CGDirectDisplayID
    public let pixelSize: SIMD2<Float>
    public let calibrated: Bool
}

public struct MotionFrame: Codable, Sendable {   // ~60 bytes，60 Hz，unreliable
    public let timestamp: TimeInterval
    public let position: SIMD3<Float>            // ARKit world-space meters
    public let orientation: simd_quatf           // ARKit world-space
    public let trackingState: UInt8              // 0 notAvailable / 1 limited / 2 normal
}

public struct ButtonEvent: Codable, Sendable {
    public enum Kind: UInt8, Codable, Sendable { case pttDown, pttUp, tap, doubleTap }
    public let kind: Kind
    public let timestamp: TimeInterval
}

public struct TextPayload: Codable, Sendable {
    public let utteranceID: UUID                 // 一次输入的逻辑 ID
    public let text: String                      // partial 时是累积文本，不是 delta
    public let timestamp: TimeInterval
}

public struct CalibrationCue: Codable, Sendable {
    public let displayID: UInt32
    public enum Marker: UInt8, Codable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight, center
    }
    public let marker: Marker
    public let displayPixelSize: SIMD2<Float>
}

public struct CalibrationSample: Codable, Sendable {
    public let displayID: UInt32
    public let marker: CalibrationCue.Marker
    public let position: SIMD3<Float>
    public let orientation: simd_quatf
    public let timestamp: TimeInterval
}

public struct Heartbeat: Codable, Sendable {
    public let timestamp: TimeInterval
}

public struct ErrorPayload: Codable, Sendable {
    public enum Code: UInt8, Codable, Sendable {
        case incompatibleVersion
        case macNotActivated
        case pairingRejected
        case calibrationTimeout
        case internalError
    }
    public let code: Code
    public let message: String?
}
```

### 7.3 可靠性

| 类型 | 模式 | 频率 |
|---|---|---|
| `motion` | `.unreliable` | 60 Hz |
| `button` | `.reliable` | 事件驱动 |
| `textPartial` | `.reliable` | 用户打字/说话节奏 |
| `textFinal` | `.reliable` | 事件驱动 |
| `hello` / `helloAck` | `.reliable` | 握手 |
| `calibrationCue` / `calibrationSample` | `.reliable` | 校准期 |
| `heartbeat` | `.reliable` | 1 Hz |

MPC 自己按消息送达，不需要自己做 framing。

## 8. 校准流程

### 8.1 首次四角校准

```
State: idle → browsing → connected → paired → needsInitialCalibration
  ↓
Mac 对每个 NSScreen 开一个 CalibrationOverlayWindow:
  [Display 1 active]     → 其他屏显示 "等待" 遮罩
     → 四角点依次亮:
         topLeft → user PTT → Mac 记录 sample → 点移动到 topRight
         topRight → user PTT → ...
         bottomRight → user PTT → ...
         bottomLeft → user PTT → ...
     → ScreenCalibration 解算该屏矩形
  [Display 2 active]     → 同上
  ...
所有屏校准完 → overlay 一起消失 → 进入 active 状态
```

### 8.2 每次启动重锚定

```
iPhone App 启动 / 前台化 → 发 hello → Mac 发 helloAck
  ↓
Mac: 检测已有 displays[].calibrated == true
  ↓
在主屏中央弹一个 CalibrationOverlayWindow，只显示一个中心点
  ↓
user 指中心 + PTT → Mac 收 calibrationSample(marker: .center)
  ↓
ScreenCalibration 用一个 sample 做"刚体变换对齐"：
  - 历史屏矩形在旧 AR world 坐标
  - 本次 AR world 是新的
  - 用当前指向中心的位姿把历史坐标整体旋转+平移对齐过来
  ↓
overlay 消失，进入 active 状态
```

### 8.3 跟踪丢失

ARKit 跟踪状态掉到 `.notAvailable` 超过 3 秒：
- Mac 端光标停在最后位置
- HUD 提示 "请把手机朝向 Mac 方向"
- 恢复到 `.normal` 后自动继续，不强制重新校准

### 8.4 蒙屏独占实现要点

- `CalibrationOverlayWindow` 设 `level = .screenSaver + 1`
- `ignoresMouseEvents = false`，但窗体本身把所有点击吞掉（不转发给下层）
- `activationPolicy = .accessory`，不抢 Mac 焦点
- 每块屏一个独立 window，绑到对应 `NSScreen`
- ESC 键允许放弃校准并关闭 overlay（防止卡死）

## 9. 文本输入路径

### 9.1 iPhone 端

iOS App 不主动调 `SFSpeechRecognizer`。用户有三种输入方式：

1. **系统键盘 + 系统听写**：点键盘上的麦按钮（系统 `UIKeyboardType` 自带），文本自然流入 `UITextView`
2. **第三方 IME 的语音**：装了搜狗/百度/讯飞/微信输入法等，切到 IME 后用它们的麦按钮。我们啥也不做，IME 自己把音频发到它们的服务器或本地处理，把文本塞进 `UITextView`
3. **手动打字**：正常键盘输入

三种方式对我们都一样：`UITextViewDelegate.textViewDidChange` 触发 → 发 `textPartial` 包到 Mac。

### 9.2 Mac 端

`SpeechManager` 增加文本源入口：

```swift
// 伪代码
extension SpeechManager {
    func ingestRemoteText(_ payload: TextPayload, final: Bool) {
        if final {
            dictationHandler.onFinal(payload.text, utteranceID: payload.utteranceID)
        } else {
            dictationHandler.onPartial(payload.text, utteranceID: payload.utteranceID)
        }
    }
}
```

`utteranceID` 的作用：同一轮输入的 partial 和 final 关联起来，避免两轮输入混淆。

### 9.3 唤醒词不受影响

唤醒词仍走 `WakeWordDetector` + Mac 本机麦。iPhone 文本源和唤醒词路径解耦：用户在 iPhone 上打字 / 说话不会触发 Mac 的唤醒逻辑，反之亦然。

## 10. 配对流程

```
[首次]
Mac Settings → iPhone Remote → "开始配对"
  → Mac 生成 6 位码（显示大字）+ 启动 MCNearbyServiceAdvertiser
iPhone App → PairingView → 扫描周围 peer → 选中 Mac 名
  → 输入 6 位码 → 发 hello(pairingCode: "123456")
Mac 收到 hello：
  - 验证 pairingCode 一致
  - 生成 sharedSecret，存 Mac keychain
  - 回 helloAck（含 sharedSecret）
iPhone 存 peerID + sharedSecret 到 Keychain
→ 进入 paired 状态

[重连]
iPhone 启动 → MCNearbyServiceBrowser 发现已 paired 的 Mac
  → 直接 hello(pairingCode: nil)
Mac 用 peerID 查 keychain → 有记录 → 回 helloAck
→ paired
```

## 11. Mac 激活态集成

Mac 端 `RemoteService` 在 `helloAck` 时带上 `macLicenseStatus`：

- `.active` / `.trial` → iPhone 端显示"已连接"，正常使用
- `.expired` → iPhone 端显示"Mac 端试用到期，请在 Mac 上激活"，拒绝后续 packet

iOS App 本身**不做任何 license 校验**，不存任何付费状态，完全跟随 Mac 端判断。这样 App Store 审核方看到的是"一个纯粹的遥控器，什么都不锁"。

## 12. App Store 清单

- [ ] iOS target 独立 bundle ID，复用 Apple Developer team
- [ ] App Store Connect 条目创建，填写描述、截图、隐私标签
- [ ] Info.plist 五条 usage description 文案审过
- [ ] App Review Notes 明确写 "This app is a companion to Aether for Mac. It cannot function standalone. The reviewer can test it by downloading Aether for Mac beta from aether.app."
- [ ] 提供 reviewer 用的测试 Mac 端 build（或 TestFlight 外部链接）
- [ ] 隐私政策 URL（语音、运动、相机数据都不出设备的声明）

## 13. 开放问题

- **ARKit world map 持久化**：如果做成"重启 App 后环境不变就自动对齐"，能省掉中心点校准，但工程量和失败率需要单独评估。**当前决策：不做，每次都要中心点。** 可以放到 v2
- **跨 Wi-Fi 网段**：MPC 默认同网段。用户 Mac 在有线、iPhone 在 Wi-Fi 但同一路由器一般 OK。如果是公司网络隔离 VLAN 可能失败，需要用 Network framework + Bonjour 的自定义实现。**当前决策：不管，文档里说明"需同一 Wi-Fi"。**
- **多 iPhone 同时配对**：`RemoteService` 当前假设一次只接一个 peer。多个 iPhone 来连的语义不明。**当前决策：一次只允许一个连接，后连的挤掉前一个。**
- **用户在 iPhone 屏上打字 vs 语音，如何进入 Mac 的输入**：现在 Mac 的 `DictationHandler` 设计里，输入总是进入当前前台 App 的光标位置。iPhone 文本来时 Mac 可能是任意 App 在前台。**当前决策：iPhone 文本严格按 Mac 当前前台 App 注入，和 Mac 本机听写行为一致。**

## 14. 参考索引

- `Apps/AetherCore/HeadMotionManager.swift` — 现有 AirPods 头追，要从中抽出光标映射
- `Apps/AetherCore/SpeechManager.swift` — 要加 `ingestRemoteText`
- `Apps/AetherCore/Speech/DictationHandler.swift` — 文本入口已兼容
- `Apps/AetherCore/Speech/VoiceCommandRouter.swift` — 下游无感
- `Apps/AetherCore/SettingsModules.swift` — 加 iPhone Remote 设置页
