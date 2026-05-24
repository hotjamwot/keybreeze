# Keybreeze — Architecture

*This document serves as the technical log for Keybreeze. It outlines the application's structure, the engineering decisions made, the roadmap, and the current state of development, including active issues and unresolved bugs. Developers and AI agents should use this file to understand the "how" and "where" of the project, including its current status, to ensure consistency as we build and refine the system.*

---

## What Keybreeze Is

A **macOS menu bar app** providing **local, low-latency text continuation** (autocomplete). Uses **Ollama** (primary) or **llama.cpp** (secondary/experimental) over HTTP. Includes **Typing Lab** — a permanent dev environment with live playground, diagnostics, prediction history, prompt editing, and runtime tuning.

**Design intent:** continuation only, short outputs, single simplified client (`LLMClient`), relentless focus on typing feel over raw intelligence.

Not an inference infrastructure project. The LLM layer is replaceable plumbing — a single `LLMClient` class that speaks the OpenAI `/v1/chat/completions` API.

**Core promise:** *Create uninterrupted writing flow.* Not autocomplete spam. Not AI authorship. Cognitive acceleration through anticipatory language completion.

---

## Roadmap & Current Status

| Phase | Status | Goal |
|-------|--------|------|
| Phase 0 — Project Skeleton | ✅ Complete | Basic app shell and lifecycle management. |
| Phase 1 — LLM Pipeline (Ollama + llama.cpp) | ✅ Complete | Core inference client built. |
| Phase 2 — Prediction Engine | ✅ Complete | Debouncing and prompt orchestration. |
| Phase 2.5 — Ghost Text + Tuning | ✅ Complete | UI integration and parameter control. |
| Typing Lab / Feel Engineering | ⚠️ In Progress | Playground works. Streaming gating done. Next: test presets, backspace correction. |
| Phase 3 — System-Wide Integration | ⏸ Paused | AX context reading + Tab accept mechanism exists but not yet reliable. |
| Phase 4 — Ghost Overlay in External Apps | ⏸ Paused | Floating overlay for third-party apps exists but has positioning bugs. |
| Phase 5+ — Polish, Style Memory, Expansion | Later | Refinements and feature expansion. |

---

## Directory Layout

| Path | Role |
|------|------|
| `Keybreeze/App/` | `@main` entry, AppKit activation policies, termination cleanup. |
| `Keybreeze/Core/` | Domain logic: `AppState`, `CompletionController`, `PredictionHistory`, `SystemWidePredictor`, `AccessibilityManager`, `InputSourceMonitor`. |
| `Keybreeze/LLM/` | `LLMClient` (HTTP client for Ollama+llama.cpp), `PromptBuilder`. |
| `Keybreeze/UI/` | Views: `MenuBarContentView`, `SessionViewModel`, `GhostTextModifier`, `SettingsView`, `SuggestionOverlayWindow`, `TypingLab/`. |
| `Keybreeze/Utils/` | `KeybreezeLatencyLogger`. |

---

## Data Flow (How Predictions Happen)

```
User types in TextField
  → $sessionVM.draftText (didSet)
    → sessionVM.handleDraftChanged()
      → CompletionController.editorStateChanged()
        → cancelAll() ← kills previous in-flight prediction instantly
        → 45ms debounce
          → runPrediction()
            → PromptBuilder.continuationPrompt(context, styleNudge, maxWords)
            → PromptBuilder.systemPrompt(customPrompt, styleNudge)
            → LLMClient.streamCompletion(prompt, systemPrompt, model, ...)
              → tokens arrive via onToken closure
                → accumulatedTokens += token
                → STREAMING GATE: only update suggestion after first complete word
                  → self.suggestion = accumulatedTokens
                    → GhostTextModifier renders grey inline ghost text
                    → SuggestionOverlayWindow shows floating overlay (external apps)
```

---

## Architecture Rules for AI Agents

### DO:
- Use `PromptBuilder` for ALL prompt construction. Never inline prompt strings.
- Use `Task { @MainActor in }` for cross-actor UI updates from within token callbacks.
- Keep latency tracking intact — TTFT and totalTime are the primary feedback mechanism.
- Check `SystemWidePredictor` gating logic whenever focus issues arise.
- Ensure all new files are added to `Keybreeze.xcodeproj`.
- Use `isEnabled` (single master bool) for controlling prediction state.
- Gate `draftText` mutations with `isAccepting` flag to prevent redundant predictions.

### DO NOT:
- Create new LLM provider files; use `LLMClient`.
- Change menu bar style to `.window`.
- Add animations to ghost text.
- Modify `NSApplication` lifecycle outside of `AppKitLifecycle.swift`.
- Remove `@MainActor` from primary core classes.
- Create separate toggles for system-wide vs playground — always use `isEnabled`.

---

## File-by-File Reference (Ground Truth)

*If you are an LLM working on this codebase, read this section thoroughly before making any changes.*

### `Keybreeze/App/KeybreezeApp.swift`
- **Role:** `@main` entry. Creates `@StateObject` `AppState`. Two scenes: `MenuBarExtra` for menu bar, `Window("settings")` for settings window.
- **Key detail:** `SessionViewModel` lives inside `AppState` as a lazily-created property (`appState.sessionViewModel`) so it survives SwiftUI scene recreation.
- **On-disappear:** Cancels current prediction, then defers `restoreToAccessory()` by 150ms to avoid lifecycle crash.

### `Keybreeze/App/AppState.swift`
- **Role:** Shared application state as `@MainActor` `ObservableObject`.
- **Key detail:** Owns the single `SessionViewModel` instance via `private var _sessionViewModel`. The computed `var sessionViewModel` lazily creates it once.
- Also manages: `LLMConfig`, `selectedBackend`, `selectedModel`, `availableModels`, `isOllamaRunning`, health check loop (5s interval), model catalog refresh.

### `Keybreeze/Core/CompletionController.swift`
- **Role:** Prediction orchestrator (`@MainActor`). The shared engine used by both Typing Lab and SystemWidePredictor.
- **Published:** `suggestion`, `isRunning`, `statusMessage`, `currentMode`, `currentLatency`, `currentTTFT`.
- **Key detail:** The `EditorState → PromptBuilder → LLMClient → Suggestion` pipeline. Features:
  - **45ms debounce** via `Task.sleep(for: .milliseconds(45))` before each prediction.
  - **Streaming threshold gating** (§10): only updates `suggestion` after first complete word (contains space) or 3 tokens minimum — prevents "dancing" predictions.
  - **Acceptance echo tracking:** `expectedTextAfterAcceptance` suppresses re-prediction when the text field echoes back an accepted suggestion.
  - **Latency tracking:** TTFT (time-to-first-token) + total time recorded on every prediction.
  - **Cancellation:** `cancelAll()` kills both the active task and debounce task immediately.
- **Debugging:** Set `OS_ACTIVITY_MODE=debug` in scheme to see full flow.

### `Keybreeze/Core/SystemWidePredictor.swift`
- **Role:** Bridges AX context into `CompletionController` for system-wide prediction in external apps.
- **Triggers:** `CGEventTap` (instant on keyDown) + 500ms idle poll (catches paste/undo/mouse).
- **Gating:** `shouldProcessApp()` checks `excludedBundleIDs`, `manualOnlyBundleIDs`, and IME composition state.
- **Overlay:** Owns `SuggestionOverlayWindowController` — transparent borderless NSWindow positioned via AX cursor rect with 4-tier fallback chain.
- **Status:** Implemented but not yet production-ready. Event tap requires Accessibility permissions. Cursor rect resolution is flaky in Terminal, web views, and Electron apps.

### `Keybreeze/UI/SessionViewModel.swift`
- **Role:** Bridge between UI and prediction engine. `@MainActor` `ObservableObject`.
- **Single master toggle:** `isEnabled` controls everything — both playground AND system-wide predictions start/stop together.
- **Key detail:** `isEnabled = true` is set in `init()` so the app auto-starts predicting on launch.
- **Acceptance:** `acceptWord()` (Tab — one word at a time) and `acceptSuggestion()` (full prediction).
- **Tab interception:** Local monitor (consumes Tab in Keybreeze windows) + Global monitor (inserts via AX in other apps).
- **Diagnostics:** `currentLatency`, `currentTTFT`, `predictionHistory` (ring buffer, 200 records).

### `Keybreeze/UI/GhostTextModifier.swift`
- **Role:** SwiftUI `ViewModifier` for Typing Lab. Overlays grey/translucent ghost text after committed text.
- **How it works:** Renders invisible `Text(draftText)` to anchor position, followed by visible `Text(suggestion)` in grey.
- **Padding:** `.padding(.leading, 13)` and `.padding(.trailing, 13)` to match TextField content inset.
- **Correction state:** When `correctionState` is set, shows strikethrough original + green suggestion.
- **No animation:** Pure static overlay. Opacity toggles between 0 and 0.45.

### `Keybreeze/UI/SettingsView.swift`
- **Role:** Main settings window with sidebar navigation (General / Typing Lab).
- **General tab:** Enable/disable toggle (`isEnabled`), Accessibility status, statistics card, backend/model pickers.
- **Typing Lab tab:** Playground with diagnostics, parameter controls, prompt editor, and behaviour presets.

### `Keybreeze/UI/TypingLab/TypingLabView.swift`
- **Role:** Dev playground that mirrors external app behavior. Shows ghost predictions inline.
- **Status indicator:** Green "Predicting" / orange "Paused" dot (visual only — not a toggle).
- **Controls:** Behaviour presets (AggressionPreset), parameter override toggles, prompt editor, diagnostics panel.
- **Debug panel:** Diagnostics panel shows live TTFT, total time, prediction history, and mode detection.

### `Keybreeze/LLM/LLMClient.swift`
- **Role:** Single HTTP client for both Ollama (SSE streaming) and llama.cpp (non-streaming POST). Speaks OpenAI `/v1/chat/completions` format.
- **Ollama:** Uses streaming SSE — tokens arrive one at a time via `onToken` closure.
- **llama.cpp:** Uses non-streaming POST (SSE never sends terminating event, causing hangs).
- **Cancellation:** `cancel()` is called before every new prediction.

### `Keybreeze/LLM/PromptBuilder.swift`
- **Role:** Builds continuation and system prompts. No LLM calls — just string construction.
- **Default system prompt:** Explicit instructions for continuation-only, no restating input, no markdown, no stylistic prefixes.
- **Parameters:** `context` (text before cursor), `styleNudge` (optional style guidance), `maxWords` (word cap).

---

## Current Diagnostic Snapshot (24 May 2026)

Collected from Typing Lab with `gemma2:2b` model, `balanced` preset (temp=0.35, topP=0.85):

| Metric | Value |
|--------|-------|
| Total Predictions | 37 |
| Accepted | 11 (29.7%) |
| Ignored | 26 (70.3%) |
| Cancelled | 0 |
| Avg TTFT | 148ms |
| Avg Total Time | 197ms |
| Word Cap (midType) | 3 (default) |
| Word Cap (pause) | 5 (default) |

**Observations:**
- TTFT is within spec (<200ms) but could be better — 148ms average is above the 40-90ms ideal range but within 100-140ms acceptable.
- `wordCount=0` logs appear on many midType predictions (user still typing partial words) — these are cancelled before any useful prediction forms. This is expected but wasteful.
- The model correctly continues context across sentence boundaries ("Hayden was sitting on the porch swing. He watched the sunset as the colors faded into darkness.").
- Acceptance rate (29.7%) is reasonable for early-stage testing.

---

## What's Working Well

- ✅ **Typing Lab flow:** Keystroke → debounce → prediction → ghost text overlay (all inline in playground)
- ✅ **Streaming gating:** Ghost text appears cleanly after first complete word — no token flicker
- ✅ **Tab acceptance:** Accepts one word at a time via `acceptWord()`, remaining ghost stays visible
- ✅ **Debounce at 45ms:** Within BEHAVIOR.md spec sweet spot
- ✅ **SessionViewModel lifecycle:** Survives scene recreation — text stays, toggles stay
- ✅ **Master enable/disable:** Single `isEnabled` toggle controls everything
- ✅ **Auto-start:** App begins predicting immediately on launch
- ✅ **Diagnostics:** Live TTFT + total time displayed, prediction history (200-record ring buffer)
- ✅ **Multi-line ghost overlay:** Correct alignment across line wraps

---

## What Still Needs Work

### High Priority

1. **Test context presets for Typing Lab** — Add dropdown-selectable scenarios (short story, email draft, markdown) that pre-fill `draftText` so the user can rapidly test prediction quality across contexts. This accelerates the feel-engineering loop.

2. **`acceptSuggestion()` missing `isAccepting` guard** — Unlike `acceptWord()`, `acceptSuggestion()` mutates `draftText` without the suppression flag. Low-risk fix.

3. **Prompt tuning + model experimentation** — Current `wordCount=0` mid-type predictions are wasted. Experiment with `maxWords` caps, `PromptBuilder` instructions, and temperature settings to reduce empty completions while maintaining quality.

### Medium Priority

4. **Backspace Correction (§7)** — `CorrectionState` struct exists in `PredictionHistory` but no detection logic or UI wiring. Show red strikethrough + green suggestion when user backspaces through a misspelled word.

5. **SystemWidePredictor gating** — `shouldProcessApp()` may incorrectly return true for Keybreeze's own bundle ID in some code paths.

### Lower Priority / Blocking

6. **System-wide integration** — AX context reading works but needs: reliable cursor rect positioning across apps, Tab insertion in external apps, event tap permission handling, app gating UI. Blocked on Lab feel engineering being locked down first.

7. **Ghost Overlay Positioning** — Fallback logic for AX cursor rects in multi-monitor setups needs robustifying (Tier 4 computed fallback is placeholder).

8. **Right Arrow word-by-word acceptance** — Per BEHAVIOR.md §5. Powerful but low priority.

---

## Summary of All Completed Fixes (24 May 2026)

| # | Issue | Fix | File(s) |
|---|-------|-----|---------|
| 1 | SessionViewModel recreated 8× on scene refresh — text disappeared | Moved to AppState as lazy strong reference | `AppState.swift`, `KeybreezeApp.swift` |
| 2 | Debounce 100ms (spec says 45ms) | Changed `debounceDelay` from 100→45ms | `CompletionController.swift` |
| 3 | GhostTextModifier never applied to playground TextField | Added `.ghostText()` modifier chain | `TypingLabView.swift` |
| 4 | Overlay padding misaligned with TextField (14px vs 12+1) | Changed to 13px to match content inset | `GhostTextModifier.swift` |
| 5 | Ghost overlay wrapping incorrectly on multi-line | Added `.padding(.trailing, 13)` | `GhostTextModifier.swift` |
| 6 | Two separate toggles (isSchedulerActive + isSystemWideEnabled) | Consolidated to single `isEnabled` | `SessionViewModel.swift` |
| 7 | Had to manually toggle "Active" in Lab to start predictions | Auto-start via `isEnabled = true` in init | `SessionViewModel.swift` |
| 8 | "Modifying state during view update" warnings | Fixed by stable VM lifecycle | `AppState.swift` |
| 9 | Streaming tokens displayed character-by-character ("I' → "I'm" → flicker) | Gate on first complete word or 3 tokens | `CompletionController.swift` |

---

## Next Steps (Recommended Order)

1. **Add test context presets to Typing Lab** — dropdown with story/email/markdown scenarios to accelerate feel engineering
2. **Fix `acceptSuggestion()` `isAccepting` guard** — small consistency fix
3. **Tune prompts and model parameters** — reduce empty mid-type predictions, experiment with maxWords
4. **Implement backspace correction** — high-impact missing feature, `CorrectionState` struct already exists
5. **Polish SystemWidePredictor** — overlay positioning, Tab insertion, gating, event tap flow
6. **System-wide rollout** — enable predictions across all apps