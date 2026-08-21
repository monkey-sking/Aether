# Task Plan: Review official marketplace readiness

## Goal
Assess what this Aether project still needs to change for Apple official marketplace distribution, based on current repo code and release docs.

## Current Phase
Phase 5

## Phases
### Phase 1: Requirements & Discovery
- [x] Understand user intent
- [x] Identify constraints and requirements
- [x] Document findings in findings.md
- **Status:** complete

### Phase 2: Planning & Structure
- [x] Define technical approach
- [x] Identify code/config/doc surfaces affecting marketplace distribution
- [x] Document decisions with rationale
- **Status:** complete

### Phase 3: Repository Review
- [x] Inspect entitlement, plist, project, and release docs
- [x] Compare docs with current code/config state
- [x] Identify concrete changes needed
- **Status:** complete

### Phase 4: Validation
- [x] Cross-check findings against repo evidence
- [x] Classify findings by severity and certainty
- [x] Document validation status in progress.md
- **Status:** complete

### Phase 5: Delivery
- [x] Summarize what needs to change
- [x] Separate verified findings from inference
- [x] Deliver concise user-facing answer
- **Status:** complete

## Key Questions
1. Does “官方市场” map to Apple App Store/TestFlight in current repo context?
2. Which code/config/release surfaces currently block or complicate official marketplace distribution?
3. Which changes are verified by source inspection versus only suggested by prior docs?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Treat the request as an Apple official marketplace review first | Repo already contains App Store/TestFlight distribution analysis and no stronger alternative “marketplace” meaning has appeared yet |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |

## Notes
- Keep findings grounded in repo evidence, not just existing analysis docs.
- Avoid build/test commands that could touch signing or installed app identities.

## Supplemental Workstream: `review/cpu-usage-diagnosis`

### Goal
Explain why Aether's CPU usage is currently high by tracing the live runtime paths in source and existing diagnostics, then separate the primary cause from secondary steady-state overhead.

### Baseline
- Date: 2026-04-08
- Scope: `/Volumes/SSD/Projects/Aether/App`
- Validation mode: source inspection + existing diagnostics only
- Risk: Medium

### Phases
- [x] Identify CPU-relevant timers, polls, and animation paths in the app runtime
- [x] Cross-check those paths against `~/Library/Logs/Aether/diagnostics.log`
- [x] Rank the likely steady-state CPU contributors
- [x] Prepare a user-facing conclusion grounded in repo evidence

### Current Hypothesis
- CPU is elevated due to stacked steady-state polling rather than a single tight loop.
- The most expensive path is the `SpeechManager` `0.15s` HUD refresh, because it also re-runs AX typing evaluation almost every tick.
- High-frequency `WakeHUD` logging and diagnostics file writes materially amplify the steady-state cost.
- `AirPodsDetector` and `HeadMotionManager` also add unconditional background work even outside active speech.

## Supplemental Workstream: `feature/voice-lexicon-app-launch-prefixes`

### Goal
Move app-launch prefixes into the main voice lexicon so users can edit phrases like “打开 / 启动 / 切到 / 切换到” in the same place as wake words and command prefixes, and make routing/suggestions consume that configuration.

### Baseline
- Date: 2026-04-08
- Scope: `/Volumes/SSD/Projects/Aether/App`
- Validation mode: static verification only
- Risk: Medium

### Phases
- [x] Identify current split between app-launch aliases and lexicon terms
- [x] Add tests for configurable app-launch prefixes and old lexicon decoding
- [x] Extend lexicon model/defaults/import-export with `appLaunchPrefixes`
- [x] Add App Launch Prefixes editor row to the main voice lexicon
- [x] Switch routing and suggestion phrases to consume configurable app-launch prefixes

## Supplemental Workstream: `fix/wake-dictation-regression`

### Goal
Bring wake follow-up dictation back in line with the earlier product design: second utterances should not get forced back to command baseline while the user is still speaking, and live dictation should continue flowing into the input target instead of waiting for final whenever partials revise earlier words.

### Baseline
- Date: 2026-04-08
- Scope: `/Volumes/SSD/Projects/Aether/App`
- Validation mode: source inspection + static checks + unit-level behavior checks where safe
- Risk: High

### Phases
- [x] Re-check current design docs against live SpeechManager/DictationHandler behavior
- [x] Bound the two active regressions to concrete code paths and diagnostics evidence
- [x] Add failing regression expectations for wake typing continuity and live dictation correction
- [x] Implement bounded fixes in `SpeechManager` and `DictationHandler`
- [ ] Run final safe verification and decide whether the branch is ready for a new beta

## Supplemental Workstream: `review/git-state-and-branch-merge`

### Goal
Inventory uncommitted changes across the Aether workspace repos, identify which branches are already merged versus still pending, and safely perform any local branch merge the current evidence supports.

### Baseline
- Date: 2026-04-15
- Scope: `/Volumes/SSD/Projects/Aether`, `/Volumes/SSD/Projects/Aether/App`, `/Volumes/SSD/Projects/Aether/Website`
- Validation mode: git inspection + safe static checks only
- Risk: Medium

### Phases
- [x] Identify repo boundaries and current working-tree status
- [x] Inspect branch topology in each repo
- [ ] Classify uncommitted changes by repo and merge relevance
- [ ] Run safe verification for any branch selected for merge
- [ ] Perform local merge and summarize remaining cleanup
