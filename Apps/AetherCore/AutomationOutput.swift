import AppKit
import CoreGraphics
import Foundation

protocol AutomationOutput {
    func moveCursor(to point: CGPoint, desktopMaxY: CGFloat)
    func mouseClick(at point: CGPoint, button: CGMouseButton, clickCount: Int)
    func pasteText(_ text: String)
    func undo()
}

final class OutputRouting: ObservableObject {
    static let shared = OutputRouting()

    @Published var forceDriverOnly: Bool = false
    @Published private(set) var pointerOutputPath: String = "Idle"
    @Published private(set) var textOutputPath: String = "CoreGraphics"

    func setPointerOutputPath(_ value: String) {
        if Thread.isMainThread {
            pointerOutputPath = value
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.pointerOutputPath = value
            }
        }
    }

    func setTextOutputPath(_ value: String) {
        if Thread.isMainThread {
            textOutputPath = value
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.textOutputPath = value
            }
        }
    }
}

final class CoreGraphicsAutomationOutput: AutomationOutput {
    func moveCursor(to point: CGPoint, desktopMaxY: CGFloat) {
        let cgPoint = CGPoint(x: point.x, y: desktopMaxY - point.y)
        CGWarpMouseCursorPosition(cgPoint)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left) {
            event.post(tap: .cgSessionEventTap)
        }
    }

    func mouseClick(at point: CGPoint, button: CGMouseButton, clickCount: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cgPoint = point

        let mouseTypeDown: CGEventType = (button == .right) ? .rightMouseDown : .leftMouseDown
        let mouseTypeUp: CGEventType = (button == .right) ? .rightMouseUp : .leftMouseUp

        if clickCount >= 2 {
            var events: [CGEvent?] = []
            for _ in 0..<clickCount {
                events.append(CGEvent(mouseEventSource: source, mouseType: mouseTypeDown, mouseCursorPosition: cgPoint, mouseButton: button))
                events.append(CGEvent(mouseEventSource: source, mouseType: mouseTypeUp, mouseCursorPosition: cgPoint, mouseButton: button))
            }
            for (idx, event) in events.enumerated() {
                event?.setIntegerValueField(.mouseEventClickState, value: Int64((idx / 2) + 1))
                event?.post(tap: .cghidEventTap)
            }
        } else {
            let mouseDown = CGEvent(mouseEventSource: source, mouseType: mouseTypeDown, mouseCursorPosition: cgPoint, mouseButton: button)
            let mouseUp = CGEvent(mouseEventSource: source, mouseType: mouseTypeUp, mouseCursorPosition: cgPoint, mouseButton: button)
            mouseDown?.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseUp?.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseDown?.post(tap: .cghidEventTap)
            mouseUp?.post(tap: .cghidEventTap)
        }
    }

    func pasteText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 55
        let vKey: CGKeyCode = 9

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }

    func undo() {
        // Cmd+Z
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 55
        let zKey: CGKeyCode = 6

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        let zDown = CGEvent(keyboardEventSource: source, virtualKey: zKey, keyDown: true)
        zDown?.flags = .maskCommand
        zDown?.post(tap: .cghidEventTap)

        let zUp = CGEvent(keyboardEventSource: source, virtualKey: zKey, keyDown: false)
        zUp?.flags = .maskCommand
        zUp?.post(tap: .cghidEventTap)

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }
}

enum AutomationOutputs {
    static var shared: AutomationOutput = PreferredAutomationOutput()
}

final class PreferredAutomationOutput: AutomationOutput {
    private let fallback = CoreGraphicsAutomationOutput()
    private let driver = DriverAutomationOutput()

    func moveCursor(to point: CGPoint, desktopMaxY: CGFloat) {
        if OutputRouting.shared.forceDriverOnly {
            if driver.moveCursor(to: point) {
                OutputRouting.shared.setPointerOutputPath("DriverKit")
            } else {
                OutputRouting.shared.setPointerOutputPath("DriverKit (Unavailable)")
            }
            return
        }

        if driver.moveCursor(to: point) {
            OutputRouting.shared.setPointerOutputPath("DriverKit")
            return
        }
        fallback.moveCursor(to: point, desktopMaxY: desktopMaxY)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics")
        driver.resetRelativeOrigin(to: point)
    }

    func mouseClick(at point: CGPoint, button: CGMouseButton, clickCount: Int) {
        if OutputRouting.shared.forceDriverOnly {
            if button == .left, driver.mouseClick(clickCount: clickCount) {
                OutputRouting.shared.setPointerOutputPath("DriverKit")
            } else {
                OutputRouting.shared.setPointerOutputPath("DriverKit (Unavailable)")
            }
            return
        }

        // Driver MVP: only supports left click.
        if button == .left, driver.mouseClick(clickCount: clickCount) {
            OutputRouting.shared.setPointerOutputPath("DriverKit")
            return
        }
        fallback.mouseClick(at: point, button: button, clickCount: clickCount)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics")
    }

    func pasteText(_ text: String) {
        // Driver path not implemented yet (keyboard injection); keep fallback.
        fallback.pasteText(text)
        OutputRouting.shared.setTextOutputPath("CoreGraphics")
    }

    func undo() {
        // Driver path not implemented yet (keyboard injection); keep fallback.
        fallback.undo()
        OutputRouting.shared.setTextOutputPath("CoreGraphics")
    }
}
