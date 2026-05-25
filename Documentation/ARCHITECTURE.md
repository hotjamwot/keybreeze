# Keybreeze — Architecture

*This document serves as the technical log for Keybreeze. It outlines the application's structure, the engineering decisions made, the roadmap, and the current state of development, including active issues and unresolved bugs. Developers and AI agents should use this file to understand the "how" and "where" of the project, including its current status, to ensure consistency as we build and refine the system.*

---

## What Keybreeze Is

A **macOS menu bar app** providing **local, low-latency text continuation** (autocomplete). Uses **Ollama** (primary) or **llama.cpp** (secondary) over HTTP. Includes **Typing Lab** — a permanent dev environment with live playground, diagnostics, prediction history, prompt editing, and runtime tuning.

**Design intent:** continuation only, short outputs, single simplified client (`LLMClient`), relentless focus on typing feel over raw intelligence.

Not an inference infrastructure project. The LLM layer is replaceable plumbing — a single `LLMClient` class that speaks the OpenAI `/v1/chat/completions` API (for Ollama) or the raw `/completion` endpoint (for llama.cpp).

**Core promise:** *Create uninterrupted writing flow.* Not autocomplete spam. Not AI authorship. Cognitive acceleration through anticipatory language completion.

---

## Roadmap & Current Status

| Phase | Status | Goal |
|-------|--------|------|
| Phase 0 — Project Skeleton | ✅ Complete | Basic app shell and lifecycle management. |
| Phase 1 — LLM Pipeline (Ollama + llama.cpp) | ✅ Complete | Core inference client + dual endpoint support. |
| Phase 2 — Prediction Engine | ✅ Complete | Debouncing and prompt orchestration. |
| Phase 2.5 — Ghost Text + Tuning | ✅ Complete | UI integration and parameter control. |
| Phase 3 — Backend Process Lifecycle | 🔄 In Progress | `BackendManager` builds and boots correctly. Ollama is working end-to-end (predictions flow with ~25-180ms TTFT). llama.cpp blocked by `--no-chat-template` flag being unsupported in installed binary version. |
| Typing Lab / Feel Engineering | ⚠️ In Progress | Ghost text constants unified. PromptBuilder updated. Backspace correction partially implemented — detection and UI exist but matching has bugs. «...» prefix still output by some models. |
| Phase 4 — System-Wide Integration | ⏸ Paused | AX context reading + Tab accept mechanism exists but not yet reliable. |
| Phase 5 — Ghost Overlay in External Apps | ⏸ Paused | Floating overlay for third-party apps exists but has positioning bugs. |
| Phase 6+ — Polish, Style Memory, Expansion | Later | Refinements and feature expansion. |

---

## Directory Layout

| Path | Role |
|------|------|
| `Keybreeze/App/` | `@main` entry, AppKit activation policies, termination cleanup. `AppState` owns backend lifecycle. |
| `Keybreeze/Core/` | Domain logic: `AppState`, `CompletionController`, `PredictionHistory`, `SystemWidePredictor`, `AccessibilityManager`, `InputSourceMonitor`, **`BackendManager`** (new — process lifecycle). |
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
              → Branch on backend:
                • Ollama: POST /v1/chat/completions (messages array, SSE stream)
                • llama.cpp: POST /completion (raw prompt string, n_predict, SSE stream)
              → tokens arrive via onToken closure
                → accumulatedTokens += token
                → STREAMING GATE: only update suggestion after first complete word
                  → self.suggestion = accumulatedTokens
                    → GhostTextModifier (playground) renders grey inline ghost text
                    → SuggestionOverlayWindow (external apps) renders floating ghost
```

**Key:** Both the playground (`GhostTextModifier`) and the system-wide overlay (`InlineGhostTextView` inside `SuggestionOverlayWindow`) now share visual constants via `GhostTextStyle` (created 24 May 2026). Previously they used duplicated values.

---

## Backend Lifecycle (New — 24 May 2026)

### `BackendManager` (`Keybreeze/Core/BackendManager.swift`)

A `@MainActor` class that manages the full lifecycle of LLM backend processes. State machine:

```
idle → starting → ready(ollama) / ready(llamaCpp)
ready(X) → stopping → idle → starting → ready(Y)
ready(llamaCpp) → restarting → ready(llamaCpp)   (model change)
```

**Ollama lifecycle:**
- Health-checks `localhost:11434` first
- If unreachable, spawns `ollama serve` via `Process()` with auto-detected binary path
- Tracks `didWeSpawnOllama` flag — only kills the process if we started it
- Model switching: no-op (just update the API payload string in `LLMClient`)

**llama.cpp lifecycle:**
- Spawns `llama-server` via `Process()` with tuned flags:
  ```
  --model <ggufPath> --host 127.0.0.1 --port 11345
  --ctx-size 512 --threads 4 --ubatch-size 256 --flash-attn on
  --no-chat-template --temp 0.0 --top-p 0.1
  ```
- Monitors stderr for startup confirmation (detects "starting server" / "model loaded" / "build info")
- Model switching: `.terminate()` → await teardown → respawn with new GGUF path
- Process monitoring runs on `Task.detached(priority: .background)` — never blocks main thread

**Binary auto-detection (both backends):**
1. User-configured custom path (optional, not yet exposed in UI)
2. `/opt/homebrew/Cellar/llama.cpp/<version>/bin/llama-server` (Homebrew cellar)
3. `/opt/homebrew/bin/ollama` / `/opt/homebrew/bin/llama-server`
4. `/usr/local/bin/ollama` / `/usr/local/bin/llama-server`
5. If none found, sets `lastError` with human-readable message

**Termination:**
- `terminateAll()` — async graceful: SIGTERM → 3s timeout → SIGKILL
- `terminateAllSync()` — synchronous emergency: immediate `kill(pid, SIGKILL)` + `pkill -9 -f llama-server` safety net
- `AppKitLifecycle.willTerminateNotification` calls `terminateAllSync()` as the authoritative teardown path
- `AppState.deinit` is NOT relied upon (would be a zombie process trap due to potential retain cycles)

### `LLMClient` Dual Endpoint Support

`LLMConfig` now has a `completionEndpoint` property:
- **Ollama:** `/v1/chat/completions` — standard OpenAI messages array with `max_tokens`
- **llama.cpp:** `/completion` — raw text prompt with `n_predict` (not `max_tokens`)

Stream parsing now handles two chunk formats:
- `OpenAIChunk` — `choices[0].delta.content` for Ollama
- `LlamaCompletionChunk` — `content` directly for llama.cpp raw streaming

Default parameters: `temperature: 0.0`, `topP: 0.1` (deterministic autocomplete). These can still be overridden via the Typing Lab sliders.

### Why llama.cpp for Gemma 4 E2B

Gemma 4 E2B is one of the best models for text continuation, but when served through Ollama, it has "thinking" mode baked into the chat template. This causes:
- First tokens in the SSE stream to be reasoning/thinking gibberish
- TTFT inflated (first "real" token arrives after thinking completes)
- Accumulated tokens polluted with thinking prefixes (e.g., `...What is your name`)

llama.cpp with `--no-chat-template` and the raw `/completion` endpoint bypasses this entirely — pure raw text in, raw text out. **However, `--no-chat-template` was only added to llama.cpp in late 2024 / early 2025 builds. Older installed versions don't have it.**

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
- **Use `BackendManager` for all process lifecycle** — never spawn `Process()` directly elsewhere.
- **Use `AppKitLifecycle.willTerminateNotification` as the authoritative shutdown path** — never rely on `deinit`.
- **When changing llama-server flags, verify the installed binary version supports them first** — some flags are version-specific.

### DO NOT:
- Create new LLM provider files; use `LLMClient`.
- Change menu bar style to `.window`.
- Add animations to ghost text.
- Modify `NSApplication` lifecycle outside of `AppKitLifecycle.swift`.
- Remove `@MainActor` from primary core classes.
- Create separate toggles for system-wide vs playground — always use `isEnabled`.
- Hardcode `.lineLimit(3)` on ghost text views — always use `GhostTextStyle.lineLimit`.
- Bypass `ContextPreset` `loadContextPreset()` to set `draftText` directly when loading test contexts.
- Rely on `AppState.deinit` for process cleanup — use the notification-based teardown instead.

---

## File-by-File Reference (Ground Truth)

*If you are an LLM working on this codebase, read this section thoroughly before making any changes.*

### `Keybreeze/App/KeybreezeApp.swift`
- **Role:** `@main` entry. Creates `@StateObject` `AppState`. Two scenes: `MenuBarExtra` for menu bar, `Window("settings")` for settings window.
- **Key detail:** `SessionViewModel` lives inside `AppState` as a lazily-created property (`appState.sessionViewModel`) so it survives SwiftUI scene recreation.
- **On-disappear:** Cancels current prediction, then defers `restoreToAccessory()` by 150ms to avoid lifecycle crash.

### `Keybreeze/App/AppState.swift`
- **Role:** Shared application state as `@MainActor` `ObservableObject`. Owns `BackendManager` and wires the full backend lifecycle.
- **Key detail:** Owns the single `SessionViewModel` instance via `private var _sessionViewModel`. The computed `var sessionViewModel` lazily creates it once.
- Also manages: `LLMConfig`, `selectedBackend`, `selectedModel`, `availableModels`, model catalog refresh, backend boot/switching.
- **Backend events (UPDATED 25 May 2026):**
  - `init()` → calls `refreshModels()` (async, no longer calls `bootCurrentBackend()` synchronously)
  - `refreshModels()` → after models load, calls `bootCurrentBackend()` at the end
  - `handleBackendChange()` → calls `refreshModels()` only (delegates boot to the async completion)
  - `handleModelChange()` → guards on `backendManager.isReady` before calling `switchModel()`; if not ready, just saves the selection for `bootCurrentBackend()` to use
- **Wires** `AppKitLifecycle.backendManager = backendManager` for clean termination.
- **Legacy sync:** `backendManager.$isReady` is bound to `$isOllamaRunning` via Combine for backward-compatible UI bindings.

### `Keybreeze/Core/BackendManager.swift` (NEW — 24 May 2026, updated 25 May 2026)
- **Role:** `@MainActor` class managing process lifecycle for both backends.
- **Published:** `state: BackendState`, `isReady: Bool`, `statusMessage: String`, `lastError: String?`
- **Ollama:** Health checks `localhost:11434`. If unreachable, spawns `ollama serve`. Only kills if we spawned it (`didWeSpawnOllama` flag).
- **llama.cpp:** Spawns `llama-server` with tuned flags:
  ```
  --model <ggufPath> --host 127.0.0.1 --port 11345
  --ctx-size 512 --threads 4 --ubatch-size 256 --flash-attn on
  --no-chat-template --temp 0.0 --top-p 0.1
  ```
  **⚠️ `--no-chat-template` is version-dependent — older llama.cpp builds don't support it.** Monitors stderr for readiness. On model change: terminate + respawn.
- **Binary resolution:** Auto-detects via custom path → Homebrew cellar → `/opt/homebrew/bin` → `/usr/local/bin`.
- **Termination:** Async graceful (`terminateAll`) and sync emergency (`terminateAllSync` with immediate SIGKILL + pkill safety net).
- **Status: Builds successfully.** Ollama connects and serves predictions. llama.cpp server crashes immediately due to unsupported `--no-chat-template` flag.

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
- **Updated 25 May 2026:** Idle poll logging ("Current focused app bundle ID") now only fires on app switch — no more every-500ms spam.

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
- **Subscribes to** `appState.$selectedBackend` and `appState.$selectedModel` to auto-clear suggestions and re-trigger predictions on change.

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
- **Role:** Single HTTP client for both Ollama (SSE streaming to `/v1/chat/completions`) and llama.cpp (SSE streaming to `/completion`).
- **Updated 24 May 2026:** Added dual endpoint support. `LLMConfig.completionEndpoint` routes to the correct path per backend.
- **Ollama:** Uses `OpenAIRequest` with messages array and `max_tokens`.
- **llama.cpp:** Uses `LlamaCompletionRequest` with raw `prompt` string and `n_predict` (not `max_tokens`).
- **Stream parsing:** Handles both `OpenAIChunk` (delta.content) and `LlamaCompletionChunk` (direct content) formats.
- **Default parameters:** `temperature: 0.0`, `topP: 0.1` for deterministic autocomplete.
- **Cancellation:** `cancel()` is called before every new prediction.

### `Keybreeze/LLM/PromptBuilder.swift`
- **Role:** Builds continuation and system prompts. No LLM calls — just string construction.
- **Default system prompt:** Explicit instructions for continuation-only, no restating input, no markdown, no stylistic prefixes. Never start with ellipsis/dashes/punctuation prefix. If text ends mid-word, complete that word naturally from where it left off.
- **Parameters:** `context` (text before cursor), `styleNudge` (optional style guidance), `maxWords` (word cap).

### `Keybreeze/App/AppKitLifecycle.swift`
- **Role:** Lightweight AppKit touchpoints. Activation policy toggles. Termination handler.
- **Updated 24 May 2026:** `willTerminateNotification` now calls `backendManager?.terminateAllSync()` instead of brute-force `pkill -9`.
- **Holds:** `nonisolated(unsafe) static weak var backendManager: BackendManager?` — set during `AppState.init()`.

---

## Current Diagnostic Snapshot (25 May 2026 — Afternoon)

### Build Status
✅ **Builds successfully.** No compilation errors.

### Runtime Status

| Backend | Status | Detail |
|---------|--------|--------|
| **Ollama** | ✅ WORKING | Predictions flow end-to-end. Menu bar shows "Ready (Ollama)". TTFT ~25-180ms with gemma2:2b model. Health check passes. Backend switch and model change work correctly. Ghost text overlay appears in Typing Lab playground. Overlay window displays in external apps (with fallback positioning). |
| **llama.cpp** | ❌ BLOCKED | Server spawns (PID visible in logs) but immediately crashes with: `error: invalid argument: --no-chat-template`. The installed llama.cpp binary version does not support this flag. `--flash-attn` fix (changed to `--flash-attn on`) was correct — that error is gone — but `--no-chat-template` is the new blocker. |

### Active Log Pattern (llama.cpp)

```
🔄 Backend changed to: llama.cpp
llama.cpp model changed to Gemma 4 E2B I1 Q4_K_M — restarting server
Spawned llama-server (PID: 35665)
[Connection refused errors to 127.0.0.1:11345]
llama-server stderr: error: invalid argument: --no-chat-template
```

### What Changed Since 24 May

| # | Issue | Root Cause | Fix | File(s) |
|---|-------|-----------|-----|---------|
| 21 | Ollama health check state transition never completed | `bootCurrentBackend()` called synchronously in `AppState.init()` before async `refreshModels()` completed — models were empty, boot was skipped, and the follow-up `switchModel` call also failed because state was still `.idle` | Moved `bootCurrentBackend()` to end of `refreshModels()` async Task. Added `isReady` guard to `handleModelChange`. Removed premature `switchBackend` call from `handleBackendChange`. | `AppState.swift` |
| 22 | Menu bar always showed "Ollama Inactive" | `MenuBarContentView` read legacy `appState.isOllamaRunning` which was never updated | Changed to read `appState.backendManager.isReady` and `appState.backendManager.statusMessage`. Added Combine subscription: `backendManager.$isReady` → `$isOllamaRunning`. | `MenuBarContentView.swift`, `AppState.swift` |
| 23 | "Boot called while in state Starting... — ignoring" (double boot) | `MenuBarContentView.task` called `refreshModels()` a second time when menu opened, racing with `init()`'s boot | Removed `.task { appState.refreshModels() }` from menu bar view. | `MenuBarContentView.swift` |
| 24 | llama-server crashed: `error: unknown value for --flash-attn: '--no-chat-template'` | `--flash-attn` requires a value (`on`/`off`/`auto`). Passing it bare caused it to consume `--no-chat-template` as its value argument | Changed `"--flash-attn"` to `"--flash-attn", "on"` (two separate array elements) | `BackendManager.swift` |
| 25 | "Current focused app bundle ID" logged every 500ms | `readAndPredict()` unconditionally logged the bundle ID on every idle poll | Gated behind `if bundleID != lastAppBundleID` — only logs on app switch | `SystemWidePredictor.swift` |
| 26 | llama-server crashed: `error: invalid argument: --no-chat-template` | The installed llama.cpp binary version does not support the `--no-chat-template` flag (added in newer builds) | **NOT YET FIXED** — needs investigation of installed version and available flags | `BackendManager.swift` |

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
- ✅ **Test context presets:** 4 pre-built scenarios with Load button for rapid feel engineering
- ✅ **acceptSuggestion() isAccepting guard:** Fixed — no longer fires redundant re-prediction on full-accept
- ✅ **Context truncation:** Only last 800 chars sent to LLM — safe for documents of any size
- ✅ **Ghost text constants unified:** `GhostTextStyle.swift` created; both `GhostTextModifier` and `InlineGhostTextView` reference it
- ✅ **Backspace correction detection** — basic pipeline exists: candidate capture, Combine subscriber on suggestion, Tab/ESC handling, correction state rendering in ghost text
- ✅ **LLMClient dual endpoint support** — Ollama uses `/v1/chat/completions`, llama.cpp uses raw `/completion` with `n_predict`
- ✅ **BackendManager process lifecycle** — full boot/switch/termination logic implemented
- ✅ **Ollama backend fully working** — predictions flow, menu bar status correct, low latency
- ✅ **SystemWidePredictor console noise reduced** — bundle ID only logged on app switch
- ✅ **No double boot race** — menu bar no longer triggers a second `refreshModels()`

---

## What Still Needs Work

### Critical — llama.cpp Backend Not Starting (25 May 2026)

1. **`--no-chat-template` flag unsupported** — The installed llama.cpp binary version does not recognize `--no-chat-template`. This flag was added to llama.cpp server in later builds. The server process is spawned but immediately exits with exit code 1 (invalid argument). All subsequent requests to `127.0.0.1:11345` get "Connection refused" because no server is listening.

   **Required actions:**
   - Determine the installed llama.cpp version: `llama-server --version` or `brew info llama.cpp`
   - Check available flags: `llama-server --help 2>&1 | grep -i chat` — is there an equivalent flag? (e.g., `--chat-template none`, `--no-chat`, `--raw`)
   - If no equivalent flag exists, either upgrade llama.cpp (`brew upgrade llama.cpp`) or remove the `--no-chat-template` flag and accept that Gemma 4 E2B may produce thinking tokens through the raw completion endpoint (which may be acceptable since we use the raw `/completion` endpoint, not chat completions — the chat template may not apply to raw mode).

### High Priority

2. **Ollama predictions sometimes start with `...`** — Despite the `PromptBuilder` rule "NEVER start with ellipsis", some Ollama models (gemma2:2b) output `...fiction for children`, `...that tells the story`. Options:
   - Post-process suggestions in CompletionController to strip leading `...`
   - Switch to llama.cpp for affected models once it's working

3. **Backspace correction (§7) — buggy matching** — The detection logic is implemented but produces false positives. 
   - **Known issues:**
     - Candidate persists across multiple word-boundary backspaces
     - Lowercase suffix matching fires on every streaming token update
     - The length guard is too permissive
   - **Suggested approach:** Wait for suggestion to settle (wordCount > 0), then check once rather than on every streaming token.
   - **UI is ready:** `GhostTextModifier` renders strikethrough+green. Tab/ESC handling works.

### Medium Priority

4. **SystemWidePredictor gating** — `shouldProcessApp()` may incorrectly return true for Keybreeze's own bundle ID in some code paths.

5. **System-wide integration** — AX context reading works but needs: reliable cursor rect positioning across apps, Tab insertion in external apps, event tap permission handling, app gating UI. Blocked on Lab feel engineering being locked down first.

### Lower Priority / Blocking

6. **Ghost Overlay Positioning** — Fallback logic for AX cursor rects in multi-monitor setups needs robustifying (Tier 4 computed fallback is placeholder).

7. **Right Arrow word-by-word acceptance** — Per BEHAVIOR.md §5. Powerful but low priority.

---

## Summary of All Completed Fixes

### 25 May 2026 Session

| # | Issue | Root Cause | Fix | File(s) |
|---|-------|-----------|-----|---------|
| 21 | Boot ordering: "No models available — skipping backend boot" | `bootCurrentBackend()` called synchronously before async model refresh | Moved to end of `refreshModels()` Task | `AppState.swift` |
| 22 | Menu bar always showed "Ollama Inactive" | Read legacy `isOllamaRunning` never updated | Changed to `backendManager.isReady` + `statusMessage`; wired Combine sync | `MenuBarContentView.swift`, `AppState.swift` |
| 23 | Double boot race ("Boot called while in state Starting...") | `MenuBarContentView.task` fired second `refreshModels()` | Removed the `.task` modifier | `MenuBarContentView.swift` |
| 24 | llama-server: `unknown value for --flash-attn: '--no-chat-template'` | `--flash-attn` needs a value, consumed next flag | Changed to `"--flash-attn", "on"` | `BackendManager.swift` |
| 25 | Console spam: "Current focused app bundle ID" every 500ms | Unconditional `log.debug` on every idle poll | Gated on `bundleID != lastAppBundleID` | `SystemWidePredictor.swift` |
| 26 | `handleModelChange` called `switchModel` when backend not ready | No guard on backend state | Added `guard backendManager.isReady else { return }` | `AppState.swift` |
| 27 | `handleBackendChange` called `switchBackend` with stale/empty model path | Called before `refreshModels()` completed | Removed direct `switchBackend` call; `refreshModels()` handles full boot | `AppState.swift` |

### 24 May 2026 Session

| # | Issue | Fix | File(s) |
|---|-------|-----|---------|
| 1 | SessionViewModel recreated on scene refresh | Moved to AppState as lazy strong reference | `AppState.swift`, `KeybreezeApp.swift` |
| 2 | Debounce 100ms (spec says 45ms) | Changed `debounceDelay` from 100→45ms | `CompletionController.swift` |
| 3 | GhostTextModifier never applied to playground TextField | Added `.ghostText()` modifier chain | `TypingLabView.swift` |
| 4 | Overlay padding misaligned | Changed to 13px to match content inset | `GhostTextModifier.swift` |
| 5 | Ghost overlay wrapping incorrectly on multi-line | Added `.padding(.trailing, 13)` | `GhostTextModifier.swift` |
| 6 | Two separate toggles | Consolidated to single `isEnabled` | `SessionViewModel.swift` |
| 7 | Had to manually toggle "Active" | Auto-start via `isEnabled = true` in init | `SessionViewModel.swift` |
| 8 | "Modifying state during view update" warnings | Fixed by stable VM lifecycle | `AppState.swift` |
| 9 | Streaming tokens displayed character-by-character | Gate on first complete word or 3 tokens | `CompletionController.swift` |
| 10 | acceptSuggestion() missing isAccepting guard | Added guard around draftText mutation | `SessionViewModel.swift` |
| 11 | No quick way to test different contexts | Added ContextPreset enum + picker + Load button | `SessionViewModel.swift`, `TypingLabView.swift` |
| 12 | Inline ghost text line limit too small | Changed `.lineLimit(3)` to `.lineLimit(10)` | `GhostTextModifier.swift`, `SuggestionOverlayWindow.swift` |
| 13 | Ghost text visual constants duplicated | Created `GhostTextStyle.swift` with shared constants | `GhostTextStyle.swift` (new), `GhostTextModifier.swift`, `SuggestionOverlayWindow.swift` |
| 14 | PromptBuilder allowed `...` prefix | Added rules: never start with ellipsis/punctuation | `PromptBuilder.swift` |
| 15 | Backspace correction not implemented | Added full detection pipeline + UI | `SessionViewModel.swift` |
| 16 | No backend process lifecycle management | Created `BackendManager` with full boot/switch/termination | `BackendManager.swift` (new) |
| 17 | LLMClient only supported Ollama chat endpoint | Added dual endpoint support with raw `/completion` for llama.cpp | `LLMClient.swift` |
| 18 | App termination used brute-force pkill | Replaced with clean `terminateAllSync()` via BackendManager | `AppKitLifecycle.swift` |
| 19 | Gemma 4 E2B thinking tokens polluted predictions | Implemented llama.cpp backend path with `--no-chat-template` | `BackendManager.swift`, `LLMClient.swift`, `AppState.swift` |
| 20 | BackendManager 4 compilation errors blocking build | Added `CustomStringConvertible` to `BackendState`, explicit `self.` in Logger autoclosures, `do/catch` for pkill `Process.run`, `try?` for fallback health check | `BackendManager.swift` |

---

## Next Steps (Recommended Order)

1. **Fix llama.cpp `--no-chat-template`** — Determine installed llama.cpp version and available flags:
   - Run: `llama-server --version`
   - Run: `llama-server --help 2>&1 | grep -i chat`
   - If no `--no-chat-template` equivalent exists: upgrade llama.cpp via Homebrew, or remove the flag (raw `/completion` endpoint may bypass chat templates regardless).

2. **Test llama.cpp backend with Gemma 4 E2B** — Once the server starts correctly, verify Gemma 4 E2B produces clean raw continuations.

3. **Post-process predictions to strip `...`** — Strip leading ellipsis/dashes from Ollama suggestions in `CompletionController`.

4. **Fix backspace correction matching** — Gate correction detection on settled suggestions (not every streaming token). Tighten the match criteria.

5. **Polish SystemWidePredictor** — Fix gating for Keybreeze's own bundle ID, improve cursor rect positioning.

6. **System-wide rollout** — Enable predictions across all apps.