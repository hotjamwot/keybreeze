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
| Typing Lab / Feel Engineering | ⚠️ In Progress | Ghost text constants unified. PromptBuilder updated. Backspace correction partially implemented — detection and UI exist but matching has bugs. |
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
| `Keybreeze/UI/` | Views: `MenuBarContentView`, `SessionViewModel`, `GhostTextModifier`, `GhostTextStyle`, `SettingsView`, `SuggestionOverlayWindow`, `TypingLab/`. |
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
                    → GhostTextModifier (playground) renders grey inline ghost text
                    → SuggestionOverlayWindow (external apps) renders floating ghost
```

**Key:** Both the playground (`GhostTextModifier`) and the system-wide overlay (`InlineGhostTextView` inside `SuggestionOverlayWindow`) now share visual constants via `GhostTextStyle` (created 24 May 2026). Previously they used duplicated values.

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
- Use `loadContextPreset()` to apply test context presets when selected from the picker.
- **Keep ghost text visual constants in a single shared source** — use `GhostTextStyle` for all opacity, font, line limit, and padding values. Never duplicate them.
- When working on backspace correction, remember that the model often outputs `...` prefix and lowercase continuation suffixes — the correction detector must strip ellipsis, handle word-boundary changes across multiple backspaces, and reject uppercase (new sentence) matches.

### DO NOT:
- Create new LLM provider files; use `LLMClient`.
- Change menu bar style to `.window`.
- Add animations to ghost text.
- Modify `NSApplication` lifecycle outside of `AppKitLifecycle.swift`.
- Remove `@MainActor` from primary core classes.
- Create separate toggles for system-wide vs playground — always use `isEnabled`.
- Hardcode `.lineLimit(3)` on ghost text views — always use `GhostTextStyle.lineLimit`.
- Bypass `ContextPreset` `loadContextPreset()` to set `draftText` directly when loading test contexts.

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
  - **Context truncation:** Only the last 800 characters of text are sent to the LLM — ensures large documents (100k+ words) don't cause latency or semantic drift.
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
- **Acceptance:** `acceptWord()` (Tab — one word at a time) and `acceptSuggestion()` (full prediction). Both correctly gate `draftText` mutations with `isAccepting` flag.
- **Context presets:** Contains `ContextPreset` enum with 4 test scenarios (Short Story, Email Draft, Markdown Notes, Creative Writing). Call `loadContextPreset()` to populate the playground — never bypass this method.
- **Tab interception:** Local monitor (consumes Tab in Keybreeze windows) + Global monitor (inserts via AX in other apps). Also handles correction Tab/ESC.
- **Correction state:** Contains `correctionState` (published), `correctionCandidateWord`, and `correctionCapturedWordCount` for the backspace correction §7 feature.
- **Correction actions:** `acceptCorrection()` replaces partial word with suggested correction; `rejectCorrection()` clears the state.
- **Correction detection (Combine subscriber):** Listens to `controller.$suggestion`, strips leading `...`/punctuation, extracts first word, appends to the current partial word, and compares against the captured candidate. Includes guards for uppercase-first-word (new sentences), length bounds, and prefix matching.
- **Diagnostics:** `currentLatency`, `currentTTFT`, `predictionHistory` (ring buffer, 200 records).

### `Keybreeze/UI/GhostTextStyle.swift`
- **Role:** Single shared constants file for all ghost text visual properties (created 24 May 2026).
- **Constants:** `suggestionOpacity` (0.45), `font` (.body), `lineLimit` (10), `leadingPadding` (13), `trailingPadding` (13), `topPadding` (13), `correctionOriginalOpacity` (0.6), `correctionStrikethroughColor` (.red), `correctionSuggestionColor` (.green), `overlayFontSize` (14), `overlayGhostOpacity` (0.45), `overlayMaxWidth` (600).

### `Keybreeze/UI/GhostTextModifier.swift`
- **Role:** SwiftUI `ViewModifier` for Typing Lab. Overlays grey/translucent ghost text after committed text.
- **How it works:** Renders invisible `Text(draftText)` to anchor position, followed by visible `Text(suggestion)` in grey.
- **Visual constants:** All sourced from `GhostTextStyle` (padding, font, line limit, opacity, correction colors).
- **Correction state:** When `correctionState` is set, shows strikethrough original + green suggestion.
- **Line limit:** Uses `GhostTextStyle.lineLimit` (10).
- **No animation:** Pure static overlay. Opacity toggles between 0 and GhostTextStyle.suggestionOpacity.

### `Keybreeze/UI/SuggestionOverlayWindow.swift`
- **Role:** Manages a borderless, transparent NSWindow that floats ghost text near the cursor in the focused third-party app.
- **Key detail:** Uses `popUpMenu` window level, click-through, no focus steal. Contains `InlineGhostTextView` — a SwiftUI view that renders the suggestion text.
- **Configuration:** `fontSize` defaults to `GhostTextStyle.overlayFontSize`, `ghostOpacity` to `GhostTextStyle.overlayGhostOpacity`, max width to `GhostTextStyle.overlayMaxWidth`.
- **Line limit:** Uses `GhostTextStyle.lineLimit` (10).

### `Keybreeze/UI/SettingsView.swift`
- **Role:** Main settings window with sidebar navigation (General / Typing Lab).
- **General tab:** Enable/disable toggle (`isEnabled`), Accessibility status, statistics card, backend/model pickers.
- **Typing Lab tab:** Playground with diagnostics, parameter controls, prompt editor, and behaviour presets.

### `Keybreeze/UI/TypingLab/TypingLabView.swift`
- **Role:** Dev playground that mirrors external app behavior. Shows ghost predictions inline.
- **Status indicator:** Green "Predicting" / orange "Paused" dot (visual only — not a toggle).
- **Test context presets:** Dropdown picker (Test Context) with Load button — lets user rapidly test prediction quality across Short Story, Email Draft, Markdown Notes, and Creative Writing scenarios.
- **Controls:** Behaviour presets (AggressionPreset), parameter override toggles, prompt editor, diagnostics panel.
- **Debug panel:** Diagnostics panel shows live TTFT, total time, prediction history, and mode detection.

### `Keybreeze/LLM/LLMClient.swift`
- **Role:** Single HTTP client for both Ollama (SSE streaming) and llama.cpp (non-streaming POST). Speaks OpenAI `/v1/chat/completions` format.
- **Ollama:** Uses streaming SSE — tokens arrive one at a time via `onToken` closure.
- **llama.cpp:** Uses non-streaming POST (SSE never sends terminating event, causing hangs).
- **Cancellation:** `cancel()` is called before every new prediction.

### `Keybreeze/LLM/PromptBuilder.swift`
- **Role:** Builds continuation and system prompts. No LLM calls — just string construction.
- **Default system prompt:** Explicit instructions for continuation-only, no restating input, no markdown, no stylistic prefixes. Updated 24 May 2026 with additional rules: never start with ellipsis/dashes/punctuation prefix, and if text ends mid-word, complete that word naturally from where it left off.
- **Parameters:** `context` (text before cursor), `styleNudge` (optional style guidance), `maxWords` (word cap).

---

## Current Diagnostic Snapshot (24 May 2026)

Collected from Typing Lab with `gemma2:2b` model, `balanced` preset (temp=0.35, topP=0.85):

| Metric | Value |
|--------|-------|
| Total Predictions | 51+ (accumulating) |
| Accepted | 0+ (acceptance testing in progress) |
| Ignored | 51+ |
| Cancelled | 0 |
| Avg TTFT | 116ms |
| Avg Total Time | 148ms |
| Word Cap (midType) | 3 (default) |
| Word Cap (pause) | 5 (default) |

**Observations from recent testing (all presets working):**
- **Ghost text rendering** is now unified via `GhostTextStyle` — playground and overlay use identical constants ✅
- **Return of `...` prefix** — gemma2:2b model frequently outputs `...tely` / `...ly` / `...ation` as continuation suffixes, which the correction detector handles by stripping leading punctuation
- **Backspace correction detection** is implemented but has false-positive issues:
  - Model outputs lowercase suffixes (e.g. "tely", "love", "stories") that get appended to the partial word, triggering unwanted corrections even for new-sentence continuations
  - Uppercase guard was added to filter out "It's" etc., but more refinement needed
- **Console is noisy** — SystemWidePredictor idle poll loop logs every 500ms even when not focused

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
- ✅ **Multi-line ghost overlay:** Correct alignment across line wraps (now supports 10 lines)
- ✅ **Test context presets:** 4 pre-built scenarios (Short Story, Email Draft, Markdown Notes, Creative Writing) with Load button for rapid feel engineering
- ✅ **acceptSuggestion() isAccepting guard:** Fixed — no longer fires redundant re-prediction on full-accept
- ✅ **Context truncation:** Only last 800 chars sent to LLM — safe for documents of any size
- ✅ **Ghost text constants unified:** `GhostTextStyle.swift` created; both `GhostTextModifier` and `InlineGhostTextView` reference it
- ✅ **Backspace correction detection** — basic pipeline exists: candidate capture, Combine subscriber on suggestion, Tab/ESC handling, correction state rendering in ghost text

---

## What Still Needs Work

### High Priority

1. **Backspace correction (§7) — buggy matching** — The detection logic is implemented but produces false positives. The model outputs continuation suffixes (like `"tely"`, `"love"`, `"stories"`) that get combined with the partial word, triggering corrections even for correct continuations. 
   - **Known issues:**
     - Candidate persists across multiple word-boundary backspaces (e.g. backspacing through "love" into "absoluttly" should update the candidate)
     - Lowercase suffix matching fires on every streaming token update — need to gate on a single stable suggestion rather than every token change
     - The length guard `firstWord.count <= partialText.count + 4` is still too permissive
   - **Suggested approach:** Wait for suggestion to settle (wordCount > 0, trailing space or complete word boundary), then check once rather than on every streaming token.
   - **UI is ready:** `GhostTextModifier` renders strikethrough+green. Tab/ESC handling works.

2. **Prompt tuning — model still outputs `...` prefix** — Despite the `PromptBuilder` rule "NEVER start with ellipsis", gemma2:2b frequently outputs `...tely`, `...ation`, `...ly`. This degrades both normal predictions and correction detection. Options:
   - Increase `repeatPenalty` or adjust `temperature` to discourage this pattern
   - Post-process suggestions in CompletionController to strip leading `...`
   - Consider a different model (e.g. qwen2.5:0.5b, phi3:mini) that may follow instructions more precisely

3. **SystemWidePredictor console noise** — The idle poll loop logs "Current focused app bundle ID" every 500ms unconditionally. Should be gated behind a debug flag or throttled.

### Medium Priority

4. **SystemWidePredictor gating** — `shouldProcessApp()` may incorrectly return true for Keybreeze's own bundle ID in some code paths.

5. **System-wide integration** — AX context reading works but needs: reliable cursor rect positioning across apps, Tab insertion in external apps, event tap permission handling, app gating UI. Blocked on Lab feel engineering being locked down first.

### Lower Priority / Blocking

6. **Ghost Overlay Positioning** — Fallback logic for AX cursor rects in multi-monitor setups needs robustifying (Tier 4 computed fallback is placeholder).

7. **Right Arrow word-by-word acceptance** — Per BEHAVIOR.md §5. Powerful but low priority.

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
| 10 | acceptSuggestion() missing isAccepting guard — redundant re-prediction on full-accept | Added `isAccepting = true/false` around `draftText` mutation | `SessionViewModel.swift` |
| 11 | No quick way to test predictions across different writing contexts | Added `ContextPreset` enum (4 scenarios) with dropdown picker + Load button, `loadContextPreset()` method | `SessionViewModel.swift`, `TypingLabView.swift` |
| 12 | Inline ghost text invisible for multi-line content (line limit 3) | Changed `.lineLimit(3)` to `.lineLimit(10)` in both `GhostTextModifier` and `InlineGhostTextView` | `GhostTextModifier.swift`, `SuggestionOverlayWindow.swift` |
| 13 | Ghost text visual constants duplicated across playground and overlay | Created `GhostTextStyle.swift` with shared constants; refactored both renderers | `GhostTextStyle.swift` (new), `GhostTextModifier.swift`, `SuggestionOverlayWindow.swift` |
| 14 | PromptBuilder allowed model to output `...` prefix and didn't handle mid-word completion | Added rules: never start with ellipsis/punctuation, complete mid-word text naturally | `PromptBuilder.swift` |
| 15 | Backspace correction detection not implemented | Added candidate capture in `handleDraftChanged()`, Combine subscriber for suggestion matching, `acceptCorrection()`/`rejectCorrection()` methods, Tab/ESC handling in event monitor | `SessionViewModel.swift` |

---

## Next Steps (Recommended Order)

1. **Fix backspace correction matching** — Gate correction detection on settled suggestions (not every streaming token). Tighten the match criteria so lowercase suffix continuations don't trigger false positives. Consider comparing against prediction history rather than just the candidate word.

2. **Post-process predictions to strip `...`** — In `CompletionController` or via a Combine subscriber, strip leading ellipsis/dashes from suggestions before they're published. This fixes both normal prediction quality and correction detection.

3. **Reduce console noise** — Throttle SystemWidePredictor's idle poll logging to debug-only, and remove the `print("draftText changed: ...")` from SessionViewModel now that the system is stable.

4. **Polish SystemWidePredictor** — Reduce idle poll noise, fix gating for Keybreeze's own bundle ID, improve cursor rect positioning.

5. **System-wide rollout** — Enable predictions across all apps.