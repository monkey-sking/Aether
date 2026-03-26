Aether `Apps` repo rules:

- Treat runtime reports in this repo as product-pipeline questions first. For issues around wake word, HUD, typing mode, AirPods, push-to-talk, input state, or speech stats, inspect the current code path and available Aether diagnostics before offering theory.
- Explain Aether behavior in Aether terms. Prefer the concrete path `capture -> EOS/finalization -> transcript -> routing -> action/stats/HUD` over generic speech-tech descriptions unless the user explicitly asks for the generic layer.
- Use repo terminology exactly as the user means it. Do not expand shorthand like `PTT`, `typing`, `control mode`, `speech stats`, or similar terms into another app, feature, or external product unless the codebase or the user confirms that mapping.
- In default conversations for this repo, avoid `xcodebuild`, XCTest, or other commands that may trigger signing unless a safe non-signing path is already confirmed. Prefer source review, existing diagnostics, and other non-signing-safe checks.
- Keep recurring regressions in one stable fix workstream when possible, such as `fix/wake-word`, `fix/typing-mode`, or `fix/ptt-stats`. If the same symptom returns, continue the same workstream instead of opening parallel near-duplicate ones.
