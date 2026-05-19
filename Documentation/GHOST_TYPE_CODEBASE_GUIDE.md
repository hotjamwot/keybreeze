# Ghost Type Main — Codebase Guide

**Location:** `/Users/haydenjweal/Movies/PROJECTS/Code/GhostType-main`

A compact (≈1,700 lines total), single-server, macOS menu-bar text-completion app that connects
to any OpenAI-compatible API endpoint (Ollama, LM Studio, llama.cpp running as a server, vLLM, etc.).
It is the "minimal reference" for GhostType's lighter-weight philosophy, compared to Keybreeze's
heavier multi-backend engineering stack.

---

## Directory Layout

```
GhostType/
├── App/
│   ├── AppDelegate.swift          — App lifecycle, status bar, window wiring, key monitor setup
│   ├── GhostTypeApp.swift         — @main, Settings scene, SettingsTab enum, AppSettings, KeyBinding
│   ├── MenuBarView.swift          — SwiftUI menu bar popover (trivial, 36 lines)
│   └── SettingsView.swift         — All settings tabs: Setup / General / Model / Inference / Appearance / Excluded Apps
├── Core/
│   ├── AccessibilityManager.swift  — AX API: reads text context + cursor rect from any focused app; inserts text
│   ├── CompletionController.swift  — Main orchestrator: buffer management, debounce, trigger → engine → overlay
│   ├── CompletionEngine.swift      — Thin inference wrapper: builds FIMRequest, calls LLMClient, trims result
│   ├── GlobalKeyMonitor.swift       — CGEventTap for system-wide keystroke capture; classifies into KeyEvent
│   └── InputSourceMonitor.swift    — TIS input-source tracking; gates auto-trigger on ASCII-only keyboards
├── LLM/
│   └── LLMProvider.swift          — LLMClient (OpenAI Chat Completions API) + FIMRequest + LLMError
├── UI/
│   ├── CompletionPopup.swift      — SwiftUI multi-suggestion popup (not currently wired)
│   └── OverlayWindow.swift      — Borderless NSWindow hosting ghost text near the cursor
└── Resources/
```

---

## Keybreeze ↔ Ghost Type: File-by-File Comparison

| Concern | Keybreeze | Ghost Type | Notes |
|---|---|---|---|
| **LLM provider / inference** | `LLM/LLMProvider.swift` (protocol) + `OllamaLLMService` + `LlamaCppService` (two backends) | `LLM/LLMProvider.swift` (single `LLMClient`, OpenAI-compatible) | Keybreeze has a formal *protocol + two implementations* pattern; Ghost Type combines them into one class. |
| **LLM config** | `LLM/LLMConfiguration.swift` + `OllamaConfiguration` + `LlamaCppConfiguration` | Inline in `AppSettings` (`serverEndpoint`, `modelName`, `maxTokens`, …) | Keybreeze uses typed config structs; Ghost Type uses flat `@Published` properties. |
| **Prompt construction** | `LLM/PromptBuilder.swift` — structured, accepts `ModelOption` + style nudge + custom prompts | Inline string literals in `LLMClient.complete()` and `CompletionEngine` | Keybreeze's is far more sophisticated; Ghost Type uses a simple system/user message pair. |
| **Context / state building** | `Core/ContextBuilder.focusedState(from:)` — trims to ~800 chars | `Core/AccessibilityManager` inline trimming (`maxChars`) | Keybreeze separates context-building; Ghost Type couples it to the AX layer. |
| **Model registry / presets** | `Core/ModelRegistry.swift` — per-model tuning presets mapped by Ollama tag | None — user enters model name manually | Ghost Type has no model-registry concept. |
| **Scheduler / debounce** | `Core/PredictionScheduler.swift` — midType + pause modes | `Core/CompletionController.scheduleAutoTrigger()` — single 300 ms debounce | Keybreeze splits short/fast vs. long/pause modes; Ghost Type has one debounce. |
| **Word cap / truncation** | `Core/WordLimiter` — token-aware word counting | `CompletionEngine` — naive String truncation | Keybreeze has instrumentation for word-quality metrics; Ghost Type is simpler. |
| **Prediction engine / streaming** | `Core/PredictionEngine.swift` — word-cap-aware streaming with latency tracking | `CompletionEngine.swift` — non-streaming single await; flow into `onToken` callback outside | Keybreeze streams tokens; Ghost Type fetches a full response in one call. |
| **Prediction history** | `Core/PredictionHistory.swift` — ring buffer (200 records), TTFT tracking | None | Ghost Type has no history. |
| **Shadow predictor** | `Core/ShadowPredictor.swift` — background quality evals | None | Ghost Type has none. |
| **UI overlay** | `UI/TypingLab/` — rich Typing Lab playground with diagnostics, tuning, history | `UI/OverlayWindow.swift` — simple borderless NSWindow + `UI/CompletionPopup.swift` (unwired) | Keybreeze's is a full IDE overlay; Ghost Type's is a lightweight popup. |
| **Context extraction (AX)** | `Core/AccessibilityManager` (similar but less mature in Ghost Type) | `Core/AccessibilityManager` (single file, 414 lines) | Both have AX context; Ghost Type's is standalone and self-contained. |
| **Keyboard / event tap** | `Core/GlobalKeyMonitor` (similar in both) | `Core/GlobalKeyMonitor.swift` (237 lines) | Architecture is very similar; event-payload structures differ slightly. |
| **Input-source tracking** | None | `Core/InputSourceMonitor.swift` — gates auto-trigger on non-ASCII IME detect | Ghost Type has this explicitly; Keybreeze handles it elsewhere or not yet. |
| **App gating (excluded apps)** | `Core/ModelRegistry` + settings | `AppSettings` — `excludedBundleIDs` + `isExcluded()` + `isManualOnly()` | Ghost Type has a well-specified per-app exclusion and "manual-only" list; Keybreeze does not yet expose this. |
| **Settings UI** | Typing Lab via ObservableObject + SwiftUI | Full SwiftUI `SettingsView` (1,013 lines): Setup, General, Model, Inference, Appearance, Excluded Apps | Ghost Type's is more featureful in the settings UI area. |

---

## Architectural Decision: OpenAI-Compatible Client vs. Custom Protocol

Ghost Type's `LLMClient` (`LLM/LLMProvider.swift:31`) uses the standard **OpenAI Chat Completions API**
(`/v1/chat/completions`) with a plain old `URLSession` + `JSONSerialization`. There is no SDK, no SDK
version lock, no streaming implementation — it is the simplest possible thing that works.

Keybreeze (by comparison) has:
- A **`LLMProvider` protocol** with `streamCompletion(prompt:model:modelOption:onToken:)` + `cancel()`
- **Two concrete providers**: `OllamaLLMService` (SSE streaming over `/api/generate`) and `LlamaCppService`
  (non-streaming `/completion` — chosen because llama.cpp SSE never sends a terminating event,
  which would cause `bytes.lines` to hang forever)
- A **`PredictionEngine`** that enforces word caps on streaming tokens and tracks first-token latency
  for diagnostics

The **takeaway for Keybreeze**: the LLM protocol layer is where the most engineering complexity lives.
Ghost Type sidesteps all of it by using one universal HTTP endpoint. If Keybreeze ever wants to add a
third backend (e.g. a cloud provider) it is already architected to do so via the protocol; Ghost Type
would need only one URL field change. The tradeoff: Ghost Type cannot make use of Ollama-specific or
llama.cpp-specific optimisations (e.g. model pre-loading, health endpoints, GGUF discovery).

---

## Architecture Pattern: Director / Orchestrator

Both apps follow the same *single-threaded, cancellation-aware* pattern:

1. **Event tap/keyboard dispatch** → 2. **Context extraction** → 3. **Prompt construction** →
4. **Scheduled/debounced engine call** → 5. **Cancellation on new keystroke** → 6. **UI overlay**

The key divergence is *where* these concerns live:
- Keybreeze splits them into **7–8 focused files** (`PredictionScheduler` / `PredictionEngine` /
  `PredictionHistory` / `ShadowPredictor` / `WordLimiter` / …)
- Ghost Type condenses them into **2 files** (`CompletionController` and `CompletionEngine`) and keeps
  context/build logic inline in `AccessibilityManager`

---

## Notable Design Patterns in Ghost Type

### 1. Two-strategy AX text extraction (`AccessibilityManager.swift:67`)
`getTextContext(maxChars:)` first tries `AXValue + AXSelectedTextRange` (native apps like TextEdit),
then falls back to `AXStringForRange` (browsers, web views). This two-strategy approach is worth
mirroring in Keybreeze's `AccessibilityManager`.

### 2. Clipboard fallback text insertion (complete with restore)
`AccessibilityManager.insertViaClipboard()` (line 390) saves the existing pasteboard, inserts via
Cmd+V, then restores. Ghost Type silently handles the case where AX-based insertion fails entirely.
Keybreeze has no such fallback path.

### 3. Per-app exclusion with icon detection
`SettingsView.swift:422` — `loadInstalledApps()` scans `/Applications`, `/System/Applications`,
`~/Applications` and uses `NSWorkspace` for both bundle-ID and icon. The exclude/manual-only lists
are driven by this rich picker, not just bundle-ID text strings.

### 4. Self-contained AccessibilityManager (no dependency on the rest of the engine)
Ghost Type's `AccessibilityManager` is a pure `AccessibilityManager` — it does not reference
`CompletionEngine`, `SettingsView`, or any overlay code. It could be extracted into a framework
module easily.

### 5. `InputSourceMonitor` for IME safety
`InputSourceMonitor.swift` fires a notification observer on `kTISNotifySelectedKeyboardInputSourceChanged`
and tracks whether the current source is a plain keyboard layout AND ASCII-capable. Auto-trigger
silently suspends while a non-ASCII IME is active — this prevents Ghost Type from interfering with
Japanese/Chinese/Korean composition. Keybreeze does not yet have an equivalent.

---

## What Keybreeze Can Learn From Ghost Type

1. **Settings completeness** — Ghost Type has 6 fully-functional settings tabs including first-launch
   setup wizard, keyboard re-binding UI, and exclusion lists. Keybreeze's settings are primarily
   reachable from Typing Lab, which is already a robust UI; add an "App gating" panel for bundle-
   ID exclusion lists if not yet present.

2. **IME awareness** — Add an `InputSourceMonitor` equivalent to Keybreeze to guard auto-trigger
   during CJK composition.

3. **AX insertion fallback** — Keybreeze's `AccessibilityManager` should add a clipboard-fallback path
   for `insertText()` so it handles apps where AX value-mutation fails. Ghost Type's implementation
   is production-ready.

4. **Two-strategy text extraction** — Mirror Ghost Type's `getContextViaValue()` + `getContextViaSelectedText()`
   fallback pattern in Keybreeze's context builder for better browser / web-app coverage.

5. **Per-model tuning is the real value add** — Ghost Type has no per-model tuning; Keybreeze's
   `ModelRegistry` with per-model presets is the key differentiating feature. Double down on this.
