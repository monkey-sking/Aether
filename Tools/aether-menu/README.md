# aether-menu

把任意运行中的 macOS App 的**菜单栏**变成 agent 可检索、可执行的结构化命令目录。

从 Aether（`VoiceCommandRouter` / `FrontmostAppCommandCatalog`）里抽取出来的能力，只保留对 agent 有实际价值的部分。

---

## 为什么需要它

有了 Computer Use 之后，「怎么操作电脑」已经解决：点击、拖拽、输入、截图、AX 树、`invoke_menu` 都有。

但缺了一层——**发现**。

| 能力 | Computer Use | aether-menu |
|---|---|---|
| 执行某个已知菜单路径 | ✅ `invoke_menu(["File","Save"])` | — |
| 列出某 App 有哪些命令 | ❌ | ✅ `list` |
| 「保存」→ `File > Save`（跨语言/口语） | ❌ | ✅ `match` |
| 命令对应的快捷键 | ❌（要自己看 AX 树） | ✅ 直接给出 `cmd+s` |

agent 面对一个没见过的 App 时，现在只能截图 + 视觉猜菜单在哪；有了这一层，可以先问「这个 App 能干什么」，再决定执行哪个。

**边界**：本工具负责「发现 + 解析」，不负责「激活窗口 / 合成按键」。执行交给 Computer Use 的 `hotkey` / `invoke_menu`，避免重复造轮子。`exec` 是便利入口，仅在目标 App 已激活且菜单可用时可靠（见「已知限制」）。

---

## 构建

```bash
cd app/Tools/aether-menu
swift build -c release --disable-sandbox
# 产物：.build/release/aether-menu
```

`--disable-sandbox` 是给受限沙盒环境用的；正常机器上直接 `swift build -c release` 即可。

安装到 PATH：

```bash
cp .build/release/aether-menu /usr/local/bin/
```

需要**辅助功能（Accessibility）权限**。首次运行会触发系统授权对话框；若没有弹窗，到
「系统设置 → 隐私与安全性 → 辅助功能」里手动勾选调用它的终端/进程。

---

## 用法

`--app` 接受 bundle id、PID、显示名或常见别名，例如
`--app com.apple.finder`、`--app 38071`、`--app 访达`、`--app Finder` 都指向同一个 App。

### 1. 看有哪些可操作的应用

```bash
$ aether-menu apps
访达	com.apple.finder	pid=38071
Google Chrome	com.google.Chrome	pid=14079
ChatGPT	com.openai.codex	pid=13669
```

### 2. 列出某个 App 的全部菜单命令

```bash
$ aether-menu list --app Finder
访达 | 167 条命令
  文件 > 新建文件夹  [shift+cmd+n]
  文件 > 打开  [cmd+o]
  文件 > 显示简介  [cmd+i]
  编辑 > 撤销拷贝“DSH NEXT.app”  [cmd+z]
  显示 > 进入全屏幕  [f]
  ...
```

`--json` 输出结构化数据，字段：

```json
[
  {
    "path": ["文件", "新建文件夹"],
    "title": "新建文件夹",
    "shortcut": "shift+cmd+n",
    "enabled": false,
    "bundleIdentifier": "com.apple.finder",
    "processIdentifier": 38071
  }
]
```

> `shortcut` 为 `null` 时字段会省略（Optional 编码行为），取值时用 `c.get('shortcut')`。

### 3. 用一句自然语言找到命令

```bash
$ aether-menu match 清空废纸篓 --app Finder
查询「清空废纸篓」@ 访达｜候选 167 条｜命中 2 条
  1.00  访达 > 清倒废纸篓  [opt+shift+cmd+delete]  <concept:emptyTrash>
  1.00  访达 > 清倒废纸篓…  [shift+cmd+delete]  <concept:emptyTrash>
```

注意这里的关键点：**用户说「清空」，菜单写「清倒」**——纯字符串匹配会 0 命中，靠概念同义词表命中。

其他实测例子：

```bash
$ aether-menu match "empty trash" --app Finder     # 英文 → 中文菜单
  1.00  访达 > 清倒废纸篓  [opt+shift+cmd+delete]

$ aether-menu match "get info" --app Finder         # 英文 → 显示简介
  0.98  文件 > 显示简介  [cmd+i]

$ aether-menu match xjwjj --app Finder              # 拼音首字母
  0.69  文件 > 新建文件夹  [shift+cmd+n]

$ aether-menu match xinjianwenjianjia --app Finder  # 全拼
  0.90  文件 > 新建文件夹  [shift+cmd+n]
```

### 4. 直接执行（便利入口）

```bash
$ aether-menu exec 显示简介 --app Finder --dry-run   # 只解析
$ aether-menu exec 显示简介 --app Finder             # AXPress 执行
```

`exec` 走 `AXPress`（不合成按键），所以没有快捷键的命令也能执行。

---

## 匹配打分的台阶

| 分数 | 含义 | 例子 |
|---|---|---|
| 1.00 | 规范化后完全相等 | 「新建文件夹」→ `新建文件夹` |
| 0.94 | 概念相同（跨语言/同义词） | 「清空废纸篓」→ `清倒废纸篓…` |
| 0.90 | 前缀匹配 | 「新建」→ `新建访达窗口` |
| 0.84 | 词边界包含 | — |
| 0.78 | 包含 | — |
| 0.70 | 全拼包含 | `xinjianwenjianjia` |
| 0.62 / 0.58 | 拼音首字母 | `xjwjj` |
| 0.45 | 子序列 | — |

之后叠加微调：

- 可点击 `+0.04`、有快捷键 `+0.03`
- 层级越浅越优先（`+0.015 × (3 - depth)`）
- 标题长度与查询接近 `+0.03`；差 6 字以上 `-0.04`
- 动态菜单项（含 `“实体名”`）`-0.12`
- Apple 菜单里的系统命令 `-0.10`

置信度分档：`≥0.85` 高（可直接执行）、`0.60–0.85` 中（建议确认）、`<0.60` 低（别执行）。

---

## 给 agent 的典型调用姿势

```bash
# 1. 先发现：这个 App 能做什么
aether-menu list --app Safari --json

# 2. 再解析：把意图映射成快捷键
SHORTCUT=$(aether-menu match "新建标签页" --app Safari --json \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['shortcut'])")

# 3. 最后执行：交给 Computer Use 的 hotkey
#    （hotkey 会处理激活窗口，比本工具的 exec 更可靠）
```

`match --json` 输出：

```json
{
  "query": "清空废纸篓",
  "app": "访达",
  "bundleIdentifier": "com.apple.finder",
  "candidateCount": 167,
  "results": [
    {
      "path": ["访达", "清倒废纸篓"],
      "title": "清倒废纸篓",
      "shortcut": "opt+shift+cmd+delete",
      "enabled": true,
      "score": 1.0,
      "reason": "concept:emptyTrash",
      "confidence": "high"
    }
  ]
}
```

---

## 已知限制（实测）

1. **`enabled` 不可靠**。App 未聚焦时大量菜单项报 `false`；Chromium / Electron 系
   （Chrome、ChatGPT、VS Code）即使在前台，菜单项也可能一律报 `false`（惰性校验）。
   → 不要把 `enabled=false` 当成「不能执行」的硬结论。

2. **快捷键位掩码在新系统上有未知位**。虽然 `AXMenuItemCmdModifiers` 的语义是
   `0=⌘ / 1=⇧ / 2=⌥ / 4=⌃ / 8=无⌘`（与 Aether 线上代码一致），但 macOS 26/27 上
   会看到 `24`、`28` 这类含未定义位（`16`）的值，解出来可能是错的（例如 Finder 的
   「进入全屏幕」被解成 `f`）。
   → **执行时优先 `invoke_menu` 按路径点，或 `exec` 走 AXPress**；把 `shortcut` 当参考。

3. **后台 AXPress 常常不行**。菜单项处于 disabled 时 `AXPress` 返回失败。
   → `exec` 需要目标 App 已激活；由 agent 侧负责激活更稳妥。

4. **噪音**。默认已过滤：Apple 菜单降权、「服务」子菜单、最近使用、窗口菜单里的
   动态窗口标题。要全量看用 `--all`。

5. **性能**。每次调用重新遍历菜单树：Finder ≈ 80ms / 167 条，Chrome ≈ 100ms / 388 条。
   高频循环里建议一次 `list --json` 缓存后再本地匹配。

---

## 代码结构

```
Sources/AetherMenuKit/
  MenuCommand.swift    数据模型（Codable，可直接喂给 agent）
  MenuCatalog.swift    AX 菜单树遍历 + 噪音过滤 + 快捷键解析
  AX.swift             AX 属性读取封装（属性名用字符串字面量，绕开编译期常量推断问题）
  MenuConcept.swift    跨语言/口语概念同义词表（本工具的核心资产）
  MenuText.swift       规范化 + 拼音（全拼 / 首字母）+ 子序列
  MenuMatcher.swift    打分与排序
  MenuExecutor.swift   AXPress 执行
Sources/AetherMenuCLI/
  main.swift           apps / list / match / exec
Tests/AetherMenuTests/
  MenuMatcherTests.swift   23 个用例，覆盖规范化、概念、拼音、打分、快捷键解码
```

跑测试：

```bash
swift test --disable-sandbox
```

---

## 扩展同义词表

用户吐槽最多的是「我说的和菜单写的不一样」。加词只需改
[`MenuConcept.swift`](Sources/AetherMenuKit/MenuConcept.swift) 的 `all` 数组：

```swift
Concept(id: "emptyTrash", terms: ["清倒废纸篓", "清空废纸篓", "清倒垃圾箱", "empty trash"]),
```

规则：同一个概念下的说法会被视为等价；判定时取**最长命中词**，所以故意把更具体的
说法（`新建文件夹`）和更泛的说法（`新建`）放在不同概念里，避免互相抢占。
