# Input Control Arbiter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace parallel typing/control truth sources with a single `InputControlArbiter` that drives HUD, speech interaction state, and head-motion auto mode.

**Architecture:** Add a shared arbiter core with authoritative `interactionState` and `utteranceDecision`, then migrate `HUDManager`, `SpeechManager`, and `HeadMotionManager` to publish evidence and consume arbiter output instead of keeping competing semantic state.

**Tech Stack:** Swift, XCTest, existing `HUDManager`, `SpeechManager`, `HeadMotionManager`, `UtteranceArbitrator`

---

### Task 1: Add shared arbiter core

**Files:**
- Create: `Apps/AetherCore/Speech/InputControlArbiter.swift`
- Modify: `Apps/AetherCore/Speech/UtteranceArbitrator.swift`
- Create: `AetherTests/InputControlArbiterTests.swift`
- Modify: `AetherTests/UtteranceArbitratorTests.swift`

- [ ] Define shared mode enums independent from `HeadMotionManager`.
- [ ] Add authoritative snapshot/state resolution for focus, session, interaction, and utterance decision.
- [ ] Route utterance arbitration through the shared mode model.
- [ ] Add focused unit coverage for interaction-state resolution and utterance-mode conversion.

### Task 2: Move HUD semantic typing display onto arbiter

**Files:**
- Modify: `Apps/AetherCore/HUD/HUDManager.swift`
- Modify: `AetherTests/VoiceCommandRouterTests.swift`

- [ ] Publish input / non-input click evidence into the arbiter.
- [ ] Publish focus typing results from `lastKnownTypingState()` into the arbiter.
- [ ] Make HUD display read arbiter interaction state instead of HUD-local semantic truth.
- [ ] Preserve current carryover rules for processing/organizing HUD stages.

### Task 3: Move speech session ownership onto arbiter

**Files:**
- Modify: `Apps/AetherCore/SpeechManager.swift`
- Modify: `AetherTests/AetherTests.swift`

- [ ] Add a speech-side sync point that publishes session facts into the arbiter.
- [ ] Convert direct `sessionTypingMode` semantic writes into arbiter-backed updates.
- [ ] Make HUD refresh and speech auto-mode helpers read arbiter interaction state.
- [ ] Publish wake follow-up utterance commitment through the arbiter.

### Task 4: Move head-motion auto mode onto arbiter

**Files:**
- Modify: `Apps/AetherCore/HeadMotionManager.swift`

- [ ] Replace `HUDManager.lastKnownTypingState()` semantic reads with arbiter interaction reads.
- [ ] Preserve transient override behavior while changing the semantic source.
- [ ] Keep manual command/dictation toggles intact.

### Task 5: Safe validation

**Files:**
- Modify: none unless fixes are needed

- [ ] Run safe source-level validation on touched Swift files.
- [ ] Review tests for stale assumptions about HUD-owned semantics.
- [ ] Summarize any remaining compatibility mirrors or cleanup follow-ups.
