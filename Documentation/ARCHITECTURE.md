# Keybreeze — Architecture

## What Keybreeze Is

A **macOS menu bar app** providing **local, low-latency text continuation** (autocomplete). Uses **Ollama** (primary) or **llama.cpp** (secondary/experimental) over HTTP. Includes **Typing Lab** — a permanent dev environment with live playground, diagnostics, prediction history, prompt editing, and runtime tuning.

**Design intent:** continuation only, short outputs, single simplified client (`LLMClient`), relentless focus on typing feel over raw intelligence.

Not an inference infrastructure project. The LLM layer is replaceable plumbing — a single `LLMClient` class that speaks the OpenAI `/v1/chat/completions` API.

---

## Phase Status

| Phase | Status |
|-------|--------|
| Phase 0 — Project Skeleton | ✅ |
| Phase 1 — LLM Pipeline (Ollama + llama.cpp) | ✅ |
| Phase 2 — Prediction Engine | ✅ |
| Phase 2.5 — Ghost Text + Tuning | ✅ |
| Typing Lab / Feel Engineering | ✅ |
| Phase 3 — System-Wide Integration (AX context reading + Tab accept) | ✅ |
| Phase 4 — Ghost Overlay in External Apps | ✅ |
| Phase 5+ — Polish, Style Memory, Expansion | Later |

**Known issues:**
1. **Typing Lab text field not responding to input** — The playground TextField in TypingLabView does not register keystrokes when the user types. The `sessionVM.draftText` binding does not update on keypress. Suspected: focus issue within Form/HSplitView/hidden-title-bar window, or ghost overlay blocking input. Workaround: use system-wide mode (enable Keybreeze, type in any app) to test predictions. See Known Issues section in BRIEF.md.
2. **Ghost overlay positioning** — Improved screen detection and baseline alignment; still tuning fallback logic for multi-monitor and non-AX-compliant apps.
3. **App gating interference** — Fixed with gating logic in `SystemWidePredictor` to ignore `Keybreeze` focused events.
4. **Typing Lab ghost text vertical offset** — Fixed by aligning overlay padding with `TextField` internal padding.

---

## Directory Layout

| Path | Role |
|------|------|
| `Keybreeze/App/` | `@main` entry (`KeybreezeApp.swift`), AppKit activation policy (`showInDockAndCmdTab`/`restoreToAccessory`), termination cleanup |
| `Keybreeze/Core/` | `AppState`, `CompletionController`, `PredictionHistory`, `PredictionMode`, `ModelOption`, `AppSettings`, `AccessibilityManager`, `InputSourceMonitor`, `SystemWidePredictor` |
| `Keybreeze/LLM/` | `LLMClient` (singleton HTTP client), `PromptBuilder`, `LLMConfig`, `LLMBackend` |
| `Keybreeze/UI/` | `MenuBarContentView`, `SessionViewModel`, `GhostTextModifier`, `SettingsView`, `SuggestionOverlayWindow`, `TypingLab/` subfolder |
| `Keybreeze/Utils/` | `KeybreezeLatencyLogger` |

---

## File-by-File Reference (For LLMs)

This section is the **ground truth** — every file that exists, what it does, and the exact responsibilities. If you are an LLM working on this codebase, read this section thoroughly before making any changes.

### `Keybreeze/App/KeybreezeApp.swift`
- **Role:** `@main` entry point. Creates `AppState` as `@StateObject`. Lazily creates `SessionViewModel` as `@State` (so it outlives menu opens/closes).
- **Scenes:** 
  - `MenuBarExtra` with `.menuBarExtraStyle(.menu)` — the menu bar dropdown.
  - `Window("Keybreeze Settings", id: "settings")` — the settings window, using SwiftUI's native Window scene with `.windowStyle(.hiddenTitleBar)` for a clean, borderless appearance. This replaced the manual `SettingsWindowController` approach, which crashed on close due to re-entrant AppKit teardown.
- **Lifecycle:** `.onAppear` calls `AppKitLifecycle.showInDockAndCmdTab()`. `.onDisappear` cancels predictions and defers `restoreToAccessory()` to avoid re-entrancy.
- **RULE:** Do NOT change the menu bar scene style to `.window`. Do NOT wrap `TypingLabRootView` in the menu bar. Do NOT use `.window` style.
- **RULE:** Use `.windowStyle(.hiddenTitleBar)` and `.commandsRemoved()` on the settings scene for a clean look. Avoid manual NSWindow lifecycle management.

### `Keybreeze/App/AppKitLifecycle.swift`
- **Role:** Sets activation policy to `.accessory`. Registers for `willTerminateNotification` to pkill any orphan `llama-server` processes.
- **Methods:** `showInDockAndCmdTab()` — temporarily switches to `.regular` activation policy when the settings window opens, making it appear in the Dock and Cmd+Tab. `restoreToAccessory()` — switches back to `.accessory` when the window closes.
- **RULE:** This is the ONLY file that touches `NSApplication` lifecycle. Do not add AppKit lifecycle code elsewhere.
- **RULE:** `restoreToAccessory()` must be called from a deferred context (e.g. `DispatchQueue.main.async`) when triggered by window teardown to avoid re-entrancy crashes.

### `Keybreeze/App/AppState.swift`
- **Role:** Shared application state: `LLMConfig`, `selectedBackend`, `selectedModel`, model catalog (`availableModels`, `modelCatalogStatus`).
- **Methods:** `refreshModels()` fetches from Ollama API or scans GGUF directory. `handleBackendChange()` toggles config and refreshes.
- **Persistence:** Config and selected model saved to UserDefaults via `JSONEncoder`.
- **RULE:** `AppState` does NOT own the prediction engine, the LLM client, or any UI state. It is purely configuration + model catalog.

### `Keybreeze/Core/CompletionController.swift`
- **Role:** The prediction orchestrator. Receives `EditorState`, debounces, builds prompts via `PromptBuilder`, calls `LLMClient.streamCompletion()`, measures TTFT and total latency, and records prediction history via `onRecordPrediction` callback.
- **Published properties:** `suggestion`, `isRunning`, `statusMessage`, `currentMode`, `currentLatency`, `currentTTFT`.
- **Settable properties:** `modelID`, `temperature`, `topP`, `maxWords`, `customSystemPrompt`, `styleNudge`.
- **Lifecycle:** `start()` / `stop()` toggles the engine. `editorStateChanged()` triggers debounced predictions.
- **RULE:** This is `@MainActor`. The `onToken` closure in `streamCompletion` captures local vars (not `self`) for actor-safety. Always use `Task { @MainActor in }` to update published properties from within the sendable token callback.
- **RULE:** Do NOT remove latency tracking. `currentTTFT` and `currentLatency` drive the diagnostics panel.
- **RULE:** Always use `PromptBuilder` for prompt construction — do not inline prompt strings.

### `Keybreeze/Core/PredictionHistory.swift`
- **Role:** `PredictionRecord` model, `PredictionResolution` enum, `PredictionHistory` ring buffer (max 200), `CorrectionState`, `AggressionPreset`.
- **RULE:** `PredictionHistory` is `@unchecked Sendable` — only accessed from `@MainActor`. Do not add threading.
- **RULE:** `AggressionPreset` is the canonical source for preset temperature/topP/repeatPenalty/confidenceThreshold values.

### `Keybreeze/Core/PredictionMode.swift`
- **Role:** `midType` vs `pause` mode enum with default word caps and debounce timings.
- **RULE:** Do not change the debounce values without also updating `CompletionController`'s debounce delay (currently 45ms).

### `Keybreeze/Core/ModelOption.swift`
- **Role:** Model option struct with per-model presets (temperature, topP, repeatPenalty, confidenceThreshold). Default model is `gemma2:2b`.
- **RULE:** Add new model presets as static factory methods. Do not add model-specific logic outside this file.

### `Keybreeze/Core/AppSettings.swift`
- **Role:** Codable settings struct with nested `InferenceSettings`, `TuningSettings`, `AppGatingSettings`, `PromptSettings`. Saved/loaded from UserDefaults.
- **RULE:** This is the single source of truth for persisted settings. `SessionViewModel.loadSettings()` reads from it.

### `Keybreeze/Core/AccessibilityManager.swift`
- **Role:** Singleton for Accessibility API: permission check/request, text context extraction (`getTextContext`), cursor rect extraction (`getCursorRect`), text insertion (`insertText`), app info (`focusedAppBundleID`). Default excluded/manual-only bundle IDs.
- **Text insertion:** Uses `insertViaKeyboardEvents()` — synthesizes CGEvent keyboard events per-character via `keyboardSetUnicodeString`. This preserves rich text formatting and editor state (Obsidian, web views, etc.). Falls back to clipboard-based insertion.
- **Cursor rect:** `getCursorRect()` uses `kAXBoundsForRangeParameterizedAttribute` to get the caret's bounding rect in AX coordinate space (top-left origin). Used by `SuggestionOverlayWindowController` to position the ghost overlay.
- **RULE:** All methods are `@MainActor`. `getTextContext` returns `TextContext?` (includes `cursorRect`). `insertText` uses keyboard event synthesis with clipboard fallback.
- **RULE:** Do NOT read/set `kAXValueAttribute` for insertion — this destroys formatting in rich editors.

### `Keybreeze/Core/InputSourceMonitor.swift`
- **Role:** Monitors keyboard input source changes via Carbon `TISCopyCurrentKeyboardInputSource`. Reports `isASCIICompatible` boolean. Used as safety gate to suspend predictions during IME composition.
- **RULE:** Singleton. Do not modify. Used by `CompletionController.readinessCheck()` and `SystemWidePredictor`.

### `Keybreeze/Core/SystemWidePredictor.swift`
- **Role:** Bridges the Accessibility API text context into the `CompletionController` for system-wide prediction. Uses two complementary trigger mechanisms: a CGEventTap (captures keyDown events system-wide for instant response) and a 500ms idle safety poll (catches paste/undo/mouse changes).
- **Owns:** CGEventTap lifecycle, debounce timer, app-gating logic, **`SuggestionOverlayWindowController`** (floating ghost overlay window).
- **Configuration:** `excludedBundleIDs`, `manualOnlyBundleIDs`, `predictInManualOnly`.
- **Published properties:** `focusedAppBundleID`, `focusedAppName`, `isPaused`, `pauseReason`.
- **Lifecycle:** `start()` / `stop()` — called by `SessionViewModel` when `isSchedulerActive` is toggled.
- **Overlay wiring:** A Combine subscription on `controller.$suggestion` shows/hides the overlay. When `suggestion` is non-empty and `lastCursorRect` is valid, the overlay displays the suggestion text positioned at the cursor. When suggestion is cleared, the overlay hides.
- **App gating:** Skips Keybreeze's own bundle ID (`app.keybreeze.Keybreeze`). Checks excluded/manual-only lists. Suspends during non-ASCII IME composition via `InputSourceMonitor.isASCIICompatible`.
- **Inspired by:** Ghost Type's `GlobalKeyMonitor` pattern — event-tap based to avoid polling overhead while ensuring instant keystroke response.
- **RULE:** `@MainActor`. Always use the convenience init `init(controller:)` which resolves shared singletons.
- **RULE:** Does NOT own `CompletionController` — just feeds it `EditorState` via `editorStateChanged()`.

### `Keybreeze/LLM/LLMClient.swift`
- **Role:** Single OpenAI-compatible HTTP client. Speaks `/v1/chat/completions` with SSE streaming. Builds request from prompt + optional systemPrompt.
- **Methods:** `streamCompletion(prompt:systemPrompt:model:maxTokens:temperature:topP:onToken:)`, `cancel()`, `scanGGUFModels(directory:)`.
- **Also contains:** `LLMConfig`, `LLMBackend`, and private DTOs (`OpenAIRequest`, `OpenAIChunk`).
- **RULE:** This is the ONLY file that makes HTTP requests to LLM backends. Do NOT create additional LLM provider files.
- **RULE:** `streamCompletion` is `@MainActor` but the `onToken` closure is `@Sendable`. Use `Task { @MainActor in }` to update UI from inside the callback.
- **RULE:** Do not add streaming logic for llama.cpp — non-streaming only (llama.cpp SSE has no terminating event).

### `Keybreeze/LLM/PromptBuilder.swift`
- **Role:** Builds system and continuation prompts. Contains `defaultSystemPrompt` string (text continuation instructions), `continuationPrompt(context:styleNudge:maxWords:)`, `systemPrompt(customPrompt:styleNudge:)`.
- **RULE:** All prompt construction MUST go through `PromptBuilder`. No inline prompt strings in `CompletionController`.
- **RULE:** Do not add markdown, explanations, or conversational tone to the prompts — they are for a continuation engine, not a chatbot.

### `Keybreeze/UI/MenuBarContentView.swift`
- **Role:** The menu bar dropdown content. A compact `VStack` with: daily completions count, Active button (enable/disable), mode indicator (always System when active), Settings button, Backend/Model pickers, status indicator, suggestion preview, Quit button.
- **Settings opening:** Uses `@Environment(\.openWindow)` to open the SwiftUI `Window` scene with `id: "settings"`. This replaces the old `SettingsWindowController` approach (manual NSWindow management) which caused EXC_BAD_ACCESS crashes on close due to re-entrant AppKit teardown.
- **RULE:** This is the ONLY dropdown content. Do NOT add Typing Lab views here. Do NOT change `.menuBarExtraStyle(.menu)`.
- **RULE:** When active, system-wide predictions are always enabled (no separate toggle needed).
- **RULE:** Focused app display reads from `sessionVM.focusedAppName`, `sessionVM.isSystemWidePaused`, `sessionVM.systemWidePauseReason` — these are backed by `SystemWidePredictor`'s published properties.
- **RULE:** "Grant AX Access" button was removed from the menu bar — it now lives in Settings → General → Status.

### `Keybreeze/UI/SettingsView.swift`
- **Role:** Standalone settings window with two tabs: General and Typing Lab. Opens via `SettingsWindowController` (separate NSWindow, not the menu bar).
- **General tab:** Active toggle, AX permission status indicator (live-refreshes via `onAppear`), Backend/Model pickers, daily stats.
- **Typing Lab tab:** Embeds `TypingLabRootView` with full Playground, Apps, Diagnostics, History panels.
- **RULE:** AX status uses `@State` + `.onAppear` only — no `Timer.publish` or `onReceive` subscribers that could fire during SwiftUI view teardown and crash.
- **RULE:** The settings window is purely a UI surface. Opening/closing it must NOT affect the prediction engine or session state.

### `Keybreeze/UI/SessionViewModel.swift`
- **Role:** The bridge between UI and prediction engine. Holds all published state for editor, prediction mode, model tuning, prompt editing, app gating, and diagnostics.
- **Owns:** `CompletionController`, `PredictionHistory`, `SystemWidePredictor` (lazy).
- **Two modes:** Playground mode (default) — predictions driven by `draftText` in the Typing Lab text field. System-wide mode — predictions driven by `SystemWidePredictor` reading the focused app's text field via Accessibility API. **Note: System-wide mode is automatically enabled when the prediction engine is active.**
- **Initialization:** Wires controller outputs via Combine. Sets `controller.onRecordPrediction` to add records to history. Sets up debounced Combine subscriptions for `$temperature`, `$topP`, `$tuningMaxWords`, `$customSystemPrompt`, `$styleNudge` → `updateControllerFromAppState()`.
- **Methods:** `acceptSuggestion()`, `acceptWord()`, `syncTuningFromModel()`, `updateControllerFromAppState()`, `loadSettings()`, `saveSettings()`, `startSystemWidePredictor()`, `stopSystemWidePredictor()`.
- **Published properties:** `isSchedulerActive` (controls both LLM engine and system-wide predictions), `isPredicting`, `suggestion`, `statusMessage`, `currentPredictionMode`, `correctionState`, plus model tuning and app gating properties.
- **Computed properties:** `focusedAppBundleID`, `focusedAppName`, `isSystemWidePaused`, `systemWidePauseReason` (derived from `SystemWidePredictor`).
- **RULE:** Do NOT call `updateControllerFromAppState()` only in init — the Combine subscriptions keep parameters in sync automatically.
- **RULE:** History records from `acceptSuggestion()`/`acceptWord()` include `currentTTFT` and `currentLatency` from the controller.
- **RULE:** `isAccepting` flag suppresses `handleDraftChanged()` during programmatic text changes, preventing stale editor states from reaching the controller.
- **RULE:** When `isSchedulerActive` is true, both the LLM controller and system-wide predictor are active (no separate toggles needed).

### `Keybreeze/UI/GhostTextModifier.swift`
- **Role:** SwiftUI `ViewModifier` that overlays ghost text as grey/translucent text (`.secondary.opacity(0.45)`) on top of the text field. Supports correction state (red strikethrough + green suggestion).
- **RULE:** No blend modes. No animations. Simple static overlay with proper padding to match the text field's inner inset.
- **NOTE:** Works inside Keybreeze's own Typing Lab text field. For third-party apps, see `SuggestionOverlayWindowController` (floating overlay window).
- **RULE:** Ghost text ONLY shows when `isSchedulerActive` is true AND `suggestion` is non-empty OR `correctionState` is non-nil.

### `Keybreeze/UI/SuggestionOverlayWindow.swift`
- **Role:** `SuggestionOverlayWindowController` — manages a borderless, transparent, floating NSWindow that displays ghost text after the caret in the focused third-party app.
- **Dependencies:** Used only by `SystemWidePredictor` (which owns the controller and wires it to `CompletionController.$suggestion`).
- **Positioning:** Uses AX cursor rect from `AccessibilityManager.getTextContext().cursorRect` (via `kAXBoundsForRangeParameterizedAttribute`). Converts from AX coordinate space (top-left origin) to NSScreen coordinate space (bottom-left origin).
- **Visual style:** Grey/translucent ghost text (`.secondary.opacity(0.45)`, matching `GhostTextModifier`). Transparent background, no border, no shadow. Click-through (`ignoresMouseEvents = true`). No focus steal (`orderFrontRegardless()`).
- **RULE:** `@MainActor`. Must be created on the main actor. All window operations are main-actor-only.
- **RULE:** Only show when `cursorRect` is valid (width >= 0, height > 0). Hide immediately when suggestion is cleared.
- **NOTE:** The `InlineGhostTextView` SwiftUI view renders only the ghost suggestion — the committed text is already in the host app's text field, so we don't duplicate it.

### `Keybreeze/UI/TypingLab/TypingLabRootView.swift`
- **Role:** The full Typing Lab development environment. Four tabs: Playground, Apps, Diagnostics, History. Contains typing playground with ghost text, preset picker, and toggleable sections (Diag, Params, Prompts).
- **RULE:** This view is opened in a standalone NSWindow by `SettingsWindowController`, NOT in the menu bar.
- **RULE:** All subviews receive `.environmentObject(appState).environmentObject(sessionVM)` explicitly — do not rely on implicit inheritance through the window hierarchy.

### `Keybreeze/UI/TypingLab/DiagnosticsPanelView.swift`
- **Role:** Live engine diagnostics: backend, model, mode, TTFT, avg time, cancel count, accepted count, accept rate, context size, prediction word count. Also has "Copy Log" export.
- **RULE:** Reads from `sessionVM.predictionHistory` and `sessionVM.currentLatency`/`currentTTFT`. No side effects.

### `Keybreeze/UI/TypingLab/ParameterControlsView.swift`
- **Role:** Runtime parameter sliders: word caps (global max, mid-type, pause), sampling (temperature, top-p, repeat penalty, confidence threshold), behaviour (verbosity bias, continuation bias, instruction strictness).
- **RULE:** Changes propagate to `SessionViewModel` → auto-synced to `CompletionController` via Combine.

### `Keybreeze/UI/TypingLab/PromptEditorView.swift`
- **Role:** Runtime prompt editing — custom system prompt override and style nudge fields with toggle switches.
- **RULE:** On appear, fills `customSystemPrompt` with `PromptBuilder.defaultSystemPrompt` if empty.

### `Keybreeze/UI/TypingLab/PredictionHistoryView.swift`
- **Role:** Scrolling timeline of prediction records with filter by resolution, stat badges (total/accepted/ignored/cancelled/accept %), clear button.
- **RULE:** Read-only display. No mutation of history.

### `Keybreeze/UI/TypingLab/AppGatingPanelView.swift`
- **Role:** Manage excluded and manual-only app bundle IDs.
- **RULE:** Uses `AccessibilityManager.defaultExcludedBundleIDs` and `AccessibilityManager.defaultManualOnlyBundleIDs` for defaults.

### `Keybreeze/Utils/KeybreezeLatencyLogger.swift`
- **Role:** Console-only latency output for engine tuning.
- **RULE:** No persistence. No UI. Called from `CompletionController.recordPrediction()`.

---

## Runtime Object Graph

```
KeybreezeApp (@main)
 ├── AppState (selectedModel, selectedBackend, LLMConfig, model catalog)
 ├── SessionViewModel (lazy @State, outlives menu opens)
 │    ├── CompletionController (orchestrator: debounce → prompt → LLM → latency → history)
 │    │    └── LLMClient (HTTP: /v1/chat/completions with SSE)
 │    ├── PredictionHistory (ring buffer, 200 records)
 │    ├── AppSettings (persisted Codable)
 │    ├── SystemWidePredictor (lazy, only when isSchedulerActive enabled)
 │    │    ├── AccessibilityManager (singleton: AX text read/insert + cursor rect)
 │    │    ├── InputSourceMonitor (singleton: IME safety gate)
 │    │    └── SuggestionOverlayWindowController (floating ghost overlay)
 │    └── Combine subscriptions: parameter changes → controller
 ├── AccessibilityManager (shared singleton)
 └── InputSourceMonitor (shared singleton)
```

### State Sharing
- `AppState` and `SessionViewModel` are created once in `KeybreezeApp`
- Menu bar dropdown receives them as `@EnvironmentObject`
- The Settings window shares the **same** state objects — changes in either view are reflected in both

---

## Prediction Pipeline

1. **`EditorState`** — text before/after caret from Typing Lab (or external editor via `SystemWidePredictor`).
2. **`CompletionController.editorStateChanged()`** — debounces (45ms), cancels previous prediction.
3. **`PromptBuilder.continuationPrompt(context:styleNudge:maxWords:)`** — strict autocomplete instructions + style profile.
4. **`PromptBuilder.systemPrompt(customPrompt:styleNudge:)`** — system instructions for the LLM.
5. **`LLMClient.streamCompletion(prompt:systemPrompt:model:maxTokens:temperature:topP:onToken:)`** — SSE streaming from Ollama's `/v1/chat/completions`.
6. **Latency tracking** — `predictionStartTime` captured before request, `firstTokenTime` captured on first token callback, TTFT and totalTime computed after stream ends.
7. **History recording** — every prediction (completed or cancelled with tokens) is recorded via `onRecordPrediction` callback.
8. **Overlay display** — in system-wide mode, `SystemWidePredictor`'s Combine subscription on `controller.$suggestion` shows/hides the `SuggestionOverlayWindowController` at the cursor position.

---

## Backend Architecture

### LLMClient (simplified single-provider pattern)

The old `LLMProvider` protocol + `OllamaLLMService` + `LlamaCppService` pattern was replaced with a single `LLMClient` class that speaks the OpenAI-compatible API (`/v1/chat/completions`).

- Both Ollama and llama.cpp expose an OpenAI-compatible endpoint
- `LLMConfig.backend` selects which base URL to use
- No separate provider protocols, no service abstraction layer
- Model catalog: Ollama via `GET /api/tags`, llama.cpp via GGUF file scanning

### Configuration

```swift
struct LLMConfig: Codable, Equatable, Sendable {
    var backend: LLMBackend = .ollama
    var ollamaBaseURL: URL = URL(string: "http://127.0.0.1:11434")!
    var llamaCppBaseURL: URL = URL(string: "http://127.0.0.1:11345")!
    var llamaCppModelsDirectory: String = "/Users/..."
}
```

### Model Selection

- `AppState.refreshAvailableModels()` dispatches to the current backend's catalog.
- **Ollama:** Fetches `GET /api/tags` and maps each tag via `ModelOption.option(resolvingOllamaTag:)`.
- **llama.cpp:** `LLMClient.scanGGUFModels(directory:)` walks the GGUF directory.
- `ModelOption` has per-model presets for temperature, topP, repeatPenalty, confidenceThreshold.

---

## UI Architecture

### Two Surfaces

1. **Menu bar dropdown** (`MenuBarContentView`)
   - Compact (280pt wide) VStack with essential controls
   - Backend/Model pickers, Active toggle, status, system-wide mode toggle
   - Settings button opens a separate NSWindow
   - ".menu" style — NOT ".window"

2. **Settings window** (`SettingsView` in SwiftUI `Window` scene with `.hiddenTitleBar`)
   - 820×580 default size, uses `.regular` activation policy while open (Dock + Cmd+Tab)
   - Two panels: General, Typing Lab — navigated via `HSplitView` sidebar
   - General panel: Active toggle, status pills, labeled statistics card, Backend/Model pickers
   - Typing Lab panel: typing playground with ghost text overlay, preset picker, toggleable Diagnostics/Parameters/Prompts sections
   - `.windowStyle(.hiddenTitleBar)` for a clean borderless look — zero chrome
   - Opens via `@Environment(\.openWindow)` from the menu bar, closes cleanly via SwiftUI lifecycle

### Ghost Text Rendering

**Two rendering paths:**

1. **Typing Lab (in-app):** `GhostTextModifier` — SwiftUI `ViewModifier` overlays ghost text on the playground TextField. Grey/translucent static overlay. No animations.

2. **Third-party apps (system-wide):** `SuggestionOverlayWindowController` — borderless, transparent NSWindow floating at the cursor position. Uses AX API `kAXBoundsForRangeParameterizedAttribute` for cursor position. Transparent background, click-through, no focus steal. Matches the same visual style as `GhostTextModifier`.

### System-Wide Ghost Overlay Data Flow

```
AX keystroke (CGEventTap)
  → debounce (40ms)
  → AccessibilityManager.getTextContext() returns TextContext { prefix, suffix, cursorRect }
  → SystemWidePredictor resolves cursorRect via 4-tier fallback (see below)
  → SystemWidePredictor feeds EditorState to CompletionController
  → CompletionController generates prediction via LLM
  → controller.$suggestion changes
  → Combine subscription in SystemWidePredictor fires (ALWAYS shows when non-empty)
  → SuggestionOverlayWindowController.show(text: at: resolvedCursorRect)
  → SuggestionOverlayWindowController falls back to screen position if rect is .zero
  → Floating ghost text appears after cursor in the third-party app
```

**Cursor Rect Resolution (4-tier fallback):**

AX cursor rect (`kAXBoundsForRangeParameterizedAttribute`) frequently fails in many apps — Terminal, web views, Electron apps (Obsidian, VS Code), and complex editors. When it fails, the overlay must not silently disappear.

1. **Tier 1 (AX embedded):** `getTextContext().cursorRect` — if valid (>0 h/w), use and cache as `lastValidCursorRect`
2. **Tier 2 (AX independent):** Independent `accessibility.getCursorRect()` call — retries AX on a fresh call
3. **Tier 3 (Cached):** `lastValidCursorRect` — persists valid rects across keystrokes. When AX intermittently fails, the overlay stays at the last known good position
4. **Tier 4 (Computed):** `computeFallbackCursorRect()` — a computed position using the focused app's main window AX attributes (`kAXMainWindowAttribute` + position/size), positioned at ~20%/30% into the window

If all AX fallbacks fail, `SuggestionOverlayWindowController` has its own last-resort fallback that positions the overlay at left-center of the screen.

**CRITICAL RULE:** The Combine subscription on `controller.$suggestion` must ALWAYS show the overlay when `suggestion` is non-empty, regardless of cursorRect validity. Never gate overlay display on `lastCursorRect != .zero` — this was the root cause of the ghost overlay being silently invisible in third-party apps.

---

## Key Design Decisions

- **LLM layer is deliberately thin.** Single `LLMClient` class. No `LLMProvider` protocol. No separated backend service files. Ollama is the primary production backend; llama.cpp uses the same endpoint.
- **Sandbox disabled** (`ENABLE_APP_SANDBOX = NO`) — required for file system access to GGUF directory and spawning `llama-server` as a child process (if ever re-added).
- **Non-streaming for llama.cpp** — SSE mode never sends a terminating event, causing hangs. Currently both backends use the OpenAI-compatible SSE streaming endpoint.
- **Runtime parameters** (`temperature`, `topP`, `repeatPenalty`, `confidenceThreshold`, biases) are user-tunable via Typing Lab sliders. Aggression presets (Conservative/Balanced/Aggressive) batch-set these.
- **Prompt editing** — system and continuation prompts are overridable at runtime via the Typing Lab. Edits propagate to `CompletionController` via Combine.
- **Prediction history** — ring buffer (200 records) with TTFT, total time, resolution tracking. Every prediction (accepted/ignored/cancelled/invalidated/rejected) recorded.
- **No animation** — ghost text is static overlay. No flicker, no transitions.
- **Latency is the primary feature.** `CompletionController` measures TTFT and total time for every prediction. `DiagnosticsPanelView` displays averages. `KeybreezeLatencyLogger` writes to stdout.
- **Floating overlay for external apps** — since we can't inject SwiftUI views into third-party app hierarchies, we use a borderless `NSWindow` at `popUpMenu` level. It's transparent, click-through (`ignoresMouseEvents = true`), and positioned via AX cursor rect with multi-tier fallback (see data flow section). The effect is identical to inline ghost text but rendered via AppKit.
- **CRITICAL: overlay must always show when prediction exists** — `SuggestionOverlayWindowController.show()` must NEVER silently bail on invalid cursor rects. If AX cursor rect fails, compute a screen-based fallback. The Combine subscription in `SystemWidePredictor` must NEVER gate overlay display on `lastCursorRect != .zero`. These two gating conditions were the root cause of the ghost overlay being permanently hidden in third-party apps.

---

## Actor Isolation Rules

This codebase uses Swift concurrency with `@MainActor` on all major classes:

| Class | Actor |
|-------|-------|
| `CompletionController` | `@MainActor` |
| `SessionViewModel` | `@MainActor` |
| `AppState` | `@MainActor` |
| `AccessibilityManager` | `@MainActor` |
| `LLMClient` | `@MainActor` (but `onToken` is `@Sendable`) |
| `SystemWidePredictor` | `@MainActor` |
| `SuggestionOverlayWindowController` | `@MainActor` |

### Critical Pattern: Sendable Closure + @MainActor

When `LLMClient.streamCompletion()` calls the `onToken` callback, it's a `@Sendable` closure. To update `@MainActor` published properties from within it:

```swift
// CORRECT:
var localFirstTokenTime: Date?  // local var, not on self
onToken: { token in
    if localFirstTokenTime == nil {
        localFirstTokenTime = now
    }
    accumulatedTokens += token
    Task { @MainActor in
        self?.suggestion = accumulatedTokens  // cross-actor via Task
    }
}

// WRONG — actor-isolation violation:
onToken: { token in
    self.suggestion += token  // ❌ main actor isolated from sendable closure
    self.firstTokenTime = now // ❌ same
}
```

---

## Logging

- `[KeybreezeLatency]` block in stdout: model, TTFT, total time, word count.
- Cancelled runs with no tokens are silent.
- Use `Logger` (`OSLog`) with subsystem `app.keybreeze` for general logging.

---

## Xcode Project

New Swift files must be added to `Keybreeze.xcodeproj` (PBXFileReference, PBXBuildFile, group, Sources phase).

---

## Rules for AI Agents Working on This Codebase

### DO:
- Use `PromptBuilder` for ALL prompt construction. Never inline prompt strings.
- Use `Task { @MainActor in }` to update published properties from within sendable closures.
- Add new model presets as static methods on `ModelOption`.
- Keep latency tracking (TTFT, totalTime) — it drives the diagnostics panel.
- Read this document and `BRIEF.md` before making changes.
- Use `.menu` style for `MenuBarExtra` — never `.window`.
- Pass `.environmentObject(appState).environmentObject(sessionVM)` explicitly to all TypingLab subviews.
- Defer `restoreToAccessory()` to next runloop when called during window teardown.
- When adding overlay positioning logic, convert AX coordinates (top-left origin) to NSScreen coordinates (bottom-left origin).
- Use `orderFrontRegardless()` for overlay windows to avoid stealing focus from the host app.

### DO NOT:
- Create new LLM provider files or protocols — `LLMClient` is the only client.
- Change the menu bar style to `.window`.
- Add animations to ghost text.
- Add conversational or markdown content to prompts.
- Remove Combine subscriptions that sync parameters to the controller.
- Add new files without adding them to the Xcode project.
- Remove latency timing from `CompletionController`.
- Create new singletons — use `AccessibilityManager.shared` and `InputSourceMonitor.shared` only.
- Split `LLMClient` into multiple files — the LLM layer is deliberately thin.
- Remove `@MainActor` from actor-isolated classes.
- Use `kAXValueAttribute` for text insertion (destroys rich text formatting).
- Cancel predictions or touch SessionViewModel in `SettingsWindowController.windowWillClose`.
- Use `Timer.publish` or `onReceive` subscribers that fire during SwiftUI view teardown.
- Call `NSWindow.orderFront()` on overlay windows (use `orderFrontRegardless()` to avoid activation).
- Use `.regular` or `.floating` window level for overlays — `.popUpMenu` keeps it above normal windows.

### When Adding Features:
1. Understand which file owns the responsibility (see File-by-File Reference).
2. If the feature crosses files, identify the data flow path.
3. Ensure `@MainActor` correctness — test with Swift 6 strict concurrency.
4. Add environment objects explicitly — don't rely on implicit inheritance.
5. Update this document and `BRIEF.md` with the new architecture.

---

## Convenience Extensions

- `Array where Element == String` has `.defaultExcluded` and `.defaultManualOnly` backed by `AccessibilityManager` defaults.
- `View.ghostText(draftText:suggestion:correctionState:isSchedulerActive:)` applies the `GhostTextModifier`.