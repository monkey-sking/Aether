# **Project "Aether" Phase 1.5 实施清单 (TODO)**

**里程碑目标**：零键鼠依赖 (Zero Keyboard/Mouse Dependency) - 让用户在安装后完全通过头部追踪和语音控制使用 Mac。

---

## **1. Phase 1 未完成项 (Carry Over)**

### 1.1 驱动验收 (DriverKit Validation)
- [ ] **安装验证**：DriverKit 扩展安装/启用后，指针移动与点击确实经由虚拟 HID 生效（非 CGEvent fallback）
- [ ] **最小闭环**：AirPods 指针移动 + 左键点击经由虚拟 HID 输出

### 1.2 连接管理 (Connection Management)
- [ ] **AirPods 断开监听**：蓝牙路由变化时自动暂停头部控制
- [ ] **Multipeer Connectivity 预研**：为 Phase 2 多设备协同做准备

---

## **2. 自动激活 (Auto Activation) [0%]**
- [ ] **AirPods 连接自启动**
    - [ ] 监听蓝牙音频路由变化 (`AVAudioSession.routeChangeNotification`)
    - [ ] 检测到 AirPods 连接 → 自动激活头部控制
    - [ ] 播放提示音或语音："Aether 已就绪"
- [ ] **登录项自启动**
    - [ ] 添加"开机自启"选项到设置
    - [ ] 使用 `SMAppService` 或 `LaunchAgent` 实现

---

## **3. 语音控制独立 (Voice-Only Control) [0%]**
- [ ] **去除 PTT 热键依赖**
    - [x] 常驻语音监听默认开启 (Build 1918)
    - [ ] **智能唤醒策略 (Context-Aware Wake)**
        - [ ] **待机状态**：必须使用唤醒词 ("Aether", "艾瑟")
        - [ ] **连指令窗口**：唤醒后 8 秒内无需再次唤醒 (e.g. "Start" -> "Scroll Down")
        - [ ] **注视免唤醒**：当 `isLookingAtScreen == true` 且正在追踪时，特定指令（如 stop/recenter）免唤醒
        - [ ] **输入与操作状态区分 (Context-Aware Mode)**：
            - **输入状态** (焦点为 `AXTextArea/TextField`)：默认听写，指令需前缀（如"指令 点击"）
            - **操作状态** (无输入框)：默认指令，听写需前缀（如"输入 你好"）
- [ ] **核心语音指令**
    | 指令 | 功能 |
    |------|------|
    | `开始` / `start` | 激活头部控制 |
    | `停止` / `stop` | 暂停头部控制 |
    | `校准` / `recenter` | 重置中心点 |
    | `悬停开` / `dwell on` | 开启 Dwell Click |
    | `悬停关` / `dwell off` | 关闭 Dwell Click |
- [ ] **滚动语音指令 (Scroll)**
    | 指令 | 功能 |
    |------|------|
    | `向上滚` / `scroll up` | 向上滚动一段 |
    | `向下滚` / `scroll down` | 向下滚动一段 |
    | `到顶` / `top` | 滚动到页首 |
    | `到底` / `bottom` | 滚动到页尾 |
- [ ] **拖拽语音指令 (Drag & Drop)**
    | 指令 | 功能 |
    |------|------|
    | `拖住` / `drag` | 按下鼠标左键（开始拖拽） |
    | `放下` / `drop` | 释放鼠标左键（结束拖拽） |

---

## **4. AirPods 手势扩展 (Gesture Expansion) [0%]**
- [ ] **长按捏 (Long Press)**
    - [ ] 检测捏合持续时间 > 0.5s
    - [ ] 触发语音输入模式（替代 PTT 热键）
- [ ] **捏住+移动 (Pinch & Move)**
    - [ ] 捏住状态下头部移动 → 拖拽操作
    - [ ] 释放捏合 → 放下

---

## **5. 头部动作扩展 (Head Motion Expansion) [0%]**
- [ ] **倾斜滚动 (Tilt Scroll)**
    - [ ] 头部向上倾斜超过阈值 → 持续向上滚动
    - [ ] 头部向下倾斜超过阈值 → 持续向下滚动
    - [ ] 回到中心位置 → 停止滚动
- [ ] **快速点头/摇头 (Head Nod/Shake)**
    - [ ] 快速点头 → 确认/左键点击（可选）
    - [ ] 快速摇头 → 取消/Escape（可选）

---

## **6. 首次运行引导 (Onboarding Enhancement) [0%]**
- [ ] **语音引导**
    - [ ] 首次启动播放语音："你好，我是 Aether"
    - [ ] 引导用户授权："请说'授权'来打开系统设置"
- [ ] **语音触发权限跳转**
    - [ ] `授权辅助功能` → 打开 Accessibility 设置
    - [ ] `授权麦克风` → 打开 Microphone 设置
    - [ ] `授权语音` → 打开 Speech Recognition 设置

---

## **验证标准 (Definition of Done)**

1. [ ] **零键鼠启动**：戴上 AirPods 后，无需任何键鼠操作即可开始控制光标
2. [ ] **语音全覆盖**：所有控制功能均可通过语音指令完成
3. [ ] **滚动能力**：可通过语音或头部倾斜完成页面滚动
4. [ ] **拖拽能力**：可通过语音或捏合手势完成拖拽操作
5. [ ] **首次引导**：新用户可通过语音完成权限授予流程
