# iPhone Remote — Tasks

按依赖顺序排列。每个 Phase 结束时都有可独立验证的产物。

---

## Phase 0 — Shared Protocol Package

**目标**：把 wire types 定义清楚，Mac 和 iOS 两端后续都依赖它。

- [x] 新建 Swift package `App/Shared/RemoteProtocol/`
  - [x] `Package.swift`，`swift-tools-version: 5.9`，products: library `RemoteProtocol`
  - [x] 无外部依赖
  - [x] 最低平台：`.iOS(.v16)` / `.macOS(.v13)`
- [x] `Sources/RemoteProtocol/ProtocolVersion.swift` — `public let protocolVersion: UInt16 = 1`
- [x] `Sources/RemoteProtocol/Packet.swift` — 10 种 case 的 `Packet` 枚举（见 design.md §7.2）
- [x] `Sources/RemoteProtocol/Payloads.swift` — 所有 payload struct（含 `Quaternion` wrapper：`simd_quatf` 不是 Codable，对外 API 仍是 `simd_quatf`）
- [x] `Sources/RemoteProtocol/Encoding.swift` — `Packet.encode()` / `Packet.decode(from:)` 包装 `PropertyListEncoder(.binary)`
- [x] 单元测试：每种 packet 做 roundtrip encode/decode，尺寸断言 `motion` 包 < 256 bytes（实际 ~195 bytes，binary plist 自带字段名 / type tags / offset table，约 3× 原始二进制 overhead；如未来带宽吃紧再换手写 binary 编码）
- [ ] 把 package 加到 `AetherCore.xcodeproj` 的 target dependencies（留到 Phase 1 真正需要 `import` 时在 Xcode UI 里 Add Local Package — 避免手编老式 pbxproj）

**验收**：`swift test` 14/14 通过（2026-04-20）。`AetherCore.xcodeproj` 的 SPM dep 等 Phase 1 开工再挂。

---

## Phase 1 — Mac Pointer Source Refactor

**目标**：把现在 `HeadMotionManager` 里"姿态 → 光标"的耦合解开，建立 `PointerSource` 抽象。本阶段不引入 iPhone，只保证现有 AirPods 路径零回归。

- [ ] `Pointer/PointerSource.swift`
  - [ ] `protocol PointerSource: AnyObject`
  - [ ] `enum PointerSourceID: Hashable { case airpodsHead, iPhoneLaser(peerID: String) }`
  - [ ] `struct PointerFrame`（globalPoint / targetDisplayID / confidence / timestamp）
  - [ ] `struct PointerButtonEvent`
  - [ ] 暴露 `framePublisher` / `buttonPublisher` / `statusPublisher`
- [ ] `Pointer/PointerCoordinator.swift`
  - [ ] 持有 `@Published var activeSource: PointerSourceID?`
  - [ ] 订阅 active source 的 `framePublisher` → `CGEventPost`
  - [ ] 订阅 `buttonPublisher` → 广播 `AetherPTTDown` / `AetherPTTUp` Notification（和现在 `HeadMotionManager.pttDownNotification` 一致）
  - [ ] 源切换时旧 source `deactivate()` / 新 source `activate()`
- [ ] `Pointer/AirPodsHeadPointerSource.swift`
  - [ ] 包一层 `HeadMotionManager`：把现在 `HeadMotionManager` 里输出 `CGWarpMouseCursorPosition` / `CGEventPost` 的那部分迁出来
  - [ ] 保持现有校准、居中、灵敏度、热区逻辑完全等价
- [ ] 改 `HeadMotionManager.swift`
  - [ ] 删掉光标移动相关代码，保留：数据采集（`CMHeadphoneMotionManager`）、手势识别、headset 按键、自动启停、手势历史
  - [ ] 对外新增 `@Published var latestAttitude: CMAttitude?`，供 `AirPodsHeadPointerSource` 订阅
- [ ] 改 `AetherApp.swift`
  - [ ] `AppState` 里 `@StateObject var pointerCoordinator: PointerCoordinator`
  - [ ] 启动时注册 `airpodsHead` source 并 `activate()`
- [ ] 回归测试
  - [ ] 用户佩戴 AirPods，光标行为和重构前一致（手动测 5 个常见动作）
  - [ ] 头部手势 nod / shake 仍触发对应 action
  - [ ] Headset 单/双/三击仍正常

**验收**：AirPods 头追用户看不出任何差别；代码改完 `HeadMotionManager` 文件行数显著变小。

---

## Phase 2 — Mac RemoteService + Fake iPhone Source

**目标**：把 MPC advertiser 跑起来，配对握手走通；用一个"假 iPhone"（XCTest 里的 MPC client）发包，证明端到端管道通。

- [ ] `Remote/RemoteService.swift`
  - [ ] 初始化 `MCPeerID`（用 `Host.current().localizedName`）
  - [ ] 启动 `MCNearbyServiceAdvertiser(peer:discoveryInfo:serviceType: "aether-remote")`
  - [ ] `MCSessionDelegate`：`didReceive data:` → `Packet.decode()` → `PassthroughSubject`
  - [ ] `sendPacket(_:reliable:)` → `session.send(_:toPeers:with:)`
  - [ ] 6 位码配对 + keychain 存 `peerID` + `sharedSecret`
  - [ ] `helloAck` 带 `macLicenseStatus`（查现有 license manager）
  - [ ] 1 Hz 发 heartbeat，超时 3s 无回直接 disconnect
- [ ] `Remote/RemoteSessionState.swift` — 状态机（idle / advertising / pairing / connected / errored）
- [ ] `Remote/iPhoneLaserPointerSource.swift`（**本阶段先留空壳**）
  - [ ] 实现 `PointerSource` 协议
  - [ ] 订阅 `RemoteService.packets`
  - [ ] `motion` 包先不做几何，直接丢弃（下阶段接）
  - [ ] `button` 包翻译成 `PointerButtonEvent` 发 publisher
- [ ] 新增 `AetherTests/RemoteServiceTests.swift`
  - [ ] 在 XCTest 里开一个 MCPeerID 当 "假 iPhone"，和 `RemoteService` 握手
  - [ ] 发 `hello` → 收 `helloAck`
  - [ ] 发 `button(.pttDown)` → 断言 `AetherPTTDown` Notification 触发
- [ ] 改 `Info.plist` + `AetherCore.entitlements`
  - [ ] `NSLocalNetworkUsageDescription`
  - [ ] `NSBonjourServices = ["_aether-remote._tcp", "_aether-remote._udp"]`
  - [ ] entitlements 确认 `com.apple.security.network.server` = true

**验收**：单元测试跑通端到端握手；Mac 应用运行时在 System Settings 的"本地网络"权限列表里出现 Aether。

---

## Phase 3 — Mac Calibration Math + Overlay

**目标**：数学解算和独占 overlay 实现。先做成"手动喂 sample"的单元测试驱动，UI 独立验证。

- [ ] `Pointer/ScreenCalibration.swift`
  - [ ] `struct DisplayCalibration { displayID, corners: [SIMD3<Float>], normal, pixelSize }`
  - [ ] `static func solve(samples: [CalibrationSample], pixelSize:) -> DisplayCalibration?`
    - 4 条射线和 4 个已知屏上点 → 最小二乘拟合平面和四角
  - [ ] `func intersect(rayOrigin:, rayDirection:, calibrations: [DisplayCalibration]) -> (displayID, screenPoint: CGPoint)?`
    - 对每块屏做射线-平面求交
    - 过滤"在相机后方"的解
    - 过滤"不在矩形内"的解（UV 参数 0..1 外）
    - 多个命中取最近
  - [ ] `static func realign(historical: [DisplayCalibration], centerSample: CalibrationSample, displayID:, pixelSize:) -> [DisplayCalibration]`
    - 用一个 center sample 做刚体变换对齐
  - [ ] 持久化：`save(to: URL)` / `load(from: URL)`，存到 `ApplicationSupport/Aether/iPhoneCalibration.plist`
- [ ] `Pointer/CalibrationCoordinator.swift`
  - [ ] 状态机：`idle / fullCalibration(displayIdx, markerIdx) / recenter / done`
  - [ ] 对每块屏依次推进 cue → 收 sample → 下一 cue
  - [ ] 超时（10s 无 sample）发 `error(.calibrationTimeout)` 并回 idle
- [ ] `Pointer/CalibrationOverlayWindow.swift`
  - [ ] `NSWindow` 子类，`styleMask = .borderless`，`level = .screenSaver + 1`
  - [ ] 黑底 80% 透明 + 一个大亮点（SwiftUI `HostingView`）
  - [ ] 接 `keyDown` 吞掉所有键（ESC 除外，ESC 放弃）
  - [ ] 一个工厂方法 `allWindows(for: [NSScreen]) -> [CalibrationOverlayWindow]`
- [ ] 单元测试 `AetherTests/ScreenCalibrationTests.swift`
  - [ ] 合成 4 个已知位姿 → solve → 反算点 → 断言误差 < 2 像素
  - [ ] 多屏场景：两个矩形 → intersect 返回正确的 displayID
  - [ ] realign 测试：原始矩形 + 已知刚体变换 → 断言对齐后还原

**验收**：单元测试精度达标；overlay 在 Mac 上手动开关正常，ESC 能退出。

---

## Phase 4 — Mac iPhone Source 接入

**目标**：把 motion frame 真的转成 `PointerFrame`，Mac 端用假数据或手动发包的 iPhone 端就能移动光标。

- [ ] `iPhoneLaserPointerSource.swift` 完善
  - [ ] 订阅 `RemoteService.packets.filter { $0 is motion }`
  - [ ] 查 `CalibrationCoordinator` 是否已 `done`，否则丢帧
  - [ ] `ScreenCalibration.intersect` → `PointerFrame`
  - [ ] 加一阶 IIR 低通滤波（可配置 α，对应 UI 灵敏度滑块）
  - [ ] 跟踪 `trackingState == .limited` 时把 `confidence` 降到 0.5，`.notAvailable` 降到 0 并停更新
- [ ] `SettingsModules.swift` 增加 "iPhone Remote" 页
  - [ ] 配对状态、"重新校准"按钮、"忘记配对"按钮
  - [ ] Source 切换：AirPods / iPhone / 两者都关
  - [ ] 灵敏度 slider（映射到低通 α）
  - [ ] 当前连接的 iPhone 名称、跟踪质量
- [ ] 手动端到端测试（用 Phase 2 的 XCTest 驱动假 iPhone）
  - [ ] 发 calibration samples → solve → 发 motion → 光标移动

**验收**：即使没有 iOS App，也能用 XCTest 手动驱动 Mac 端移动光标。

---

## Phase 5 — iOS Target Scaffold

**目标**：把 iOS App 结构建起来，能连上 Mac、发 hello、收 helloAck。

- [ ] 新建 `App/Apps/AetherRemote/AetherRemote.xcodeproj`
  - [ ] 单 target，iOS 16+
  - [ ] Bundle ID 占位（正式 ID 在 App Store 提交前敲定）
  - [ ] SPM 依赖 `Shared/RemoteProtocol/`
- [ ] `AetherRemoteApp.swift` — `@main`，`isIdleTimerDisabled = true`
- [ ] `Remote/RemoteClient.swift`
  - [ ] `MCNearbyServiceBrowser(peer:serviceType: "aether-remote")`
  - [ ] 发现、连接、send/receive、heartbeat
- [ ] `Remote/PairingStore.swift` — Keychain 读写 peerID + sharedSecret
- [ ] `Views/PairingView.swift`
  - [ ] 浏览列表 → 选 Mac → 输 6 位码 → 发 hello
- [ ] `Views/MainView.swift`
  - [ ] 空壳：顶部连接状态、中央"未实现"、底部齿轮
- [ ] `Resources/Info.plist` 5 条 usage description（见 design.md §6.2）
- [ ] 手动端到端测试
  - [ ] Mac 和 iPhone 同局域网 → iPhone App 找到 Mac → 配对 → 连上
  - [ ] 断开 Wi-Fi 后 heartbeat 超时 → iPhone 端显示"连接已断开"

**验收**：配对成功，状态在 Mac 和 iOS 两端都正确显示。

---

## Phase 6 — iOS Motion Streaming

**目标**：ARKit + 陀螺双路径跑通，Mac 光标真的能被 iPhone 控制。

- [ ] `Motion/MotionStreamer.swift`
  - [ ] `ARSession` + `ARWorldTrackingConfiguration`（`worldAlignment = .gravity`）
  - [ ] `ARSessionDelegate.session(_:didUpdate:)` → 60 Hz 生成 MotionFrame
  - [ ] `CMMotionManager` 兜底（ARKit 降级时启动，`.limited` 标记）
  - [ ] 发 packet 频率节流到 60 Hz（ARSession 默认 60，超了丢帧）
- [ ] `MainView` 完善
  - [ ] 中央大 PTT 圆按钮（`UILongPressGestureRecognizer` minDuration 0 → `.began / .ended` → pttDown/pttUp）
  - [ ] 右上角跟踪质量指示灯（绿 normal / 黄 limited / 红 notAvailable）
  - [ ] 屏幕中央顶部"请把手机朝向 Mac 屏"的 AR coaching overlay（用 `ARCoachingOverlayView`）
- [ ] `Views/CalibrationAssistView.swift`
  - [ ] 校准期：Mac 发 `calibrationCue` → iPhone 显示"指向 Mac 屏 [左上/右上/...]，按 PTT 确认"
  - [ ] PTT 按下时把当前 ARFrame 位姿打包 `calibrationSample` 发回
- [ ] 端到端手动测试
  - [ ] 首次配对后自动进入四角校准
  - [ ] 完成校准后光标真的跟着 iPhone 指向移动
  - [ ] 灵敏度 slider 改变光标响应
  - [ ] 重新启动 iPhone App → 中心点重锚定后恢复正常

**验收**：手持 iPhone 指 Mac 屏上任意图标，光标能落在那个图标附近（误差 <10 像素）。

---

## Phase 7 — iOS Text Input Streaming

**目标**：iPhone 上的文本（无论来自系统键盘、系统听写、还是第三方 IME）能流到 Mac 当前前台 App。

- [ ] `Input/TextStreamer.swift`
  - [ ] 持有一个 `UITextView`
  - [ ] `UITextViewDelegate.textViewDidChange` → 计算新的累积文本 → 发 `textPartial`
  - [ ] "发送"按钮 → 发 `textFinal` → 清空
  - [ ] 每次开始输入生成新 `utteranceID: UUID`
- [ ] `MainView` 补齐底部
  - [ ] `UITextView`（SwiftUI 里用 `UIViewRepresentable` 包）
  - [ ] "发送"按钮
  - [ ] 键盘工具条："清空 / 发送 / 隐藏键盘"
- [ ] Mac 端 `SpeechManager` 加 `ingestRemoteText(payload:final:)`
  - [ ] `final = false` → `dictationHandler.onPartial(...)`
  - [ ] `final = true` → `dictationHandler.onFinal(...)`
  - [ ] `RemoteService` 收到 `textPartial` / `textFinal` 时路由到这里
- [ ] 端到端手动测试
  - [ ] iPhone 上打字 → Mac 前台文本框实时出现
  - [ ] iPhone 用系统键盘的听写 → Mac 前台出现相同文本
  - [ ] iPhone 切到搜狗输入法用其语音 → 同样工作
  - [ ] 中途修正（比如系统 STT 改 "好吧" → "好啊"）Mac 端不出现 "好吧好啊"

**验收**：iPhone 用户的三种输入方式（打字 / 系统听写 / 第三方 IME 语音）都能正确把文本送到 Mac。

---

## Phase 8 — UX Polish + Error Paths

- [ ] 跟踪丢失 3s 后 Mac HUD 提示 "请把手机朝向 Mac"
- [ ] iPhone 端后台化时 `ARSession.pause()`，前台化时恢复并触发重锚定
- [ ] Mac 端"重新校准"按钮走完整四角流程（而不是只重锚定）
- [ ] iPhone 端"忘记 Mac"按钮清 keychain，Mac 端"忘记 iPhone"按钮同理
- [ ] Mac 激活到期时 iPhone 端显示明确提示、不发 motion
- [ ] iPhone 端 "关于" 页：版本、protocol 版本、连接日志最近 10 条
- [ ] 多屏切换时 HUD 简短提示 "光标已切到 Display 2"
- [ ] 本地化：中英双语（和 Mac 端对齐）

---

## Phase 9 — App Store Submission

- [ ] 正式 Bundle ID 注册，Provisioning profile 建好
- [ ] App Store Connect 条目：名称、副标题、描述（三语：中英西 if 同 Mac 端）
- [ ] 截图（iPhone 6.7" / 6.1"）
- [ ] 隐私标签：
  - 不收集用户数据（语音、运动、相机均本地处理）
  - 本地网络仅用于和 Mac 通讯
- [ ] App Review Notes 说明这是 companion app
- [ ] 给 reviewer 提供 Mac 端测试 build 或 TestFlight 外链
- [ ] 提交 TestFlight 内部测试
- [ ] 外部测试（招募 20-50 beta 用户）
- [ ] 正式提交

---

## 估时参考

| Phase | 估时（单人） |
|---|---|
| Phase 0 | 1 天 |
| Phase 1 | 3-5 天（现有代码耦合度较高） |
| Phase 2 | 2-3 天 |
| Phase 3 | 3-4 天（数学要仔细） |
| Phase 4 | 1-2 天 |
| Phase 5 | 2 天 |
| Phase 6 | 3-4 天 |
| Phase 7 | 2 天 |
| Phase 8 | 3-5 天 |
| Phase 9 | 1-2 周（等审核） |

总计：**4-5 周开发 + 审核等待**。
