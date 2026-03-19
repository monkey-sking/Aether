import SwiftUI

enum L10n {
    // Generic
    static let on: LocalizedStringKey = "generic.on"
    static let off: LocalizedStringKey = "generic.off"
    static let idle: LocalizedStringKey = "generic.idle"
    static let ready: LocalizedStringKey = "generic.ready"
    static let tracking: LocalizedStringKey = "generic.tracking"
    static let selectItem: LocalizedStringKey = "generic.select_item"

    // App
    static let projectTitle: LocalizedStringKey = "app.project_title"

    // Status
    static let perceptionNetwork: LocalizedStringKey = "status.perception_network"
    static let pointerOutput: LocalizedStringKey = "status.pointer_output"
    static let textOutput: LocalizedStringKey = "status.text_output"
    static let mode: LocalizedStringKey = "status.mode"
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

    // Controls
    static let alwaysListening: LocalizedStringKey = "control.always_listening"
    static let alwaysListeningWakeWindow: LocalizedStringKey = "control.always_listening_wake_window"
    static let triggerSources: LocalizedStringKey = "control.trigger_sources"
    static let triggerHotkey: LocalizedStringKey = "control.trigger_hotkey"
    static let triggerWakeWord: LocalizedStringKey = "control.trigger_wakeword"
    static let sessionStrategy: LocalizedStringKey = "control.session_strategy"
    static let strategySingleSession: LocalizedStringKey = "control.strategy_single_session"
    static let strategyContinuous: LocalizedStringKey = "control.strategy_continuous"
    static let llmEnhanceDictation: LocalizedStringKey = "control.llm_enhance_dictation"
    static let hudAutoHide: LocalizedStringKey = "control.hud_auto_hide"
    static let hudAutoHideHint: LocalizedStringKey = "control.hud_auto_hide_hint"
    static let pushToTalkHint: LocalizedStringKey = "control.push_to_talk_hint"
    static let toggleTrackingHint: LocalizedStringKey = "control.toggle_tracking_hint"
    static let alwaysListeningWakeWindowHint: LocalizedStringKey = "control.always_listening_wake_window_hint"
    
    // Unified Activation
    static let activationMethods: LocalizedStringKey = "settings.activation_methods"
    static let activationShortcut: LocalizedStringKey = "settings.activation.shortcut"
    static let activationShortcutHint: LocalizedStringKey = "settings.activation.shortcut_hint"
    static let activationWakeWordHint: LocalizedStringKey = "settings.activation.wakeword_hint"
    static let activationAlwaysHint: LocalizedStringKey = "settings.activation.always_hint"
    static let activationAlwaysWarning: LocalizedStringKey = "settings.activation.always_warning"

    // Sections
    static let quickStart: LocalizedStringKey = "section.quick_start"
    static let runtimeStatus: LocalizedStringKey = "section.runtime_status"
    static let voiceAndListening: LocalizedStringKey = "section.voice_listening"
    static let hudSettings: LocalizedStringKey = "section.hud_settings"
    static let advancedSettings: LocalizedStringKey = "section.advanced_settings"

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
    static let menuStartPointer: LocalizedStringKey = "menu.start_pointer"
    static let menuStopPointer: LocalizedStringKey = "menu.stop_pointer"
    static let menuRecenterPointer: LocalizedStringKey = "menu.recenter_pointer"
    static let menuShowWindow: LocalizedStringKey = "menu.show_window"
    static let menuQuit: LocalizedStringKey = "menu.quit"

    // Dynamic Menu Keys (Formatted)
    static func menuStartPointer(_ hotkey: String) -> LocalizedStringKey { "menu.start_pointer_fmt \(hotkey)" }
    static func menuStopPointer(_ hotkey: String) -> LocalizedStringKey { "menu.stop_pointer_fmt \(hotkey)" }
    static func controlToggleTracking(_ hotkey: String) -> LocalizedStringKey { "control.toggle_tracking_fmt \(hotkey)" }

    // New Controls
    static let showDockIcon: LocalizedStringKey = "control.show_dock_icon"
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

    // Dashboard & Settings (New)
    static let settingsTabOverview: LocalizedStringKey = "settings.tab.overview"
    static let settingsTabGeneral: LocalizedStringKey = "settings.tab.general"
    static let settingsTabInput: LocalizedStringKey = "settings.tab.input"
    static let settingsTabFeedback: LocalizedStringKey = "settings.tab.feedback"
    static let settingsTabAdvanced: LocalizedStringKey = "settings.tab.advanced"

    static let settingsHeaderMotion: LocalizedStringKey = "settings.header.motion"
    static let settingsHeaderShortcuts: LocalizedStringKey = "settings.header.shortcuts"

    static let dashboardHintCommand: LocalizedStringKey = "dashboard.hint.command"
    static let dashboardHintWakeword: LocalizedStringKey = "dashboard.hint.wakeword"

    static let dashboardHintEnable: LocalizedStringKey = "dashboard.hint.enable"
    
    // Command Center
    static let commandCenterTitle: LocalizedStringKey = "command.center.title"
    static let commandCenterVoiceStream: LocalizedStringKey = "command.center.voice_stream"
    static let commandCenterMotionMatrix: LocalizedStringKey = "command.center.motion_matrix"
    static let systemActive: LocalizedStringKey = "status.system.active"
    static let systemOffline: LocalizedStringKey = "status.system.offline"
    static let actionRecenter: LocalizedStringKey = "action.recenter"
    
    // Navigation
    static let navControls: LocalizedStringKey = "navigation.section.controls"
    static let navSystem: LocalizedStringKey = "navigation.item.system"
    static let navConfiguration: LocalizedStringKey = "navigation.section.configuration"
    
    // Visualization
    static let vizVoiceSignal: LocalizedStringKey = "viz.voice_signal"
    static let vizLastCommand: LocalizedStringKey = "viz.last_command"
    static let vizCalibration: LocalizedStringKey = "viz.calibration"
    static let vizVelocity: LocalizedStringKey = "viz.velocity"
    
    // Settings Settings
    static let settingsVoiceInput: LocalizedStringKey = "settings.voice_input"
    static let settingsWakewordSensitivity: LocalizedStringKey = "settings.wakeword_sensitivity"
    static let settingsAdvancedProcessing: LocalizedStringKey = "settings.advanced_processing"
    static let settingsSmarterDictation: LocalizedStringKey = "settings.smarter_dictation"
    static let settingsCommandMode: LocalizedStringKey = "settings.command_mode"
    static let settingsDictationMode: LocalizedStringKey = "settings.dictation_mode"
    static let settingsMicrophone: LocalizedStringKey = "settings.microphone"
    static let settingsNoMicrophone: LocalizedStringKey = "settings.no_microphone"
    static let settingsSpeechLanguage: LocalizedStringKey = "settings.speech_language"
    static let settingsVoiceEnabled: LocalizedStringKey = "settings.voice.enable"
    static let settingsVoiceEnabledHint: LocalizedStringKey = "settings.voice.enable_hint"
    static let settingsVoiceAutoEnableHeadset: LocalizedStringKey = "settings.voice.auto_enable_headset"
    static let settingsVoiceAutoEnableHeadsetHint: LocalizedStringKey = "settings.voice.auto_enable_headset_hint"
    static let languageSystem: LocalizedStringKey = "language.system"
    static let languageEnglishUS: LocalizedStringKey = "language.en_US"
    static let languageChineseSC: LocalizedStringKey = "language.zh_CN"
    static let languageJapanese: LocalizedStringKey = "language.ja_JP"
    static let languageKorean: LocalizedStringKey = "language.ko_KR"
    static let languageFrench: LocalizedStringKey = "language.fr_FR"
    static let languageGerman: LocalizedStringKey = "language.de_DE"
    static let languageSpanish: LocalizedStringKey = "language.es_ES"
    
    // Voice Activation
    static let settingsActivationTitle: LocalizedStringKey = "settings.activation.title"
    static let settingsActivationHandsFree: LocalizedStringKey = "settings.activation.hands_free"
    static let settingsActivationPushToTalk: LocalizedStringKey = "settings.activation.push_to_talk"
    static let settingsActivationWakeWord: LocalizedStringKey = "settings.activation.wake_word"
    static let settingsActivationGazeWake: LocalizedStringKey = "settings.activation.gaze_wake"
    static let settingsActivationKeepAwake: LocalizedStringKey = "settings.activation.keep_awake"
    
    static let settingsDefaultDevice: LocalizedStringKey = "settings.default_device"
    static let settingsCommandTimeout: LocalizedStringKey = "settings.command_timeout"
    static let settingsFeedbackSound: LocalizedStringKey = "settings.feedback_sound"
    static let settingsAutoPunctuation: LocalizedStringKey = "settings.auto_punctuation"
    static let settingsCalibration: LocalizedStringKey = "settings.calibration"
    static let settingsCurrentStatus: LocalizedStringKey = "settings.current_status"
    static let actionRecenterMatrix: LocalizedStringKey = "action.recenter_matrix"
    static let statusActive: LocalizedStringKey = "status.active"
    static let statusDisabled: LocalizedStringKey = "status.disabled"
    static let statusPaused: LocalizedStringKey = "status.paused"
    static let calibrationNormal: LocalizedStringKey = "calibration.normal"
    static let hotkeyResetSingle: LocalizedStringKey = "hotkey.reset_single"

    // Voice Lexicon
    static let voiceLexiconTitle: LocalizedStringKey = "voice_lexicon.title"
    static let voiceLexiconDescription: LocalizedStringKey = "voice_lexicon.description"
    static let voiceLexiconEditingLanguage: LocalizedStringKey = "voice_lexicon.editing_language"
    static let voiceLexiconCurrentTarget: LocalizedStringKey = "voice_lexicon.current_target"
    static let voiceLexiconResetLanguage: LocalizedStringKey = "voice_lexicon.reset_language"
    static let voiceLexiconExport: LocalizedStringKey = "voice_lexicon.export"
    static let voiceLexiconImport: LocalizedStringKey = "voice_lexicon.import"
    static let voiceLexiconWakeWords: LocalizedStringKey = "voice_lexicon.wake_words"
    static let voiceLexiconCommandPrefixes: LocalizedStringKey = "voice_lexicon.command_prefixes"
    static let voiceLexiconDictationPrefixes: LocalizedStringKey = "voice_lexicon.dictation_prefixes"
    static let voiceLexiconLeaveEmpty: LocalizedStringKey = "voice_lexicon.leave_empty"
    static let voiceLexiconDefault: LocalizedStringKey = "voice_lexicon.default"
    static let voiceLexiconCustom: LocalizedStringKey = "voice_lexicon.custom"
    static let voiceLexiconClear: LocalizedStringKey = "voice_lexicon.clear"
    static let voiceLexiconImported: LocalizedStringKey = "voice_lexicon.imported"
    static let voiceLexiconExported: LocalizedStringKey = "voice_lexicon.exported"
    static let voiceLexiconImportFailed: LocalizedStringKey = "voice_lexicon.import_failed"
    static let voiceLexiconExportFailed: LocalizedStringKey = "voice_lexicon.export_failed"
}
