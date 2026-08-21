# Aether Workstream Inbox

This file is the intake and dispatch queue for project-related work collected in the dispatcher conversation.

- Use this file for newly received work that still needs to be assigned, clarified, or split into execution threads.
- Keep [TODO.md](/Volumes/SSD/Projects/Aether/TODO.md) as the curated cross-project backlog.
- When a queued item turns into real implementation work, give it a stable workstream name in the form `<type>/<short-scope>`.

## Status

- `queued`: collected here and ready for triage
- `dispatched`: handed off to a workstream or execution conversation
- `blocked`: waiting on a decision or dependency
- `done`: completed and safe to archive later

## Intake Template

```md
## WS-YYYY-MM-DD-001 `type/short-scope`
- Status: `queued`
- Priority: `high` / `medium` / `low`
- Surface: `App` / `Website` / `Admin` / `cross-project`
- Requested by: user
- Created: `YYYY-MM-DD`
- Dependencies:
- Scope:
- Acceptance:
- Dispatch target:
- Notes:
```

## Active Queue

## WS-2026-04-01-001 `fix/hud-state-rules`
- Status: `dispatched`
- Priority: `high`
- Surface: `App`
- Requested by: user
- Created: `2026-04-01`
- Dependencies:
  - `App/Apps/AetherCore/HUD/HUDManager.swift`
  - `App/Apps/AetherCore/SpeechManager.swift`
  - current `InputControlArbiter` integration
  - fresh runtime diagnostics for HUD transitions
- Scope:
  - Audit and simplify HUD state ownership, mode selection, and hide/show precedence.
  - Reduce cross-module rule overlap between `HUDManager.lastKnownTypingState()` and `SpeechManager.refreshContinuousHUD(...)`.
  - Focus on user-visible HUD behavior first: wrong mode, premature hide, unstable standby/listening/dictation transitions, and hard-to-explain rule stacking.
- Acceptance:
  - HUD mode matches the authoritative input/control state instead of drifting between display-only and session-sticky rules.
  - Wake standby, idle typing, dictation, and temporary HUD states have a clear precedence order with no obvious flicker or contradictory transitions.
  - Diagnostics can explain why the HUD is visible, hidden, or in a given mode without needing to infer from multiple subsystems.
  - Any remaining app-specific heuristics are isolated and explicitly documented instead of being mixed into the main decision tree.
- Dispatch target: `fix/hud-state-rules`
- Notes:
  - Initial code review shows HUD behavior is currently split across `HUDManager` and `SpeechManager`, with many early-return branches in `refreshContinuousHUD(...)`.
  - `HUDManager.handleGlobalMouseDown(...)` and `lastKnownTypingState()` still own focus/suppression evidence, while `SpeechManager` also decides visibility and mode.
  - Current diagnostics include repeated `WakeHUD reason=wake-standby-hidden` samples while `sessionTypingMode=true`, which suggests rule stacking is still producing confusing idle behavior.
  - Additional user symptom: in wake mode, the HUD often becomes visible even while the app is still unawakened.
  - Code evidence: the `wake-standby-hidden` branch is not a hard hide. It can still keep the HUD visible when `isSpeechExitBarsHoldActive(...)` is true, or when a temporary HUD / language indicator is already active.
  - Diagnostic nuance: `WakeHUD` snapshots log the current `HUDManager.shared.state` before the branch finishes hiding, so samples like `reason=wake-standby-hidden hud=dictation` may reflect stale on-screen state during transition rather than the branch intentionally choosing dictation mode.
  - Likely subproblem to isolate: distinguish legitimate transient carry-over HUDs from incorrect unawakened standby exposure, and make that reason explicit in diagnostics.
  - `2026-04-02`: now actively owned by App branch `fix/hud-state-rules`; implementation is consolidating visibility/mode/message into one decision path instead of separate patches.

## WS-2026-04-02-002 `fix/wake-followup-second-utterance-hud`
- Status: `dispatched`
- Priority: `high`
- Surface: `App`
- Requested by: user
- Created: `2026-04-02`
- Dependencies:
  - `App/Apps/AetherCore/SpeechManager.swift`
  - `App/Apps/AetherCore/Speech/VoiceActivityHoldPolicy.swift`
  - wake-follow-up timeout / recovery / HUD keepalive diagnostics
- Scope:
  - Investigate why, after wake activation, the HUD can disappear while the user is still speaking the second sentence.
  - Focus on the overlap between wake-follow-up timeout, post-wake recognition restarts, VAD activity refresh, and HUD keepalive.
  - Keep this scoped to follow-up runtime behavior; do not bundle general HUD redesign.
- Acceptance:
  - During wake follow-up, the second utterance should not lose the HUD mid-speech when voice activity is still present.
  - Wake-follow-up should not finalize as empty while the user is still actively speaking or while recognition is recovering from the wake handoff.
  - Diagnostics should clearly show whether a failure was caused by timeout expiry, missing VAD refresh, recognition restart/no-speech recovery, or HUD-only visibility logic.
- Dispatch target: `fix/hud-state-rules`
- Notes:
  - This overlaps with `fix/hud-state-rules`; do not run both blindly in parallel against the same `SpeechManager` HUD logic without ownership split.
  - Existing local notes already tracked a nearby workstream `fix/hud-voice-activity-hold`, but new runtime evidence suggests a residual or adjacent gap remains.
  - Fresh log sample on `2026-04-02 09:13:27` shows:
    - wake phrase `你好` begins follow-up window
    - recognition immediately hits two `No speech detected` recoverable errors after wake segmentation
    - only one `WakeFollowUp activity-extend reason=voice-activity` arrives at `09:13:29`
    - follow-up then `timeout-finalized` at `09:13:37` with `lastTranscript=''` and `hud=dictation`
  - This pattern suggests the failure is not only “HUD hid itself”, but “wake follow-up lost keepalive / usable recognition during the second-utterance window, and HUD disappeared as a consequence.”
  - `2026-04-02`: folded into `fix/hud-state-rules` because the runtime symptom shares the same HUD visibility decision path as the broader wake-gated hide/show problem.

## WS-2026-04-02-003 `fix/hud-text-latency`
- Status: `dispatched`
- Priority: `high`
- Surface: `App`
- Requested by: user
- Created: `2026-04-02`
- Dependencies:
  - `App/Apps/AetherCore/SpeechManager.swift`
  - `App/Apps/AetherCore/HUD/HUDManager.swift`
  - HUD transcript/message update path diagnostics
- Scope:
  - Investigate why HUD text appears slow, delayed, or visually laggy during speech.
  - Focus on the HUD text pipeline from `lastTranscript` / streamed dictation state through `collapsedHUDMessage(...)` into `HUDManager.shared.update(...)`.
  - Separate transcript/update latency from general HUD visibility and wake-follow-up timeout issues.
- Acceptance:
  - HUD text should update promptly enough to feel live during partial speech, without obvious stutter or long delay.
  - Diagnostics should distinguish whether lag comes from ASR partial delivery, dictation stream reconciliation, text collapsing/tail slicing, or HUD view rendering/update cadence.
  - If HUD intentionally shows a summarized tail instead of raw partial text, that behavior should still feel responsive and be explainable.
- Dispatch target: `fix/hud-state-rules`
- Notes:
  - This overlaps with both `fix/hud-state-rules` and `fix/wake-followup-second-utterance-hud`, but the user-visible symptom here is specifically text latency/jank rather than hide/show correctness.
  - Current static code path is layered:
    - `lastTranscript`
    - `remainingDictationHUDText()`
    - `displayedDictationHUDTail()`
    - `collapsedHUDMessage(...)`
    - `HUDManager.shared.update(...)`
  - That means HUD text lag could originate from upstream partial timing, text reconciliation against `screenTypedText`, semantic tail slicing, or downstream HUD rendering cadence.
  - `2026-04-02`: folded into `fix/hud-state-rules` so HUD text selection can be separated from visibility/mode rules in one bounded refactor.

## Dispatch Log

_No dispatched items yet._
