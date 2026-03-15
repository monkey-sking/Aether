import AppKit
import CoreGraphics
import Foundation
import os.log

protocol AutomationOutput {
    var isDraggingActive: Bool { get }
    func moveCursor(to point: CGPoint, desktopMaxY: CGFloat)
    func mouseClick(at point: CGPoint, button: CGMouseButton, clickCount: Int)
    func pasteText(_ text: String)
    func undo()
    func pasteFromClipboard()
    func pressShortcut(_ binding: HotkeyBinding, targetPID: pid_t?)
    func scroll(dx: Int, dy: Int)
    func drag(start: Bool, at point: CGPoint?)
    func backspace(count: Int, targetPID: pid_t?)
    func typeText(_ text: String, targetPID: pid_t?)
}

final class OutputRouting: ObservableObject {
    static let shared = OutputRouting()

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
    private var isDragging: Bool = false
    private let mouseSource = CGEventSource(stateID: .combinedSessionState)
    private var lastPostedMouseLocation: CGPoint?
    private var lastProgrammaticMoveAt: Date = .distantPast
    private var dragEventTap: CFMachPort?
    private var dragEventTapRunLoopSource: CFRunLoopSource?
    private let dragSyntheticEventMarker: Int64 = 0xA37E42

    var isDraggingActive: Bool { isDragging }

    deinit {
        teardownSyntheticDragEventTap()
    }

    private func postKeyboardEvent(_ event: CGEvent?, targetPID: pid_t?) {
        guard let event else { return }
        if let targetPID, targetPID > 0 {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    func moveCursor(to point: CGPoint, desktopMaxY: CGFloat) {
        let cgPoint = CGPoint(x: point.x, y: desktopMaxY - point.y)
        lastProgrammaticMoveAt = Date()
        let mouseType: CGEventType = isDragging ? .leftMouseDragged : .mouseMoved
        let tap: CGEventTapLocation = isDragging ? .cghidEventTap : .cgSessionEventTap
        if !isDragging {
            CGWarpMouseCursorPosition(cgPoint)
        }
        if let event = CGEvent(mouseEventSource: mouseSource, mouseType: mouseType, mouseCursorPosition: cgPoint, mouseButton: .left) {
            if isDragging {
                event.setDoubleValueField(.mouseEventPressure, value: 1.0)
                applyMouseDelta(to: event, currentLocation: cgPoint)
            }
            event.post(tap: tap)
            lastPostedMouseLocation = cgPoint
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

    func pressShortcut(_ binding: HotkeyBinding, targetPID: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let flags = CGEventFlags(rawValue: binding.modifiers)
        let keyCode = CGKeyCode(binding.keyCode)

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        postKeyboardEvent(down, targetPID: targetPID)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        postKeyboardEvent(up, targetPID: targetPID)
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
        if start, isDragging {
            return
        }

        var loc = point
        if loc == nil {
            loc = CGEvent(source: nil)?.location
        }
        guard let pos = loc else { return }

        let type: CGEventType = start ? .leftMouseDown : .leftMouseUp
        if let event = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: pos, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            if start {
                event.setDoubleValueField(.mouseEventPressure, value: 1.0)
            }
            event.setIntegerValueField(.eventSourceUserData, value: dragSyntheticEventMarker)
            event.post(tap: .cghidEventTap)
            lastPostedMouseLocation = pos
            if start {
                isDragging = true
                installSyntheticDragEventTapIfNeeded()
                postSyntheticDraggedEvent(at: pos)
            } else {
                isDragging = false
                teardownSyntheticDragEventTap()
            }
        }
    }

    private func installSyntheticDragEventTapIfNeeded() {
        guard shouldUsePhysicalMouseDragContinuation() else {
            teardownSyntheticDragEventTap()
            return
        }
        guard dragEventTap == nil, dragEventTapRunLoopSource == nil else { return }

        let install = { [weak self] in
            guard let self else { return }
            guard self.dragEventTap == nil, self.dragEventTapRunLoopSource == nil else { return }

            var mask: CGEventMask = 0
            mask |= (1 << CGEventType.mouseMoved.rawValue)
            mask |= (1 << CGEventType.leftMouseDragged.rawValue)
            mask |= (1 << CGEventType.otherMouseDragged.rawValue)

            func callback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let output = Unmanaged<CoreGraphicsAutomationOutput>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = output.dragEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard output.isDragging else { return Unmanaged.passUnretained(event) }
                guard output.shouldUsePhysicalMouseDragContinuation() else { return Unmanaged.passUnretained(event) }
                guard event.getIntegerValueField(.eventSourceUserData) != output.dragSyntheticEventMarker else {
                    return Unmanaged.passUnretained(event)
                }

                event.type = .leftMouseDragged
                event.setDoubleValueField(.mouseEventPressure, value: 1.0)
                output.applyMouseDelta(to: event, currentLocation: event.location)
                output.lastPostedMouseLocation = event.location
                return Unmanaged.passUnretained(event)
            }

            let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: unsafeSelf
            ) else {
                os_log("Failed to create drag event tap", type: .error)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.dragEventTap = tap
            self.dragEventTapRunLoopSource = source
        }

        if Thread.isMainThread {
            install()
        } else {
            DispatchQueue.main.async(execute: install)
        }
    }

    private func teardownSyntheticDragEventTap() {
        let teardown = {
            if let tap = self.dragEventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
                self.dragEventTap = nil
            }
            if let source = self.dragEventTapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                self.dragEventTapRunLoopSource = nil
            }
        }

        if Thread.isMainThread {
            teardown()
        } else {
            DispatchQueue.main.async(execute: teardown)
        }
    }

    private func postSyntheticDraggedEvent(at point: CGPoint) {
        guard isDragging else { return }
        guard let event = CGEvent(
            mouseEventSource: mouseSource,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        event.setDoubleValueField(.mouseEventPressure, value: 1.0)
        event.setIntegerValueField(.eventSourceUserData, value: dragSyntheticEventMarker)
        applyMouseDelta(to: event, currentLocation: point)
        event.post(tap: .cghidEventTap)
        lastPostedMouseLocation = point
    }

    private func shouldUsePhysicalMouseDragContinuation() -> Bool {
        !HeadMotionManager.shared.isTracking
    }

    private func applyMouseDelta(to event: CGEvent, currentLocation: CGPoint) {
        let previous = lastPostedMouseLocation ?? currentLocation
        let deltaX = Int64((currentLocation.x - previous.x).rounded())
        // CG dragged events expect positive deltaY for upward movement, which is
        // the inverse of the screen-space Y coordinates we use here.
        let deltaY = Int64((previous.y - currentLocation.y).rounded())
        event.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
        event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
    }

    func backspace(count: Int, targetPID: pid_t?) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let deleteKey: CGKeyCode = 51

        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true)
            postKeyboardEvent(down, targetPID: targetPID)
            let up = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false)
            postKeyboardEvent(up, targetPID: targetPID)
        }
    }

    func typeText(_ text: String, targetPID: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Split text into lines if needed, or handle as a single block
        // CGEvent(keyboardEventSource:...) with unicode string is the most reliable "zero-clipboard" method
        for char in text.utf16 {
            let key: CGKeyCode = 0 
            
            if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
                var unit = char
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                postKeyboardEvent(down, targetPID: targetPID)
            }
            
            if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                var unit = char
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                postKeyboardEvent(up, targetPID: targetPID)
            }
        }
    }
}

enum AutomationOutputs {
    static var shared: AutomationOutput = PreferredAutomationOutput()
}

final class PreferredAutomationOutput: AutomationOutput {
    private let fallback = CoreGraphicsAutomationOutput()

    var isDraggingActive: Bool { fallback.isDraggingActive }

    func moveCursor(to point: CGPoint, desktopMaxY: CGFloat) {
        fallback.moveCursor(to: point, desktopMaxY: desktopMaxY)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics")
    }

    func mouseClick(at point: CGPoint, button: CGMouseButton, clickCount: Int) {
        fallback.mouseClick(at: point, button: button, clickCount: clickCount)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics")
    }

    func pasteText(_ text: String) {
        // Driver path not implemented yet (keyboard injection); keep fallback.
        fallback.pasteText(text)
        OutputRouting.shared.setTextOutputPath("CoreGraphics")
    }

    func typeText(_ text: String, targetPID: pid_t?) {
        fallback.typeText(text, targetPID: targetPID)
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

    func pressShortcut(_ binding: HotkeyBinding, targetPID: pid_t?) {
        fallback.pressShortcut(binding, targetPID: targetPID)
        OutputRouting.shared.setTextOutputPath("CoreGraphics")
    }

    func scroll(dx: Int, dy: Int) {
        fallback.scroll(dx: dx, dy: dy)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics (Scroll)")
    }
    
    func drag(start: Bool, at point: CGPoint?) {
        fallback.drag(start: start, at: point)
        OutputRouting.shared.setPointerOutputPath("CoreGraphics (Drag)")
    }
    
    func backspace(count: Int, targetPID: pid_t?) {
        fallback.backspace(count: count, targetPID: targetPID)
        OutputRouting.shared.setTextOutputPath("CoreGraphics")
    }
}
