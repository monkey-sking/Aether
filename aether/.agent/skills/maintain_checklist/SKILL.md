---
name: maintain_checklist
description: Best practices for managing verification checklists (`verification_checklist.md`).
---

# Verification Checklist Management

This skill defines the protocol for creating and maintaining the `verification_checklist.md` file. This file acts as the "Test Plan" for the user to verify functionality before a release.

## 1. When to Use
- **Release Candidates**: Always check this file before building a release.
- **Feature Development**: Add new items when implementing features that require manual testing.
- **Bug Fixes**: Add items to verify the fix.

## 2. Rules of Engagement
- **Language**: All new items must be written in **Simplified Chinese (简体中文)**.
- **NEVER Pre-check Items**: **Do not marks items as completed (`[x]`) unless the USER has explicitly verified them or you have undeniable automated proof.** 
    - *Wrong*: "I wrote the code, so it's done `[x]`."
    - *Right*: "I implemented it, adding it to the list for you to check `[ ]`."
- **Be Specific**: Checklist items should describe the *expected behavior* (e.g., "Pressing Option+Space triggers 'Listening...' HUD").
- **Group Logically**: Use headers like `## Core Voice`, `## UI/UX` to organize items.

## 3. Workflow
1.  **Implement Feature/Fix**.
2.  **IMMEDIATELY Add Item**: **Before running any build or notifying the user**, append a new `[ ]` item to `verification_checklist.md`.
    - *Example*: `- [ ] **Feature Name**: Description of what to verify.`
    - **Do NOT forget this step. It is part of the coding process.**
3.  **Notify User**: Tell the user, "I've added X to the checklist. Please verify."
4.  **User Verification**: The user checks the box `[x]` after testing.

## 4. Maintenance
- Remove obsolete items if the feature is removed.
- If a check fails, do NOT remove the item; fix the code and ask to verify again.
