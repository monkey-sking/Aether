import AppKit
import CoreGraphics
import Foundation
import os.log

protocol AutomationOutput {
    func moveCursor(to point: CGPoint, desktopMaxY: CGFloat)
    func mouseClick(at point: CGPoint, button: CGMouseButton, clickCount: Int)
    func pasteText(_ text: String)
    func undo()
    func pasteFromClipboard()
    func scroll(dx: Int, dy: Int)
    func drag(start: Bool, at point: CGPoint?)
    func backspace(count: Int)
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
            
            if mouseDown == nil || mouseUp == nil {
                os_log("CoreGraphics Error: Failed to create mouse events at (%.1f, %.1f)", type: .error, cgPoint.x, cgPoint.y)
            } else {
                mouseDown?.setIntegerValueField(.mouseEventClickState, value: 1)
                mouseUp?.setIntegerValueField(.mouseEventClickState, value: 1)
                mouseDown?.post(tap: .cghidEventTap)
                mouseUp?.post(tap: .cghidEventTap)
                // We cannot verify success of post(), but assume it worked if event created.
            }
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

    func pasteFromClipboard() {
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

    func scroll(dx: Int, dy: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // scrollWheel event: arg1=line height (y), arg2=line width (x), but unit is vague.
        // Usually wheel1 is Y (negative down?), wheel2 is X.
        // CGEvent(scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:)
        // Units: .line (classic scroll) or .pixel (smooth scroll)
        
        let event = CGEvent(scrollWheelEvent2Source: source,
                            units: .pixel,
                            wheelCount: 2,
                            wheel1: Int32(dy * -1), // Invert Y for natural scrolling typically? or not?
                            // Standard: Positive deltaY is up (scrolling up content, viewing higher).
                            // If user says "Scroll Down", they want to see lower content -> deltaY should be negative?
                            // Wait, macOS scroll direction "Natural" inverts this.
                            // Let's assume standard mouse wheel: "Down" = negative delta.
                            // Let's verify: CGEvent scroll wheel1 is Y. Negative value scrolls down (content moves up).
                            
                            // user says "Scroll Down" (dy=300).
                            // We want to send negative Y delta.
                            // So wheel1 = -dy.
                            wheel2: Int32(dx), // X
                            wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    func drag(start: Bool, at point: CGPoint?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // For drag, we just simulate left button down or up at current location
        
        var loc = point
        if loc == nil {
            loc = CGEvent(source: nil)?.location
        }
        guard let pos = loc else { return }

        let type: CGEventType = start ? .leftMouseDown : .leftMouseUp
        if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: pos, mouseButton: .left) {
            // Dragging often requires specific click state, but just Down/Up is usually enough
            if !start {
                event.setIntegerValueField(.mouseEventClickState, value: 1) // Click count 1 on release
            }
            event.post(tap: .cghidEventTap)
        }
    }

    func backspace(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let deleteKey: CGKeyCode = 51

        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
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

    func pasteFromClipboard() {
        fallback.pasteFromClipboard()
        OutputRouting.shared.setTextOutputPath("CoreGraphics")
    }

    func scroll(dx: Int, dy: Int) {
        // Driver not implemented for scroll yet.
        fallback.scroll(dx: dx, dy: dy)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics (Scroll)")
    }
    
    func drag(start: Bool, at point: CGPoint?) {
        // Driver not implemented for drag (button hold) specifically exposed yet, 
        // though it has "updateButtonState".
        // Use fallback for safety for now.
        fallback.drag(start: start, at: point)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics (Drag)")
    }
    
    func backspace(count: Int) {
        fallback.backspace(count: count)
        OutputRouting.shared.setTextOutputPath("CoreGraphics")
    }
}
