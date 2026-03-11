# Aether Whisper / Multi-ASR Backend Implementation Checklist

## Goal

Add an optional speech-recognition backend switch for Aether without regressing the current Apple Speech path.

Initial target backends:

- `Apple Speech` as the default
- `Whisper Local` via local `whisper` CLI

Optional later:

- `OpenAI Whisper API`

## Current State

- Audio capture is already isolated in `AudioCaptureSession`.
- Recognition is currently hard-wired to `SFSpeechRecognizer` in `RecognitionSession`.
- `SpeechManager` orchestrates the active recognition lifecycle and routing.
- SkillHub `openai-whisper` has been installed locally, but it is only a skill descriptor and not an SDK integration layer for Aether.

## Phase 1: Backend Abstraction

- [ ] Define a `SpeechRecognitionBackend` protocol
- [ ] Separate backend lifecycle from routing logic in `SpeechManager`
- [ ] Preserve the current callback model:
  - partial transcript
  - final transcript
  - recoverable / unrecoverable error
- [ ] Keep audio capture ownership in `AudioCaptureSession`
- [ ] Ensure backend switching does not affect current wake-word / command routing flow

## Phase 2: Apple Speech Backend Refactor

- [ ] Rename or wrap current `RecognitionSession` as `AppleSpeechBackend`
- [ ] Keep current `preferOnDeviceRecognition` behavior
- [ ] Keep current punctuation and contextual string behavior
- [ ] Keep current locale selection behavior
- [ ] Verify no behavioral regression in:
  - command mode
  - dictation mode
  - push-to-talk
  - always listening

## Phase 3: Whisper Local Backend

- [ ] Add a `WhisperCLIBackend`
- [ ] Decide the first implementation mode:
  - preferred first cut: segment-based transcription after speech stop
- [ ] Reuse `AudioCaptureSession` buffers for Whisper input
- [ ] Add temporary audio export pipeline for Whisper consumption
- [ ] Support at least:
  - input file path generation
  - model selection
  - output text parsing
- [ ] Handle first-run model download latency explicitly
- [ ] Handle `whisper` missing / execution failure gracefully

## Phase 4: Settings and UX

- [ ] Add a new settings item: `Recognition Engine`
- [ ] Provide user-facing options:
  - `Apple Speech`
  - `Whisper Local`
- [ ] Show a short description for each backend:
  - `Apple Speech`: lower latency, better for command control
  - `Whisper Local`: stronger transcription quality, better for long-form speech
- [ ] Add readiness checks for `Whisper Local`:
  - CLI installed
  - model available or downloadable
- [ ] Persist selected backend in `UserDefaults`

## Phase 5: Runtime Behavior

- [ ] Switch backend without changing the rest of the intent pipeline
- [ ] Keep `VoiceCommandRouter` unchanged as much as possible
- [ ] Keep dictation injection flow unchanged as much as possible
- [ ] Ensure the same final transcript format reaches downstream logic
- [ ] Keep logs explicit about active backend

## Phase 6: Error Handling

- [ ] If Whisper CLI is unavailable, fall back cleanly or surface actionable UI
- [ ] If Whisper transcription times out, surface backend-specific error
- [ ] Avoid blocking the UI thread while waiting for Whisper results
- [ ] Cancel in-flight Whisper work correctly when session is aborted

## Phase 7: Validation Matrix

- [ ] Apple Speech still works after refactor
- [ ] Whisper Local can transcribe short commands
- [ ] Whisper Local can transcribe longer dictation
- [ ] Chinese speech works
- [ ] English speech works
- [ ] Mixed Chinese / English speech works
- [ ] AirPods microphone works
- [ ] Built-in microphone works
- [ ] Push-to-talk works with both backends
- [ ] Always listening works with both backends, or is explicitly limited with clear UX

## Phase 8: Performance Review

- [ ] Measure command latency with Apple Speech
- [ ] Measure command latency with Whisper Local
- [ ] Measure long-form dictation quality with both
- [ ] Compare small vs medium Whisper models
- [ ] Decide whether Whisper should stay optional or become recommended for dictation

## Phase 9: Future Extensions

- [ ] Evaluate `faster-whisper` instead of the Python `whisper` CLI
- [ ] Evaluate streaming / incremental Whisper integration
- [ ] Add `OpenAI Whisper API` as a third backend if needed
- [ ] Consider per-mode backend selection:
  - Apple for control mode
  - Whisper for dictation mode

## Definition Of Done

- [ ] Aether exposes a backend switch in settings
- [ ] Apple Speech remains the default and does not regress
- [ ] Whisper Local is usable end-to-end from microphone to transcript
- [ ] Final transcript still flows into existing command / dictation pipeline
- [ ] Backend-specific failures are visible and actionable
- [ ] Acceptance checklist is updated with a dedicated validation section
