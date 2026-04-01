# Utterance Arbitration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace competing input/control heuristics with a single shared utterance arbitrator, then wire wake follow-up onto it first so partial injection, HUD, execution, and usage history all consume one committed result.

**Architecture:** Introduce a pure `UtteranceArbitrator` core in the speech layer, then add a wake-specific adapter inside `SpeechManager` that feeds evidence into that core and gates partial dictation until arbitration commits. Keep `DictationHandler` and command execution as downstream consumers only, then migrate non-wake capture paths onto the same core once wake is stable.

**Tech Stack:** Swift, XCTest, Xcode macOS app target, existing `SpeechManager`, `VoiceCommandRouter`, `DictationHandler`, `AetherApp` usage history pipeline

---

### Task 1: Add Shared Arbitration Core

**Files:**
- Create: `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/Speech/UtteranceArbitrator.swift`
- Create: `/Volumes/SSD/Projects/Aether/App/AetherTests/UtteranceArbitratorTests.swift`
- Reference: `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/Speech/VoiceCommandRouter.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Aether

final class UtteranceArbitratorTests: XCTestCase {
    func testExplicitCommandModeCommitsCommand() {
        let result = UtteranceArbitrator.resolve(
            evidence: .init(
                controlMode: .command,
                normalizedText: "打开面板",
                routerDecision: .init(intent: .showShortcutPanel, confidence: .high, reason: "alias"),
                hasStableTypingEvidence: true,
                hasLiveTypingEvidence: false,
                transport: .wakeFollowUp,
                hasCommittedDictation: false
            )
        )

        XCTAssertEqual(result.state, .commandCommitted)
        XCTAssertFalse(result.allowsDictationStreaming)
    }

    func testAutoModeKeepsPendingWithoutTypingEvidenceForDictationLikeText() {
        let result = UtteranceArbitrator.resolve(
            evidence: .init(
                controlMode: .auto,
                normalizedText: "今天下午三点开会",
                routerDecision: .init(intent: .dictation("今天下午三点开会"), confidence: .medium, reason: "dictation"),
                hasStableTypingEvidence: false,
                hasLiveTypingEvidence: false,
                transport: .wakeFollowUp,
                hasCommittedDictation: false
            )
        )

        XCTAssertEqual(result.state, .pending)
        XCTAssertFalse(result.allowsDictationStreaming)
    }

    func testAutoModeCommitsDictationWhenTypingEvidenceIsStable() {
        let result = UtteranceArbitrator.resolve(
            evidence: .init(
                controlMode: .auto,
                normalizedText: "今天下午三点开会",
                routerDecision: .init(intent: .dictation("今天下午三点开会"), confidence: .medium, reason: "dictation"),
                hasStableTypingEvidence: true,
                hasLiveTypingEvidence: false,
                transport: .wakeFollowUp,
                hasCommittedDictation: false
            )
        )

        XCTAssertEqual(result.state, .dictationCommitted)
        XCTAssertTrue(result.allowsDictationStreaming)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/UtteranceArbitratorTests
```

Expected: FAIL with missing `UtteranceArbitrator` types or unresolved symbols.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

enum UtteranceTransportContext: Equatable {
    case wakeFollowUp
    case pushToTalk
    case oneShot
}

enum UtteranceArbitrationState: Equatable {
    case pending
    case dictationCommitted
    case commandCommitted
}

struct UtteranceArbitrationEvidence: Equatable {
    let controlMode: HeadMotionManager.RecognitionControlMode
    let normalizedText: String
    let routerDecision: VoiceCommandDecision
    let hasStableTypingEvidence: Bool
    let hasLiveTypingEvidence: Bool
    let transport: UtteranceTransportContext
    let hasCommittedDictation: Bool
}

struct UtteranceArbitrationResult: Equatable {
    let state: UtteranceArbitrationState

    var allowsDictationStreaming: Bool {
        state == .dictationCommitted
    }
}

enum UtteranceArbitrator {
    static func resolve(evidence: UtteranceArbitrationEvidence) -> UtteranceArbitrationResult {
        switch evidence.controlMode {
        case .command:
            return .init(state: .commandCommitted)
        case .dictation:
            return .init(state: .dictationCommitted)
        case .auto:
            break
        }

        if isCommandIntent(evidence.routerDecision.intent),
           evidence.routerDecision.confidence >= .medium {
            return .init(state: .commandCommitted)
        }

        if evidence.hasCommittedDictation || evidence.hasStableTypingEvidence {
            return .init(state: .dictationCommitted)
        }

        return .init(state: .pending)
    }

    private static func isCommandIntent(_ intent: VoiceIntent) -> Bool {
        switch intent {
        case .dictation, .unknown:
            return false
        default:
            return true
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/UtteranceArbitratorTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C /Volumes/SSD/Projects/Aether/App add Apps/AetherCore/Speech/UtteranceArbitrator.swift AetherTests/UtteranceArbitratorTests.swift
git -C /Volumes/SSD/Projects/Aether/App commit -m "feat: add shared utterance arbitrator core"
```

### Task 2: Add Wake Adapter and Replace Wake-Only Ownership

**Files:**
- Modify: `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift` around current wake helpers and routing setup (`resolvedUtteranceTypingMode`, wake fallback helpers, partial/final wake routing around current lines 744-985, 2788-2915, 4565-4860)
- Modify: `/Volumes/SSD/Projects/Aether/App/AetherTests/VoiceCommandRouterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testWakeAdapterPrefersCommandCommitForWakeCommandPayload() {
    let decision = SpeechManager.resolveWakeFollowUpArbitration(
        controlMode: .auto,
        transcript: "打开面板",
        routerDecision: .init(intent: .showShortcutPanel, confidence: .high, reason: "alias"),
        hasStableTypingEvidence: true,
        hasLiveTypingEvidence: false,
        hasCommittedDictation: false
    )

    XCTAssertEqual(decision.state, .commandCommitted)
}

func testWakeAdapterKeepsPendingBeforeDictationCommitWithoutStableTypingEvidence() {
    let decision = SpeechManager.resolveWakeFollowUpArbitration(
        controlMode: .auto,
        transcript: "今天下午三点开会",
        routerDecision: .init(intent: .dictation("今天下午三点开会"), confidence: .medium, reason: "dictation"),
        hasStableTypingEvidence: false,
        hasLiveTypingEvidence: false,
        hasCommittedDictation: false
    )

    XCTAssertEqual(decision.state, .pending)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/VoiceCommandRouterTests/testWakeAdapterPrefersCommandCommitForWakeCommandPayload -only-testing:AetherTests/VoiceCommandRouterTests/testWakeAdapterKeepsPendingBeforeDictationCommitWithoutStableTypingEvidence
```

Expected: FAIL with missing `resolveWakeFollowUpArbitration`.

- [ ] **Step 3: Write minimal implementation**

```swift
private var currentUtteranceArbitration: UtteranceArbitrationResult = .init(state: .pending)

static func resolveWakeFollowUpArbitration(
    controlMode: HeadMotionManager.RecognitionControlMode,
    transcript: String,
    routerDecision: VoiceCommandDecision,
    hasStableTypingEvidence: Bool,
    hasLiveTypingEvidence: Bool,
    hasCommittedDictation: Bool
) -> UtteranceArbitrationResult {
    UtteranceArbitrator.resolve(
        evidence: .init(
            controlMode: controlMode,
            normalizedText: transcript,
            routerDecision: routerDecision,
            hasStableTypingEvidence: hasStableTypingEvidence,
            hasLiveTypingEvidence: hasLiveTypingEvidence,
            transport: .wakeFollowUp,
            hasCommittedDictation: hasCommittedDictation
        )
    )
}

private func wakeFollowUpArbitrationResult(
    controlMode: HeadMotionManager.RecognitionControlMode,
    transcript: String,
    routerDecision: VoiceCommandDecision?,
    hasStableTypingEvidence: Bool,
    hasLiveTypingEvidence: Bool
) -> UtteranceArbitrationResult {
    let decision = routerDecision ?? commandRouter.routeDetailed(
        transcript: transcript,
        bias: .commandPreferred,
        localeIdentifier: activeLocale.identifier
    )

    return Self.resolveWakeFollowUpArbitration(
        controlMode: controlMode,
        transcript: transcript,
        routerDecision: decision,
        hasStableTypingEvidence: hasStableTypingEvidence,
        hasLiveTypingEvidence: hasLiveTypingEvidence,
        hasCommittedDictation: currentUtteranceArbitration.state == .dictationCommitted
    )
}
```

Then replace wake-only ownership decisions so that:

```swift
let arbitration = wakeFollowUpArbitrationResult(
    controlMode: controlMode,
    transcript: text,
    routerDecision: commandRouter.routeDetailed(
        transcript: text,
        bias: .commandPreferred,
        localeIdentifier: activeLocale.identifier
    ),
    hasStableTypingEvidence: hasStrongTypingFallback,
    hasLiveTypingEvidence: liveTyping
)
currentUtteranceArbitration = arbitration
```

And stop using wake fallback helpers as direct final owners of `typingContext`.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/VoiceCommandRouterTests/testWakeAdapterPrefersCommandCommitForWakeCommandPayload -only-testing:AetherTests/VoiceCommandRouterTests/testWakeAdapterKeepsPendingBeforeDictationCommitWithoutStableTypingEvidence
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C /Volumes/SSD/Projects/Aether/App add Apps/AetherCore/SpeechManager.swift AetherTests/VoiceCommandRouterTests.swift
git -C /Volumes/SSD/Projects/Aether/App commit -m "refactor: route wake follow-up through utterance arbitrator"
```

### Task 3: Gate Partial Streaming and Intent Queueing on Committed Arbitration

**Files:**
- Modify: `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift` around partial dispatch and intent queueing (`sessionTypingMode` / `dictationHandler.onPartial` around current lines 2913-2925, queue setup around 4863-4908, processed job handling around 5631-6068)
- Modify: `/Volumes/SSD/Projects/Aether/App/AetherTests/AetherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testPendingArbitrationDoesNotAllowWakeDictationStreaming() {
    XCTAssertFalse(
        SpeechManager.shouldStreamDictationPartial(
            arbitrationState: .pending,
            dictationEnabled: true,
            commandEnabled: true,
            hasPendingExplicitCommandPrefix: false,
            partialText: "打开面板"
        )
    )
}

func testCommittedDictationAllowsWakeDictationStreaming() {
    XCTAssertTrue(
        SpeechManager.shouldStreamDictationPartial(
            arbitrationState: .dictationCommitted,
            dictationEnabled: true,
            commandEnabled: true,
            hasPendingExplicitCommandPrefix: false,
            partialText: "今天下午三点开会"
        )
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/AetherTests/testPendingArbitrationDoesNotAllowWakeDictationStreaming -only-testing:AetherTests/AetherTests/testCommittedDictationAllowsWakeDictationStreaming
```

Expected: FAIL with missing `shouldStreamDictationPartial`.

- [ ] **Step 3: Write minimal implementation**

```swift
static func shouldStreamDictationPartial(
    arbitrationState: UtteranceArbitrationState,
    dictationEnabled: Bool,
    commandEnabled: Bool,
    hasPendingExplicitCommandPrefix: Bool,
    partialText: String
) -> Bool {
    guard dictationEnabled else { return false }
    guard arbitrationState == .dictationCommitted else { return false }
    guard !hasPendingExplicitCommandPrefix else { return false }
    guard !partialMayBecomeExplicitCommandPrefix(partialText) else { return false }
    return true
}
```

Then change the partial dispatch branch from:

```swift
if sessionTypingMode && featureAvailability.dictationEnabled {
    dictationHandler.onPartial(text)
}
```

to:

```swift
if Self.shouldStreamDictationPartial(
    arbitrationState: currentUtteranceArbitration.state,
    dictationEnabled: featureAvailability.dictationEnabled,
    commandEnabled: featureAvailability.commandEnabled,
    hasPendingExplicitCommandPrefix: pendingExplicitCommandPrefix,
    partialText: text
) {
    dictationHandler.onPartial(text)
}
```

Also add committed arbitration state onto queued jobs:

```swift
let job = IntentJob(
    seq: -1,
    intent: hydratedIntent,
    localeIdentifier: localeID,
    dictationEnhancementEnabled: isAutoDictationEnhancementEnabled,
    fullTextRewriteEnabled: isFullTextRewriteEnabled,
    originSessionGeneration: originSessionGeneration,
    utteranceID: utteranceID,
    sessionTypingMode: typingContext,
    committedArbitrationState: currentUtteranceArbitration.state,
    streamedTextSnapshot: dictationHandler.screenTypedText,
    screenTypedCount: dictationHandler.screenTypedText.count,
    targetPID: pid,
    targetBundleID: bid,
    targetElementFingerprint: fp,
    targetSource: source,
    verificationSnapshot: verificationSnapshot,
    holdsTextRewriteBarrier: holdsTextRewriteBarrier,
    spokenText: spokenText,
    routeReason: routeReason,
    commandHUDPreviewMessage: commandHUDPreviewMessage
)
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/AetherTests/testPendingArbitrationDoesNotAllowWakeDictationStreaming -only-testing:AetherTests/AetherTests/testCommittedDictationAllowsWakeDictationStreaming
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C /Volumes/SSD/Projects/Aether/App add Apps/AetherCore/SpeechManager.swift AetherTests/AetherTests.swift
git -C /Volumes/SSD/Projects/Aether/App commit -m "refactor: gate wake partial injection on committed arbitration"
```

### Task 4: Make HUD and Usage History Mirror Committed Class

**Files:**
- Modify: `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift` (`primeQueuedHUDStage`, `applyProcessedJob`, dictation rollback and command execution around current lines 4863-4908 and 5631-6068)
- Modify: `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/AetherApp.swift` around `recordVoiceUsageEvent(...)` (current lines 5448-5495)
- Modify: `/Volumes/SSD/Projects/Aether/App/AetherTests/AetherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testCommittedCommandUsesControlHUDStage() {
    let mode = SpeechManager.queuedHUDControlMode(
        arbitrationState: .commandCommitted,
        intent: .showShortcutPanel
    )

    XCTAssertEqual(mode, .command)
}

func testCommittedDictationUsesDictationHUDStage() {
    let mode = SpeechManager.queuedHUDControlMode(
        arbitrationState: .dictationCommitted,
        intent: .dictation("今天下午三点开会")
    )

    XCTAssertEqual(mode, .dictation)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/AetherTests/testCommittedCommandUsesControlHUDStage -only-testing:AetherTests/AetherTests/testCommittedDictationUsesDictationHUDStage
```

Expected: FAIL with missing `queuedHUDControlMode`.

- [ ] **Step 3: Write minimal implementation**

```swift
static func queuedHUDControlMode(
    arbitrationState: UtteranceArbitrationState,
    intent: VoiceIntent
) -> HUDRecognitionControlMode {
    switch arbitrationState {
    case .commandCommitted:
        return .command
    case .dictationCommitted:
        return .dictation
    case .pending:
        return isCommandIntent(intent) ? .command : .auto
    }
}
```

Use that helper in `primeQueuedHUDStage(...)` instead of recomputing from `typingContext`.

Then add committed class into usage logging so the history reflects the same decision source:

```swift
private func recordVoiceUsageEvent(
    kind: VoiceUsageEventKind,
    action: String,
    content: String?,
    originalContent: String? = nil,
    spokenText: String? = nil,
    enhancedContent: String? = nil,
    committedContent: String? = nil,
    enhancementStatus: String? = nil,
    appName: String?,
    bundleIdentifier: String?,
    eventCode: String? = nil,
    committedUtteranceClass: String? = nil,
    wakeGroupID: String? = nil,
    wakePhrase: String? = nil,
    localeIdentifier: String? = nil,
    rewriteScope: String? = nil,
    rewriteMode: String? = nil
) { ... }
```

And send `committedUtteranceClass` from the committed arbitration state when command or dictation completes.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/AetherTests/testCommittedCommandUsesControlHUDStage -only-testing:AetherTests/AetherTests/testCommittedDictationUsesDictationHUDStage
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C /Volumes/SSD/Projects/Aether/App add Apps/AetherCore/SpeechManager.swift Apps/AetherCore/AetherApp.swift AetherTests/AetherTests.swift
git -C /Volumes/SSD/Projects/Aether/App commit -m "refactor: align hud and usage history with committed arbitration"
```

### Task 5: Migrate Non-Wake Capture Paths onto the Same Core

**Files:**
- Modify: `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift`
- Modify: `/Volumes/SSD/Projects/Aether/App/AetherTests/UtteranceArbitratorTests.swift`
- Modify: `/Volumes/SSD/Projects/Aether/App/AetherTests/AetherTests.swift`
- Reference: `/Volumes/SSD/Projects/Aether/docs/superpowers/specs/2026-03-31-utterance-arbitration-design.md`

- [ ] **Step 1: Write the failing test**

```swift
func testPushToTalkCommandUsesSharedArbitrator() {
    let result = UtteranceArbitrator.resolve(
        evidence: .init(
            controlMode: .auto,
            normalizedText: "粘贴",
            routerDecision: .init(intent: .paste, confidence: .high, reason: "alias"),
            hasStableTypingEvidence: false,
            hasLiveTypingEvidence: false,
            transport: .pushToTalk,
            hasCommittedDictation: false
        )
    )

    XCTAssertEqual(result.state, .commandCommitted)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/UtteranceArbitratorTests/testPushToTalkCommandUsesSharedArbitrator
```

Expected: FAIL because transport-specific path is not yet wired or behavior diverges from wake path.

- [ ] **Step 3: Write minimal implementation**

```swift
private func arbitrationTransportContext() -> UtteranceTransportContext {
    if isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled {
        return .wakeFollowUp
    }
    if isPTTHeld {
        return .pushToTalk
    }
    return .oneShot
}

private func currentUtteranceArbitrationResult(
    transcript: String,
    controlMode: HeadMotionManager.RecognitionControlMode,
    routerDecision: VoiceCommandDecision,
    hasStableTypingEvidence: Bool,
    hasLiveTypingEvidence: Bool
) -> UtteranceArbitrationResult {
    UtteranceArbitrator.resolve(
        evidence: .init(
            controlMode: controlMode,
            normalizedText: transcript,
            routerDecision: routerDecision,
            hasStableTypingEvidence: hasStableTypingEvidence,
            hasLiveTypingEvidence: hasLiveTypingEvidence,
            transport: arbitrationTransportContext(),
            hasCommittedDictation: currentUtteranceArbitration.state == .dictationCommitted
        )
    )
}
```

Route non-wake partial/final paths through the same helper instead of keeping separate ownership logic.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/UtteranceArbitratorTests/testPushToTalkCommandUsesSharedArbitrator
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C /Volumes/SSD/Projects/Aether/App add Apps/AetherCore/SpeechManager.swift AetherTests/UtteranceArbitratorTests.swift AetherTests/AetherTests.swift
git -C /Volumes/SSD/Projects/Aether/App commit -m "refactor: reuse utterance arbitrator across capture paths"
```

### Task 6: Regression Sweep and Acceptance Notes

**Files:**
- Modify: `/Volumes/SSD/Projects/Aether/App/docs/PENDING_ACCEPTANCE.md`
- Reference: `/Volumes/SSD/Projects/Aether/docs/superpowers/specs/2026-03-31-utterance-arbitration-design.md`

- [ ] **Step 1: Add acceptance checklist entry for arbitration rollout**

```markdown
- [ ] 【语音仲裁一致性】wake、PTT 与一次性识别应共享同一套输入/控制仲裁，不再出现 HUD 与最终意图分类不一致
  验证重点：`wake + 命令`、`wake + 听写`、PTT 命令、PTT 听写 四条路径的 HUD、执行结果、使用统计应一致
```

- [ ] **Step 2: Run targeted regression commands**

Run:

```bash
swiftc -parse /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SpeechManager.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/Apps/AetherCore/Speech/UtteranceArbitrator.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/AetherTests/UtteranceArbitratorTests.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/AetherTests/VoiceCommandRouterTests.swift
swiftc -parse /Volumes/SSD/Projects/Aether/App/AetherTests/AetherTests.swift
```

Expected: all commands exit `0`.

- [ ] **Step 3: Run focused XCTest suite**

Run:

```bash
xcodebuild -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:AetherTests/UtteranceArbitratorTests -only-testing:AetherTests/VoiceCommandRouterTests -only-testing:AetherTests/AetherTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git -C /Volumes/SSD/Projects/Aether/App add docs/PENDING_ACCEPTANCE.md
git -C /Volumes/SSD/Projects/Aether/App commit -m "docs: add utterance arbitration acceptance coverage"
```
