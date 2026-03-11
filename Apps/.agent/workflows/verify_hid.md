---
description: 验证虚拟 HID 设备 (鼠标/触控板) 是否工作正常
---

# Verify Virtual HID Skill

本技能用于验证 AetherDriver 是否成功创建了虚拟设备，并能响应输入。

## 1. 检查 IORegistry
使用 `ioreg` 确认设备是否存在：

```bash
ioreg -l | grep "AetherVirtualMouse"
```

## 2. 也是用 IOHIDUserClient 调试
使用 Apple 的 `hidutil` 工具监控输入报告：

```bash
# 列出所有 HID 设备
hidutil list

# 监听特定设备的 Report (替换 DeviceID)
hidutil dump -d <DeviceID>
```

## 3. 自动化测试脚本 (Python)
(Todo: 创建 `scripts/test_mouse_move.py` 模拟 IPC 发送)

```python
# 伪代码示例
import aether_ipc
mouse = aether_ipc.connect()
mouse.move(x=10, y=10)
```
