# Aether Acceptance Checklist

## 未验收（Pending）

### Browser HUD Behavior（未验收项）
- [ ] 浏览器普通页面（非输入框）中，控制模式 HUD 跟随鼠标移动
    有问题，有时候不跟着鼠标走,在一个离鼠标很远的地方,显示的是输入框，这块输入控制判定需要优化下

### Voice Progress Ring
- [ ] 无语音输入时，进度环不持续转圈
- [ ] 仅在检测到语音活动时，进度环显示并推进
- [ ] 语音停止后，进度环可隐藏/复位
- [ ] 不会出现“一圈转完又一圈”持续空转
    有问题，现在我没有说话还是在转，是受环境声音导致的一直转吗

### Speech Recognition Text Quality（未验收项）
- [ ] 中文短句识别不会出现尾部重复（例如“通过并完成通过并完成”）
- [ ] 中英混读（含英文术语）场景下不会出现尾短语回环重复
    已加识别后处理：`normalizeRecognizedText` + `deduplicateRepeatedTailPhrase`，待你实测验收
- [ ] LLM 语音识别结束润色与纠错 (Pending Feature)
    利用大模型能力对 Final 文本进行上下文纠错和近音词修复（例如“交脱入”->“将拖入”），以解决 SFSpeechRecognizer 原生识别的幻觉和断句问题。

### Dictation And Injection
- [ ] 输入模式下 partial 增量输入正常
- [ ] final 修正不会重复注入
- [ ] 焦点变化/目标 PID 变化时，不会误删或误改其它输入框内容
- [ ] `Undo` 回退最近一次注入正常

### Hotkey And Mode Switching（未验收项）
- [x] 在没有输入框焦点时，切换到输入模式会提示并回落到控制模式（提示时长需合理）
    提示文本显示时间过长了
- [ ] 手动切到控制模式后，再点击输入框会自动回到输入模式
    有问题，手动切到控制模式后，再点击输入框，模式没有自动回到输入模式
- [ ] `Esc` 退出输入模式后，再点击输入框会恢复输入模式
    有问题，Esc后，再点击输入框，模式没有自动回到输入模式

### Build / Permissions（未验收项）
- [x] 首次启动权限提示应按预期串行展示，且不会重复弹出
    会弹出多个权限请求，应该要依次弹出吧

### Stability
- [x] 从系统设置撤销再恢复辅助功能权限后，热键可恢复
- [x] 从系统设置撤销再恢复辅助功能权限后，模式可随焦点恢复（不会卡在输入模式）
    恢复后功能异常了，快捷键无效,一直是输入模式,需要重新启动

### Suggested Test Matrix
- [ ] Chrome / Safari / Electron 类应用（至少 2 个）
- [ ] 普通文本输入框 + 富文本输入框
- [ ] 英文输入法 + 中文输入法
- [ ] 外接麦克风 + AirPods（如有）

## 已验收（Passed）

### 本轮必验 (P0)
- [x] 浏览器输入区域：输入模式 HUD 回到输入框/光标锚点
- [x] 手动切换模式时：左侧仍是麦克风/设备图标，右侧才是模式图标（command/keyboard）

### 本轮新增功能验收（2026-03-05）
- [x] 语言切换快捷键可用（默认 `Shift`）
- [x] 左/右 `Shift` 都可触发语言切换
- [x] 连续按住 `Shift` 不会误触发多次切换（仅按下触发）
- [x] 与现有输入/控制模式快捷键无冲突

### Build
- [x] 安装包使用最新构建产物：`.build/release/Aether_Installer.dmg` 或 `.build/release/Aether.zip`
- [x] 应用可正常启动，无崩溃

### 本次正式包验签结果（2026-03-05）
- [x] 使用发布链路生成正式包（`Scripts/ReleaseForUsers.sh`，非 `AETHER_UNSIGNED=1`）
- [x] App 验签通过：`codesign --verify --deep --strict` + `spctl -a -t exec -vv`
- [x] DMG 验签通过：`codesign --verify` + `spctl -a -t open -vv --context context:primary-signature`
- [x] Notary 公证通过（Submission ID: `df7c1785-9333-4834-a9de-cad4388f62df`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）

### 权限复用专项（已验收项）
- [x] 从 `/Applications` 运行已签名版本，覆盖升级后不会重复请求辅助功能权限
- [x] 从 DMG 内直接运行时会提示安装到 `/Applications`（避免权限反复）
- [x] 点击“修复辅助功能”时只出现一个授权引导窗口（不再出现双弹窗）
- [x] 未签名/临时签名包（开发构建）可能触发系统重新授权（记录为预期行为）
    上次重复授权的直接原因：使用了 `AETHER_UNSIGNED=1` 产物，且可能未固定在 `/Applications/Aether.app` 路径运行

### Hotkey And Mode Switching（已验收项）
- [x] 快捷键切换输入/控制模式可触发（连续按 5 次）
- [x] 在输入框内手动切到控制模式后，HUD 进入控制语义
- [x] `Esc` 在输入语义下可退出到控制模式

### Browser HUD Behavior（已验收项）
- [x] 浏览器输入框（地址栏/文本框）中，输入模式 HUD 跟随输入框/光标锚点
- [x] 浏览器在输入框与非输入区域来回切换时，HUD 图标与位置同步切换
- [x] 焦点切换后 HUD 不会卡在旧位置

### HUD Icons
- [x] 模式切换时“模式图标”在右侧上下文位切换（command/keyboard）
- [x] 左侧麦克风图标保持为输入设备图标（不会因模式切换变成 command/keyboard/info）
- [x] 语言切换按钮显示与点击正常

### Control Intents
- [x] 控制指令（点击/双击/滚动/右键/拖拽）在控制模式下可执行
- [x] 输入模式下控制指令不会误触发为控制动作

### Stability（已验收项）
- [x] 长时间运行后热键仍可触发（事件 tap 不失效）
- [x] 连续切模式 + 切焦点 2 分钟，不出现 HUD 抖动/冻结/状态错乱
