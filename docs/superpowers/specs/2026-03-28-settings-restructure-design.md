# Aether Settings Restructure Design

## Goal

Make the settings window feel lighter for everyday use while preserving advanced capabilities in a dedicated advanced area.

## Product Direction

- Primary grouping is task-based, not subsystem-based.
- Keep an `Overview` page, but make it a compact home instead of a dense dashboard.
- Preserve power-user features, but move them out of the normal first-run and daily-use flow.
- Reduce visual weight across settings pages by toning down the repeated hero treatment.

## Approved IA Direction

### Primary Sidebar

1. `Overview`
2. `Voice Input`
3. `Text Cleanup`
4. `Controls & Shortcuts`
5. `Permissions & Status`
6. `About`
7. `Advanced`

### Content Mapping

#### Overview

- Keep readiness summary.
- Keep a smaller set of core feature summaries/quick controls.
- Remove the denser global/system setup material that belongs elsewhere.

#### Voice Input

- Microphone device selection
- Speech language selection
- Activation mode selection
- Voice enable / headset auto-enable
- Speech permission warnings that are tightly coupled to activation

This page is backed by the existing `.basics` settings content.

#### Text Cleanup

- Developer terminology boost
- Auto punctuation status
- Speech term correction groups
- Automatic dictation cleanup / manual full-text rewrite configuration

This page merges the current term-correction content with the current LLM rewrite card because both belong to the same user task: improving dictated text.

#### Controls & Shortcuts

- Pointer control basics
- Head gesture / hot-zone behavior
- Keyboard shortcut bindings

This page is a task page for input control, replacing the current split across separate technical pages.

#### Permissions & Status

- Readiness / permission setup card
- Launch-at-login
- App language
- Global pause-after-idle behavior

This page holds app/system state and setup flows that do not belong inside content-related settings pages.

#### Advanced

- Voice lexicon editor
- App controls / app aliases / shortcut rule customization
- Voice insights
- Wake insights

Advanced is explicitly a power-user destination. Import/export, aliases, app-specific rules, and diagnostics stay available but no longer compete with the default settings flow.

## UI Rules

- Settings pages should use a lighter page header instead of a repeated heavy hero card.
- Page structure should prioritize the first actionable controls above descriptive chrome.
- Advanced content should remain discoverable from the sidebar, not hidden behind secret gestures or mixed into unrelated pages.
- User-facing pages should avoid raw file names and raw error strings where a friendly status message can do the job.

## Implementation Shape

### AetherMainView

- Replace the current sidebar taxonomy with the approved task-based list.
- Remove obsolete or unreachable panels such as the old `voiceTerms` route.
- Route new sidebar items to new/recomposed settings pages.

### SettingsModules

- Reuse the existing `.basics` implementation for `Voice Input`.
- Extract reusable content blocks from the existing monolithic settings pages so they can be recomposed:
  - term-correction content
  - pointer-control content
  - head-gesture content
  - app-controls content where needed
- Build new wrapper pages for:
  - `TextCleanupSettingsView`
  - `ControlsShortcutsSettingsView`
  - `PermissionsStatusSettingsView`
  - `AdvancedSettingsView`

### VizComponents

- Lighten `SettingsPageHero` / `SettingsPage` so the global page chrome feels calmer and less dashboard-like.

## Out of Scope

- No packaging/release work.
- No new underlying speech/head-tracking behavior.
- No major rewrite of settings data models.
- No broad localization cleanup beyond what the new page labels require.
