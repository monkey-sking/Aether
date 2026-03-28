# Settings Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize Aether’s settings window into a lighter task-based structure with a dedicated advanced area.

**Architecture:** Keep the existing settings data flow and most existing controls, but recompose them into new task-based pages. Extract reusable page content from the current monolithic settings implementations, simplify the shared page chrome, and update the sidebar to the new taxonomy.

**Tech Stack:** SwiftUI, AppKit interop, existing `AetherMainView` / `SettingsModules` / shared settings components

---

### Task 1: Rebuild the sidebar taxonomy

**Files:**
- Modify: `Apps/AetherCore/AetherMainView.swift`

- [ ] Define the new panel enum cases for the task-based sidebar.
- [ ] Remove unreachable legacy cases such as the old voice terms route.
- [ ] Update the sidebar sections/items to the approved primary pages.
- [ ] Route each new item to the correct page view.

### Task 2: Lighten shared settings chrome

**Files:**
- Modify: `Apps/AetherCore/VizComponents.swift`

- [ ] Replace the heavy repeated settings hero treatment with a lighter page header treatment.
- [ ] Keep titles/subtitles readable while moving the first interactive controls higher on the page.
- [ ] Verify the shared layout still works for pages with and without header trailing content.

### Task 3: Promote voice basics into a first-class page

**Files:**
- Modify: `Apps/AetherCore/SettingsModules.swift`

- [ ] Keep the current `.basics` content intact, but expose it from the new sidebar as `Voice Input`.
- [ ] Ensure its title/subtitle match the new task-based naming.

### Task 4: Build the new text cleanup page

**Files:**
- Modify: `Apps/AetherCore/SettingsModules.swift`

- [ ] Extract the current term-correction block into reusable content.
- [ ] Recompose that content with `LLMRewriteSettingsCard` into a new `TextCleanupSettingsView`.
- [ ] Keep existing data bindings and sheet flows for term group editing.

### Task 5: Build the new controls & shortcuts page

**Files:**
- Modify: `Apps/AetherCore/SettingsModules.swift`
- Modify: `Apps/AetherCore/KeyRecorderView.swift` (only if extraction convenience is needed)

- [ ] Extract reusable pointer-control content from the current pointer page.
- [ ] Extract reusable head-gesture content from the current head-gesture page.
- [ ] Compose a new `ControlsShortcutsSettingsView` that shows pointer controls, head gestures, and hotkey settings in one task page.

### Task 6: Build the permissions & status page

**Files:**
- Modify: `Apps/AetherCore/AetherMainView.swift`
- Modify: `Apps/AetherCore/SettingsModules.swift` (only if helper extraction is needed)

- [ ] Move readiness/system-setup material out of the heavy overview flow into a dedicated page.
- [ ] Keep launch-at-login, app language, and idle-pause settings together there.
- [ ] Preserve existing guided permission actions.

### Task 7: Split advanced settings from logs and diagnostics

**Files:**
- Modify: `Apps/AetherCore/SettingsModules.swift`
- Modify: `Apps/AetherCore/AetherMainView.swift`

- [ ] Replace the single `Advanced` destination with two sidebar groups: `Advanced` and `Logs & Diagnostics`.
- [ ] Keep lexicon, app rules, and transfer actions under `Advanced`.
- [ ] Move usage/wake diagnostics into `Logs & Diagnostics`.
- [ ] Add focused wrapper pages for `Import / Export` and `Focus & Input Diagnostics`.

### Task 8: Slim the overview page

**Files:**
- Modify: `Apps/AetherCore/AetherMainView.swift`

- [ ] Keep overview as a home/status page.
- [ ] Remove or downscope material that now belongs to `Permissions & Status`.
- [ ] Leave a lighter summary surface that still helps first-run users orient themselves.

### Task 9: Safe validation

**Files:**
- Modify: none unless fixes are needed

- [ ] Run safe source-level checks that do not cross the repo’s signing/build boundary.
- [ ] Review the changed Swift files for obvious missing references, routing mistakes, and reused bindings.
- [ ] Summarize any residual risk if validation remains source-review-only.
