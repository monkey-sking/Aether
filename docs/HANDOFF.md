# Aether App — Development Handoff

> For the next developer / AI on a new machine. Read this first.

Last updated: 2026-08-21 (machine handoff)

## Project

- **Product**: Aether — macOS app (SwiftUI, `Apps/AetherCore/`). Audio / dictation focus with Sparkle auto-update.
- **Lane**: macOS Developer ID + notarization.
- **Remote**: `git@github.com:monkey-sking/Aether.git` (private).
- **Local path (old Mac)**: `/Volumes/SSD/Projects/Aether/App`.
- **Sibling repos**: `Aether/Website` → `git@github.com:monkey-sking/Aether_Website.git`. The `Aether` root folder also holds a local meta-doc repo (README/TODO, no remote).

## Release flow

- Release script: `Scripts/ReleaseForUsers.sh`. It uses the shared `apple-release` signing layer.
- Signing identity: Developer ID Application for team `4Z7654KAZZ` from the shared signing keychain.
- Verify with: `~/apple-release/bin/preflight-project-gui.sh aether`.
- Notary profile: `AetherRelease` (recreated via `apple-release/bin/setup-notary-profile.sh` with the ASC API key).

## Sparkle (auto-update)

- **The Aether Sparkle key was rotated on 2026-07-25** (trust-chain reset, no meaningful installed base at the time). Current public key `SUPublicEDKey`:
  `BDucvmSUp3NcNFW/jdQ6O8BW9Gzz2Ju03gt658TFIMI=`
- Private EdDSA key: `apple-release/private/sparkle/aether-sparkle-private-key.txt`.
- Feeds: `Aether/Website` → stable `aether/appcast.xml`, beta `aether-beta/appcast.xml` (latest-only, no deltas).

## Secrets (never commit)

- ASC API key (`AuthKey_35AZAVYXT9.p8`) and signing keychain: `apple-release/private/`.
- Sparkle private key: `apple-release/private/sparkle/`.

## Notes

- Recent release commits: `83fd64d` (sparkle key rotation + shared signing lane), followed by real releases.
- Current working branch: `fix/wake-dictation-regression` (pushed).
- Docs live in `docs/` — see `docs/RELEASE_DISTRIBUTION.md` for packaging path.

## Lessons learned (from shared memory, move to this repo)

- **Sparkle EdDSA key is a one-way asset**: rotating the Sparkle private key breaks automatic-update compatibility for existing installs. Never generate a new key casually — if the old private key is lost, restoring it (or an explicit trust-chain reset) is required before publishing. Aether already went through this (2026-07-25) — the key was lost, and because the installed base was negligible the user approved a trust-chain reset instead. The current private key now lives in `apple-release/private/sparkle/aether-sparkle-private-key.txt`. Keep it backed up; losing it again forces another trust-chain reset.
- **Signing uses the shared apple-release layer** — never revert to per-project ad-hoc signing. Verification: `preflight-project-gui.sh aether`; notary profile `AetherRelease` in the shared signing keychain.