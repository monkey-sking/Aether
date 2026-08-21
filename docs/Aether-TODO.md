# Aether Rollout TODO (cross-project)

This file tracks what still needs to be done across the three projects living under this folder:

- `App/` (Aether macOS app, Sparkle release pipeline)
- `Website/` (aether.7caifei.com marketing + download surface)
- `ProcessZero/Admin` (entitlement + activation issuance backend, lives elsewhere)

Status values: `todo` / `doing` / `blocked` / `done`

Source-review sync note (2026-03-28):

- `todo`: no local implementation landed yet, or the dependency lives outside this workspace and there is not enough local evidence to advance it
- `doing`: local code/UI/assets are present, but end-to-end validation, external dependency hookup, or release-path proof is still missing
- `done`: the local repos in this folder already satisfy the listed exit criteria by source inspection
- This sync is code-first: recent commits + current implementation take priority over older planning docs
- Do not keep abandoned tracks in the active backlog. Current example: Driver keyboard injection is not a live work item.

## Website (aether.7caifei.com)

| item | status | owner | dependencies | exit criteria |
|---|---|---|---|---|
| Home copy audit (CN+EN) | doing |  |  | Home/Download/Pricing/FAQ pages read like user outcomes (not implementation), CN+EN stay consistent |
| Reduce Beta emphasis | doing |  |  | Home already uses Stable as the primary CTA and demotes Beta to a footnote-style link; finish checking the download surface so Beta stays secondary there too |
| Download CTA behavior | done |  |  | Clicking “Download” triggers a direct DMG download (no navigation to a new page) |
| Mobile layout: primary CTA placement | doing |  |  | On portrait/mobile, the main “Download” CTA sits on the right with clean alignment |
| App icon + favicon consistency | doing |  | App icon export | Website logo/favicon assets are in place; finish confirming they match the app branding and stay crisp across surfaces |
| Download attribution wiring | doing |  | Admin endpoints / analytics | Website/app already emit tracked manual vs update download URLs; finish proving the admin counters ingest them as separate events |
| Pricing page real plans / commercial copy | todo |  | pricing model | Pricing page stops being placeholder-only and shows the actual commercial surface instead of “coming soon” copy |
| Referral / invite copy | todo |  | `App/docs/REFERRAL_MVP.md` | Pricing / FAQ / Download clearly explain invite rewards and tell users where to enter a referral code |

## App (Aether macOS)

| item | status | owner | dependencies | exit criteria |
|---|---|---|---|---|
| Rewrite Context implementation | todo |  | `App/docs/specs/rewrite-context/` | Rewrite Context exists as an actual app capability: separate switch, short-term reuse, long-term preference, and observability |
| Referral panel in About / License Management | doing |  | Admin referral summary API, `App/docs/REFERRAL_MVP.md` | Trialing / active users can already enter/carry a referral code in License Management; finish adding reward totals and recent referral activity |
| Verification: activation gating edge cases | doing |  |  | Root view + runtime gating already exist locally; finish manually confirming locked/unlocked/loading/device-limit/offline-grace transitions |
| Verification: offline entitlement grace | doing |  |  | Offline grace logic and offline status text exist locally; finish validating that refresh failure preserves access within the grace window and surfaces the right message |
| Verification: device limit self-serve removal | doing |  | Admin `/devices` | In device-limit state, device list/removal UI already exists locally; finish proving the admin `/devices` path works without requiring prior “active” status |
| Verification: Sparkle framework load / RPATH | doing |  | Xcode build settings | Sparkle is integrated locally; finish proving the built app launches and Sparkle loads correctly (no `@rpath/Sparkle.framework` crash) |
| Verification: Sparkle signing/feed parity for Stable | doing |  | Release secrets, stable appcast publish | `SUPublicEDKey` is already wired and the beta signing pipeline is proven; finish revalidating the same end-to-end path for the stable channel and keep the feed/update assets consistent |
| Verification: update channel switching in-app | doing |  | Website appcasts | Channel picker + feed resolver are in the app; finish proving Stable/Beta switching updates feed URL and update behavior end-to-end |

## Admin (ProcessZero/Admin)

| item | status | owner | dependencies | exit criteria |
|---|---|---|---|---|
| Multi-product config layer (Legacy + Aether) | todo |  | current production | Aether has its own host + namespace |
| Aether activation issuance (email-based) | todo |  | mail provider | Start trial + resend + activate all work; emails are delivered reliably |
| Referral code issuance + reward settlement | todo |  | `App/docs/REFERRAL_MVP.md` | Each account has a stable referral code; `/trial/start` can apply a referral; reward totals and recent events are queryable by the app |
| Download attribution endpoints | todo |  | Website + App | Admin records “manual download” vs “update download” as separate counters |

## Release / QA

| item | status | owner | dependencies | exit criteria |
|---|---|---|---|---|
| Beta recruiting + TG group process | todo |  |  | A simple, non-prominent entry point exists; testers know how to get builds and report issues |
| Referral MVP end-to-end rehearsal | todo |  | Website + App + Admin | Inviter can copy a code, invitee can apply it during trial start, both sides receive the expected reward outcome, and the app surfaces the updated state correctly |
| End-to-end rehearsal (Website -> download -> install -> activate -> update) | todo |  |  | A full dry run completes without manual patching |
| Universal packaging path recovery + verification | done |  | `App/docs/RELEASE_DISTRIBUTION.md`, Xcode 26.4 CLI packaging path | `AETHER_UNIVERSAL=1` release path has been revalidated end-to-end; beta `0.1.6 / b142` ships again as a universal package |
