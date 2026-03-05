# Aether Acceptance Checklist

## 本轮必验 (P0)
- [x] 浏览器非输入区域：控制模式 HUD 会跟随鼠标移动（不被陈旧光标/输入锚点锁住）
    有问题，有时候不跟着鼠标走,在一个离鼠标很远的地方
- [x] 浏览器输入区域：输入模式 HUD 回到输入框/光标锚点
- [x] 语音进度环只在检测到语音活动时显示并推进；静音时不空转
    有问题，现在我没有说话还是在转，是受环境声音导致的一直转吗
- [x] 手动切换模式时：左侧仍是麦克风/设备图标，右侧才是模式图标（command/keyboard）

## 本轮新增功能验收（2026-03-05）
- [x] 语言切换快捷键可用（默认 `Shift`）
- [x] 左/右 `Shift` 都可触发语言切换
- [x] 连续按住 `Shift` 不会误触发多次切换（仅按下触发）
- [x] 与现有输入/控制模式快捷键无冲突

## Build
- [x] 安装包使用最新构建产物：`.build/release/Aether_Installer.dmg` 或 `.build/release/Aether.zip`
- [x] 应用可正常启动，无崩溃
- [x] 首次启动权限提示流程正常（辅助功能/麦克风/语音识别）
    会弹出多个权限请求，应该要依次弹出吧
    还有辅助权限要了好多次，现在我们签名没有变，打包后会重复要权限

## 本次正式包验签结果（2026-03-05）
- [x] 使用发布链路生成正式包（`Scripts/ReleaseForUsers.sh`，非 `AETHER_UNSIGNED=1`）
- [x] App 验签通过：`codesign --verify --deep --strict` + `spctl -a -t exec -vv`
- [x] DMG 验签通过：`codesign --verify` + `spctl -a -t open -vv --context context:primary-signature`
- [x] Notary 公证通过（Submission ID: `d4ff6e81-0ff5-4c52-ba1a-bef8908a24fb`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）

## 权限复用专项（安装包）
- [ ] 从 `/Applications` 运行已签名版本，覆盖升级后不会重复请求辅助功能权限
- [ ] 从 DMG 内直接运行时会提示安装到 `/Applications`（避免权限反复）
- [x] 未签名/临时签名包（开发构建）可能触发系统重新授权（记录为预期行为）
    上次重复授权的直接原因：使用了 `AETHER_UNSIGNED=1` 产物，且可能未固定在 `/Applications/Aether.app` 路径运行

## Hotkey And Mode Switching
- [x] 快捷键切换输入/控制模式可触发（连续按 5 次）
- [ ] 在没有输入框焦点时，切换到输入模式会提示并回落到控制模式
    提示文本显示时间过长了
- [x] 在输入框内手动切到控制模式后，HUD 进入控制语义
- [x] 之后点击回输入框时，模式自动回到输入模式（不被手动模式长期锁住）
    有问题，手动切到控制模式后，再点击输入框，模式没有自动回到输入模式
- [x] `Esc` 在输入语义下可退出到控制模式
- [x] `Esc` 后再次点击输入框可恢复输入模式（跟焦点生效）
    有问题，Esc后，再点击输入框，模式没有自动回到输入模式

## Browser HUD Behavior
- [ ] 浏览器普通页面（非输入框）中，控制模式 HUD 跟随鼠标移动
    有问题，有时候不跟着鼠标走,在一个离鼠标很远的地方,显示的是输入框，这块输入控制判定需要优化下
- [x] 浏览器输入框（地址栏/文本框）中，输入模式 HUD 跟随输入框/光标锚点
- [x] 浏览器在输入框与非输入区域来回切换时，HUD 图标与位置同步切换
- [x] 焦点切换后 HUD 不会卡在旧位置

## HUD Icons
- [x] 模式切换时“模式图标”在右侧上下文位切换（command/keyboard）
- [x] 左侧麦克风图标保持为输入设备图标（不会因模式切换变成 command/keyboard/info）
- [x] 语言切换按钮显示与点击正常

## Voice Progress Ring
- [ ] 无语音输入时，进度环不持续转圈
- [ ] 仅在检测到语音活动时，进度环显示并推进
- [ ] 语音停止后，进度环可隐藏/复位
- [ ] 不会出现“一圈转完又一圈”持续空转

## Dictation And Injection
- [ ] 输入模式下 partial 增量输入正常
- [ ] final 修正不会重复注入
- [ ] 焦点变化/目标 PID 变化时，不会误删或误改其它输入框内容
- [ ] `Undo` 回退最近一次注入正常

## Control Intents
- [ ] 控制指令（点击/双击/滚动/右键/拖拽）在控制模式下可执行
- [ ] 输入模式下控制指令不会误触发为控制动作

## Stability
- [ ] 长时间运行后热键仍可触发（事件 tap 不失效）
- [ ] 从系统设置撤销再恢复辅助功能权限后，热键可恢复
- [ ] 连续切模式 + 切焦点 2 分钟，不出现 HUD 抖动/冻结/状态错乱

## Suggested Test Matrix
- [ ] Chrome / Safari / Electron 类应用（至少 2 个）
- [ ] 普通文本输入框 + 富文本输入框
- [ ] 英文输入法 + 中文输入法
- [ ] 外接麦克风 + AirPods（如有）
