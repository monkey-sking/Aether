---
name: SwiftUI Liquid Glass Design
description: 如何在 SwiftUI 中实现 macOS 2025/2026 的 Liquid Glass 视觉语言
---

# SwiftUI Liquid Glass Design Skill

本 skill 指导如何在 ProcessZero 项目中实现符合 macOS Tahoe 的 Liquid Glass 设计风格。

## 设计理念

Liquid Glass 是超越传统"毛玻璃" (Frosted Glass) 的新材质，强调：

- **光线折射**: 界面元素产生真实的光线折射效果
- **流动性**: 动态的光影流动效果
- **深度感**: 多层级的材质通透度

## 核心技术实现

### 1. 材质层级

```swift
import SwiftUI

// 基础 Liquid Glass 材质
struct LiquidGlassModifier: ViewModifier {
    var intensity: Double = 0.8

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background {
                VisualEffectBlur(
                    material: .hudWindow,
                    blendingMode: .withinWindow,
                    state: .active
                )
            }
            .overlay {
                // 动态光照层
                LinearGradient(
                    colors: [
                        .white.opacity(0.15),
                        .clear,
                        .white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func liquidGlass(intensity: Double = 0.8) -> some View {
        modifier(LiquidGlassModifier(intensity: intensity))
    }
}
```

### 2. AppKit 视觉效果桥接

```swift
import AppKit
import SwiftUI

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
```

### 3. 层级规范

| 层级   | 材质                          | 用途               |
| ------ | ----------------------------- | ------------------ |
| 控制层 | `.ultraThinMaterial` + 高模糊 | MenuBar Panel, HUD |
| 内容层 | `.thinMaterial`               | 卡片、列表项       |
| 背景层 | `.regularMaterial`            | 设置页面背景       |

## 菜单栏窗口实现

```swift
@main
struct ProcessZeroApp: App {
    var body: some Scene {
        MenuBarExtra("ProcessZero", systemImage: "sparkles") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 320, height: 500)
    }
}

struct MenuBarContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            AppListView()
            BottomBarView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass()
    }
}
```

## 动效规范

### 弹簧阻尼动画

```swift
// 系统级弹簧动画
.animation(.spring(response: 0.35, dampingFraction: 0.7), value: isExpanded)

// 轻量交互反馈
.animation(.easeInOut(duration: 0.15), value: isHovered)
```

### 悬停效果

```swift
struct HoverableCard: View {
    @State private var isHovered = false

    var body: some View {
        content
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .brightness(isHovered ? 0.05 : 0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}
```

## 参考资源

- [Liquid Glass in Swift: Official Best Practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [LiquidGlassReference GitHub](https://github.com/conorluddy/LiquidGlassReference)
- [Apple HIG - Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

## 检查清单

使用此 skill 时，确保：

- [ ] 使用 `.ultraThinMaterial` 或更高强度材质
- [ ] Blur Radius > 40px
- [ ] 添加动态光照渐变层
- [ ] 使用 `continuous` 圆角样式
- [ ] 实现悬停状态变化
- [ ] 所有动画使用弹簧阻尼
