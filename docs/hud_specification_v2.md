# Aether HUD 技术规范 (v2.7)

> **版本：** 2026.02.14 (Trigger Persistence Fix)  
> **状态：** 已部署 (Stable)  
> **核心哲学：** 区分“物理实体”与“活动信号”，确立“全寂静”安全屏障，实现极致的自动化控制。

---

## 一、 核心模式与状态定义

HUD 采用分层视觉语言，中间区域根据当前模式动态切换展示负载。

| 模式 (Mode) | 硬件图标 (白色) | 中心负载 (Payload) | 语义上下文 (Status) |
| :--- | :--- | :--- | :--- |
| **Standby** | 🟢 (绿色点) | 无 | Aether 正在后台守候 |
| **Listening** | 设备图标 | “正在聆听...” (动态) | 准备接收指令 |
| **Command** | 设备图标 | **实时转录文字** | ⌘ (执行系统指令) |
| **Dictation** | 设备图标 | **5点动态波形 (绿)** | ⌨️ (文字输入到光标) |
| **Processing** | ⋯ (省略号) | 无 | AI 正在思考/处理中 |

---

## 二、 设备感知与图标映射 (Device Awareness)

### 1. 优先级策略 (Priority Hierarchy)
HUD 图标展示遵循“**佩戴感知优先**”原则，以消除系统音频路由延迟带来的视觉脱节：
1. **[最高级] 硬件缺失拦截**：如果扫描发现没有任何物理录音硬件，强制显示 `mic.slash`。
2. **[第二级] AirPods 佩戴感知**：只要 `AirPodsDetector` 检测到 In-Ear 状态，直接显示耳机图标（忽略系统默认选择）。
3. **[第三级] 活动设备识别**：显示当前系统默认输入硬件的专用图标。
4. **[最低级] 诊断占位符**：未检测到激活硬件时，显示 `mic.slash` 并伴随“未检测到麦克风”文字。

### 2. 详细图标映射表
| 设备类型/状态 | SFSymbol 图标 | 含义与文本反馈 |
| :--- | :--- | :--- |
| **硬故障 / 未就绪** | `mic.slash` | **未检测到麦克风** |
| **AirPods (双耳)** | `airpod.gen3` | 双耳佩戴中 |
| **AirPods (左耳)** | `airpod.gen3.left` | 单左耳佩戴 |
| **AirPods (右耳)** | `airpod.gen3.right` | 单右耳佩戴 |
| **AirPods Max** | `airpodsmax` | 头戴式识别 |
| **MacBook 内置** | `laptopcomputer` | 笔记本内置麦克风 |
| **外接录音设备** | `mic.fill` | 专业麦克风 / USB 设备 |

---

## 三、 实时同步机制 (Synchronization)

1. **底层监听**：
   * 监听 `kAudioHardwarePropertyDefaultInputDevice` (系统心跳)。
   * 监听 `IOKit` 蓝牙注册表变化 (AirPods 快轨)。
2. **跨层通知**：
   * `AirPodsDetector` 变化时向 `SpeechManager` 发送通知。
   * 触发 `refreshContinuousHUD` 实现 HUD 秒级自刷新，确保视觉图标与物理动作同步。

---

## 四、 触发器互锁与全寂静逻辑 (Trigger Interlock & Global Silence)

为了节约系统资源并保护用户隐私，HUD 的可见性与引擎状态受三大触发器联合控制。

### 1. 触发器定义
*   **PTT (Push-To-Talk)**：手动物理按键触发。
*   **Wake Word ("Hey Aether")**：被动监听触发，需要引擎常驻。
*   **Hands-Free / 免提（常驻监听）**：主动持续监听，无唤醒词模式，需要引擎常驻。

### 2. HUD 状态映射逻辑
| 触发器组合状态 | 引擎状态 | HUD 初始视觉状态 | 隐身/退出逻辑 |
| :--- | :--- | :--- | :--- |
| **全关 (All OFF)** | **Teardown (释放资源)** | **Hidden (完全隐身)** | 实时检测，全关即消失 |
| **仅 PTT 开** | 休眠中 (随按随启) | **Hidden** | 仅在按下按键时浮现，松开处理完后隐身 |
| **唤醒词 或 常驻监听 开** | **Active (正在运行)** | **Standby (🟢 绿点)** | 保持常驻显示，指示 Aether 正在守候 |

---

## 五、 智能语言切换逻辑 (Smart Toggle)

HUD 右侧的语言按钮具备“母语记忆”功能：
1. **母语记忆**：自动记录最后一次手动选择的非英语言（默认 `zh-CN`）。
2. **一键翻转**：在“英语”与“记忆中的母语”之间快速切换。

---

## 五、 配色与渲染美学

| 颜色分类 | 色值 | 应用场景 |
| :--- | :--- | :--- |
| **硬件白 (Base)** | `White (1.0)` | 设备图标、主文字内容、⋯ 动画。 |
| **信号绿 (Activity)** | `Green (0.8+)` | 待机点、动态波形。 |
| **错误红 (Alert)** | `Red (0.9)` | (未来规划) 彻底故障时的警示。 |

---

## 六、 维护路径
* **硬件监听与图标逻辑**：[SpeechManager.swift](file:///Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift)
* **佩戴探测快轨**：`AirPodsDetector` 内部类 (@ SpeechManager.swift)
* **视图层渲染**：[HUDView.swift](file:///Volumes/SSD/Projects/Aether/App/Apps/AetherCore/HUD/HUDView.swift)
