# Activation Gating TODO

## Goal
Make Aether require a valid activation or trial before the core product can be used.

Current state:
- The app already has activation, trial, and entitlement refresh UI in `AboutCenter.swift`.
- The app does **not** currently gate core features behind activation.
- Users can still access and use the main product without a valid entitlement.

## Required Outcome
- Aether launches into either:
  - an activated state, or
  - a locked state that clearly asks the user to activate or start a trial
- Core product features must not be usable when entitlement is inactive or expired.
- The activation path must remain recoverable from inside the app.

## Scope
This task is for the macOS app in:
- `/Volumes/SSD/Projects/Aether/Apps/Apps/AetherCore`

Primary existing files to review:
- [AboutCenter.swift](/Volumes/SSD/Projects/Aether/Apps/Apps/AetherCore/AboutCenter.swift)
- [AetherMainView.swift](/Volumes/SSD/Projects/Aether/Apps/Apps/AetherCore/AetherMainView.swift)
- [AetherApp.swift](/Volumes/SSD/Projects/Aether/Apps/Apps/AetherCore/AetherApp.swift)

## Problems To Fix
1. Activation state is currently mostly informational.
The `AetherLicenseManager` tracks `status`, `plan`, and `isActivated`, but this state is not being used to block the main experience.

2. Core controls are still reachable without entitlement.
The user can enter the main interface and access product panels even if activation is missing.

3. There is no unified locked-state UX.
The app needs a clear "you need activation" experience instead of scattered disabled controls.

4. Expired and inactive states are not product-gated.
The app should treat `inactive`, `expired`, and invalid entitlement states as locked for normal usage.

## Implementation Tasks

### 1. Create a shared entitlement gate model
- Add one clear app-level source of truth for access state.
- Recommended states:
  - `active`
  - `trialing`
  - `inactive`
  - `expired`
  - `device_limit_reached`
  - `loading`
- The gate should derive from `AetherLicenseManager`, not duplicate license logic in multiple places.

Exit criteria:
- One place in app code decides whether the product is usable.
- Other views can read a simple gate state instead of re-implementing entitlement checks.

### 2. Add a locked root experience
- When entitlement is not active/trialing, the app should open into a locked screen instead of the normal product UI.
- This locked screen should include:
  - email field
  - activation code field
  - "Activate"
  - "Start Trial"
  - "Resend Activation"
  - current status / error messaging
- Reuse existing `AetherLicenseManager` actions instead of re-implementing network calls.

Exit criteria:
- Launching without valid entitlement shows a locked screen first.
- A successful activation/trial transitions the user into the main app.

### 3. Gate the main window and core panels
- Prevent normal product panels from being the initial/default experience when not activated.
- At minimum gate:
  - overview
  - voice controls
  - head gesture controls
  - shortcuts / input-related surfaces
- About can remain reachable as part of recovery flow.

Exit criteria:
- Unactivated users cannot meaningfully use the main interface.
- Activated users still see the normal app flow.

### 4. Gate runtime feature enablement
- Even if a user reaches some UI accidentally, core runtime behavior must still be blocked.
- Review and gate the services that actually execute product behavior:
  - voice input / dictation execution
  - voice command execution
  - head tracking / motion-driven controls
  - any global command / shortcut execution path
- The gate should fail closed when entitlement is inactive or expired.

Exit criteria:
- No core input/control behavior runs without valid entitlement.
- Locking is enforced at the service/runtime layer, not only at the view layer.

### 5. Handle cold start and refresh correctly
- On launch, do not treat missing credentials as active.
- While entitlement is being refreshed, show a deterministic loading or locked state.
- Avoid a brief "fully usable" window before license refresh completes.

Exit criteria:
- App startup does not temporarily expose the full product before refresh completes.
- Activation status is stable on launch.

### 6. Define inactive and expired behavior clearly
- `trialing`, `active`, `valid`, `activated` should allow use.
- `inactive`, `expired`, and equivalent failure states should lock use.
- `device_limit_reached` should be recoverable via device management UI and should not silently behave like success.

Exit criteria:
- Each backend license state maps to a clear UX and access behavior.

### 7. Keep recovery paths available
- Locked users still need:
  - activation
  - start trial
  - resend activation
  - refresh entitlement
  - device management, if relevant for recovery
- Do not dead-end the user in a locked screen with no recovery path.

Exit criteria:
- A user can recover from inactive, expired, or wrong-device states without leaving the app.

### 8. Verify channel behavior is unaffected
- Activation gating must not break:
  - Stable/Beta switching
  - update checks
  - About page status display
- Update UI may remain visible, but product usage must still require entitlement.

Exit criteria:
- Activation gate does not regress About, channel switching, or update logic.

## Recommended File Changes
- Add a new locked-state root view, or equivalent:
  - example: `ActivationGateView.swift`
- Update:
  - `AetherMainView.swift`
  - `AetherApp.swift`
  - `AboutCenter.swift`
- Only add new state where necessary. Prefer reusing `AetherLicenseManager`.

## Test Checklist
- Fresh install with no email and no activation code:
  - app opens locked
  - core features are not usable
- Start trial:
  - app unlocks
  - feature access becomes available
- Activate with valid code:
  - app unlocks
  - device appears in entitlement state
- Expired entitlement:
  - app returns to locked state
  - recovery path remains available
- Device limit reached:
  - app shows a recoverable blocked state
- Launch after previous activation:
  - app remains locked until entitlement refresh confirms valid access
- About page:
  - still shows status, devices, channel, and actions correctly

## Non-Goals
- Do not redesign the commercial model in this task.
- Do not rewrite backend licensing endpoints in this task.
- Do not remove the existing About activation center; reuse it where possible.

## Suggested Priority
1. App-level locked state
2. Runtime feature gating
3. Recovery UX polish
4. State mapping cleanup

