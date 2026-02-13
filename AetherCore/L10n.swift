import SwiftUI

enum L10n {
    // Generic
    static let on: LocalizedStringKey = "generic.on"
    static let off: LocalizedStringKey = "generic.off"
    static let idle: LocalizedStringKey = "generic.idle"
    static let ready: LocalizedStringKey = "generic.ready"
    static let tracking: LocalizedStringKey = "generic.tracking"

    // App
    static let projectTitle: LocalizedStringKey = "app.project_title"

    // Status
    static let perceptionNetwork: LocalizedStringKey = "status.perception_network"
    static let pointerOutput: LocalizedStringKey = "status.pointer_output"
    static let textOutput: LocalizedStringKey = "status.text_output"
    static let mode: LocalizedStringKey = "status.mode"
    static let modeDriverOnly: LocalizedStringKey = "status.mode.driver_only"
    static let modeAuto: LocalizedStringKey = "status.mode.auto"

    // Rows
    static let virtualHID: LocalizedStringKey = "row.virtual_hid"
    static let airPodsMatrix: LocalizedStringKey = "row.airpods_matrix"
    static let voice: LocalizedStringKey = "row.voice"
    static let lidSensor: LocalizedStringKey = "row.lid_sensor"

    // Permissions
    static let permissionsTitle: LocalizedStringKey = "permissions.title"
    static let permissionAccessibility: LocalizedStringKey = "permissions.accessibility"
    static let permissionMicrophone: LocalizedStringKey = "permissions.microphone"
    static let permissionSpeech: LocalizedStringKey = "permissions.speech"
    static let fixAccessibility: LocalizedStringKey = "permissions.fix_accessibility"
    static let fixMicrophone: LocalizedStringKey = "permissions.fix_microphone"
    static let fixSpeech: LocalizedStringKey = "permissions.fix_speech"
    static let openPane: LocalizedStringKey = "permissions.open_pane"
    static let recheck: LocalizedStringKey = "permissions.recheck"

    // System extension
    static let systemExtensionNeedsApproval: LocalizedStringKey = "system_extension.needs_approval"
    static let openPrivacyAndSecurity: LocalizedStringKey = "system_extension.open_privacy_security"

    // Controls
    static let dwellClick: LocalizedStringKey = "control.dwell_click"
    static let forceDriverOnly: LocalizedStringKey = "control.force_driver_only"
    static let alwaysListening: LocalizedStringKey = "control.always_listening"
    static let llmEnhanceDictation: LocalizedStringKey = "control.llm_enhance_dictation"
    static let preferInputMethodCaret: LocalizedStringKey = "control.prefer_inputmethod_caret"
    static let caretEngineCompare: LocalizedStringKey = "control.caret_engine_compare"
    static let hudAutoHide: LocalizedStringKey = "control.hud_auto_hide"
    static let pushToTalkHint: LocalizedStringKey = "control.push_to_talk_hint"
    static let toggleTrackingHint: LocalizedStringKey = "control.toggle_tracking_hint"

    // Actions
    static let activatePerception: LocalizedStringKey = "action.activate_perception"
    static let startMotionMatrix: LocalizedStringKey = "action.start_motion_matrix"
    static let stopMotionMatrix: LocalizedStringKey = "action.stop_motion_matrix"
    static let finishRangeCalibration: LocalizedStringKey = "action.finish_range_calibration"

    // Onboarding
    static let setupRequired: LocalizedStringKey = "onboarding.setup_required"
    static let onboardingAccessibility: LocalizedStringKey = "onboarding.accessibility"
    static let onboardingMicrophone: LocalizedStringKey = "onboarding.microphone"
    static let onboardingSpeech: LocalizedStringKey = "onboarding.speech"

    // Menu bar
    static let menuPointer: LocalizedStringKey = "menu.pointer"
    static let menuVoice: LocalizedStringKey = "menu.voice"
    static let menuDriver: LocalizedStringKey = "menu.driver"
    static let menuActivateDriver: LocalizedStringKey = "menu.activate_driver"
    static let menuStartPointer: LocalizedStringKey = "menu.start_pointer"
    static let menuStopPointer: LocalizedStringKey = "menu.stop_pointer"
    static let menuRecenterPointer: LocalizedStringKey = "menu.recenter_pointer"
    static let menuShowWindow: LocalizedStringKey = "menu.show_window"
    static let menuQuit: LocalizedStringKey = "menu.quit"

    // Dynamic Menu Keys (Formatted)
    static func menuStartPointer(_ hotkey: String) -> LocalizedStringKey { "menu.start_pointer_fmt \(hotkey)" }
    static func menuStopPointer(_ hotkey: String) -> LocalizedStringKey { "menu.stop_pointer_fmt \(hotkey)" }
    static func menuAirPodsLock(_ hotkey: String) -> LocalizedStringKey { "menu.airpods_lock_fmt \(hotkey)" }
    static func controlToggleTracking(_ hotkey: String) -> LocalizedStringKey { "control.toggle_tracking_fmt \(hotkey)" }

    // New Controls
    static let showDockIcon: LocalizedStringKey = "control.show_dock_icon"
    static let tiltScroll: LocalizedStringKey = "control.tilt_scroll"
    static let debugMode: LocalizedStringKey = "control.debug_mode"

    // Speech Status
    static let speechListening: LocalizedStringKey = "speech.listening"
    static let speechWaitingCommand: LocalizedStringKey = "speech.waiting_command"
    static let speechIdle: LocalizedStringKey = "speech.idle"
    static let speechUnavailable: LocalizedStringKey = "speech.unavailable"
    static let speechError: LocalizedStringKey = "speech.error"
    static let speechPasted: LocalizedStringKey = "speech.pasted"
    static let speechUndo: LocalizedStringKey = "speech.undo"
    static let speechDone: LocalizedStringKey = "speech.done"
}
