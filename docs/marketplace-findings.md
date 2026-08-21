# Findings & Decisions

## Requirements
- Answer what this project still needs to change for “official marketplace” distribution.
- Default to repo evidence first.
- Distinguish verified current-state findings from older documentation or inference.

## Research Findings
- The workspace README says this repo contains `App/`, `Website/`, and `Admin/`; the commercial model already includes public stable/beta channels outside App Store.
- `App/docs/TESTFLIGHT_ANALYSIS.md` explicitly evaluates TestFlight/App Store readiness and says current blockers are sandbox migration plus removal of the unused driver target.
- `App/AGENTS.md` says repo-specific answers should come from current code/config inspection and warns against unsafe Apple build/test commands in default conversations.
- Current entitlements still disable sandbox: `App/Apps/AetherCore/AetherCore.entitlements` sets `com.apple.security.app-sandbox` to `false` and only enables microphone + speech recognition.
- The app currently depends on outbound network access for entitlement verification, trial start, device management, appcast fetching, and optional LLM providers, but the entitlements file does not include `com.apple.security.network.client`.
- `App/Apps/AetherCore/AetherApp.swift` dynamically loads `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote` and calls `MRMediaRemoteGetNowPlayingInfo` / `MRMediaRemoteGetNowPlayingApplicationPID`; this is a strong App Store risk because it relies on private APIs.
- Sparkle is deeply integrated, not just present in docs: the Xcode target links the Sparkle package, the info plist includes `SUFeedURL`, and `SparkleUpdater.swift` starts `SPUStandardUpdaterController` plus exposes manual “Check for Updates” behavior.
- The About flow exposes a non-App-Store commercial model: email + activation code, direct trial start against backend APIs, referral codes, device management, and external stable/beta update channels.
- The old TestFlight doc says the unused driver target should be removed. Current `project.pbxproj` only contains `Aether` and `AetherTests` native targets, so the driver target appears already removed from the active project. Release packaging also strips `Contents/Library/SystemExtensions`.

## Official Reference Findings
- Apple’s current App Sandbox docs state that sandbox is required for Mac App Store distribution.
- Apple’s App Sandbox docs also call out `com.apple.security.network.client` as the entitlement needed for outgoing network connections.
- Apple’s App Review Guidelines currently say Mac App Store apps must use the Mac App Store to distribute updates; other update mechanisms are not allowed.
- Apple’s App Review Guidelines currently say apps may only use public APIs.
- Apple’s App Review Guidelines currently say apps may not use their own mechanisms to unlock functionality such as license keys; digital features/subscriptions generally need In-App Purchase unless a specific exception applies.

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Review App Store/TestFlight readiness by source inspection | Matches user question and project rules; avoids unsafe runtime/build actions |
| Treat external activation/subscription as a likely App Store blocker | The current product model unlocks in-app digital functionality using email/license/referral flows, which conflicts with Apple’s current review guidance unless a narrow exception applies |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| No direct repo string for “官方市场” | Mapped scope using docs and release terminology; will keep this mapping explicit in the final answer |

## Resources
- `/Volumes/SSD/Projects/Aether/README.md`
- `/Volumes/SSD/Projects/Aether/App/AGENTS.md`
- `/Volumes/SSD/Projects/Aether/App/docs/TESTFLIGHT_ANALYSIS.md`
- `/Volumes/SSD/Projects/Aether/App/docs/RELEASE_DISTRIBUTION.md`
- `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/AetherCore.entitlements`
- `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/Info.plist`
- `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/AetherApp.swift`
- `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/SparkleUpdater.swift`
- `/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/AboutCenter.swift`
- `/Volumes/SSD/Projects/Aether/App/Aether.xcodeproj/project.pbxproj`
- `/Volumes/SSD/Projects/Aether/App/Scripts/ReleaseForUsers.sh`
- `https://developer.apple.com/app-store/review/guidelines/`
- `https://developer.apple.com/documentation/security/app-sandbox`
- `https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client`

## Visual/Browser Findings
- None.

## 2026-04-08 CPU Usage Diagnosis

- The current high CPU is not best explained by one infinite loop. Source inspection points to several always-on loops stacking together in idle and near-idle states.
- Primary steady-state hotspot:
  - `App/Apps/AetherCore/SpeechManager.swift`
  - `SpeechManager` installs `Timer.publish(every: 0.15, on: .main, in: .common)` and calls `refreshContinuousHUD(isDictating:)` on every tick.
  - That refresh path calls `focusedTypingHUDEvidence()`, which calls `HUDManager.shared.currentAXTypingEvaluation()`.
  - `HUDManager.axTypingEvaluationThrottled(now:)` only caches for `0.12s`, so the `0.15s` HUD poll effectively re-runs AX-focused typing evaluation almost every refresh.
- Strong runtime evidence from existing diagnostics:
  - `~/Library/Logs/Aether/diagnostics.log` currently contains thousands of `WakeHUD` entries during idle wake-gated standby.
  - Measured from the log: `WakeHUD` averages about `6.55` lines per active second, with peaks of `8-9` lines per second.
  - The logged state is overwhelmingly:
    - `awake=false`
    - `effectiveDictating=false`
    - `recognitionRunning=true`
    - `audioRunning=true`
    - `isUtteranceActive=false`
  - That means the app is still keeping the recognition/HUD pipeline hot even while the user-facing state is "not awake."
- Logging amplification is real, not incidental:
  - `logWakeHUDStateIfNeeded(...)` builds its dedupe signature from the full wake snapshot.
  - That snapshot includes continuously changing fields such as `wakeAge` and `pendingWakeAge`, so identical logical state still generates a new signature almost every poll.
  - `GlobalLogger.shouldSuppressRepeatedLog(...)` has no dedicated suppression rule for `WakeHUD`.
  - `GlobalLogger.log(...)` not only uses `os_log`; it also appends each message to `~/Library/Logs/Aether/diagnostics.log`, adding file I/O on top of the poll itself.
- Additional steady-state contributors:
  - `App/Apps/AetherCore/Speech/AirPodsDetector.swift`
    - Starts polling in `init()`.
    - Runs a `1.0s` timer unconditionally.
    - Fast refresh spawns `/usr/sbin/ioreg` roughly once per second.
    - Bluetooth reconciliation can also spawn `/usr/bin/log show --last 12s`.
  - `App/Apps/AetherCore/HeadMotionManager.swift`
    - Calls `startHotZoneMonitorTimer()` during init.
    - Starts a `1.0 / 30.0` timer unconditionally.
    - `pollMouseHotZoneRecognition()` reads cursor location before it checks `headGestureToggleEnabled`, so mouse polling still happens even when the head-gesture feature is off.
  - `App/Apps/AetherCore/HUD/HUDManager.swift`
    - Starts a background fullscreen timer at `1.2s`.
    - Begins an `NSActivity` with `.userInitiated` and `.latencyCritical`, which makes the process less likely to nap while the above loops continue.
    - Also has an additional `0.2s` timer that always calls `HeadMotionManager.shared.refreshTransientRecognitionControlModeIfNeeded()`.
- Conclusion:
  - The strongest verified CPU cause is the speech/HUD/AX focus loop.
  - The strongest verified amplifier is high-frequency `WakeHUD` diagnostics logging with file writes.
  - `AirPodsDetector` and `HeadMotionManager` add meaningful constant background cost on top of that baseline.

---
*Update this file after every 2 view/browser/search operations*
*This prevents visual information from being lost*

## 2026-04-08 Voice Lexicon App-Launch Prefixes

- Current repo state split app-launch language into two places: route hardcoding plus the separate `Launch Aliases` page.
- Main voice lexicon previously only exposed wake words, command prefixes, dictation prefixes, and control-command aliases.
- App-launch command prefixes such as `打开 / 启动 / 切到 / 切换到` were not user-editable from the main voice lexicon, which made the feature feel incomplete compared with command aliases like `右键`.
- Implemented a new `appLaunchPrefixes` field inside `VoiceLanguageTermsOverrideConfig`, wired through defaults, import/export merge, AppState accessors, main lexicon UI, routing, and suggested command phrases.
- Backward compatibility is preserved by decoding old voice-lexicon payloads with missing `appLaunchPrefixes` as an empty list.

## 2026-04-08 Wake / Dictation Regression

- Current behavior drifted away from the earlier HUD/dictation design.
  - Design intent in `App/docs/hud_specification_v3.md`: input-mode feedback should feel simultaneous between HUD and the actual input target.
  - Design intent in `App/docs/superpowers/plans/2026-03-31-utterance-arbitration.md`: wake follow-up dictation should stream once dictation is the committed path, rather than waiting for final.
- Two concrete regressions were confirmed in source and diagnostics:
  1. Wake follow-up can still lose typing continuity.
     - `SpeechManager.handleWakeActivation(...)` was explicitly resetting auto-mode typing sessions back to command baseline on wake activation.
     - During wake lifecycle, partial/final routing then over-weighted `dictationCommitted` and under-used the existing wake typing fallback/promotion evidence.
  2. Live dictation into the input target stalls too easily.
     - `DictationHandler.onPartial(...)` only streamed when the new partial strictly extended `screenTypedText`.
     - As soon as Apple STT revised earlier words, live typing stopped and waited for final correction.
     - Existing diagnostics already showed large gaps between streamed text and final text, e.g. finalCount much larger than streamedCount at finalize/diff-correct.
- Implemented direction in the current fix branch:
  - Wake activation now keeps typing baseline when wake follow-up typing state should be preserved.
  - Wake lifecycle typing resolution now allows wake typing fallback / inline typing promotion to keep dictation alive before arbitration fully commits, while still yielding to likely-command wake payloads.
  - `DictationHandler` now promotes certain divergent partials into live correction instead of always waiting for final:
    - tail-only rewrites
    - longer revised partials that continue well past the current on-screen text
    - follow-up partials after an earlier deferred rewrite

## 2026-04-15 Git State / Branch Merge Triage

- The workspace contains three independent git repos:
  - `/Volumes/SSD/Projects/Aether`
  - `/Volumes/SSD/Projects/Aether/App`
  - `/Volumes/SSD/Projects/Aether/Website`
- Root repo state:
  - Current branch: `release/universal-packaging-followup`
  - `main` and `release/universal-packaging-followup` point to the same commit `7723044`
  - Uncommitted root changes are local docs/task files:
    - modified: `.gitignore`, `README.md`, `TODO.md`
    - deleted: `v2ex_draft.md`
    - untracked: `App/`, `WORKSTREAM_INBOX.md`, `docs/`
- App repo state:
  - Current branch: `fix/wake-dictation-regression`
  - Working tree has one untracked file: `docs/video_scripts_2026-04-08.md`
  - `fix/wake-dictation-regression` is the only local branch not yet merged into `main`
  - Earlier local fix branches (`fix/hud-state-rules`, `fix/hud-text-speed`, `fix/runtime-speech-rollup`, `fix/voice-activity-hold-policy`) are already reachable from `main`
- Website repo state:
  - Current branch: `main`
  - No local working-tree changes
  - Local `main` is ahead of `origin/main` by one commit: `acee6c7 chore(beta): publish 0.1.18 b151`
