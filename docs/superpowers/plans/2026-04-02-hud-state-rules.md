# HUD State Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify HUD visibility, mode selection, and text selection so the HUD no longer drifts from authoritative interaction state or loses wake-follow-up/partial-text correctness for unrelated reasons.

**Architecture:** Keep `InputControlArbiter` as the authoritative input/control source, but move HUD display decisions onto an explicit pipeline inside `SpeechManager`: gather evidence, resolve visibility, resolve mode, resolve message. Reduce `HUDManager` carryover so it remains a renderer and evidence collector, not a parallel semantic owner.

**Tech Stack:** Swift, XCTest, `SpeechManager`, `HUDManager`, existing `VoiceActivityHoldPolicy`, `InputControlArbiter`

---

### Task 1: Add failing tests for HUD visibility, mode, and text decision helpers

**Files:**
- Modify: `AetherTests/AetherTests.swift`
- Modify: `AetherTests/VoiceCommandRouterTests.swift`

- [ ] **Step 1: Add failing HUD visibility tests to `AetherTests.swift`**

```swift
func testWakeGatedStandbyHidesHUDWhenNoKeepaliveAndNoOverrides() {
    let decision = SpeechManager.resolvedHUDVisibility(
        isWakeGatedStandby: true,
        isSpeechExitBarsHoldActive: false,
        hasTemporaryHUD: false,
        hasLanguageIndicator: false,
        isContinuousActive: true,
        isSessionActive: false,
        isPushToTalkOnlyIdle: false,
        dictationOnlyWithoutFocusHidden: false,
        hasRealHardware: true,
        isWakeGatedHiddenBeforeModeSelection: false
    )

    XCTAssertEqual(decision.action, .hide)
    XCTAssertEqual(decision.reason, "wake-gated-standby")
}

func testWakeGatedStandbyUsesSpeechBarsInsteadOfFallingThroughToVisibleHUD() {
    let decision = SpeechManager.resolvedHUDVisibility(
        isWakeGatedStandby: true,
        isSpeechExitBarsHoldActive: true,
        hasTemporaryHUD: false,
        hasLanguageIndicator: false,
        isContinuousActive: true,
        isSessionActive: false,
        isPushToTalkOnlyIdle: false,
        dictationOnlyWithoutFocusHidden: false,
        hasRealHardware: true,
        isWakeGatedHiddenBeforeModeSelection: false
    )

    XCTAssertEqual(decision.action, .speechBars)
    XCTAssertEqual(decision.reason, "wake-gated-standby-exit-bars")
}
```

- [ ] **Step 2: Run a safe RED check for the new visibility tests**

Run:

```bash
swiftc -parse \
  /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift \
  /Volumes/SSD/Projects/Aether/App/AetherTests/AetherTests.swift
```

Expected: fail because `SpeechManager.resolvedHUDVisibility` and its return type do not exist yet.

- [ ] **Step 3: Add failing mode/message tests to `VoiceCommandRouterTests.swift`**

```swift
func testHUDModePrefersDictationOverListeningWhenEffectiveDictating() {
    let mode = SpeechManager.resolvedHUDMode(
        shouldCollapseHandsFreeHUDToStandby: false,
        shouldShowProcessingDots: false,
        shouldShowRecognizingWhileDictating: false,
        effectiveDictating: true,
        shouldShowIdleAutoDictationHUD: false,
        lastTranscript: ""
    )

    XCTAssertEqual(mode, .dictation)
}

func testHUDMessageUsesRawRemainingDictationTextBeforeCollapsedTail() {
    let message = SpeechManager.resolvedHUDMessage(
        mode: .dictation,
        explicitMessage: "",
        lastTranscript: "我们今天一起讨论这个问题怎么解决",
        screenTypedText: "我们今天一起",
        isInputMutationActive: false,
        collapseToTwoState: false
    )

    XCTAssertEqual(message, "讨论这个问题怎么解决")
}

func testCollapsedHUDMessageStillUsesTailWhenCollapseEnabled() {
    let message = SpeechManager.resolvedHUDMessage(
        mode: .dictation,
        explicitMessage: "",
        lastTranscript: "我们今天一起讨论这个问题怎么解决",
        screenTypedText: "我们今天一起",
        isInputMutationActive: false,
        collapseToTwoState: true
    )

    XCTAssertFalse(message.isEmpty)
}
```

- [ ] **Step 4: Run a safe RED check for the new mode/message tests**

Run:

```bash
swiftc -parse \
  /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift \
  /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/HUD/HUDState.swift \
  /Volumes/SSD/Projects/Aether/App/AetherTests/VoiceCommandRouterTests.swift
```

Expected: fail because `resolvedHUDMode` and `resolvedHUDMessage` do not exist yet.

- [ ] **Step 5: Commit the failing test additions**

```bash
git add AetherTests/AetherTests.swift AetherTests/VoiceCommandRouterTests.swift
git commit -m "test: add failing hud state rules coverage"
```

### Task 2: Introduce explicit HUD decision helpers in `SpeechManager`

**Files:**
- Modify: `Apps/AetherCore/SpeechManager.swift`

- [ ] **Step 1: Add decision types near the existing HUD helpers**

```swift
extension SpeechManager {
    enum HUDVisibilityAction: Equatable {
        case visible
        case hide
        case preserveCurrentVisible
        case speechBars
    }

    struct HUDVisibilityDecision: Equatable {
        let action: HUDVisibilityAction
        let reason: String
    }
}
```

- [ ] **Step 2: Add the pure visibility resolver**

```swift
static func resolvedHUDVisibility(
    isWakeGatedStandby: Bool,
    isSpeechExitBarsHoldActive: Bool,
    hasTemporaryHUD: Bool,
    hasLanguageIndicator: Bool,
    isContinuousActive: Bool,
    isSessionActive: Bool,
    isPushToTalkOnlyIdle: Bool,
    dictationOnlyWithoutFocusHidden: Bool,
    hasRealHardware: Bool,
    isWakeGatedHiddenBeforeModeSelection: Bool
) -> HUDVisibilityDecision {
    if isWakeGatedStandby {
        if isSpeechExitBarsHoldActive {
            return HUDVisibilityDecision(action: .speechBars, reason: "wake-gated-standby-exit-bars")
        }
        if hasTemporaryHUD || hasLanguageIndicator {
            return HUDVisibilityDecision(action: .preserveCurrentVisible, reason: "wake-gated-standby-temporary")
        }
        return HUDVisibilityDecision(action: .hide, reason: "wake-gated-standby")
    }

    if !isContinuousActive && !isSessionActive {
        if isSpeechExitBarsHoldActive {
            return HUDVisibilityDecision(action: .speechBars, reason: "no-session-exit-bars")
        }
        if isPushToTalkOnlyIdle {
            if hasTemporaryHUD || hasLanguageIndicator {
                return HUDVisibilityDecision(action: .preserveCurrentVisible, reason: "ptt-idle-temporary")
            }
            return HUDVisibilityDecision(action: .hide, reason: "ptt-idle-hidden")
        }
        if !hasRealHardware {
            return HUDVisibilityDecision(action: .visible, reason: "no-hardware-feedback")
        }
        if hasTemporaryHUD || hasLanguageIndicator {
            return HUDVisibilityDecision(action: .preserveCurrentVisible, reason: "no-session-temporary")
        }
        return HUDVisibilityDecision(action: .hide, reason: "no-session-hidden")
    }

    if dictationOnlyWithoutFocusHidden {
        if isSpeechExitBarsHoldActive {
            return HUDVisibilityDecision(action: .speechBars, reason: "dictation-only-without-focus-exit-bars")
        }
        return HUDVisibilityDecision(action: .hide, reason: "dictation-only-without-focus-hidden")
    }

    if isWakeGatedHiddenBeforeModeSelection {
        if isSpeechExitBarsHoldActive {
            return HUDVisibilityDecision(action: .speechBars, reason: "wake-gated-before-mode-exit-bars")
        }
        return HUDVisibilityDecision(action: .hide, reason: "wake-gated-before-mode-hidden")
    }

    return HUDVisibilityDecision(action: .visible, reason: "normal-visible")
}
```

- [ ] **Step 3: Add the pure mode and message resolvers**

```swift
static func resolvedHUDMode(
    shouldCollapseHandsFreeHUDToStandby: Bool,
    shouldShowProcessingDots: Bool,
    shouldShowRecognizingWhileDictating: Bool,
    effectiveDictating: Bool,
    shouldShowIdleAutoDictationHUD: Bool,
    lastTranscript: String
) -> HUDMode {
    if shouldCollapseHandsFreeHUDToStandby { return .standby }
    if shouldShowProcessingDots || shouldShowRecognizingWhileDictating { return .organizing }
    if effectiveDictating { return .dictation }
    if shouldShowIdleAutoDictationHUD { return .listening }
    if !lastTranscript.isEmpty { return .command }
    return .listening
}
```

```swift
static func resolvedHUDMessage(
    mode: HUDMode,
    explicitMessage: String,
    lastTranscript: String,
    screenTypedText: String,
    isInputMutationActive: Bool,
    collapseToTwoState: Bool
) -> String
```

Implementation notes:
- keep the existing `remainingDictationHUDText` and tail-slice behavior
- when `collapseToTwoState == false`, return the raw remaining dictation text for `.dictation`
- when `collapseToTwoState == true`, keep collapsed/tail behavior isolated inside this resolver

- [ ] **Step 4: Re-run the RED checks and make them GREEN**

Run:

```bash
swiftc -parse /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/AetherTests/AetherTests.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/AetherTests/VoiceCommandRouterTests.swift
```

Expected: parse succeeds after the helpers exist and test code matches the new signatures.

- [ ] **Step 5: Commit the helper extraction**

```bash
git add Apps/AetherCore/SpeechManager.swift AetherTests/AetherTests.swift AetherTests/VoiceCommandRouterTests.swift
git commit -m "refactor: extract hud decision helpers"
```

### Task 3: Route `refreshContinuousHUD(...)` through the unified decision path

**Files:**
- Modify: `Apps/AetherCore/SpeechManager.swift`

- [ ] **Step 1: Replace ad-hoc visibility branches with `resolvedHUDVisibility(...)`**

Implementation notes:
- preserve precedence for:
  - temporary HUD override
  - missing permission hint
  - active stage mode
- after those early explicit owners, route the general path through:
  - visibility decision
  - mode decision
  - message decision

- [ ] **Step 2: Make visibility results explicit in the main path**

Implementation notes:
- `.hide` -> `HUDManager.shared.hide()`
- `.preserveCurrentVisible` -> return without recomputing persistent HUD
- `.speechBars` -> `showSpeechBarsHUD(...)`
- `.visible` -> continue to mode/message resolution

- [ ] **Step 3: Make mode selection independent from message shaping**

Implementation notes:
- call `resolvedHUDMode(...)` once
- then call `resolvedHUDMessage(...)`
- then apply playback leak fallback only after mode/message are already decided

- [ ] **Step 4: Keep diagnostics aligned with the new pipeline**

Implementation notes:
- reuse existing `logWakeHUDStateIfNeeded(...)`
- make the logged reason reflect the new visibility reason, not a pre-hide snapshot path name

- [ ] **Step 5: Commit the HUD decision pipeline refactor**

```bash
git add Apps/AetherCore/SpeechManager.swift
git commit -m "refactor: unify hud state decisions"
```

### Task 4: Reduce `HUDManager` display carryover drift

**Files:**
- Modify: `Apps/AetherCore/HUD/HUDManager.swift`
- Modify: `AetherTests/VoiceCommandRouterTests.swift`

- [ ] **Step 1: Tighten `resolvedTypingContext(...)` so persistent HUD updates do not override authoritative current state**

Implementation notes:
- keep forced `.command` => `false`
- keep forced `.dictation` => `true`
- in `.auto`, only allow previous typing carryover for explicitly temporary display cases
- processing/organizing/checking/feedback on normal persistent updates should fall back to current inferred typing context

- [ ] **Step 2: Add/update tests for carryover behavior**

```swift
func testAutoHUDProcessingUsesCurrentTypingContextOnPersistentPath() {
    let resolved = HUDManager.resolvedTypingContext(
        recognitionControlMode: .auto,
        inferredTypingContext: false,
        hudMode: .processing,
        previousTypingContext: true,
        allowPreviousTypingContextCarryover: false
    )

    XCTAssertFalse(resolved)
}
```

- [ ] **Step 3: Commit the HUDManager carryover tightening**

```bash
git add Apps/AetherCore/HUD/HUDManager.swift AetherTests/VoiceCommandRouterTests.swift
git commit -m "fix: reduce hud display carryover drift"
```

### Task 5: Safe validation and handoff

**Files:**
- Modify: `docs/PENDING_ACCEPTANCE.md` (only if acceptance wording needs sync)

- [ ] **Step 1: Run safe static validation on touched files**

Run:

```bash
swiftc -parse /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/HUD/HUDManager.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/AetherTests/AetherTests.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/AetherTests/VoiceCommandRouterTests.swift
git diff --check
```

Expected: all parse checks succeed; `git diff --check` prints nothing.

- [ ] **Step 2: Review spec coverage and confirm no requirement was skipped**

Check against:

```text
/Volumes/SSD/Projects/Aether/App/docs/superpowers/specs/2026-04-02-hud-state-rules-design.md
```

- [ ] **Step 3: Update `docs/PENDING_ACCEPTANCE.md` if the user-facing acceptance wording changed**

Implementation notes:
- only update wording if the work materially changes what the user should verify
- do not mark issues done without runtime confirmation

- [ ] **Step 4: Final commit**

```bash
git add Apps/AetherCore/SpeechManager.swift Apps/AetherCore/HUD/HUDManager.swift AetherTests/AetherTests.swift AetherTests/VoiceCommandRouterTests.swift docs/PENDING_ACCEPTANCE.md
git commit -m "fix: unify hud state rules"
```
