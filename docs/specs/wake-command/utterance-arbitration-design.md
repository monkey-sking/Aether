# Utterance Arbitration Design

Date: 2026-03-31
Scope: core `input vs control` utterance arbitration, with `wake word + follow-up` as the first integration target
Workstream: `fix/wake-command`
Status: Draft for review

## Problem

The current speech pipeline has multiple layers that can independently shift an utterance between `command` and `dictation`.

Known effects:

- HUD can appear to be in control mode while the final intent is recorded as `dictation`.
- Partial streaming can begin as dictation before final routing has actually settled the utterance type.
- Sticky state such as `sessionTypingMode` and `screenTypedText` can push an utterance back to `dictationPreferred` even when the text itself is a valid command.
- Usage stats can end up reflecting an intermediate routing path instead of the final committed user intent.

The result is not that the system lacks an input/control classifier. The real problem is that multiple layers compete for ownership of the final classification.

## Goal

Create a single arbitration layer for all spoken utterances so that each utterance has exactly one committed class:

- `command`
- `dictation`

Everything else in the pipeline must consume that committed class and stop reinterpreting it.

Wake follow-up is the first migration target because it currently exposes the problem most clearly.

## Non-Goals

- No immediate full migration of every existing speech path in one change.
- No packaging or release changes.
- No wake-word model changes.

## Current Failure Mode

Today, these sources can all influence the same utterance:

1. Text semantic routing from `VoiceCommandRouter.routeDetailed(...)`
2. Utterance typing inference from `resolvedUtteranceTypingMode(...)`
3. Wake fallback restoration
4. Inline wake payload promotion to typing
5. Sticky streamed-text state from `DictationHandler.screenTypedText`
6. HUD-derived or focus-derived typing evidence

This creates two classes of bugs:

1. Split-brain outcome
   - HUD looks like control
   - final usage event becomes dictation

2. Early commitment bug
   - partial streaming begins as dictation
   - streamed text then influences final routing
   - final classification is no longer based on the original utterance intent alone

## Design Principle

There must be one and only one owner of utterance classification.

That owner is a new pure-logic layer:

- `UtteranceArbitrator`

Its output is authoritative for the rest of the speech pipeline.

The following signals are inputs only, never final owners:

- focused editable context
- recent click fallback
- AX typing evidence
- `sessionTypingMode`
- `screenTypedText`
- wake typing fallback windows
- HUD state

## Target Pipeline

The core utterance path should be:

1. ASR partial/final arrives
2. optional pre-processing strips transport-specific framing
   - wake phrase stripping
   - explicit command prefix consumption
   - other mode-local normalization
3. utterance arbitrator evaluates the normalized utterance
4. arbitrator emits one state:
   - `pending`
   - `dictationCommitted`
   - `commandCommitted`
5. downstream consumers react:
   - partial text injection only if `dictationCommitted`
   - command execution only if `commandCommitted`
6. HUD, analytics, and usage history mirror the committed state

This means the final intent is no longer allowed to be changed by downstream side effects.

## Core Arbitration State

The shared arbitration core introduces only three states:

- `pending`
- `dictationCommitted`
- `commandCommitted`

Rules:

- `pending` is the only undecided state.
- Once the state becomes `dictationCommitted` or `commandCommitted`, no later layer may reinterpret the utterance class.

## Wake Follow-Up Lifecycle

Wake follow-up still has its own outer lifecycle:

- `standby`
- `wakeDetected`
- `followUpPending`
- `dictationCommitted`
- `commandCommitted`
- `completed`

Valid transitions:

- `standby -> wakeDetected`
- `wakeDetected -> followUpPending`
- `followUpPending -> dictationCommitted`
- `followUpPending -> commandCommitted`
- `dictationCommitted -> completed`
- `commandCommitted -> completed`

Rules:

- `followUpPending` is the only undecided state.
- Once outer state maps to `dictationCommitted` or `commandCommitted`, it is driven by the shared arbitration result.
- `completed` clears wake-follow-up-local arbitration state only after execution or injection bookkeeping finishes.

## Arbitrator Inputs

The arbitrator should consume a single normalized evidence struct:

- explicit recognition control mode: `command`, `dictation`, `auto`
- normalized utterance text
- transport context:
  - wake follow-up active
  - push-to-talk active
  - one-shot capture
- command routing decision from `VoiceCommandRouter.routeDetailed(...)`
- stable typing evidence summary:
  - authoritative focused input present
  - recent click fallback present
  - special app-wide typing mode active
- live typing evidence summary
- whether dictation has already been explicitly committed for the current utterance

Notably absent:

- HUD mode
- `screenTypedText` as a classifier input

`screenTypedText` may still exist, but only as output-side execution state.

## Arbitration Rules

### Explicit command mode

If user mode is explicitly `command`, arbitrator emits `commandCommitted`.

### Explicit dictation mode

If user mode is explicitly `dictation`, arbitrator emits `dictationCommitted`.

### Auto mode

In `auto`, the arbitrator works in this order:

1. Ask the router for the text semantic decision.
2. If semantic decision is a sufficiently confident command intent, emit `commandCommitted`.
3. If semantic decision is clearly dictation, and stable typing evidence exists, emit `dictationCommitted`.
4. If evidence is still inconclusive on early partials, stay in `followUpPending`.
5. If partial remains inconclusive until final, decide once at final using the same evidence stack.

Important constraint:

- `pending` does not allow text injection.

This prevents early dictation side effects from changing later classification.

The same rule applies regardless of whether the utterance came from wake follow-up, push-to-talk, or another capture path.

## Partial and Final Responsibilities

### Partial phase

Partial phase may do three things only:

- maintain wake lifecycle timing
- feed evidence into the arbitrator
- render non-committal HUD states while still pending

Partial phase must not:

- start dictation streaming while arbitration is still `pending`
- treat HUD state as a routing override
- use existing streamed text to force dictation classification

If arbitration reaches `dictationCommitted` during partials, partial streaming may start from that point onward.

### Final phase

Final phase must:

- finalize the same arbitrator state machine
- execute command or inject dictation based on committed result
- update stats and usage history using committed result only

Final phase must not:

- re-derive the utterance class from downstream state such as streamed text count
- let sticky typing state override a committed command decision

## HUD and Stats Rules

HUD and stats become read-only consumers of arbitration output.

### HUD

- `followUpPending` may show a neutral wake/listening/organizing state.
- `dictationCommitted` may show input-oriented typing state.
- `commandCommitted` may show control/executing state.

HUD must not feed back into the routing decision.

### Usage stats

Usage stats must record:

- committed intent type
- execution result

They must not record intermediate partial routing artifacts as the final class.

## Dictation Streaming and Rollback

The preferred design is to avoid starting dictation streaming before `dictationCommitted`.

However, rollout can be staged:

Stage 1:

- keep current rollback path
- if command wins after accidental partial dictation side effects, delete streamed text and execute the command

Stage 2:

- move injection gate earlier
- do not start dictation streaming until arbitration commits dictation

Stage 2 is the target steady state.

## Proposed Refactor Boundaries

### New isolated logic

Create a pure logic type for utterance arbitration, separate from UI and injector concerns.

Suggested responsibilities:

- accept evidence snapshots
- produce arbitration state transitions
- expose whether dictation injection is allowed
- expose committed utterance class

### Existing code to demote into evidence providers

The following should stop mutating final routing directly and instead provide evidence:

- wake typing fallback restoration
- inline wake payload typing promotion
- focus-derived typing checks
- recent-click fallback typing checks

### Existing code to keep as execution-only

- `DictationHandler`
- command execution pipeline
- rollback of streamed dictation when command wins

### Outer adapters

Outer lifecycle adapters translate source-specific capture state into core arbitration inputs.

Initial adapter:

- `WakeFollowUpAdapter`

Future adapters:

- `PushToTalkAdapter`
- `OneShotCaptureAdapter`

## Migration Plan

### Step 1

Introduce `UtteranceArbitrator` as a pure helper with unit tests.

### Step 2

Introduce `WakeFollowUpAdapter` that maps wake lifecycle state into the shared arbitrator, without changing execution behavior yet.

### Step 3

Replace direct typing overrides with evidence collection and a single arbitration result.

### Step 4

Gate partial dictation injection on `dictationCommitted` for wake follow-up.

### Step 5

Switch HUD and usage history to read committed arbitration output only.

### Step 6

Remove redundant wake-specific routing helpers that are no longer owners of classification.

### Step 7

Migrate PTT and other non-wake capture paths onto the same `UtteranceArbitrator`.

## Validation Plan

Minimum regression coverage for the shared arbitrator:

1. `wake + command` in auto mode commits command and never lands as dictation stats.
2. `wake + dictation` in a stable input context commits dictation and streams only after commit.
3. PTT command utterances and wake command utterances resolve through the same core arbitrator.
4. HUD mode always matches committed arbitration class once committed.
5. Final command routing is not overridden by streamed text leftovers.
6. Final dictation routing is not blocked by temporary pending state.
7. No-input-target failures are only emitted for utterances committed as dictation.

## Risks

- If pending lasts too long, wake follow-up dictation may feel less immediate.
- If command confidence thresholds are too aggressive, some intended dictation may commit as command in auto mode.
- If execution code still reads sticky typing state directly, split-brain behavior can persist despite the arbitrator.

## Recommended Rollout

Ship the refactor in two passes:

1. shared arbitration core plus wake integration
2. delayed partial injection after dictation commit
3. migrate remaining capture paths onto the same core

This reduces risk while still eliminating the current split-brain classification bug early.

## Decision Summary

This design does not add special phrase rules.

Instead, it fixes ownership:

- one classifier for all utterances
- one committed result per utterance
- no downstream layer allowed to reinterpret the utterance class
