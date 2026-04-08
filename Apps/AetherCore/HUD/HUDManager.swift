import SwiftUI
import AppKit
import Combine
import ApplicationServices
import OSLog
import CoreText

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ displayUUID: CFString) -> UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: Int32, _ displayUUID: CFString) -> CFArray

fileprivate let log = OSLog(subsystem: "com.7fei.Aether", category: "HUDManager")

/* Private CoreGraphics API to check cursor visibility */
@_silgen_name("CGCursorIsVisible")
func CGCursorIsVisible() -> Bool

struct AXFocusedTypingEvaluation {
    let editableLikely: Bool
    let insertionContextAvailable: Bool
    let looselyEditableForWeb: Bool
    let role: String
    let hasEditableAttribute: Bool
    let hasSettableValue: Bool
    let hasEditableAncestor: Bool

    static let unavailable = AXFocusedTypingEvaluation(
        editableLikely: false,
        insertionContextAvailable: false,
        looselyEditableForWeb: false,
        role: "",
        hasEditableAttribute: false,
        hasSettableValue: false,
        hasEditableAncestor: false
    )
}

struct RecentMouseDownAnchor {
    let point: CGPoint
    let timestamp: Date
    let bundleID: String?
}

private final class CaretDebugDotView: NSView {
    static let dotSize: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.cornerRadius = Self.dotSize / 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isOpaque: Bool { false }

    func updateColor(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
    }
}

enum AXFocusedTypingContextDetector {
    static func evaluate(
        focusedRect: CGRect?,
        caretRect: CGRect?,
        frontmostBundleID: String?,
        isWholeWindowRect: (CGRect) -> Bool,
        isTypingBoxSizedRect: (CGRect) -> Bool,
        isWebInputSizedRect: (CGRect) -> Bool
    ) -> AXFocusedTypingEvaluation {
        guard let element = focusedElement() else { return .unavailable }

        let role = stringAttr(element, kAXRoleAttribute as CFString) ?? ""
        let isSemanticControlRole = semanticControlRoles.contains(role)
        let hasEditableAttribute = boolAttr(element, "AXEditable" as CFString) == true
        let hasSettableValue = valueAttributeIsSettable(element)
        let hasEditableAncestor = editableAncestor(for: element) != nil
        let hasInsertionContextOnFocus = hasInsertionContext(element)
        let allowWebInputSizedRects = HUDManager.shouldUseWebInputSizedRectHeuristics(bundleID: frontmostBundleID)
        let focusedRectLooksLikeInput = {
            guard let focusedRect, !isWholeWindowRect(focusedRect) else { return false }
            if isTypingBoxSizedRect(focusedRect) { return true }
            return allowWebInputSizedRects && isWebInputSizedRect(focusedRect)
        }()
        let hasStrongInsertionEvidenceOnFocus = hasInsertionContextOnFocus && (caretRect != nil || focusedRectLooksLikeInput)
        let editableEvidence = hasEditableAttribute || hasSettableValue || hasEditableAncestor
        let insertionContextAvailable = {
            guard hasInsertionContextOnFocus else { return false }
            if isSemanticControlRole {
                return hasEditableAttribute || hasSettableValue
            }
            if containerLikeRoles.contains(role) {
                if caretRect != nil { return true }
                return focusedRectLooksLikeInput
            }
            return true
        }()

        let editableLikely: Bool = {
            if isSemanticControlRole {
                return hasEditableAttribute || hasSettableValue
            }
            if insertionContextAvailable && editableEvidence {
                return true
            }
            if directEditableRoles.contains(role) { return true }
            if role == kAXTextAreaRole as String {
                return hasInsertionContextOnFocus || hasEditableAncestor || hasSettableValue
            }
            if role == "AXWebArea" {
                if hasStrongInsertionEvidenceOnFocus { return true }
                if editableEvidence && focusedRectLooksLikeInput { return true }
                if isWeirdWebTypingApp(bundleID: frontmostBundleID),
                   focusedRectLooksLikeInput,
                   (insertionContextAvailable || editableEvidence) {
                    return true
                }
                return false
            }
            if groupLikeRoles.contains(role) {
                if hasStrongInsertionEvidenceOnFocus { return true }
                if focusedRectLooksLikeInput && (hasEditableAncestor || hasEditableDescendant(element)) { return true }
                if editableEvidence && focusedRectLooksLikeInput { return true }
                return false
            }
            if hasInsertionContextOnFocus {
                if role == "AXStaticText" {
                    return hasStrongInsertionEvidenceOnFocus || hasEditableAncestor
                }
                return true
            }
            return editableEvidence
        }()

        let looselyEditableForWeb: Bool = {
            if isSemanticControlRole { return false }
            if directEditableRoles.contains(role) || role == kAXTextAreaRole as String { return true }
            guard containerLikeRoles.contains(role),
                  focusedRectLooksLikeInput else {
                return false
            }
            return insertionContextAvailable || editableEvidence
        }()

        return AXFocusedTypingEvaluation(
            editableLikely: editableLikely,
            insertionContextAvailable: insertionContextAvailable,
            looselyEditableForWeb: looselyEditableForWeb,
            role: role,
            hasEditableAttribute: hasEditableAttribute,
            hasSettableValue: hasSettableValue,
            hasEditableAncestor: hasEditableAncestor
        )
    }

    private static let directEditableRoles: Set<String> = [
        kAXTextFieldRole as String,
        "AXSearchField",
        "AXComboBox",
        "AXHTMLTextInput"
    ]

    private static let semanticControlRoles: Set<String> = [
        "AXRadioButton",
        "AXButton",
        "AXLink"
    ]

    private static let groupLikeRoles: Set<String> = [
        "AXGroup",
        "AXScrollArea",
        "AXSplitGroup"
    ]

    private static let containerLikeRoles: Set<String> = groupLikeRoles.union([
        "AXWebArea",
        "AXStaticText"
    ])

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            return nil
        }
        return (focusedElement as! AXUIElement)
    }

    private static func boolAttr(_ element: AXUIElement, _ name: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    fileprivate static func stringAttr(_ element: AXUIElement, _ name: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? String
    }

    private static func uiElementAttr(_ element: AXUIElement, _ name: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func valueAttributeIsSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private static func hasInsertionContext(_ element: AXUIElement) -> Bool {
        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
           let selectedRangeValue,
           CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() {
            let ax = selectedRangeValue as! AXValue
            if AXValueGetType(ax) == .cfRange {
                var range = CFRange()
                if AXValueGetValue(ax, .cfRange, &range) {
                    if range.length == 0 { return true }
                } else {
                    return true
                }
            } else {
                return true
            }
        }

        var markerRangeValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success
    }

    private static func hasEditableDescendant(_ element: AXUIElement, depth: Int = 4) -> Bool {
        if depth <= 0 { return false }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }

        let conditionalRoles = [kAXTextAreaRole as String, "AXWebArea", "AXStaticText"]
        for child in children {
            let childRole = stringAttr(child, kAXRoleAttribute as CFString) ?? ""
            if directEditableRoles.contains(childRole) { return true }
            if conditionalRoles.contains(childRole),
               (boolAttr(child, "AXEditable" as CFString) == true || valueAttributeIsSettable(child) || hasInsertionContext(child)) {
                return true
            }
            if editableAncestor(for: child) != nil { return true }
            if hasInsertionContext(child) { return true }
            if hasEditableDescendant(child, depth: depth - 1) { return true }
        }
        return false
    }

    private static func editableAncestor(for element: AXUIElement, depth: Int = 6) -> AXUIElement? {
        for attr in ["AXEditableAncestor", "AXHighestEditableAncestor"] {
            if let ancestor = uiElementAttr(element, attr as CFString) {
                return ancestor
            }
        }

        var current = element
        for _ in 0..<depth {
            guard let parent = uiElementAttr(current, kAXParentAttribute as CFString) else { break }
            let role = stringAttr(parent, kAXRoleAttribute as CFString) ?? ""
            if boolAttr(parent, "AXEditable" as CFString) == true ||
                valueAttributeIsSettable(parent) ||
                hasInsertionContext(parent) ||
                directEditableRoles.contains(role) ||
                role == kAXTextAreaRole as String {
                return parent
            }
            current = parent
        }
        return nil
    }

    private static func isWeirdWebTypingApp(bundleID: String?) -> Bool {
        HUDManager.isWeirdWebTypingAppBundleIdentifier(bundleID)
    }

}

final class HUDManager {
    static let shared = HUDManager()
    static let typingContextSuppressedByNonInputClickNotification =
        Notification.Name("AetherTypingContextSuppressedByNonInputClick")

    static func isBrowserLikeBundleIdentifier(_ bundleID: String?) -> Bool {
        let bundleID = (bundleID ?? "").lowercased()
        guard !bundleID.isEmpty else { return false }
        return bundleID.contains("safari")
            || bundleID.contains("chrome")
            || bundleID.contains("chromium")
            || bundleID.contains("brave")
            || bundleID.contains("arc")
            || bundleID.contains("firefox")
            || bundleID.contains("edge")
            || bundleID.contains("kagi")
    }

    static func isWeirdWebTypingAppBundleIdentifier(_ bundleID: String?) -> Bool {
        let bundle = (bundleID ?? "").lowercased()
        return bundle.contains("codex")
            || bundle.contains("antigravity")
            || bundle.contains("telegram")
            || bundle.contains("xinwechat")
            || bundle.contains("wechat")
    }

    static func shouldUseWebInputSizedRectHeuristics(bundleID: String?) -> Bool {
        isBrowserLikeBundleIdentifier(bundleID) || isWeirdWebTypingAppBundleIdentifier(bundleID)
    }

    static func shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: String?) -> Bool {
        let bundle = (bundleID ?? "").lowercased()
        return bundle.contains("codex")
            || bundle.contains("antigravity")
            || bundle.contains("telegram")
    }

    static func shouldAllowExplicitTypingReentryAfterFocusChange(
        sourceFingerprint: String?,
        sourceRect: CGRect?,
        currentFingerprint: String?,
        currentRect: CGRect?,
        clickPoint: CGPoint?,
        clickAge: TimeInterval
    ) -> Bool {
        guard clickAge < 1.6,
              let clickPoint,
              let currentRect else {
            return false
        }

        let expandedRect = currentRect.insetBy(dx: -24, dy: -24)
        guard expandedRect.contains(clickPoint) else { return false }

        if let sourceFingerprint,
           let currentFingerprint,
           sourceFingerprint == currentFingerprint {
            return false
        }

        if let sourceRect,
           rectsApproximatelyEqual(sourceRect, currentRect) {
            return false
        }

        return true
    }

    private static func rectsApproximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat = 14
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

    private struct HUDPresentationSnapshot {
        let mode: HUDMode
        let message: String
        let language: String
        let recognitionControlMode: HUDRecognitionControlMode
        let inputDeviceIcon: String
        let inputDeviceHealth: HUDInputDeviceHealth
        let contextIcon: String
    }

    struct MouseDownDiagnosticRecord {
        let timestamp: Date
        let point: CGPoint
        let bundleID: String?
        let preferredInputRect: CGRect?
        let hitPreferredInputRect: Bool
    }

    struct TypingSuppressionDiagnosticRecord {
        let timestamp: Date
        let suppressed: Bool
        let reason: String
        let bundleID: String?
        let suppressedUntil: Date
        let requiresExplicitTypingReentry: Bool
    }

    struct TypingSuppressionStateSnapshot {
        let requiresExplicitTypingReentry: Bool
        let explicitTypingReentryBundleID: String?
        let explicitTypingReentrySourceFingerprint: String?
        let explicitTypingReentrySourceRect: CGRect?
        let typingSuppressedUntil: Date
        let preferredExplicitTypingInputRect: CGRect?
    }

    struct DisplayStateSnapshot {
        let mode: HUDMode
        let isTypingContext: Bool
        let recognitionControlMode: HUDRecognitionControlMode
    }

    enum HUDUpdateLifetime {
        case persistent
        case temporary(UUID)
    }

    static func shouldRefreshTypingContextForDisplayUpdate(
        currentMode: HUDMode,
        nextMode: HUDMode,
        currentLanguage: String,
        nextLanguage: String,
        currentRecognitionControlMode: HUDRecognitionControlMode,
        nextRecognitionControlMode: HUDRecognitionControlMode,
        currentInputDeviceIcon: String,
        nextInputDeviceIcon: String,
        currentInputDeviceHealth: HUDInputDeviceHealth,
        nextInputDeviceHealth: HUDInputDeviceHealth,
        currentContextIcon: String,
        nextContextIcon: String,
        lifetime: HUDUpdateLifetime
    ) -> Bool {
        guard case .persistent = lifetime else { return true }
        return currentMode != nextMode
            || currentLanguage != nextLanguage
            || currentRecognitionControlMode != nextRecognitionControlMode
            || currentInputDeviceIcon != nextInputDeviceIcon
            || currentInputDeviceHealth != nextInputDeviceHealth
            || currentContextIcon != nextContextIcon
    }
    
    let state = HUDState()

    var isTemporaryHUDActive: Bool {
        activeTemporaryToken != nil
    }
    private let detector = CaretDetector()
    private var lastAXTypingEvaluationAt: Date = .distantPast
    private var cachedAXTypingEvaluation: AXFocusedTypingEvaluation = .unavailable
    private var lastAXFocusRectCheckAt: Date = .distantPast
    private var cachedAXFocusRect: CGRect?
    private var lastAXCaretRectCheckAt: Date = .distantPast
    private var cachedAXCaretRect: CGRect?
    private var lastAXLineRectCheckAt: Date = .distantPast
    private var cachedAXLineRect: CGRect?
    private var cachedAXLineRectCaretIndex: Int = -1
    private var lastAXEstimatedCaretCheckAt: Date = .distantPast
    private var cachedAXEstimatedCaretPoint: CGPoint?
    private var cachedAXEstimatedCaretBounds: CGRect?
    private var lastAXFocusDebugCheckAt: Date = .distantPast
    private var cachedAXFocusDebugSignature: String = "focus=nil"
    private var lastAnchorTraceAt: Date = .distantPast
    private var lastAnchorTraceSignature: String = ""
    private var lastFullscreenSuppressionCheckAt: Date = .distantPast
    private var cachedFullscreenSuppressionResult: Bool = false
    private var cachedFullscreenSuppressionBundleID: String = ""
    private let pointerFollowThrottleInterval: TimeInterval = 1.0 / 50.0
    private var lastPointerFollowAt: Date = .distantPast
    private var lastPointerMoveAt: Date = .distantPast
    private var typingMouseAvoidUntil: Date = .distantPast
    private var mouseAvoidLockUntil: Date = .distantPast
    private var mouseAvoidLockOrigin: CGPoint?
    private var lastGoodTypingRect: CGRect?
    private var lastGoodTypingRectAt: Date = .distantPast
    private var lastExplicitTypingInputRect: CGRect?
    private var lastExplicitTypingInputRectAt: Date = .distantPast
    private var lastExplicitTypingInputBundleID: String?
    private var lastInputInteractionPoint: CGPoint?
    private var lastInputInteractionAt: Date = .distantPast
    private var lastMouseDownPoint: CGPoint?
    private var lastMouseDownAt: Date = .distantPast
    private var lastMouseDownBundleID: String?
    private var lastMouseDownHitPreferredInputRect: Bool = false
    private var recentMouseDownDiagnostics: [MouseDownDiagnosticRecord] = []
    private var explicitTypingReentrySourceFingerprint: String?
    private var explicitTypingReentrySourceRect: CGRect?
    private var typingSuppressedUntil: Date = .distantPast
    private var requiresExplicitTypingReentry: Bool = false
    private var explicitTypingReentryBundleID: String?
    private var typingSuppressionDiagnostics: [TypingSuppressionDiagnosticRecord] = []
    private var hudWindow: NSPanel?
    private var caretDebugWindow: NSPanel?
    private var hideTask: DispatchWorkItem?
    private var languageIndicatorHideTask: DispatchWorkItem?
    private var pendingRepositionWorkItem: DispatchWorkItem?
    private var lastSmoothedWindowOrigin: CGPoint?
    private var lastPersistentSnapshot: HUDPresentationSnapshot?
    private var activeTemporaryToken: UUID?
    private var activeTemporaryFallbackSnapshot: HUDPresentationSnapshot?
    private var isDragStatusForced: Bool = false
    private var dragStatusFallbackSnapshot: HUDPresentationSnapshot?
    private var stickyMeasuredContentWidth: CGFloat?
    private var cancellables = Set<AnyCancellable>()
    private var backgroundFullscreenCheckTimer: Timer?
    private var appNapActivityToken: NSObjectProtocol?
    private var lastVisibilityDiagnosticAt: Date = .distantPast
    private var lastVisibilityDiagnosticSignature: String = ""
    
    private init() {
        os_log("HUDManager: init started", log: log, type: .default)
        setupSubscriptions()
        detector.start()
        startBackgroundFullscreenCheck()
    }

    private func currentTypingContextBundleID() -> String? {
        // Suppression/reentry state is app-scoped. Prefer the real frontmost app so
        // stale detector source bundles from the previous app cannot keep the new app
        // stuck in an old "non-input click" state.
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? detector.currentUpdate.sourceBundleID
    }

    static func resolvedTypingContext(
        recognitionControlMode: HUDRecognitionControlMode,
        inferredTypingContext: Bool,
        hudMode: HUDMode,
        previousTypingContext: Bool,
        allowPreviousTypingContextCarryover: Bool = true
    ) -> Bool {
        switch recognitionControlMode {
        case .command:
            return false
        case .dictation:
            return true
        case .auto:
            if hudMode == .dictation || hudMode == .typing {
                return true
            }
            if hudMode == .organizing
                || hudMode == .processing
                || hudMode == .checking
                || hudMode == .feedback {
                guard allowPreviousTypingContextCarryover else {
                    return inferredTypingContext
                }
                return previousTypingContext
            }
            return inferredTypingContext
        }
    }

    private func shouldCarryOverPreviousTypingContextForDisplay(frontBundle: String?) -> Bool {
        let suppressionState = currentTypingSuppressionStateSnapshot()
        guard suppressionState.requiresExplicitTypingReentry else { return true }
        guard isExplicitTypingSuppressionApp(bundleID: frontBundle) else { return true }
        guard let lockedBundle = suppressionState.explicitTypingReentryBundleID else { return false }
        return lockedBundle != frontBundle
    }

    private func startBackgroundFullscreenCheck() {
        backgroundFullscreenCheckTimer?.invalidate()
        
        // Prevent App Nap during detection to ensure the timer runs accurately
        if appNapActivityToken == nil {
            os_log("HUDManager: beginning NSActivity to prevent App Nap", log: log, type: .default)
            appNapActivityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Aether HUD Fullscreen Video Detection"
            )
        }

        // Check every 1.2 seconds (matching the inactivity threshold)
        os_log("HUDManager: starting 1.2s background timer", log: log, type: .default)
        backgroundFullscreenCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.checkFullscreenSuppressionLocally()
        }
    }

    private func checkFullscreenSuppressionLocally() {
        guard state.mode != .hidden else { return }
        // If we are already hidden due to fullscreen, this will keep it hidden.
        // If we are visible and should be suppressed (e.g. mouse just disappeared), this will trigger it.
        requestReposition()
    }
    
    // MARK: - Public API
    
    func update(
        mode: HUDMode,
        message: String = "",
        language: String,
        recognitionControlMode: HUDRecognitionControlMode = .auto,
        inputDeviceIcon: String = "mic.fill",
        inputDeviceHealth: HUDInputDeviceHealth = .normal,
        contextIcon: String = "",
        lifetime: HUDUpdateLifetime = .persistent
    ) {
        
        // Main thread safety
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.update(
                    mode: mode,
                    message: message,
                    language: language,
                    recognitionControlMode: recognitionControlMode,
                    inputDeviceIcon: inputDeviceIcon,
                    inputDeviceHealth: inputDeviceHealth,
                    contextIcon: contextIcon,
                    lifetime: lifetime
                )
            }
            return
        }

        if isDragStatusForced && mode != .dragging {
            return
        }

        if case .persistent = lifetime, activeTemporaryToken != nil {
            if mode == .hidden {
                lastPersistentSnapshot = nil
            } else {
                lastPersistentSnapshot = HUDPresentationSnapshot(
                    mode: mode,
                    message: message,
                    language: language,
                    recognitionControlMode: recognitionControlMode,
                    inputDeviceIcon: inputDeviceIcon,
                    inputDeviceHealth: inputDeviceHealth,
                    contextIcon: contextIcon
                )
            }
            return
        }
        
        let shouldRefreshTypingContext = Self.shouldRefreshTypingContextForDisplayUpdate(
            currentMode: state.mode,
            nextMode: mode,
            currentLanguage: state.language,
            nextLanguage: language,
            currentRecognitionControlMode: state.recognitionControlMode,
            nextRecognitionControlMode: recognitionControlMode,
            currentInputDeviceIcon: state.inputDeviceIcon,
            nextInputDeviceIcon: inputDeviceIcon,
            currentInputDeviceHealth: state.inputDeviceHealth,
            nextInputDeviceHealth: inputDeviceHealth,
            currentContextIcon: state.contextIcon,
            nextContextIcon: contextIcon,
            lifetime: lifetime
        )

        // Refresh focus evidence only when the semantic display state changes.
        // Message-only partial updates are the hot path during dictation and
        // should not re-run a full typing-context probe before every HUD redraw.
        if shouldRefreshTypingContext {
            _ = lastKnownTypingState()
        }
        let inferredTypingContext = InputControlArbiter.shared.currentSnapshot.interactionState.isTyping
        let frontBundle = currentTypingContextBundleID()
        let allowDisplayCarryover = {
            switch lifetime {
            case .temporary:
                return shouldCarryOverPreviousTypingContextForDisplay(frontBundle: frontBundle)
            case .persistent:
                return false
            }
        }()
        let effectiveTypingContext = Self.resolvedTypingContext(
            recognitionControlMode: recognitionControlMode,
            inferredTypingContext: inferredTypingContext,
            hudMode: mode,
            previousTypingContext: state.isTypingContext,
            allowPreviousTypingContextCarryover: allowDisplayCarryover
        )

        let isNoopVisibleRefresh =
            state.mode == mode &&
            state.message == message &&
            state.language == language &&
            state.isTypingContext == effectiveTypingContext &&
            state.recognitionControlMode == recognitionControlMode &&
            state.inputDeviceIcon == inputDeviceIcon &&
            state.inputDeviceHealth == inputDeviceHealth &&
            state.contextIcon == contextIcon

        switch lifetime {
        case .persistent:
            activeTemporaryToken = nil
            activeTemporaryFallbackSnapshot = nil
            if mode == .hidden {
                lastPersistentSnapshot = nil
            } else {
                lastPersistentSnapshot = HUDPresentationSnapshot(
                    mode: mode,
                    message: message,
                    language: language,
                    recognitionControlMode: recognitionControlMode,
                    inputDeviceIcon: inputDeviceIcon,
                    inputDeviceHealth: inputDeviceHealth,
                    contextIcon: contextIcon
                )
            }
        case .temporary(let token):
            activeTemporaryToken = token
        }

        state.update(
            mode: mode,
            message: message,
            language: language,
            isTypingContext: effectiveTypingContext,
            recognitionControlMode: recognitionControlMode,
            inputDeviceIcon: inputDeviceIcon,
            inputDeviceHealth: inputDeviceHealth,
            contextIcon: contextIcon
        )
        if !shouldPreserveMeasuredWidth(for: mode) {
            stickyMeasuredContentWidth = nil
        }
        if mode == .hidden {
            // Ensure transient indicators don't linger when the HUD is dismissed.
            state.isMicProgressVisible = false
            state.micProgress = 0.0
            state.isPositionAnimating = false
            state.updateGestureTrail(points: [], status: "", visible: false)
            hideLanguageIndicator()
        }

        if mode != .hidden, shouldSuppressHUDForFullscreenVideo() {
            cancelHide()
            hudWindow?.orderOut(nil)
            updateCaretDebugDot(point: nil, enabled: false)
            return
        }
        
        // Mode-specific behavior
        switch mode {
        case .hidden:
            performHide()
        case .standby:
            cancelHide()
            requestReposition(immediate: true)
            ensureWindowVisible()
        case .listening, .command, .dictation, .organizing, .typing, .executing, .optimizing, .checking, .dragging, .processing, .feedback:
            // Keep temporary HUD hide timer alive when refreshes are semantic no-ops.
            // Otherwise short toasts can become "always visible" under periodic updates.
            if !isNoopVisibleRefresh {
                cancelHide()
            }
            requestReposition(immediate: true)
            ensureWindowVisible()
        }
    }

    func updateMicProgress(progress: CGFloat, visible: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.updateMicProgress(progress: progress, visible: visible) }
            return
        }
        let clamped = min(max(progress, 0.0), 1.0)
        state.micProgress = clamped
        state.isMicProgressVisible = visible
    }

    func updateHeadGestureTrail(
        points: [HUDState.GestureTrailPoint],
        status: String,
        visible: Bool
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.updateHeadGestureTrail(points: points, status: status, visible: visible)
            }
            return
        }
        state.updateGestureTrail(points: points, status: status, visible: visible)
    }
    
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
             // Further reduced gain from 10.0 to 8.0 to ensure 
             // normal speech doesn't constantly clip at 100%.
             self.state.audioLevel = CGFloat(min(level * 8.0, 1.0))
        }
    }
    
    func showTemporary(
        message: String,
        language: String? = nil,
        recognitionControlMode: HUDRecognitionControlMode = .auto,
        icon: String? = nil,
        duration: TimeInterval? = nil
    ) {
        let token = UUID()
        activeTemporaryFallbackSnapshot = activeTemporaryFallbackSnapshot ?? lastPersistentSnapshot
        let fallbackControlMode = lastPersistentSnapshot?.recognitionControlMode ?? state.recognitionControlMode
        let controlMode: HUDRecognitionControlMode
        switch recognitionControlMode {
        case .auto:
            controlMode = fallbackControlMode
        case .command, .dictation:
            // Do not let temporary toasts override the active control mode.
            controlMode = lastPersistentSnapshot == nil ? recognitionControlMode : fallbackControlMode
        }
        update(
            mode: .feedback,
            message: message,
            language: language ?? state.language,
            recognitionControlMode: controlMode,
            inputDeviceIcon: icon ?? state.inputDeviceIcon,
            inputDeviceHealth: state.inputDeviceHealth,
            contextIcon: state.contextIcon,
            lifetime: .temporary(token)
        )
        let resolvedDuration = duration ?? suggestedTemporaryDuration(for: message)
        scheduleHide(delay: max(0.4, resolvedDuration), token: token)
    }

    func setDragStatusActive(
        _ active: Bool,
        language: String,
        recognitionControlMode: HUDRecognitionControlMode = .command,
        icon: String = "hand.draw.fill"
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.setDragStatusActive(
                    active,
                    language: language,
                    recognitionControlMode: recognitionControlMode,
                    icon: icon
                )
            }
            return
        }

        isDragStatusForced = active
        if active {
            dragStatusFallbackSnapshot = lastPersistentSnapshot
            update(
                mode: .dragging,
                message: NSLocalizedString("speech.dragging", comment: ""),
                language: language,
                recognitionControlMode: recognitionControlMode,
                inputDeviceIcon: icon,
                inputDeviceHealth: state.inputDeviceHealth,
                contextIcon: state.contextIcon,
                lifetime: .persistent
            )
        } else if let snapshot = dragStatusFallbackSnapshot {
            dragStatusFallbackSnapshot = nil
            update(
                mode: snapshot.mode,
                message: snapshot.message,
                language: snapshot.language,
                recognitionControlMode: snapshot.recognitionControlMode,
                inputDeviceIcon: snapshot.inputDeviceIcon,
                inputDeviceHealth: snapshot.inputDeviceHealth,
                contextIcon: snapshot.contextIcon,
                lifetime: .persistent
            )
        } else {
            dragStatusFallbackSnapshot = nil
            hide()
        }
    }
    
    func hide() {
        update(mode: .hidden, language: state.language, inputDeviceIcon: state.inputDeviceIcon, inputDeviceHealth: state.inputDeviceHealth, contextIcon: state.contextIcon)
    }

    func hideImmediately() {
        hide()
        hudWindow?.orderOut(nil)
        caretDebugWindow?.orderOut(nil)
        lastSmoothedWindowOrigin = nil
        state.isPositionAnimating = false
        mouseAvoidLockOrigin = nil
        mouseAvoidLockUntil = .distantPast
    }

    func showTemporaryLanguageIndicator(duration: TimeInterval = 1.1) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.showTemporaryLanguageIndicator(duration: duration) }
            return
        }

        let shouldRevealHUD = state.mode == .hidden
        languageIndicatorHideTask?.cancel()
        state.isLanguageIndicatorVisible = true

        if shouldRevealHUD {
            let token = UUID()
            activeTemporaryFallbackSnapshot = activeTemporaryFallbackSnapshot ?? lastPersistentSnapshot
            update(
                mode: .standby,
                message: "",
                language: state.language,
                recognitionControlMode: state.recognitionControlMode,
                inputDeviceIcon: state.inputDeviceIcon,
                inputDeviceHealth: state.inputDeviceHealth,
                contextIcon: state.contextIcon,
                lifetime: .temporary(token)
            )
            scheduleHide(delay: max(0.4, duration), token: token)
        }

        // If HUD is hidden or nearly hidden, briefly show it just for the language indicator
        if hudWindow?.isVisible == false || hudWindow?.alphaValue ?? 0 < 0.1 {
            hudWindow?.alphaValue = 1.0
            hudWindow?.orderFront(nil)
        }
        
        requestReposition(immediate: true)

        let task = DispatchWorkItem { [weak self] in
            self?.hideLanguageIndicator()
        }
        languageIndicatorHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, duration), execute: task)
    }

    func suggestedTemporaryDuration(for message: String) -> TimeInterval {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0.75 }

        if compactSuccessToastMessages.contains(trimmed) {
            return 0.85
        }
        if warningToastMessages.contains(trimmed) || looksLikeWarningToast(trimmed) {
            return 1.3
        }
        if errorToastMessages.contains(trimmed) || looksLikeErrorToast(trimmed) {
            return 1.6
        }
        if infoToastMessages.contains(trimmed) || looksLikeInfoToast(trimmed) {
            return 1.0
        }

        let base: TimeInterval = 1.0
        let maxDuration: TimeInterval = 2.2

        // Heuristic: if any ASCII letters present, treat as English-ish; otherwise Chinese-ish.
        let isEnglishLike = trimmed.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
        if isEnglishLike {
            let words = trimmed.split { $0.isWhitespace || $0.isNewline }.count
            let extraWords = max(0, words - 3)
            let duration = base + (Double(extraWords) * 0.12)
            return min(max(duration, base), maxDuration)
        } else {
            let chars = trimmed.count
            let extraChars = max(0, chars - 6)
            let duration = base + (Double(extraChars) * 0.05)
            return min(max(duration, base), maxDuration)
        }
    }

    private var compactSuccessToastMessages: Set<String> {
        [
            NSLocalizedString("speech.done", comment: ""),
            NSLocalizedString("speech.typed", comment: ""),
            NSLocalizedString("speech.pasted", comment: ""),
            NSLocalizedString("speech.pasted_cmdv", comment: ""),
            NSLocalizedString("speech.undo", comment: ""),
            NSLocalizedString("speech.undo_done", comment: ""),
            "Rewrite done",
            "No changes",
            "优化完成",
            "无需修改"
        ]
    }

    private var warningToastMessages: Set<String> {
        [
            NSLocalizedString("speech.playback_leak.detected", comment: ""),
            NSLocalizedString("speech.playback_leak.suppression_active", comment: ""),
            AppLocalization.isChinese ? "正在优化，请稍候" : "Optimizing. Please wait.",
            AppLocalization.isChinese ? "已切到Mac麦" : "Switched to Mac mic"
        ]
    }

    private var errorToastMessages: Set<String> {
        [
            NSLocalizedString("speech.no_matching_command", comment: ""),
            NSLocalizedString("speech.no_editable_field", comment: ""),
            NSLocalizedString("speech.no_mic_detected", comment: ""),
            NSLocalizedString("speech.need_mic_permission", comment: ""),
            NSLocalizedString("speech.need_recognition_permission", comment: ""),
            NSLocalizedString("speech.voice_input_disabled", comment: ""),
            NSLocalizedString("speech.voice_control_disabled", comment: ""),
            AppLocalization.isChinese ? "没完成" : "Didn't finish"
        ]
    }

    private var infoToastMessages: Set<String> {
        [
            AppLocalization.isChinese ? "耳机已连接" : "Headset connected",
            AppLocalization.isChinese ? "耳机已断开" : "Headset disconnected",
            AppLocalization.isChinese ? "已切到耳机" : "Switched to headset",
            AppLocalization.isChinese ? "左耳" : "Left",
            AppLocalization.isChinese ? "右耳" : "Right",
            AppLocalization.isChinese ? "双耳" : "Both"
        ]
    }

    private func looksLikeWarningToast(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        if AppLocalization.isChinese {
            return message.contains("请稍候")
                || message.contains("Mac麦")
                || message.contains("不可用")
                || message.contains("干扰")
        }
        return lowercased.contains("please wait")
            || lowercased.contains("switched to mac mic")
            || lowercased.contains("unavailable")
            || lowercased.contains("interference")
    }

    private func looksLikeErrorToast(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        if AppLocalization.isChinese {
            return message.contains("失败")
                || message.contains("失效")
                || message.contains("不支持")
                || message.contains("没找到")
                || message.contains("关闭")
        }
        return lowercased.contains("failed")
            || lowercased.contains("not support")
            || lowercased.contains("not found")
            || lowercased.contains("turned off")
    }

    private func looksLikeInfoToast(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        if AppLocalization.isChinese {
            return message.contains("已连接")
                || message.contains("已切到")
        }
        return lowercased.contains("connected")
            || lowercased.hasPrefix("switched to ")
    }

    func notifyPointerMoved() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.notifyPointerMoved() }
            return
        }
        let now = Date()
        lastPointerMoveAt = now

        guard state.mode != .hidden else { return }
        if state.recognitionControlMode == .dictation {
            return
        }
        if state.isTypingContext {
            guard let panel = hudWindow, panel.isVisible else { return }
            let mouseLoc = currentCursorLocation()
            let minDim = min(panel.frame.width, panel.frame.height)
            let avoidPadding = max(CGFloat(24), min(CGFloat(56), minDim * 0.35))
            var shouldTriggerAvoid = panel.frame.insetBy(dx: -avoidPadding, dy: -avoidPadding).contains(mouseLoc)
            if !shouldTriggerAvoid, let caret = detector.currentUpdate.caretRect {
                shouldTriggerAvoid = caret.insetBy(dx: -16, dy: -12).contains(mouseLoc)
            }
            if shouldTriggerAvoid {
                typingMouseAvoidUntil = now.addingTimeInterval(0.6)
                guard now.timeIntervalSince(lastPointerFollowAt) >= 0.035 else { return }
                lastPointerFollowAt = now
                requestReposition(immediate: true)
            }
            return
        }

        guard now.timeIntervalSince(lastPointerFollowAt) >= pointerFollowThrottleInterval else { return }
        lastPointerFollowAt = now
        requestReposition(immediate: true)
    }

    func recoverFromAccessibilityTrustChange(trusted: Bool, source: String = "ax-trust-change") {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.recoverFromAccessibilityTrustChange(trusted: trusted, source: source) }
            return
        }

        detector.handleAccessibilityTrustChange(trusted: trusted)
        lastAXTypingEvaluationAt = .distantPast
        cachedAXTypingEvaluation = .unavailable
        lastAXFocusRectCheckAt = .distantPast
        lastAXCaretRectCheckAt = .distantPast
        lastAXEstimatedCaretCheckAt = .distantPast
        lastAXFocusDebugCheckAt = .distantPast
        lastGoodTypingRect = nil
        lastGoodTypingRectAt = .distantPast
        lastExplicitTypingInputRect = nil
        lastExplicitTypingInputRectAt = .distantPast
        lastExplicitTypingInputBundleID = nil
        let didClearSuppression = requiresExplicitTypingReentry || typingSuppressedUntil > Date()
        requiresExplicitTypingReentry = false
        explicitTypingReentryBundleID = nil
        explicitTypingReentrySourceFingerprint = nil
        explicitTypingReentrySourceRect = nil
        if didClearSuppression {
            appendTypingSuppressionDiagnostic(
                suppressed: false,
                reason: "ax-trust-change",
                bundleID: currentTypingContextBundleID()
            )
        }

        guard trusted, state.mode != .hidden else { return }
        _ = source
        requestReposition(immediate: true)
    }

    func handleGlobalMouseDown(at point: CGPoint) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.handleGlobalMouseDown(at: point) }
            return
        }

        let now = Date()
        let bundleID = currentTypingContextBundleID()
        lastMouseDownPoint = point
        lastMouseDownAt = now
        lastMouseDownBundleID = bundleID

        let activeInputRect = preferredExplicitTypingInputRect()
        let hitPreferredInputRect = activeInputRect?.insetBy(dx: -8, dy: -8).contains(point) ?? false
        lastMouseDownHitPreferredInputRect = hitPreferredInputRect
        appendMouseDownDiagnostic(
            timestamp: now,
            point: point,
            bundleID: bundleID,
            preferredInputRect: activeInputRect,
            hitPreferredInputRect: hitPreferredInputRect
        )

        if hitPreferredInputRect {
            rememberExplicitTypingInputRect(activeInputRect, at: now, bundleID: bundleID)
            typingSuppressedUntil = .distantPast
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
            explicitTypingReentrySourceFingerprint = nil
            explicitTypingReentrySourceRect = nil
            InputControlArbiter.shared.updateFocusState(
                .typing,
                bundleID: bundleID,
                source: "hud.mouse-input"
            )
            appendTypingSuppressionDiagnostic(
                suppressed: false,
                reason: "mouse-in-input",
                bundleID: bundleID
            )
            lastInputInteractionPoint = point
            lastInputInteractionAt = now
            return
        }

        typingSuppressedUntil = now.addingTimeInterval(0.8)
        requiresExplicitTypingReentry = true
        explicitTypingReentryBundleID = bundleID
        explicitTypingReentrySourceFingerprint = currentFocusedElementFingerprint()
        explicitTypingReentrySourceRect = activeInputRect ?? axFocusedElementRectThrottled()
        appendTypingSuppressionDiagnostic(
            suppressed: true,
            reason: "mouse-noninput",
            bundleID: bundleID
        )
        InputControlArbiter.shared.updateFocusState(
            .suppressed,
            bundleID: bundleID,
            source: "hud.mouse-noninput"
        )
        NotificationCenter.default.post(
            name: Self.typingContextSuppressedByNonInputClickNotification,
            object: self,
            userInfo: ["bundleID": bundleID as Any]
        )
        lastAXTypingEvaluationAt = .distantPast
        cachedAXTypingEvaluation = .unavailable
        lastAXCaretRectCheckAt = .distantPast
        cachedAXCaretRect = nil
        lastAXEstimatedCaretCheckAt = .distantPast
        cachedAXEstimatedCaretPoint = nil
        cachedAXEstimatedCaretBounds = nil
        lastGoodTypingRect = nil
        lastGoodTypingRectAt = .distantPast
        lastInputInteractionPoint = nil
        lastInputInteractionAt = .distantPast

        guard state.mode != .hidden else { return }
        requestReposition(immediate: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.requestReposition(immediate: true)
            HeadMotionManager.shared.refreshTransientRecognitionControlModeIfNeeded(source: "mouse-noninput")
        }
    }

    func recentMouseDownAnchor(maxAge: TimeInterval = 1.8) -> RecentMouseDownAnchor? {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                recentMouseDownAnchor(maxAge: maxAge)
            }
        }

        guard let point = lastMouseDownPoint else { return nil }
        let now = Date()
        guard now.timeIntervalSince(lastMouseDownAt) <= maxAge else { return nil }
        return RecentMouseDownAnchor(point: point, timestamp: lastMouseDownAt, bundleID: lastMouseDownBundleID)
    }

    func recentMouseDownDiagnosticHistory() -> [MouseDownDiagnosticRecord] {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                recentMouseDownDiagnosticHistory()
            }
        }
        return recentMouseDownDiagnostics
    }

    func typingSuppressionDiagnosticHistory() -> [TypingSuppressionDiagnosticRecord] {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                typingSuppressionDiagnosticHistory()
            }
        }
        return typingSuppressionDiagnostics
    }

    func currentTypingSuppressionStateSnapshot() -> TypingSuppressionStateSnapshot {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                currentTypingSuppressionStateSnapshot()
            }
        }
        return TypingSuppressionStateSnapshot(
            requiresExplicitTypingReentry: requiresExplicitTypingReentry,
            explicitTypingReentryBundleID: explicitTypingReentryBundleID,
            explicitTypingReentrySourceFingerprint: explicitTypingReentrySourceFingerprint,
            explicitTypingReentrySourceRect: explicitTypingReentrySourceRect,
            typingSuppressedUntil: typingSuppressedUntil,
            preferredExplicitTypingInputRect: preferredExplicitTypingInputRect()
        )
    }

    func currentDisplayStateSnapshot() -> DisplayStateSnapshot {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                currentDisplayStateSnapshot()
            }
        }

        return DisplayStateSnapshot(
            mode: state.mode,
            isTypingContext: state.isTypingContext,
            recognitionControlMode: state.recognitionControlMode
        )
    }

    @discardableResult
    func refreshInputControlFocusState() -> InputControlSnapshot {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                refreshInputControlFocusState()
            }
        }
        _ = lastKnownTypingState()
        return InputControlArbiter.shared.currentSnapshot
    }

    private func appendMouseDownDiagnostic(
        timestamp: Date,
        point: CGPoint,
        bundleID: String?,
        preferredInputRect: CGRect?,
        hitPreferredInputRect: Bool
    ) {
        recentMouseDownDiagnostics.append(
            MouseDownDiagnosticRecord(
                timestamp: timestamp,
                point: point,
                bundleID: bundleID,
                preferredInputRect: preferredInputRect,
                hitPreferredInputRect: hitPreferredInputRect
            )
        )
        if recentMouseDownDiagnostics.count > 8 {
            recentMouseDownDiagnostics.removeFirst(recentMouseDownDiagnostics.count - 8)
        }
    }

    private func appendTypingSuppressionDiagnostic(
        suppressed: Bool,
        reason: String,
        bundleID: String?
    ) {
        typingSuppressionDiagnostics.append(
            TypingSuppressionDiagnosticRecord(
                timestamp: Date(),
                suppressed: suppressed,
                reason: reason,
                bundleID: bundleID,
                suppressedUntil: typingSuppressedUntil,
                requiresExplicitTypingReentry: requiresExplicitTypingReentry
            )
        )
        if typingSuppressionDiagnostics.count > 16 {
            typingSuppressionDiagnostics.removeFirst(typingSuppressionDiagnostics.count - 16)
        }
    }

    // Replacement for HotkeyFeedbackHUD.typingContextSnapshot()
    func lastKnownTypingState() -> Bool {
        let now = Date()
        let frontBundle = currentTypingContextBundleID()
        let suppressionSensitiveApp = isExplicitTypingSuppressionApp(bundleID: frontBundle)
        let explicitTypingClickReentry = suppressionSensitiveApp ? false : hasRecentExplicitTypingClickReentry(at: now)
        var resolvedFocusState: InputControlFocusState = .unknown
        defer {
            InputControlArbiter.shared.updateFocusState(
                resolvedFocusState,
                bundleID: frontBundle,
                source: "hud.last-known-typing"
            )
        }

        if isSiriLikeBundle(frontBundle) {
            if detector.currentUpdate.caretRect != nil || detector.recentCaretRect() != nil {
                requiresExplicitTypingReentry = false
                explicitTypingReentryBundleID = nil
                resolvedFocusState = .typing
                return true
            }
            if axCaretRectThrottled() != nil || axEstimatedCaretContextThrottled() != nil {
                requiresExplicitTypingReentry = false
                explicitTypingReentryBundleID = nil
                resolvedFocusState = .typing
                return true
            }
            if let r = axFocusedElementRectThrottled(), !isProbablyWholeWindowRect(r) {
                requiresExplicitTypingReentry = false
                explicitTypingReentryBundleID = nil
                resolvedFocusState = .typing
                return true
            }
        }

        let axEvaluation = axTypingEvaluationThrottled(now: now)
        let shouldReleaseSuppression = shouldReleaseExplicitTypingSuppression(
            now: now,
            frontBundle: frontBundle,
            evaluation: axEvaluation
        )

        if Date() < typingSuppressedUntil, !explicitTypingClickReentry {
            if shouldReleaseSuppression {
                clearExplicitTypingSuppression(reason: "strong-ax-evidence", bundleID: frontBundle)
            } else {
                resolvedFocusState = .suppressed
                return false
            }
        }

        if !explicitTypingClickReentry,
           !requiresExplicitTypingReentry,
           lastGoodTypingRect != nil,
           now.timeIntervalSince(lastGoodTypingRectAt) < 1.2 {
            resolvedFocusState = .typing
            return true
        }

        if requiresExplicitTypingReentry {
            if explicitTypingClickReentry {
                clearExplicitTypingSuppression(reason: "explicit-click-reentry", bundleID: frontBundle)
            } else if let lockedBundle = explicitTypingReentryBundleID,
               let frontBundle,
               lockedBundle != frontBundle {
                clearExplicitTypingSuppression(reason: "frontmost-bundle-changed", bundleID: frontBundle)
            } else if shouldReleaseSuppression {
                clearExplicitTypingSuppression(reason: "strong-ax-evidence", bundleID: frontBundle)
            } else {
                resolvedFocusState = .suppressed
                return false
            }
        }

        // Prefer caret/sticky (fast, high confidence), but fall back to AX focused element editability.
        // This fixes cases where the caret rect is not obtainable (some apps / web views),
        // but the focus is clearly in a text input.
        if detector.currentUpdate.caretRect != nil {
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
            resolvedFocusState = .typing
            return true
        }
        // Sticky can linger in "weird" apps; only treat it as typing if we still have a recent caret rect.
        if detector.currentUpdate.isSticky, detector.recentCaretRect() != nil {
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
            resolvedFocusState = .typing
            return true
        }

        let axEditableLikely = axEvaluation.editableLikely
        if axEvaluation.insertionContextAvailable,
           (axEvaluation.hasEditableAttribute || axEvaluation.hasSettableValue || axEvaluation.hasEditableAncestor) {
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
            resolvedFocusState = .typing
            return true
        }

        // Geometry-first fallback (works better for browser/webview inputs where AX role is often AXWebArea/AXGroup).
        if axCaretRectThrottled() != nil, axEditableLikely || axEvaluation.insertionContextAvailable {
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
            resolvedFocusState = .typing
            return true
        }
        if let r = detector.currentUpdate.inputRect, isTypingBoxSizedRect(r), !isProbablyWholeWindowRect(r) {
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
            resolvedFocusState = .typing
            return true
        }
        if let r = axFocusedElementRectThrottled(),
           !isProbablyWholeWindowRect(r) {
            let insertionAvailable = axEvaluation.insertionContextAvailable
            if insertionAvailable,
               (isTypingBoxSizedRect(r) || (Self.shouldUseWebInputSizedRectHeuristics(bundleID: frontBundle) && isWebInputSizedRect(r))) {
                requiresExplicitTypingReentry = false
                explicitTypingReentryBundleID = nil
                resolvedFocusState = .typing
                return true
            }
            if axEditableLikely {
                if isTypingBoxSizedRect(r) {
                    requiresExplicitTypingReentry = false
                    explicitTypingReentryBundleID = nil
                    resolvedFocusState = .typing
                    return true
                }
                if Self.shouldUseWebInputSizedRectHeuristics(bundleID: frontBundle), isWebInputSizedRect(r) {
                    requiresExplicitTypingReentry = false
                    explicitTypingReentryBundleID = nil
                    resolvedFocusState = .typing
                    return true
                }
            }
        }

        if isWeirdWebTypingApp(bundleID: frontBundle),
           axEvaluation.looselyEditableForWeb {
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
            resolvedFocusState = .typing
            return true
        }
        if axEditableLikely {
            requiresExplicitTypingReentry = false
            explicitTypingReentryBundleID = nil
        }
        resolvedFocusState = axEditableLikely ? .typing : .nonTyping
        return axEditableLikely
    }

    private func hasStrongAXTypingEvidence(
        now: Date,
        frontBundle: String?,
        evaluation axEvaluation: AXFocusedTypingEvaluation
    ) -> Bool {
        if axEvaluation.insertionContextAvailable,
           (axEvaluation.hasEditableAttribute || axEvaluation.hasSettableValue || axEvaluation.hasEditableAncestor) {
            return true
        }

        if axCaretRectThrottled() != nil,
           axEvaluation.editableLikely || axEvaluation.insertionContextAvailable {
            return true
        }

        if let r = axFocusedElementRectThrottled(),
           !isProbablyWholeWindowRect(r) {
            if axEvaluation.insertionContextAvailable,
               (isTypingBoxSizedRect(r) || (Self.shouldUseWebInputSizedRectHeuristics(bundleID: frontBundle) && isWebInputSizedRect(r))) {
                return true
            }
            if axEvaluation.editableLikely {
                if isTypingBoxSizedRect(r) {
                    return true
                }
                if Self.shouldUseWebInputSizedRectHeuristics(bundleID: frontBundle), isWebInputSizedRect(r) {
                    return true
                }
            }
        }

        if isWeirdWebTypingApp(bundleID: frontBundle),
           axEvaluation.looselyEditableForWeb {
            return true
        }

        return false
    }

    func currentAXTypingEvaluation() -> AXFocusedTypingEvaluation {
        axTypingEvaluationThrottled(now: Date())
    }

    private func shouldUseBrowserPointerFollowFastPath(now: Date) -> Bool {
        guard state.recognitionControlMode == .auto else { return false }
        guard !state.isTypingContext else { return false }
        guard now.timeIntervalSince(lastPointerMoveAt) < 0.18 else { return false }

        let bundleID = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "").lowercased()
        guard !bundleID.isEmpty else { return false }
        return bundleID.contains("safari")
            || bundleID.contains("chrome")
            || bundleID.contains("chromium")
            || bundleID.contains("brave")
            || bundleID.contains("arc")
            || bundleID.contains("firefox")
            || bundleID.contains("edge")
            || bundleID.contains("kagi")
    }

    private func isAXFocusedElementEditable() -> Bool {
        axTypingEvaluationThrottled(now: Date()).editableLikely
    }

    private func isAXFocusedElementLooselyEditableForWeb() -> Bool {
        axTypingEvaluationThrottled(now: Date()).looselyEditableForWeb
    }

    private func isWeirdWebTypingApp(bundleID: String?) -> Bool {
        Self.isWeirdWebTypingAppBundleIdentifier(bundleID)
    }

    private func isExplicitTypingSuppressionApp(bundleID: String?) -> Bool {
        Self.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: bundleID)
    }

    private func shouldReleaseExplicitTypingSuppression(
        now: Date,
        frontBundle: String?,
        evaluation: AXFocusedTypingEvaluation
    ) -> Bool {
        guard requiresExplicitTypingReentry else { return false }
        if Self.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: frontBundle) {
            // For editor-like surfaces such as Codex, a stale AX container can look
            // "editable" again a moment after a non-input click. Keep suppression
            // latched until the user explicitly clicks back into an input or leaves
            // the app, instead of auto-releasing on AX evidence alone.
            return false
        }
        guard hasStrongAXTypingEvidence(
            now: now,
            frontBundle: frontBundle,
            evaluation: evaluation
        ) else {
            return false
        }
        guard !shouldHoldSuppressionAgainstStrongAXEvidence(
            now: now,
            frontBundle: frontBundle,
            evaluation: evaluation
        ) else {
            return false
        }
        return true
    }

    private func clearExplicitTypingSuppression(reason: String, bundleID: String?) {
        typingSuppressedUntil = .distantPast
        requiresExplicitTypingReentry = false
        explicitTypingReentryBundleID = nil
        explicitTypingReentrySourceFingerprint = nil
        explicitTypingReentrySourceRect = nil
        appendTypingSuppressionDiagnostic(
            suppressed: false,
            reason: reason,
            bundleID: bundleID
        )
    }

    func hasRecentExplicitTypingClickReentry() -> Bool {
        hasRecentExplicitTypingClickReentry(at: Date())
    }

    func isTypingExplicitlySuppressedForCurrentApp() -> Bool {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                isTypingExplicitlySuppressedForCurrentApp()
            }
        }

        guard requiresExplicitTypingReentry else { return false }
        let now = Date()
        let frontBundle = currentTypingContextBundleID()
        let suppressionSensitiveApp = isExplicitTypingSuppressionApp(bundleID: frontBundle)
        if !suppressionSensitiveApp, hasRecentExplicitTypingClickReentry(at: now) {
            return false
        }
        if let lockedBundle = explicitTypingReentryBundleID,
           let frontBundle,
           lockedBundle != frontBundle {
            return false
        }
        let axEvaluation = axTypingEvaluationThrottled(now: now)
        if shouldReleaseExplicitTypingSuppression(
            now: now,
            frontBundle: frontBundle,
            evaluation: axEvaluation
        ) {
            clearExplicitTypingSuppression(reason: "strong-ax-evidence", bundleID: frontBundle)
            return false
        }
        return isExplicitTypingSuppressionApp(bundleID: frontBundle)
    }

    private func hasRecentExplicitTypingClickReentry(at now: Date) -> Bool {
        guard lastMouseDownPoint != nil else { return false }
        guard now.timeIntervalSince(lastMouseDownAt) < 1.2 else { return false }
        return lastMouseDownHitPreferredInputRect
    }

    private func shouldHoldSuppressionAgainstStrongAXEvidence(
        now: Date,
        frontBundle: String?,
        evaluation: AXFocusedTypingEvaluation
    ) -> Bool {
        guard requiresExplicitTypingReentry else { return false }
        guard !lastMouseDownHitPreferredInputRect else { return false }
        guard let point = lastMouseDownPoint else { return false }
        guard now.timeIntervalSince(lastMouseDownAt) < 1.6 else { return false }
        guard let rect = preferredExplicitTypingInputRect() else { return false }

        let expandedRect = rect.insetBy(dx: -24, dy: -24)
        guard !expandedRect.contains(point) else { return false }

        let dx: CGFloat
        if point.x < expandedRect.minX {
            dx = expandedRect.minX - point.x
        } else if point.x > expandedRect.maxX {
            dx = point.x - expandedRect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < expandedRect.minY {
            dy = expandedRect.minY - point.y
        } else if point.y > expandedRect.maxY {
            dy = point.y - expandedRect.maxY
        } else {
            dy = 0
        }

        let distance = hypot(dx, dy)
        let browserLike = isBrowserLikeBundle(frontBundle)
        let searchLikeRole = evaluation.role == "AXSearchField" || evaluation.role == kAXTextFieldRole as String
        return distance >= 96 && (browserLike || searchLikeRole)
    }

    private func preferredExplicitTypingInputRect() -> CGRect? {
        let frontBundle = currentTypingContextBundleID()
        let now = Date()
        let axEvaluation = axTypingEvaluationThrottled(now: now)
        let allowLooseGeometryCandidates = shouldAllowLooseTypingRectCandidates(
            frontBundle: frontBundle,
            evaluation: axEvaluation
        )
        var candidates: [CGRect] = []
        if let r = detector.currentUpdate.inputRect,
           isTypingGeometryCandidateRect(r, bundleID: frontBundle),
           allowLooseGeometryCandidates || detector.currentUpdate.caretRect != nil || detector.recentCaretRect() != nil {
            candidates.append(r)
        }
        if let r = axFocusedElementRectThrottled(),
           isTypingGeometryCandidateRect(r, bundleID: frontBundle),
           allowLooseGeometryCandidates {
            candidates.append(r)
        }
        if candidates.isEmpty,
           let rememberedRect = lastExplicitTypingInputRect,
           let rememberedBundle = lastExplicitTypingInputBundleID,
           rememberedBundle == frontBundle,
           Date().timeIntervalSince(lastExplicitTypingInputRectAt) < 2.0,
           isTypingGeometryCandidateRect(rememberedRect, bundleID: rememberedBundle) {
            candidates.append(rememberedRect)
        }
        guard !candidates.isEmpty else { return nil }
        if isExplicitTypingSuppressionApp(bundleID: frontBundle) {
            return candidates.min(by: { ($0.width * $0.height) < ($1.width * $1.height) })
        }
        return candidates.first
    }

    private func currentFocusedTypingInputRectCandidate() -> CGRect? {
        let frontBundle = currentTypingContextBundleID()
        let now = Date()
        let axEvaluation = axTypingEvaluationThrottled(now: now)
        let allowLooseGeometryCandidates = shouldAllowLooseTypingRectCandidates(
            frontBundle: frontBundle,
            evaluation: axEvaluation
        )
        var candidates: [CGRect] = []
        if let r = detector.currentUpdate.inputRect,
           isTypingGeometryCandidateRect(r, bundleID: frontBundle),
           allowLooseGeometryCandidates || detector.currentUpdate.caretRect != nil || detector.recentCaretRect() != nil {
            candidates.append(r)
        }
        if let r = axFocusedElementRectThrottled(),
           isTypingGeometryCandidateRect(r, bundleID: frontBundle),
           allowLooseGeometryCandidates {
            candidates.append(r)
        }
        guard !candidates.isEmpty else { return nil }
        if Self.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: frontBundle) {
            return candidates.min(by: { ($0.width * $0.height) < ($1.width * $1.height) })
        }
        return candidates.first
    }

    private func shouldAllowLooseTypingRectCandidates(
        frontBundle: String?,
        evaluation: AXFocusedTypingEvaluation
    ) -> Bool {
        if !isBrowserLikeBundle(frontBundle) && !isWeirdWebTypingApp(bundleID: frontBundle) {
            return true
        }
        return evaluation.editableLikely
            || evaluation.insertionContextAvailable
            || evaluation.looselyEditableForWeb
    }

    private func shouldAllowExplicitTypingReentryForChangedFocusedInput(now: Date) -> Bool {
        let currentFingerprint = currentFocusedElementFingerprint()
        let currentRect = currentFocusedTypingInputRectCandidate()
        return Self.shouldAllowExplicitTypingReentryAfterFocusChange(
            sourceFingerprint: explicitTypingReentrySourceFingerprint,
            sourceRect: explicitTypingReentrySourceRect,
            currentFingerprint: currentFingerprint,
            currentRect: currentRect,
            clickPoint: lastMouseDownPoint,
            clickAge: now.timeIntervalSince(lastMouseDownAt)
        )
    }

    private func isBrowserLikeBundle(_ bundleID: String?) -> Bool {
        Self.isBrowserLikeBundleIdentifier(bundleID)
    }

    private func isAXFocusedElementInsertionContextAvailable() -> Bool {
        axTypingEvaluationThrottled(now: Date()).insertionContextAvailable
    }

    private func axTypingEvaluationThrottled(now: Date) -> AXFocusedTypingEvaluation {
        if now.timeIntervalSince(lastAXTypingEvaluationAt) < 0.12 {
            return cachedAXTypingEvaluation
        }
        lastAXTypingEvaluationAt = now
        let evaluation = AXFocusedTypingContextDetector.evaluate(
            focusedRect: axFocusedElementRectThrottled(),
            caretRect: axCaretRectThrottled(),
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            isWholeWindowRect: { [weak self] rect in
                self?.isProbablyWholeWindowRect(rect) ?? true
            },
            isTypingBoxSizedRect: { [weak self] rect in
                self?.isTypingBoxSizedRect(rect) ?? false
            },
            isWebInputSizedRect: { [weak self] rect in
                self?.isWebInputSizedRect(rect) ?? false
            }
        )
        cachedAXTypingEvaluation = evaluation
        return evaluation
    }

    private func appKitRectFromAX(_ axRect: CGRect) -> CGRect? {
        let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        guard desktopMaxY > 0 else { return nil }
        return CGRect(
            x: axRect.origin.x,
            y: desktopMaxY - axRect.origin.y - axRect.size.height,
            width: axRect.size.width,
            height: axRect.size.height
        )
    }

    private func normalizeCaretRect(_ rect: CGRect) -> CGRect {
        if rect.width <= 0 {
            return CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        }
        return rect
    }

    private func isLikelyCaretRect(_ rect: CGRect) -> Bool {
        guard rect.height > 0 else { return false }
        let maxWidth = max(6.0, min(12.0, rect.height * 0.6))
        return rect.width <= maxWidth && rect.height <= 60
    }

    private func selectedTextRange(from value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ax, .cfRange, &range) else { return nil }
        if range.location < 0 { return nil }
        return range
    }

    private func visibleCharacterRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXVisibleCharacterRange" as CFString, &value) == .success,
              let value else {
            return nil
        }
        return selectedTextRange(from: value)
    }

    private func intersectRange(_ a: CFRange, _ b: CFRange) -> CFRange? {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        let start = max(a.location, b.location)
        let end = min(aEnd, bEnd)
        if end <= start { return nil }
        return CFRange(location: start, length: end - start)
    }

    private func boundsForRange(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        )
        guard err == .success, let boundsRef else { return nil }
        guard CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var axRect = CGRect.zero
        let axV = boundsRef as! AXValue
        guard AXValueGetValue(axV, .cgRect, &axRect) else { return nil }
        return appKitRectFromAX(axRect)
    }

    private func axFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            return nil
        }
        return focusedElement as! AXUIElement
    }

    private func currentFocusedElementFingerprint() -> String? {
        guard let element = axFocusedElement() else { return nil }
        return axElementFingerprint(element)
    }

    private func axElementFingerprint(_ element: AXUIElement) -> String {
        let role = sanitizeFingerprintComponent(AXFocusedTypingContextDetector.stringAttr(element, kAXRoleAttribute as CFString), fallback: "?")
        let subrole = sanitizeFingerprintComponent(AXFocusedTypingContextDetector.stringAttr(element, kAXSubroleAttribute as CFString))
        let identifier = sanitizeFingerprintComponent(AXFocusedTypingContextDetector.stringAttr(element, "AXIdentifier" as CFString))
        let title = sanitizeFingerprintComponent(AXFocusedTypingContextDetector.stringAttr(element, kAXTitleAttribute as CFString))
        let placeholder = sanitizeFingerprintComponent(AXFocusedTypingContextDetector.stringAttr(element, "AXPlaceholderValue" as CFString))
        let position = axCGPointAttribute(element, kAXPositionAttribute as CFString).map {
            "\(Int($0.x.rounded()))x\(Int($0.y.rounded()))"
        } ?? "-"
        let size = axCGSizeAttribute(element, kAXSizeAttribute as CFString).map {
            "\(Int($0.width.rounded()))x\(Int($0.height.rounded()))"
        } ?? "-"

        var windowTitle = "-"
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
           let windowRef,
           CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
            windowTitle = sanitizeFingerprintComponent(
                AXFocusedTypingContextDetector.stringAttr(windowRef as! AXUIElement, kAXTitleAttribute as CFString)
            )
        }

        return [role, subrole, identifier, title, placeholder, windowTitle, position, size].joined(separator: "|")
    }

    private func sanitizeFingerprintComponent(_ raw: String?, fallback: String = "-") -> String {
        guard let raw else { return fallback }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return trimmed.replacingOccurrences(of: "|", with: "/")
    }

    private func axCGPointAttribute(_ element: AXUIElement, _ attr: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func axCGSizeAttribute(_ element: AXUIElement, _ attr: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func axSelectedTextRange(for element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else {
            return nil
        }
        return selectedTextRange(from: rangeRef)
    }

    private func axLineRect(for element: AXUIElement, caretIndex: Int) -> CGRect? {
        let now = Date()
        if now.timeIntervalSince(lastAXLineRectCheckAt) < 0.12,
           cachedAXLineRectCaretIndex == caretIndex,
           let cached = cachedAXLineRect {
            return cached
        }
        lastAXLineRectCheckAt = now
        cachedAXLineRectCaretIndex = caretIndex

        let indexNumber = NSNumber(value: caretIndex)
        var lineRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXLineForIndex" as CFString, indexNumber, &lineRef) == .success,
              let lineNumber = lineRef as? NSNumber else {
            cachedAXLineRect = nil
            return nil
        }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXRangeForLine" as CFString, lineNumber, &rangeRef) == .success,
              let rangeRef,
              let lineRange = selectedTextRange(from: rangeRef) else {
            cachedAXLineRect = nil
            return nil
        }
        let rect = boundsForRange(element, range: lineRange)
        cachedAXLineRect = rect
        return rect
    }

    private func adjustCaretRectByLineHeight(_ rect: CGRect, element: AXUIElement, caretIndex: Int) -> CGRect {
        guard let lineRect = axLineRect(for: element, caretIndex: caretIndex),
              lineRect.height > 0 else { return rect }
        let width = rect.width > 0 ? rect.width : 2
        let needsAdjust =
            rect.height < lineRect.height * 0.5 ||
            rect.midY < lineRect.minY + lineRect.height * 0.35 ||
            rect.midY > lineRect.maxY + 2
        if needsAdjust {
            return CGRect(x: rect.minX, y: lineRect.minY, width: width, height: lineRect.height)
        }
        return rect
    }

    private func adjustCaretRectByLineHeight(_ rect: CGRect) -> CGRect {
        guard let element = axFocusedElement(),
              let range = axSelectedTextRange(for: element) else {
            return rect
        }
        let caretIndex = max(0, range.location + range.length)
        return adjustCaretRectByLineHeight(rect, element: element, caretIndex: caretIndex)
    }

    private func caretRectFromLineInfo(_ element: AXUIElement, caretIndex: Int) -> CGRect? {
        let indexNumber = NSNumber(value: caretIndex)
        var lineRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXLineForIndex" as CFString, indexNumber, &lineRef) == .success,
              let lineNumber = lineRef as? NSNumber else {
            return nil
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXRangeForLine" as CFString, lineNumber, &rangeRef) == .success,
              let rangeRef,
              let lineRange = selectedTextRange(from: rangeRef) else {
            return nil
        }

        guard let lineRect = boundsForRange(element, range: lineRange) else { return nil }

        let visibleRange = visibleCharacterRange(element)
        let effectiveRange = visibleRange.flatMap { intersectRange(lineRange, $0) } ?? lineRange

        var baseRect = lineRect
        if let effectiveRect = boundsForRange(element, range: effectiveRange) {
            baseRect = effectiveRect
        } else if let elementBounds = axFocusedElementRectThrottled() {
            baseRect = CGRect(x: elementBounds.minX, y: lineRect.minY, width: elementBounds.width, height: lineRect.height)
        }

        let firstCharRect: CGRect? = {
            guard effectiveRange.length > 0 else { return nil }
            let r = CFRange(location: effectiveRange.location, length: 1)
            return boundsForRange(element, range: r)
        }()
        let lastCharRect: CGRect? = {
            guard effectiveRange.length > 0 else { return nil }
            let lastIndex = effectiveRange.location + max(0, effectiveRange.length - 1)
            let r = CFRange(location: lastIndex, length: 1)
            return boundsForRange(element, range: r)
        }()

        if let first = firstCharRect, isLikelyCharRect(first) {
            if let last = lastCharRect, isLikelyCharRect(last) {
                baseRect = CGRect(
                    x: first.minX,
                    y: first.minY,
                    width: max(2, last.maxX - first.minX),
                    height: first.height
                )
            } else {
                baseRect = CGRect(
                    x: first.minX,
                    y: first.minY,
                    width: max(2, baseRect.maxX - first.minX),
                    height: first.height
                )
            }
        }

        let visibleStart = effectiveRange.location
        let visibleEnd = effectiveRange.location + effectiveRange.length
        if caretIndex <= visibleStart {
            return CGRect(x: baseRect.minX - 1, y: baseRect.minY, width: 2, height: baseRect.height)
        }
        if caretIndex >= visibleEnd {
            return CGRect(x: baseRect.maxX - 1, y: baseRect.minY, width: 2, height: baseRect.height)
        }

        let offset = max(0, caretIndex - visibleStart)
        var prefixAttr: NSAttributedString?
        if offset > 0 {
            let prefixRange = CFRange(location: visibleStart, length: offset)
            prefixAttr = attributedStringForRange(element, range: prefixRange)
            if prefixAttr == nil {
                if let lineAttr = attributedStringForRange(element, range: lineRange) {
                    let startInLine = max(0, min(visibleStart - lineRange.location, lineAttr.length))
                    let len = max(0, min(offset, lineAttr.length - startInLine))
                    if len > 0 {
                        prefixAttr = lineAttr.attributedSubstring(from: NSRange(location: startInLine, length: len))
                    }
                }
            }
        }

        let width: CGFloat
        if let prefixAttr {
            let ctLine = CTLineCreateWithAttributedString(prefixAttr)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
        } else {
            width = 0
        }

        let x = min(max(baseRect.minX + width, baseRect.minX), baseRect.maxX)
        return CGRect(x: x - 1, y: baseRect.minY, width: 2, height: baseRect.height)
    }

    private func attributedStringForRange(_ element: AXUIElement, range: CFRange) -> NSAttributedString? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var attrRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForRange" as CFString,
            rangeValue,
            &attrRef
        )
        guard err == .success, let attrRef else { return nil }
        return attrRef as? NSAttributedString
    }

    private func isLikelyCharRect(_ rect: CGRect) -> Bool {
        if rect.width <= 0 || rect.height <= 0 { return false }
        if rect.width > 80 || rect.height > 80 { return false }
        return true
    }

    private func refineCaretRect(_ element: AXUIElement, selectedRange: CFRange) -> CGRect? {
        let caretIndex = max(0, selectedRange.location + selectedRange.length)
        let caretRange = CFRange(location: caretIndex, length: 0)
        if let caretRect = boundsForRange(element, range: caretRange) {
            let normalized = normalizeCaretRect(caretRect)
            if isLikelyCaretRect(normalized) {
                return normalized
            }
            if caretRect.width > max(80, caretRect.height * 6),
               let lineCaret = caretRectFromLineInfo(element, caretIndex: caretIndex) {
                return lineCaret
            }
        }

        let candidates: [(CFRange, Bool)] = [
            (CFRange(location: max(0, caretIndex - 1), length: 1), true),
            (CFRange(location: caretIndex, length: 1), false)
        ]

        for (range, useMaxX) in candidates {
            if range.location < 0 || range.length <= 0 { continue }
            if let charRect = boundsForRange(element, range: range) {
                if charRect.height <= 0 { continue }
                if charRect.width > max(80, charRect.height * 6),
                   let lineCaret = caretRectFromLineInfo(element, caretIndex: caretIndex) {
                    return lineCaret
                }
                let x = useMaxX ? charRect.maxX : charRect.minX
                return CGRect(x: x - 1, y: charRect.minY, width: 2, height: charRect.height)
            }
        }
        return nil
    }

    private func isProbablyWholeWindowRect(_ r: CGRect) -> Bool {
        guard r.width > 0, r.height > 0 else { return true }
        // Use intersection rather than midpoint: some bogus AX rects have insane origins and midpoints off-screen.
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(r) }) ??
            NSScreen.screens.first(where: { $0.visibleFrame.intersects(r) }) ??
            NSScreen.main ??
            NSScreen.screens.first
        let s = screen?.visibleFrame ?? .zero
        guard s.width > 0, s.height > 0 else { return false }
        // Treat huge WebArea/window bounds as not a useful "input box" anchor.
        // We intentionally bias towards rejecting large containers (Codex/Antigravity often reports the whole pane).
        let area = r.width * r.height
        let screenArea = s.width * s.height
        if screenArea > 0, area > screenArea * 0.22 { return true }
        // Allow medium/tall text inputs (multi-line composer) without classifying them as whole-window.
        if r.height > 280 { return true }
        if r.width > s.width * 0.92, r.height > 60 { return true }
        return (r.width > s.width * 0.65) && (r.height > s.height * 0.45)
    }

    private func isTypingBoxSizedRect(_ r: CGRect) -> Bool {
        // Heuristic for "single-line input" / compact editor input region.
        // Codex prompt box tends to be short; the big editor pane is tall.
        if r.width <= 0 || r.height <= 0 { return false }
        if r.height < 18 { return false }
        if r.height > 220 { return false }
        if r.width < 140 { return false }
        return true
    }

    private func isWebInputSizedRect(_ r: CGRect) -> Bool {
        if r.width <= 0 || r.height <= 0 { return false }
        if r.height < 18 { return false }
        if r.height > 220 { return false }
        if r.width < 56 { return false }
        return true
    }

    private func stableTypingRect(now: Date, candidate: CGRect?) -> CGRect? {
        if let c = candidate, isTypingBoxSizedRect(c), !isProbablyWholeWindowRect(c) {
            lastGoodTypingRect = c
            lastGoodTypingRectAt = now
            rememberExplicitTypingInputRect(c, at: now, bundleID: currentTypingContextBundleID())
            return c
        }
        if let last = lastGoodTypingRect, now.timeIntervalSince(lastGoodTypingRectAt) < 0.8 {
            return last
        }
        return nil
    }

    private func rememberExplicitTypingInputRect(_ rect: CGRect?, at now: Date, bundleID: String?) {
        guard let rect,
              isTypingGeometryCandidateRect(rect, bundleID: bundleID) else {
            return
        }
        lastExplicitTypingInputRect = rect
        lastExplicitTypingInputRectAt = now
        lastExplicitTypingInputBundleID = bundleID
    }

    private func isTypingGeometryCandidateRect(_ rect: CGRect, bundleID: String?) -> Bool {
        guard !isProbablyWholeWindowRect(rect) else { return false }
        if isTypingBoxSizedRect(rect) { return true }
        return Self.shouldUseWebInputSizedRectHeuristics(bundleID: bundleID) && isWebInputSizedRect(rect)
    }

    private func axFocusedElementRectThrottled() -> CGRect? {
        let now = Date()
        if now.timeIntervalSince(lastAXFocusRectCheckAt) < 0.18 {
            return cachedAXFocusRect
        }
        lastAXFocusRectCheckAt = now

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            cachedAXFocusRect = nil
            return nil
        }
        let element = focusedElement as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef,
              let sizeRef else {
            cachedAXFocusRect = nil
            return nil
        }
        var p = CGPoint.zero
        var s = CGSize.zero
        let posVal = posRef as! AXValue
        let sizeVal = sizeRef as! AXValue
        guard AXValueGetValue(posVal, .cgPoint, &p),
              AXValueGetValue(sizeVal, .cgSize, &s) else {
            cachedAXFocusRect = nil
            return nil
        }

        let axRect = CGRect(origin: p, size: s)
        let r = appKitRectFromAX(axRect)
        cachedAXFocusRect = r
        return r
    }

    // Prefer caret geometry derived from the focused element's selected range.
    // This is significantly more reliable in web-based inputs (Chromium/WebView/Electron),
    // where the focused element bounds often represent a huge AXWebArea/container.
    private func axCaretRectThrottled() -> CGRect? {
        let now = Date()
        if now.timeIntervalSince(lastAXCaretRectCheckAt) < 0.12 {
            return cachedAXCaretRect
        }
        lastAXCaretRectCheckAt = now

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            cachedAXCaretRect = nil
            return nil
        }
        let element = focusedElement as! AXUIElement

        func rectFromParameterizedBounds(parameter: CFTypeRef, attr: CFString) -> CGRect? {
            var boundsRef: CFTypeRef?
            let err = AXUIElementCopyParameterizedAttributeValue(element, attr, parameter, &boundsRef)
            guard err == .success, let boundsVal = boundsRef else { return nil }
            guard CFGetTypeID(boundsVal) == AXValueGetTypeID() else { return nil }
            var axRect = CGRect.zero
            let axV = boundsVal as! AXValue
            guard AXValueGetValue(axV, .cgRect, &axRect) else { return nil }
            return appKitRectFromAX(axRect)
        }

        // 1) SelectedTextRange -> BoundsForRange (parameterized) => caret/selection rect in screen coords.
        var axRect: CGRect? = nil
        var rangeRef: CFTypeRef?
        var selectedRange: CFRange?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeVal = rangeRef {
            selectedRange = selectedTextRange(from: rangeVal)
            axRect = rectFromParameterizedBounds(parameter: rangeVal, attr: kAXBoundsForRangeParameterizedAttribute as CFString)
        }

        // 2) SelectedTextMarkerRange -> BoundsForTextMarkerRange (parameterized)
        // Some web-based apps expose marker ranges but not standard CFRange-based bounds.
        if axRect == nil {
            var markerRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRef) == .success,
               let markerVal = markerRef {
                axRect = rectFromParameterizedBounds(parameter: markerVal, attr: "AXBoundsForTextMarkerRange" as CFString)
            }
        }

        guard let r0 = axRect else {
            cachedAXCaretRect = nil
            return nil
        }

        let r = r0

        // Reject obviously-wrong container rects.
        if isProbablyWholeWindowRect(r) {
            cachedAXCaretRect = nil
            return nil
        }
        var candidate = normalizeCaretRect(r)
        if isLikelyCaretRect(candidate) {
            if let range = selectedRange {
                let caretIndex = max(0, range.location + range.length)
                candidate = adjustCaretRectByLineHeight(candidate, element: element, caretIndex: caretIndex)
            }
            cachedAXCaretRect = candidate
            return candidate
        }

        var refineRange: CFRange?
        if let rangeRef, let range = selectedTextRange(from: rangeRef) {
            refineRange = range
        } else {
            var tmp: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &tmp) == .success,
               let tmp,
               let range = selectedTextRange(from: tmp) {
                refineRange = range
            }
        }
        if let range = refineRange, let refined = refineCaretRect(element, selectedRange: range) {
            cachedAXCaretRect = refined
            return refined
        }

        cachedAXCaretRect = nil
        return nil
    }

    // Estimate caret point inside the focused element by using its value + selected range.
    // This helps for web-based inputs where bounds-for-range returns nil, but selected range/value exist.
    private func axEstimatedCaretContextThrottled() -> (point: CGPoint, bounds: CGRect)? {
        let now = Date()
        if now.timeIntervalSince(lastAXEstimatedCaretCheckAt) < 0.12 {
            if let p = cachedAXEstimatedCaretPoint, let b = cachedAXEstimatedCaretBounds {
                return (point: p, bounds: b)
            }
            return nil
        }
        lastAXEstimatedCaretCheckAt = now

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        let element = focusedElement as! AXUIElement

        // Focused element bounds in AX coords.
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef,
              let sizeRef else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        var p = CGPoint.zero
        var s = CGSize.zero
        let posVal = posRef as! AXValue
        let sizeVal = sizeRef as! AXValue
        guard AXValueGetValue(posVal, .cgPoint, &p),
              AXValueGetValue(sizeVal, .cgSize, &s) else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        guard let bounds = appKitRectFromAX(CGRect(origin: p, size: s)) else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        // Only use this estimator for "input-like" bounds; never for huge containers.
        if isProbablyWholeWindowRect(bounds) {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }

        // Selected range + value.
        var valueRef: CFTypeRef?
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let valueStr = valueRef as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        var range = CFRange()
        let axV = selectedRangeValue as! AXValue
        guard AXValueGetValue(axV, .cfRange, &range) else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }

        let total = max(0, valueStr.count)
        let location = max(0, min(range.location + range.length, total))
        if total == 0 {
            // No text: assume caret near left inset.
            let pt = CGPoint(x: bounds.minX + 18, y: bounds.midY)
            cachedAXEstimatedCaretPoint = pt
            cachedAXEstimatedCaretBounds = bounds
            return (point: pt, bounds: bounds)
        }

        func isCJKScalar(_ u: UnicodeScalar) -> Bool {
            let v = u.value
            if (0x4E00...0x9FFF).contains(v) { return true }
            if (0x3400...0x4DBF).contains(v) { return true }
            if (0xF900...0xFAFF).contains(v) { return true }
            if (0x3040...0x30FF).contains(v) { return true }
            if (0xAC00...0xD7AF).contains(v) { return true }
            return false
        }
        func advanceUnit(_ ch: Character) -> CGFloat {
            if ch == " " { return 0.33 }
            let scalars = String(ch).unicodeScalars
            if scalars.count == 1, let u = scalars.first {
                if u.isASCII {
                    if (48...57).contains(u.value) { return 0.62 }
                    if (65...90).contains(u.value) { return 0.60 }
                    if (97...122).contains(u.value) { return 0.58 }
                    return 0.48
                }
                if isCJKScalar(u) { return 1.0 }
                if u.value > 0xFFFF { return 1.1 }
                return 0.9
            }
            for u in scalars {
                if isCJKScalar(u) { return 1.0 }
                if u.value > 0xFFFF { return 1.1 }
            }
            return 0.95
        }
        func weightedUnits(_ s: String, upTo n: Int) -> CGFloat {
            if n <= 0 { return 0 }
            var units: CGFloat = 0
            var i = 0
            for ch in s {
                if i >= n { break }
                units += advanceUnit(ch)
                i += 1
            }
            return units
        }

        // Model inside the bounds:
        // - If text "fits" in the control, use a fixed-step model (more accurate for short strings).
        // - If text is longer than the control, clamp to the usable width (caret tends to pin to the right).
        let leadingInset = min(max(10.0, bounds.height * 0.5), 22.0)
        let trailingInset: CGFloat = 10.0
        let usableWidth = max(8.0, bounds.width - leadingInset - trailingInset)
        let unitsSoFar = weightedUnits(valueStr, upTo: location)
        let totalUnits = max(0.1, weightedUnits(valueStr, upTo: total))
        let step = min(max(9.0, bounds.height * 0.52), 13.0)
        let totalPx = totalUnits * step
        let offset: CGFloat
        if totalPx <= usableWidth {
            offset = unitsSoFar * step
        } else {
            offset = min(unitsSoFar * step, usableWidth)
        }
        let pt = CGPoint(x: bounds.minX + leadingInset + min(max(offset, 0.0), usableWidth), y: bounds.midY)
        cachedAXEstimatedCaretPoint = pt
        cachedAXEstimatedCaretBounds = bounds
        return (point: pt, bounds: bounds)
    }

    private func isSiriLikeBundle(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        let lowered = bundleID.lowercased()
        if lowered.contains("apple.siri") { return true }
        if lowered.contains("spotlight") { return true }
        if lowered.contains("notificationcenterui") { return true }
        return false
    }

    private func adjustedCaretRectForSiri(_ rect: CGRect, focusRect: CGRect?) -> CGRect {
        guard let focus = focusRect, focus.height > 0 else { return rect }
        let width = rect.width > 0 ? rect.width : 2
        let baseHeight = rect.height > 0 ? rect.height : min(18, focus.height * 0.6)
        var height = baseHeight
        var y = rect.minY

        // If the caret rect is clearly outside the focused bounds, recenter within the focus.
        let outOfBounds = rect.midY < focus.minY - 2 || rect.midY > focus.maxY + 2
        if outOfBounds {
            height = min(max(baseHeight, 12), max(14, focus.height * 0.6))
            let targetY = focus.midY - height / 2
            y = min(max(targetY, focus.minY), focus.maxY - height)
        } else if rect.height <= 2 {
            // Expand tiny rects but keep the original vertical alignment.
            height = min(max(baseHeight, 12), max(14, focus.height * 0.6))
            y = min(max(rect.midY - height / 2, focus.minY), focus.maxY - height)
        }

        return CGRect(x: rect.minX, y: y, width: width, height: height)
    }

    private func axFocusedElementDebugSignatureThrottled() -> String {
        let now = Date()
        if now.timeIntervalSince(lastAXFocusDebugCheckAt) < 0.18 {
            return cachedAXFocusDebugSignature
        }
        lastAXFocusDebugCheckAt = now

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            cachedAXFocusDebugSignature = "focus=nil"
            return cachedAXFocusDebugSignature
        }
        let element = focusedElement as! AXUIElement

        func boolAttr(_ name: CFString) -> Bool {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return false }
            if let b = value as? Bool { return b }
            if let n = value as? NSNumber { return n.boolValue }
            return false
        }

        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String ?? "-")
            : "-"

        var selectedRangeRef: CFTypeRef?
        let hasSelectedRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success
        var markerRangeRef: CFTypeRef?
        let hasMarkerRange = AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef) == .success

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "-"

        cachedAXFocusDebugSignature = "role=\(role),editable=\(boolAttr("AXEditable" as CFString) ? 1 : 0),sel=\(hasSelectedRange ? 1 : 0),marker=\(hasMarkerRange ? 1 : 0),pid=\(pid),bundle=\(bundleID)"
        return cachedAXFocusDebugSignature
    }

    private func isTopBarInputRect(_ r: CGRect) -> Bool {
        // Browser address bars / top search fields live near the top of the visible frame.
        // In that case, placing the HUD above the input will often get clamped into awkward corners.
        guard r.width > 0, r.height > 0 else { return false }
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(r) }) ??
            NSScreen.screens.first(where: { $0.frame.intersects(r) }) ??
            NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        guard vf.height > 0 else { return false }
        let topGap = max(0, vf.maxY - r.maxY)
        return topGap < 90
    }
    
    // MARK: - Internal Logic
    
    private func setupSubscriptions() {
        // 1. Detector Updates (Caret moved)
        detector.$currentUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestReposition()
            }
            .store(in: &cancellables)

        // 2. State updates that can affect layout.
        Publishers.CombineLatest4(state.$mode, state.$message, state.$language, state.$isTypingContext)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestReposition()
            }
            .store(in: &cancellables)

        // 3. Focus change in "weird" UIs (Codex/Antigravity) often doesn't move the caret rect.
        // Poll at low frequency while HUD is visible so clicking elsewhere can exit input mode
        // without requiring ESC.
        Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                HeadMotionManager.shared.refreshTransientRecognitionControlModeIfNeeded()
                guard let panel = self.hudWindow, panel.isVisible else { return }
                if self.state.mode == .hidden { return }
                self.requestReposition()
            }
            .store(in: &cancellables)

    }

    private func requestReposition(immediate: Bool = false) {
        pendingRepositionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.repositionWindow()
        }
        pendingRepositionWorkItem = work
        if immediate {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012, execute: work)
        }
    }
    
    private func ensureWindow() {
        guard hudWindow == nil else { return }
        
        let rootView = HUDView(state: state)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentViewController = hostingController
        
        self.hudWindow = panel
    }

    private func ensureCaretDebugWindow() {
        guard caretDebugWindow == nil else { return }

        let size = CaretDebugDotView.dotSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.ignoresMouseEvents = true
        panel.contentView = CaretDebugDotView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        caretDebugWindow = panel
    }

    private func updateCaretDebugDot(point: CGPoint?, enabled: Bool, color: NSColor = .systemRed) {
        guard enabled, let point else {
            caretDebugWindow?.orderOut(nil)
            return
        }
        ensureCaretDebugWindow()
        guard let panel = caretDebugWindow else { return }
        if let dotView = panel.contentView as? CaretDebugDotView {
            dotView.updateColor(color)
        }
        let size = CaretDebugDotView.dotSize
        let origin = CGPoint(x: point.x - size / 2, y: point.y - size / 2)
        let rect = CGRect(origin: origin, size: CGSize(width: size, height: size))
        if panel.frame.size != rect.size {
            panel.setFrame(rect, display: false)
        } else {
            panel.setFrameOrigin(rect.origin)
        }
        if !panel.isVisible {
            panel.alphaValue = 1.0
            panel.orderFront(nil)
        }
    }
    
    private func ensureWindowVisible() {
        ensureWindow()
        guard let panel = hudWindow else {
            updateCaretDebugDot(point: nil, enabled: false)
            return
        }
        guard !shouldSuppressHUDForAetherForegroundWindow() else {
            logHUDVisibilityIfNeeded(reason: "ensure-visible-suppressed-aether-frontmost", panel: panel, force: true)
            panel.orderOut(nil)
            return
        }
        if !panel.isVisible || panel.alphaValue < 0.9 {
            logHUDVisibilityIfNeeded(reason: "ensure-visible-before-front", panel: panel, force: true)
            panel.alphaValue = 1.0
            panel.orderFront(nil)
            logHUDVisibilityIfNeeded(reason: "ensure-visible-after-front", panel: panel, force: true)
        }
    }

    private func repositionWindow() {
        // [Ghost Keyboard Fix] Accessing mode from state should be main-thread safe enough here
        // If hidden, DO NOT move or update content (prevents "Ghost Keyboard" when fading out)
        os_log("HUDManager: repositionWindow called, mode=%{public}@", log: log, type: .default, String(describing: state.mode))
        if state.mode == .hidden {
            updateCaretDebugDot(point: nil, enabled: false)
            return
        }

        guard let panel = hudWindow else { return }
        logHUDVisibilityIfNeeded(reason: "reposition-entry", panel: panel)

        if shouldSuppressHUDForAetherForegroundWindow() {
            logHUDVisibilityIfNeeded(reason: "reposition-suppressed-aether-frontmost", panel: panel, force: true)
            panel.orderOut(nil)
            updateCaretDebugDot(point: nil, enabled: false)
            return
        }
        
        // --- Fullscreen Video Check ---
        if shouldSuppressHUDForFullscreenVideo() {
            logHUDVisibilityIfNeeded(reason: "reposition-suppressed-fullscreen-video", panel: panel, force: true)
            hideForHiddenCursor()
            updateCaretDebugDot(point: nil, enabled: false)
            return
        }
        // Restore alpha if returning from fullscreen suppression
        if hudWindow?.alphaValue ?? 1 < 0.9, state.mode != .hidden {
            hudWindow?.alphaValue = 1.0
        }
        
        let update = detector.currentUpdate
        let mouseLoc = currentCursorLocation()
        let now = Date()

        // 1. Determine Anchor & Mode
        var anchor = mouseLoc
        // `state.isTypingContext` is the current HUD display state derived from the
        // shared arbiter. Layout may still probe caret geometry below, but it must not
        // compute and write back a second semantic typing verdict or we recreate the
        // HUD/SpeechManager feedback loop.
        let uiTypingMode = state.isTypingContext
        let wasTypingMode = state.isTypingContext
        var layoutTypingMode = false
        var preferAboveInput = false
        var preferBelowInput = false
        var typingRect: CGRect? = nil
        let hudAnchorTraceEnabled = UserDefaults.standard.object(forKey: "hudAnchorTraceEnabled") as? Bool ?? false
        let caretDebugEnabled = false
        var axFocusRect: CGRect?
        var axCaret: CGRect?
        var axEstimated: (point: CGPoint, bounds: CGRect)?
        var axFocusInfo: String = ""
        var axTrusted = false
        if uiTypingMode || hudAnchorTraceEnabled || caretDebugEnabled {
            axFocusRect = axFocusedElementRectThrottled()
            axCaret = axCaretRectThrottled()
            axEstimated = axEstimatedCaretContextThrottled()
            if hudAnchorTraceEnabled {
                axFocusInfo = axFocusedElementDebugSignatureThrottled()
                axTrusted = AXIsProcessTrusted()
            }
        }

        if !uiTypingMode {
            // Prevent stale anchors from "sticking" after focus leaves an input box.
            lastGoodTypingRect = nil
            lastGoodTypingRectAt = .distantPast
        }

        if uiTypingMode {
            // Prefer caret detector input rect when it's sane; otherwise fall back to the AX focused element bounds.
            if let r = update.inputRect, !isProbablyWholeWindowRect(r) {
                typingRect = r
            } else if let r = axFocusRect, !isProbablyWholeWindowRect(r) {
                typingRect = r
            }
            typingRect = stableTypingRect(now: now, candidate: typingRect)

            // Top-bar inputs (browser address bar) should prefer placing the HUD below,
            // otherwise we tend to clamp into awkward "top right" positions.
            if let r = typingRect, isTopBarInputRect(r) {
                preferBelowInput = true
                preferAboveInput = false
            } else if let r = typingRect, r.height >= 54 || r.width >= 420 {
                // Large compose boxes should prefer staying above the input area so the HUD
                // does not cover the newest typed text near the caret.
                preferAboveInput = true
                preferBelowInput = false
            }
        }

        // If we just entered typing mode (often via keyboard focus like Cmd+L),
        // initialize a reasonable "interaction point" so we don't bias the HUD far away.
        if uiTypingMode, !wasTypingMode, let r = typingRect {
            let isTopBar = isTopBarInputRect(r)
            let x: CGFloat
            if isTopBar {
                // Address bar caret is frequently at the end when focused via keyboard.
                x = r.maxX - 16
            } else {
                let bias = min(220, r.width * 0.33)
                x = r.minX + bias
            }
            lastInputInteractionPoint = CGPoint(x: min(max(x, r.minX + 8), r.maxX - 8), y: r.midY)
            lastInputInteractionAt = now
        }

        if uiTypingMode, let r = typingRect, r.contains(mouseLoc) {
            // Capture the last interaction point within the input box so we can estimate caret X
            // without "following the mouse" after focus leaves the input.
            lastInputInteractionPoint = mouseLoc
            lastInputInteractionAt = now
        }
        
        if uiTypingMode {
            let strongCaret = update.caretRect.flatMap { isLikelyCaretRect($0) ? $0 : nil }
            let siriLike = isSiriLikeBundle(update.sourceBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            if siriLike, let estimated = axEstimated {
                anchor = estimated.point
                layoutTypingMode = true
                // Keep the typing rect so we avoid covering the input when no other signal exists.
                if typingRect == nil {
                    typingRect = estimated.bounds
                    typingRect = stableTypingRect(now: now, candidate: typingRect)
                }
            } else if let caret = strongCaret {
                let adjusted = siriLike ? adjustedCaretRectForSiri(caret, focusRect: axFocusRect) : caret
                anchor = CGPoint(x: adjusted.midX, y: adjusted.midY)
                layoutTypingMode = true
            } else if update.isSticky,
                      let last = detector.recentCaretRect(),
                      isLikelyCaretRect(last) {
                let adjusted = siriLike ? adjustedCaretRectForSiri(last, focusRect: axFocusRect) : last
                anchor = CGPoint(x: adjusted.midX, y: adjusted.midY)
                layoutTypingMode = true
            } else if let axCaret {
                // Web-based UIs (Codex/Antigravity) often fail caret detection but expose bounds-for-range.
                let adjusted = siriLike ? adjustedCaretRectForSiri(axCaret, focusRect: axFocusRect) : axCaret
                anchor = CGPoint(x: adjusted.midX, y: adjusted.midY)
                layoutTypingMode = true
            } else if let axEstimated {
                // If bounds-for-range is unavailable, fall back to an estimated caret X within focused bounds.
                anchor = axEstimated.point
                layoutTypingMode = true
                preferAboveInput = true
                // Critical: treat focused bounds as typingRect so the HUD avoids covering the input text.
                if typingRect == nil {
                    typingRect = axEstimated.bounds
                    typingRect = stableTypingRect(now: now, candidate: typingRect)
                }
            } else if let r = typingRect {
                // Typing context, but no caret geometry: estimate caret X from recent input interaction,
                // and anchor ABOVE the input box to avoid colliding with the input rect.
                let recentInteraction = now.timeIntervalSince(lastInputInteractionAt) < 1.8
                let estimatedX: CGFloat = {
                    if recentInteraction, let p = lastInputInteractionPoint {
                        return min(max(p.x, r.minX + 8), r.maxX - 8)
                    }
                    if isTopBarInputRect(r) {
                        // If we have no interaction signal, assume address-bar caret near the end.
                        return r.maxX - 16
                    }
                    // No interaction signal.
                    // For wide "prompt" inputs, bias closer to the left so we don't end up far from caret.
                    if r.width > 420 {
                        let bias = min(140, r.width * 0.2)
                        return min(max(r.minX + bias, r.minX + 8), r.maxX - 8)
                    }
                    let bias = min(220, r.width * 0.33)
                    return min(max(r.minX + bias, r.minX + 8), r.maxX - 8)
                }()
                if preferBelowInput || isTopBarInputRect(r) {
                    preferBelowInput = true
                    preferAboveInput = false
                    anchor = CGPoint(x: estimatedX, y: r.minY)
                } else {
                    anchor = CGPoint(x: estimatedX, y: r.maxY)
                    preferAboveInput = true
                }
                layoutTypingMode = true
            }
        }
        
        if state.recognitionControlMode == .dictation && !layoutTypingMode {
            panel.orderOut(nil)
            updateCaretDebugDot(point: nil, enabled: false)
            return
        }

        // If we are in a typing context (keyboard icon) but we don't have a reliable caret/sticky anchor,
        // do NOT fall back to mouse-follow. Keeping the HUD stable is preferable to jitter.
        // This also matches Codex/Antigravity-style UIs where caret geometry is often missing or misleading.
        if uiTypingMode && !layoutTypingMode && panel.isVisible {
            // In explicit dictation mode, freezing at stale coordinates is worse than mouse-follow fallback.
            // Keep the strict "hold position" behavior only for auto mode.
            if state.recognitionControlMode == .auto {
                return
            }
        }
        
        // Do not let the HUD steal clicks from other apps. Keep click handling only
        // when Aether itself is frontmost; otherwise the overlay must be pass-through.
        let interactiveModes: [HUDMode] = [.listening, .command, .dictation]
        let isAetherFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        panel.ignoresMouseEvents = !(interactiveModes.contains(state.mode) && isAetherFrontmost)
        
        // 2. Determine Reference Screen
        let referencePoint = layoutTypingMode ? anchor : mouseLoc
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = currentScreen.visibleFrame
        
        // 3. Size Calculation
        // Avoid forcing a synchronous layout pass here; doing so during app startup
        // can re-enter SwiftUI graph updates and trigger AG precondition crashes.
        let existingSize = panel.frame.size
        var size: CGSize
        if let measuredSize = measuredHUDContentSize(for: panel) {
            size = measuredSize
        } else if existingSize.width > 1, existingSize.height > 1 {
            size = existingSize
        } else {
            size = CGSize(width: 220, height: 60)
        }
        
        // 4. Candidate Position Evaluation
        let padding: CGFloat = layoutTypingMode ? 18 : 16
        size.width = min(size.width, max(visibleFrame.width - padding * 2, 72))
        size.height = min(size.height, max(visibleFrame.height - padding * 2, 34))
        
        let siriLike = isSiriLikeBundle(update.sourceBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let strongCaretRect = update.caretRect.flatMap { isLikelyCaretRect($0) ? $0 : nil }
        let siriPreferEstimated = siriLike && axEstimated != nil
        let adjustedStrongCaretRect = strongCaretRect.map { rect -> CGRect in
            var r = rect
            if update.caretSourceLabel == "AX" {
                r = adjustCaretRectByLineHeight(r)
            }
            if siriLike {
                r = adjustedCaretRectForSiri(r, focusRect: axFocusRect)
            }
            return r
        }
        let adjustedAxCaret = axCaret.map { siriLike ? adjustedCaretRectForSiri($0, focusRect: axFocusRect) : $0 }
        var effectiveCaretRect = siriPreferEstimated ? nil : (adjustedStrongCaretRect ?? adjustedAxCaret)
        let caretDebugPoint: CGPoint?
        let caretDebugColor: NSColor
        if siriPreferEstimated, let estimated = axEstimated {
            caretDebugPoint = estimated.point
            caretDebugColor = .systemRed
            if effectiveCaretRect == nil {
                let width: CGFloat = 2
                let height: CGFloat = 18
                effectiveCaretRect = CGRect(
                    x: estimated.point.x - width / 2,
                    y: estimated.point.y - height / 2,
                    width: width,
                    height: height
                )
            }
        } else if let caret = adjustedStrongCaretRect {
            caretDebugPoint = CGPoint(x: caret.midX, y: caret.midY)
            caretDebugColor = .systemGreen
        } else if let caret = adjustedAxCaret {
            caretDebugPoint = CGPoint(x: caret.midX, y: caret.midY)
            caretDebugColor = .systemYellow
        } else if let estimated = axEstimated {
            caretDebugPoint = estimated.point
            caretDebugColor = .systemRed
            if effectiveCaretRect == nil {
                let width: CGFloat = 2
                let height: CGFloat = 18
                effectiveCaretRect = CGRect(
                    x: estimated.point.x - width / 2,
                    y: estimated.point.y - height / 2,
                    width: width,
                    height: height
                )
            }
        } else {
            caretDebugPoint = caretDebugEnabled ? anchor : nil
            caretDebugColor = .systemRed
        }
        let hasCaretAnchor = effectiveCaretRect != nil
        updateCaretDebugDot(point: caretDebugPoint, enabled: caretDebugEnabled, color: caretDebugColor)
        if caretDebugEnabled {
            state.caretDebugIndicatorVisible = true
            state.caretDebugIndicatorColor = Color(caretDebugColor)
            let sourceLabel: String = {
                if siriPreferEstimated, axEstimated != nil {
                    return "EST"
                }
                if adjustedStrongCaretRect != nil {
                    return update.caretSourceLabel ?? "AX"
                }
                if adjustedAxCaret != nil {
                    return "AX"
                }
                if axEstimated != nil {
                    return "EST"
                }
                return "ANCHOR"
            }()
            if state.caretDebugIndicatorLabel != sourceLabel {
                state.caretDebugIndicatorLabel = sourceLabel
            }
        } else if state.caretDebugIndicatorVisible {
            state.caretDebugIndicatorVisible = false
            state.caretDebugIndicatorLabel = ""
        }

        // [Legacy Order]
        // Typing Mode: Prefer Right-Center (input-adjacent), then fall back to corners.
        // Command Mode: Prefer Bottom-Right (Natural mouse follow)
        let candidates: [(BindingPosition, String)]
        if layoutTypingMode {
            if hasCaretAnchor {
                // Caret-first: below center, then above center, then other options.
                candidates = [
                    (.bottomCenter, "BC"),
                    (.topCenter, "TC"),
                    (.bottomRight, "BR"),
                    (.bottomLeft, "BL"),
                    (.topRight, "TR"),
                    (.topLeft, "TL"),
                    (.rightCenter, "RC"),
                    (.leftCenter, "LC")
                ]
            } else if preferBelowInput {
                candidates = [
                    (.bottomRight, "BR"),
                    (.bottomCenter, "BC"),
                    (.bottomLeft, "BL"),
                    (.rightCenter, "RC"),
                    (.leftCenter, "LC"),
                    (.topRight, "TR"),
                    (.topCenter, "TC"),
                    (.topLeft, "TL")
                ]
            } else if preferAboveInput {
                candidates = [
                    (.topRight, "TR"),
                    (.topCenter, "TC"),
                    (.topLeft, "TL"),
                    (.rightCenter, "RC"),
                    (.leftCenter, "LC"),
                    (.bottomRight, "BR"),
                    (.bottomCenter, "BC"),
                    (.bottomLeft, "BL")
                ]
            } else {
                candidates = [
                    (.bottomRight, "BR"),
                    (.rightCenter, "RC"),
                    (.bottomCenter, "BC"),
                    (.topRight, "TR"),
                    (.topCenter, "TC"),
                    (.leftCenter, "LC"),
                    (.bottomLeft, "BL"),
                    (.topLeft, "TL")
                ]
            }
        } else {
            candidates = [
                (.bottomRight, "BR"), (.topRight, "TR"), (.bottomLeft, "BL"), (.topLeft, "TL")
            ]
        }
        
        var bestPos: CGPoint? = nil
        
        // [Legacy] Avoidance Zones
        var zones: [CGRect] = []
        let isInputMode = state.recognitionControlMode != .command
        let hasRecentCaretSignal = update.caretRect != nil || detector.recentCaretRect() != nil || axCaret != nil || axEstimated != nil
        let hasRecentTypingSignal = hasRecentCaretSignal || now.timeIntervalSince(lastInputInteractionAt) < 1.0
        let mouseAvoidPadding: CGFloat = max(CGFloat(20), min(CGFloat(48), min(size.width, size.height) * 0.3))
        let mouseInPanel = uiTypingMode && panel.isVisible && panel.frame.insetBy(dx: -mouseAvoidPadding, dy: -mouseAvoidPadding).contains(mouseLoc)
        if isInputMode && uiTypingMode && mouseInPanel {
            typingMouseAvoidUntil = now.addingTimeInterval(0.6)
        }
        let shouldAvoidMouse = isInputMode && uiTypingMode && (mouseInPanel || now < typingMouseAvoidUntil)
        let shouldAvoidTypingContext = isInputMode && uiTypingMode && hasRecentTypingSignal

        if shouldAvoidMouse || shouldAvoidTypingContext || (uiTypingMode && layoutTypingMode && typingRect != nil) {
            // Avoid Mouse
            if shouldAvoidMouse {
                let mouseAvoidRadius: CGFloat = 26
                zones.append(CGRect(x: mouseLoc.x - mouseAvoidRadius,
                                    y: mouseLoc.y - mouseAvoidRadius,
                                    width: mouseAvoidRadius * 2,
                                    height: mouseAvoidRadius * 2))
            }

            // Avoid Caret itself (Legacy: caret.insetBy(dx: -5, dy: -2))
            if shouldAvoidTypingContext, let caret = effectiveCaretRect {
                zones.append(caret.insetBy(dx: -8, dy: -6))
            }

            // Avoid Input Context (Text Area)
            if layoutTypingMode, let inputRect = typingRect ?? update.inputRect {
                 // When we have a caret anchor, avoid only the caret itself so the HUD can center below/above it.
                 // Otherwise, keep the HUD outside the input region.
                 if !hasCaretAnchor {
                     let largeInput = inputRect.height >= 220 || inputRect.width >= visibleFrame.width * 0.75
                     if largeInput {
                         let bandHeight: CGFloat = 36
                         let bandY = min(max(anchor.y - bandHeight / 2, inputRect.minY), inputRect.maxY - bandHeight)
                         let band = CGRect(x: inputRect.minX, y: bandY, width: inputRect.width, height: bandHeight)
                         zones.append(band.insetBy(dx: -8, dy: -6))
                     } else {
                         zones.append(inputRect.insetBy(dx: -14, dy: -12))
                     }
                 }
            }
        }

        if hasCaretAnchor {
            let centerCandidates: [BindingPosition] = [.bottomCenter, .topCenter]
            for cand in centerCandidates {
                var p = calculateCandidate(cand, anchor: anchor, size: size, padding: padding, isTyping: layoutTypingMode)
                p.x = min(max(p.x, visibleFrame.minX + 2), visibleFrame.maxX - size.width - 2)
                let rect = CGRect(origin: p, size: size)
                if visibleFrame.contains(rect) {
                    var collision = false
                    for zone in zones {
                        if rect.intersects(zone) {
                            collision = true
                            break
                        }
                    }
                    if !collision && isInputMode && uiTypingMode {
                        let mouseHit = rect.insetBy(dx: -8, dy: -8).contains(mouseLoc)
                        if mouseHit {
                            collision = true
                        }
                    }
                    if !collision {
                        bestPos = p
                        break
                    }
                }
            }
        }

        if bestPos == nil {
            for (cand, _) in candidates {
                let p = calculateCandidate(cand, anchor: anchor, size: size, padding: padding, isTyping: layoutTypingMode)
                let rect = CGRect(origin: p, size: size)
                
                // Rule 1: Must be within visible frame
                if visibleFrame.contains(rect) {
                    // Rule 2: Avoid Collision
                    var collision = false
                    for zone in zones {
                        if rect.intersects(zone) {
                            collision = true
                            break
                        }
                    }
                    if !collision && isInputMode && uiTypingMode {
                        let mouseHit = rect.insetBy(dx: -8, dy: -8).contains(mouseLoc)
                        if mouseHit {
                            collision = true
                        }
                    }
                    
                    if !collision {
                        bestPos = p
                        break
                    }
                }
            }
        }
        
        // 5. Fallback: choose the least-overlapping candidate when all collide
        if bestPos == nil {
            var bestOverlap = CGFloat.greatestFiniteMagnitude
            var bestOverlapPos: CGPoint? = nil
            for (cand, _) in candidates {
                let p = calculateCandidate(cand, anchor: anchor, size: size, padding: padding, isTyping: layoutTypingMode)
                let rect = CGRect(origin: p, size: size)
                if !visibleFrame.contains(rect) { continue }
                var overlap: CGFloat = 0
                for zone in zones {
                    let inter = rect.intersection(zone)
                    if !inter.isNull {
                        overlap += inter.width * inter.height
                    }
                }
                if overlap < bestOverlap {
                    bestOverlap = overlap
                    bestOverlapPos = p
                }
            }
            if let p = bestOverlapPos {
                bestPos = p
            }
        }

        // 6. Fallback: Edge Clamping & Smart Vertical Jump
        if bestPos == nil {
            var p = calculateCandidate(.bottomRight, anchor: anchor, size: size, padding: padding, isTyping: layoutTypingMode)
            
            // [Legacy Smart Fallback]: If inside text area, jump below it
            if layoutTypingMode, let _ = update.inputRect {
                // Not fully implementing the complex jump logic yet to avoid regressions,
                // relying on Clamping below.
            }
            
            // Clamp to visible frame (Legacy used 'padding' aka 16, not 8)
            p.x = max(visibleFrame.minX + padding, min(p.x, visibleFrame.maxX - size.width - padding))
            p.y = max(visibleFrame.minY + padding, min(p.y, visibleFrame.maxY - size.height - padding))

            // Legacy behavior: keep the HUD horizontally within the input box when in typing mode.
            // This prevents bottom-center placement from drifting far from the caret for long address bars.
            if layoutTypingMode, let r = typingRect {
                p.x = min(max(r.minX, p.x), r.maxX - size.width)
            }
            bestPos = p
        }
        
        if let pos = bestPos {
            var targetPos = pos
            if shouldAvoidMouse {
                mouseAvoidLockOrigin = pos
                mouseAvoidLockUntil = now.addingTimeInterval(0.8)
            } else if now > mouseAvoidLockUntil {
                mouseAvoidLockOrigin = nil
            }

            if let lock = mouseAvoidLockOrigin, now < mouseAvoidLockUntil {
                let lockRect = CGRect(origin: lock, size: size)
                let stillOccupied = lockRect.insetBy(dx: -8, dy: -8).contains(mouseLoc)
                if !stillOccupied {
                    targetPos = lock
                } else {
                    mouseAvoidLockOrigin = nil
                    mouseAvoidLockUntil = .distantPast
                }
            }

            let unclampedFinalOrigin: CGPoint
            var isPositionAnimating = false
            if panel.isVisible, panel.alphaValue > 0.01, let prev = lastSmoothedWindowOrigin {
                let dx = targetPos.x - prev.x
                let dy = targetPos.y - prev.y
                let dist = hypot(dx, dy)
                if dist < 1 {
                    unclampedFinalOrigin = targetPos
                } else {
                    isPositionAnimating = true
                    // Responsive follow:
                    // - large jumps snap to target to avoid trailing lag
                    // - small movements keep a light smoothing to reduce jitter
                    if dist > 36 {
                        unclampedFinalOrigin = targetPos
                    } else {
                        let alpha: CGFloat = 0.72
                        unclampedFinalOrigin = CGPoint(x: prev.x + dx * alpha, y: prev.y + dy * alpha)
                    }
                }
            } else {
                unclampedFinalOrigin = targetPos
            }
            let finalOrigin = clampedHUDOrigin(unclampedFinalOrigin, size: size, visibleFrame: visibleFrame, padding: padding)
            if state.isPositionAnimating != isPositionAnimating {
                state.isPositionAnimating = isPositionAnimating
            }
            panel.setFrame(NSRect(origin: finalOrigin, size: size), display: false)
            lastSmoothedWindowOrigin = finalOrigin
            if !panel.isVisible && (state.mode != .hidden) {
                ensureWindowVisible()
            }
            logHUDVisibilityIfNeeded(reason: "reposition-exit", panel: panel)

            // Lightweight file trace for weird UIs (Codex/Antigravity).
            // Only logs when the computed anchor/typing rect or final position changes meaningfully.
            if hudAnchorTraceEnabled, now.timeIntervalSince(lastAnchorTraceAt) > 0.12 {
                lastAnchorTraceAt = now
                func fmt(_ r: CGRect?) -> String {
                    guard let r else { return "nil" }
                    return "\(Int(r.origin.x)),\(Int(r.origin.y)),\(Int(r.size.width)),\(Int(r.size.height))"
                }
                let lastPtSig: String = {
                    guard let p = lastInputInteractionPoint, lastInputInteractionAt != .distantPast else { return "nil" }
                    let ageMs = Int(now.timeIntervalSince(lastInputInteractionAt) * 1000)
                    return "\(Int(p.x)),\(Int(p.y))@\(ageMs)ms"
                }()
                let sig = "mode=\(state.mode.rawValue) uiTyping=\(uiTypingMode) layoutTyping=\(layoutTypingMode) sticky=\(update.isSticky) axTrusted=\(axTrusted ? 1 : 0) anchor=\(Int(anchor.x)),\(Int(anchor.y)) lastPt=\(lastPtSig) inputRect=\(fmt(update.inputRect)) typingRect=\(fmt(typingRect)) axCaret=\(fmt(axCaret)) axFocus=\(fmt(axFocusRect)) axInfo=\(axFocusInfo) lastGood=\(fmt(lastGoodTypingRect)) caret=\(fmt(update.caretRect)) final=\(Int(pos.x)),\(Int(pos.y)) size=\(Int(size.width))x\(Int(size.height))"
                if sig != lastAnchorTraceSignature {
                    lastAnchorTraceSignature = sig
                    let line = "\(now): \(sig)\n"
                    if let data = line.data(using: .utf8) {
                        let path = "/tmp/aether_hud_anchor_trace.txt"
                        if !FileManager.default.fileExists(atPath: path) {
                            FileManager.default.createFile(atPath: path, contents: nil)
                        }
                        if let fh = FileHandle(forWritingAtPath: path) {
                            fh.seekToEndOfFile()
                            fh.write(data)
                            try? fh.close()
                        }
                    }
                }
            }
        }
    }

    private func measuredHUDContentSize(for panel: NSPanel) -> CGSize? {
        guard let hostingView = panel.contentViewController?.view else { return nil }
        let fitting = hostingView.fittingSize
        guard fitting.width.isFinite, fitting.height.isFinite else { return nil }
        guard fitting.width > 24, fitting.height > 20 else { return nil }
        let minimumWidth: CGFloat = isTwoStateSpeechMode(state.mode) ? 72 : 96
        let clampedWidth = min(max(ceil(fitting.width), minimumWidth), 360)
        let clampedHeight = min(max(ceil(fitting.height), 34), 180)
        let resolvedWidth: CGFloat
        if shouldPreserveMeasuredWidth(for: state.mode) {
            let stickyWidth = max(stickyMeasuredContentWidth ?? 0, clampedWidth)
            stickyMeasuredContentWidth = stickyWidth
            resolvedWidth = stickyWidth
        } else {
            stickyMeasuredContentWidth = nil
            resolvedWidth = clampedWidth
        }
        return CGSize(width: resolvedWidth, height: clampedHeight)
    }

    private func shouldPreserveMeasuredWidth(for mode: HUDMode) -> Bool {
        switch mode {
        case .dragging:
            return true
        case .hidden, .standby, .feedback, .listening, .command, .dictation, .organizing, .typing, .executing, .optimizing, .checking, .processing:
            return false
        }
    }

    private func isTwoStateSpeechMode(_ mode: HUDMode) -> Bool {
        switch mode {
        case .listening, .command, .dictation, .organizing, .typing, .executing, .optimizing, .checking, .processing:
            return true
        case .hidden, .standby, .feedback, .dragging:
            return false
        }
    }

    private func clampedHUDOrigin(_ origin: CGPoint, size: CGSize, visibleFrame: CGRect, padding: CGFloat) -> CGPoint {
        let horizontalInset = min(padding, max((visibleFrame.width - size.width) / 2, 0))
        let verticalInset = min(padding, max((visibleFrame.height - size.height) / 2, 0))
        return CGPoint(
            x: max(visibleFrame.minX + horizontalInset, min(origin.x, visibleFrame.maxX - size.width - horizontalInset)),
            y: max(visibleFrame.minY + verticalInset, min(origin.y, visibleFrame.maxY - size.height - verticalInset))
        )
    }

    private func hudRectSummary(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width))x\(Int(rect.size.height))"
    }

    private func hudAlphaSummary(_ alpha: CGFloat) -> String {
        String(format: "%.2f", alpha)
    }

    private func logHUDVisibilityIfNeeded(reason: String, panel: NSPanel, force: Bool = false) {
        let now = Date()
        let screenName = panel.screen?.localizedName ?? "nil"
        let screenFrame = hudRectSummary(panel.screen?.visibleFrame)
        let frame = hudRectSummary(panel.frame)
        let alpha = hudAlphaSummary(panel.alphaValue)
        let occlusionVisible = panel.occlusionState.contains(.visible) ? 1 : 0
        let activeSpace = panel.isOnActiveSpace ? 1 : 0
        let signature =
            "reason=\(reason) mode=\(state.mode.rawValue) visible=\(panel.isVisible ? 1 : 0) alpha=\(alpha) " +
            "occlusionVisible=\(occlusionVisible) activeSpace=\(activeSpace) level=\(panel.level.rawValue) " +
            "typing=\(state.isTypingContext ? 1 : 0) ignoresMouse=\(panel.ignoresMouseEvents ? 1 : 0) " +
            "frame=\(frame) screen=\(screenName) screenFrame=\(screenFrame)"

        if !force,
           signature == lastVisibilityDiagnosticSignature,
           now.timeIntervalSince(lastVisibilityDiagnosticAt) < 1.0 {
            return
        }

        lastVisibilityDiagnosticSignature = signature
        lastVisibilityDiagnosticAt = now
        os_log("[HUDVisibility] %{public}@", log: log, type: .default, signature)
    }
    
    // --- Fullscreen Video Logic ---
    
    private func shouldSuppressHUDForFullscreenVideo() -> Bool {
        // Restore the historically stable model from 3a5db83:
        // fullscreen window + cursor-hidden idle threshold.
        guard UserDefaults.standard.object(forKey: "suppressHUDInFullscreenVideo") as? Bool ?? true else {
            return false
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let front = app.bundleIdentifier?.lowercased() else {
            os_log("Fullscreen Suppression: No frontmost app", log: log, type: .default)
            return false
        }
        if isSiriLikeBundle(front) {
            os_log("Fullscreen Suppression: Bailed for Siri/Spotlight", log: log, type: .default)
            return false
        }
        // Never suppress while user is in typing context.
        if state.isTypingContext {
            os_log("Fullscreen Suppression: Bailed due to Typing Context", log: log, type: .default)
            return false
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(currentCursorLocation()) }) ?? NSScreen.main else {
            os_log("Fullscreen Suppression: No screen found", log: log, type: .default)
            return false
        }

        let now = Date()
        if front == cachedFullscreenSuppressionBundleID,
           now.timeIntervalSince(lastFullscreenSuppressionCheckAt) < 0.22 {
            return cachedFullscreenSuppressionResult
        }
        lastFullscreenSuppressionCheckAt = now
        cachedFullscreenSuppressionBundleID = front

        let isFullscreenByWindow = isFrontmostFocusedWindowLikelyFullscreen(app: app, on: screen)

        let inactivity = now.timeIntervalSince(lastPointerMoveAt)
        let cursorHidden = !CGCursorIsVisible()
        let result = isFullscreenByWindow && ((cursorHidden && inactivity > 0.5) || inactivity > 3.0)

        os_log("Fullscreen Suppression: app=%{public}@, isFS=%d, inactivity=%.1f, cursorHidden=%d, result=%d",
               log: log, type: .default, front, isFullscreenByWindow ? 1 : 0, inactivity, cursorHidden ? 1 : 0, result ? 1 : 0)

        cachedFullscreenSuppressionResult = result
        return result
    }

    private func shouldSuppressHUDForAetherForegroundWindow() -> Bool {
        // Aether relies on the HUD as the primary in-app speech feedback surface too.
        // Hiding it whenever any Aether window is frontmost makes dictation/command feedback disappear
        // inside the app itself, which regressed developer and settings workflows.
        false
    }

    private func isFrontmostFocusedWindowLikelyFullscreen(app: NSRunningApplication, on screen: NSScreen) -> Bool {
        let appAX = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let focusedWindowRef else {
            return false
        }

        let windowAX = focusedWindowRef as! AXUIElement
        
        // Space-Aware Check: Detect if the current space is a Fullscreen Space (Type 4)
        // This is the logic used by Aion/ProcessZero.
        let cid = CGSMainConnectionID()
        let displayUUID = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID()).takeRetainedValue()
        let uuidString = CFUUIDCreateString(nil, displayUUID)!
        let currentSpaceID = CGSManagedDisplayGetCurrentSpace(cid, uuidString)
        
        os_log("Fullscreen Suppression: Checking SpaceID %llu", log: log, type: .default, currentSpaceID)
        
        if let allSpaces = CGSCopyManagedDisplaySpaces(cid, uuidString) as? [[String: Any]] {
            for spaceDict in allSpaces {
                if let sid = spaceDict["id64"] as? NSNumber, sid.uint64Value == currentSpaceID {
                    let type = spaceDict["type"] as? Int ?? 0
                    os_log("Fullscreen Suppression: current space type is %d", log: log, type: .default, type)
                    if type == 4 { // kCGSSpaceFullscreen
                        os_log("Fullscreen Suppression: Space-Type 4 detected (Dedicated Fullscreen Space)", log: log, type: .default)
                        return true
                    }
                }
            }
        }

        // Global Geometric Check: Detect any window (including Renderer Helpers) that covers the screen.
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        if let windowInfos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for info in windowInfos {
                // Must be in a high enough layer (usually 0 is normal apps, but fullscreen can be higher)
                guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0 else { continue }
                guard let boundsValue = info[kCGWindowBounds as String] else { continue }
                let boundsDict = boundsValue as! CFDictionary
                guard let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
                
                // If a window covers >98% of the target screen, it's effectively a fullscreen scenario.
                if let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.5 {
                    let wRatio = bounds.width / screen.frame.width
                    let hRatio = bounds.height / screen.frame.height
                    
                    if wRatio > 0.98 && hRatio > 0.98 {
                        let owner = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
                        let name = info[kCGWindowName as String] as? String ?? "-"
                        os_log("Fullscreen Suppression: Geometric Match - %{public}@ (%{public}@), Layer: %d", log: log, type: .default, owner, name, layer)
                        return true
                    }
                }
            }
        }
        
        // Final fallback: Scan all windows of the current frontmost app for AXFullScreen.
        var windowList: CFTypeRef?
        if AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowList) == .success,
           let windows = windowList as? [AXUIElement] {
            for win in windows {
                var fs: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &fs) == .success {
                    if let b = fs as? Bool, b { return true }
                    if let n = fs as? NSNumber, n.boolValue { return true }
                }
            }
        }

        func cgPoint(_ e: AXUIElement, _ key: CFString) -> CGPoint? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, key, &v) == .success,
                  let axv = v,
                  CFGetTypeID(axv) == AXValueGetTypeID() else { return nil }
            let value = axv as! AXValue
            guard AXValueGetType(value) == .cgPoint else { return nil }
            var point = CGPoint.zero
            return AXValueGetValue(value, .cgPoint, &point) ? point : nil
        }

        func cgSize(_ e: AXUIElement, _ key: CFString) -> CGSize? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, key, &v) == .success,
                  let axv = v,
                  CFGetTypeID(axv) == AXValueGetTypeID() else { return nil }
            let value = axv as! AXValue
            guard AXValueGetType(value) == .cgSize else { return nil }
            var size = CGSize.zero
            return AXValueGetValue(value, .cgSize, &size) ? size : nil
        }

        guard let pos = cgPoint(windowAX, kAXPositionAttribute as CFString),
              let size = cgSize(windowAX, kAXSizeAttribute as CFString) else {
            return false
        }

        let windowRect = CGRect(origin: pos, size: size)
        let screenRect = screen.frame
        let tolerance: CGFloat = 10

        let coversScreen =
            abs(windowRect.minX - screenRect.minX) <= tolerance &&
            abs(windowRect.minY - screenRect.minY) <= tolerance &&
            abs(windowRect.maxX - screenRect.maxX) <= tolerance &&
            abs(windowRect.maxY - screenRect.maxY) <= tolerance

        return coversScreen
    }

    private func hideForHiddenCursor() {
        guard let panel = hudWindow, panel.isVisible == true else { return }
        // Already fading or hidden
        guard panel.alphaValue > 0.05 else { return }
        // Animate fade-out to visually sync with cursor disappearance
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, panel.alphaValue <= 0.05 else { return }
            self.hudWindow?.orderOut(nil)
        })
    }
    
    private enum BindingPosition {
        case topRight, bottomRight, topLeft, bottomLeft, topCenter, bottomCenter, rightCenter, leftCenter
    }
    
    private func calculateCandidate(_ pos: BindingPosition, anchor: CGPoint, size: CGSize, padding: CGFloat, isTyping: Bool) -> CGPoint {
        // Typing Mode: Use padding (16) to create gap from caret.
        // Control Mode: Use 24 to clear cursor.
        let yOffset: CGFloat = isTyping ? padding : 24
        
        switch pos {
        case .topRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y + yOffset)
        case .topLeft:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y + yOffset)
        case .topCenter:
            return CGPoint(x: anchor.x - size.width / 2, y: anchor.y + yOffset)
        case .bottomRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y - size.height - padding)
        case .bottomLeft:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y - size.height - padding)
        case .bottomCenter:
            return CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - padding)
        case .rightCenter:
            return CGPoint(x: anchor.x + padding, y: anchor.y - size.height / 2)
        case .leftCenter:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y - size.height / 2)
        }
    }

    private func currentCursorLocation() -> CGPoint {
        NSEvent.mouseLocation
    }
    
    // MARK: - Hide Logic
    
    private func scheduleHide(delay: TimeInterval, token: UUID? = nil) {
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            if let token {
                self?.restoreAfterTemporaryHide(token: token)
            } else {
                self?.performHide()
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    
    private func cancelHide() {
        hideTask?.cancel()
    }

    private func hideLanguageIndicator() {
        languageIndicatorHideTask?.cancel()
        languageIndicatorHideTask = nil
        guard state.isLanguageIndicatorVisible else { return }
        state.isLanguageIndicatorVisible = false
        requestReposition(immediate: true)
    }
    
    private func performHide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.hudWindow?.animator().alphaValue = 0
        }, completionHandler: {
            self.stickyMeasuredContentWidth = nil
            self.lastSmoothedWindowOrigin = nil
            self.hudWindow?.orderOut(nil)
        })
    }

    private func restoreAfterTemporaryHide(token: UUID) {
        guard activeTemporaryToken == token else { return }

        let fallback = activeTemporaryFallbackSnapshot
        activeTemporaryToken = nil
        activeTemporaryFallbackSnapshot = nil

        if let fallback, fallback.mode != .hidden {
            update(
                mode: fallback.mode,
                message: fallback.message,
                language: fallback.language,
                recognitionControlMode: fallback.recognitionControlMode,
                inputDeviceIcon: fallback.inputDeviceIcon,
                inputDeviceHealth: fallback.inputDeviceHealth,
                contextIcon: fallback.contextIcon
            )
            return
        }

        update(
            mode: .hidden,
            message: "",
            language: state.language,
            recognitionControlMode: state.recognitionControlMode,
            inputDeviceIcon: state.inputDeviceIcon,
            inputDeviceHealth: state.inputDeviceHealth,
            contextIcon: state.contextIcon
        )
    }
}
