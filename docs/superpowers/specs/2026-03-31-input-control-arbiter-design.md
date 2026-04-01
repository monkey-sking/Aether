# Input Control Arbiter Design

## Goal

Replace the competing typing/control state heuristics with one authoritative state source so focus changes, HUD, speech routing, and head-motion control all follow the same interaction truth.

## Problem

The current app still keeps parallel truth sources:

- `HUDManager.lastKnownTypingState()` owns focus/click suppression and explicit reentry.
- `SpeechManager.sessionTypingMode` plus recovery/sticky dictation owns the active speech session.
- `HeadMotionManager` infers auto mode from HUD typing state.
- `UtteranceArbitrator` only unifies command vs dictation commitment for one utterance.

This split creates the same failure mode in different forms:

- Clicking outside an input can suppress HUD focus state while speech still thinks it is typing.
- Wake follow-up can still be routed as dictation after HUD already looks like control mode.
- Head-motion auto mode follows HUD inference instead of the real active interaction state.

## Product Rule

There must be one authoritative answer to:

1. Is the app currently in `typing` or `command` interaction?
2. Is the app currently `suppressed` from typing because the user explicitly clicked out?
3. For the current utterance, has the app committed to `command`, committed to `dictation`, or not committed yet?

Everyone else reads that answer. No other module gets to keep an independent semantic copy.

## Authoritative Core

Introduce `InputControlArbiter` as the shared source of truth.

### External Outputs

- `interactionState`
  - `command`
  - `typing`
  - `suppressed`
  - `pending`
- `utteranceDecision`
  - `pending`
  - `commandCommitted`
  - `dictationCommitted`

### Internal Layers

- `focusState`
  - `typing`
  - `nonTyping`
  - `suppressed`
  - `unknown`
- `sessionState`
  - `idle`
  - `typingSession`
  - `commandSession`
  - `recoveryHold`

## Ownership

### HUDManager

- Still owns low-level focus evidence collection:
  - global mouse clicks
  - explicit typing reentry
  - AX/caret/input-rect heuristics
- No longer owns semantic typing truth for display.
- Must publish focus evidence into `InputControlArbiter`.
- HUD display must read arbiter output instead of re-deriving semantics locally.

### SpeechManager

- Still owns speech-session facts:
  - wake follow-up activity
  - capture/running state
  - recovery hold
  - streamed/committed dictation evidence
  - utterance router decisions
- No longer owns an independent semantic truth for interaction mode.
- During migration, `sessionTypingMode` may remain as a compatibility mirror, but arbiter output becomes authoritative.

### HeadMotionManager

- Must stop inferring auto recognition control mode from `HUDManager.lastKnownTypingState()`.
- Must read the arbiter interaction state directly.

### Utterance Arbitration

- `UtteranceArbitrator` remains the low-level command-vs-dictation decision function for now.
- It moves onto the same shared mode model and is invoked through `InputControlArbiter`, not as a floating parallel truth source.

## Resolution Rules

### Interaction State

1. Explicit `command` mode resolves to `command`.
2. Explicit `dictation` mode resolves to `typing`.
3. In `auto` mode:
   - `focusState == suppressed` resolves to `suppressed`.
   - `sessionState == typingSession` resolves to `typing`.
   - `sessionState == recoveryHold` resolves to `typing`.
   - `focusState == typing` resolves to `typing`.
   - `sessionState == commandSession` resolves to `command`.
   - `focusState == nonTyping` resolves to `command`.
   - otherwise resolve to `pending`.

### Utterance Decision

- Explicit command mode commits `command`.
- Explicit dictation mode commits `dictation`.
- Auto mode routes through the shared arbitration function, using authoritative typing state instead of ad hoc HUD/session copies.

## Migration Strategy

### Phase 1

- Add `InputControlArbiter` core.
- Move shared mode enums away from `HeadMotionManager`.
- Add focused unit coverage for interaction-state resolution.

### Phase 2

- HUD publishes focus evidence and reads arbiter interaction state for `state.isTypingContext`.
- Non-input click suppression updates arbiter immediately.

### Phase 3

- Speech publishes session facts and reads arbiter interaction state for HUD/auto-mode decisions.
- Keep `sessionTypingMode` as a mirror only where existing pipelines still need it.

### Phase 4

- Head-motion auto mode reads arbiter interaction state.
- Wake follow-up utterance commitment is published through arbiter.

### Phase 5

- Remove redundant direct semantic readers/writers in HUD, speech, and head motion.

## Out Of Scope

- Packaging, signing, or runtime permission mutation.
- Rewriting the entire wake pipeline.
- Replacing AX heuristics themselves.
- Replacing dictation injection or command execution logic.

## Acceptance Criteria

1. Clicking a non-input region clears typing interaction in one place, and HUD / speech / head motion all follow it.
2. Clicking back into an input restores typing interaction in one place, and HUD / speech / head motion all follow it.
3. Auto-mode head control no longer depends on HUD-local typing inference.
4. Wake follow-up command vs dictation commitment still works with the shared mode model.
5. No new semantic state source is introduced outside `InputControlArbiter`.
