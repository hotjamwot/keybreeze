# Keybreeze — Architecture
Last updated: 26 May 2026

*This document serves as the technical log for Keybreeze. It outlines the application's structure, the engineering decisions made, and the "how" of the project. When you make any changes to the app, please ask the user to test the app first before you update any of the documentation.*

---

## What Keybreeze Is

A macOS menu bar app providing local, low-latency text continuation (autocomplete). Uses Ollama (primary) or llama.cpp (secondary) over HTTP.

**Core promise:** *Create uninterrupted writing flow.*

---

## Data Flow (How Predictions Happen)

```
User types in TextField
  → sessionVM.handleDraftChanged()
    → CompletionController.editorStateChanged()
      → cancelAll()
      → 45ms debounce
        → runPrediction()
          → PromptBuilder.continuationPrompt()
            → Branch on backend:
              • Ollama (raw: false): prompt = context + "\n\nContinue with the next few words only:\n"
              • llama.cpp (raw: true): prompt = context + trailing space (if not already present)
                — No system prompt, no chat template tokens, no instructions
          → LLMClient.streamCompletion(prompt, systemPrompt, model)
            → Branch on backend:
              • Ollama: POST /v1/chat/completions (SSE stream)
                — systemPrompt sent as "system" message in messages array
              • llama.cpp: POST /completion (SSE stream)
                — prompt is bare context text
                — stop tokens: ["<"] (prevents HTML, not \n which kills mid-word output)
                — repeat_penalty sent per-request
            → tokens arrive via onToken closure
            → STREAMING GATE: mid-word shows immediately, between-words waits for full word
              → GhostTextModifier renders grey inline ghost text
```

---

## System-Wide Prediction (External Apps)

### Core Flow

```
User types in external app (e.g. Obsidian, Chrome, TextEdit)
  → SystemWidePredictor (CGEventTap callback)
    → 40ms debounce
      → readAndPredict()
        → accessibility.getTextContext() — reads AX text from focused element
          → 3-tier fallback:
            Tier 1: resolved focused element (deep-nested walk)
            Tier 2: ancestor text container walk (Chromium/Electron)
            Tier 3: raw (non-resolved) focused element
        → resolveCursorRect() — 4-tier fallback for overlay position
        → controller.editorStateChanged()
          → (same prediction flow as above)
    → controller.$suggestion publishes
      → SuggestionOverlayWindowController.show() — floating ghost overlay
```

### AX Text Context Extraction (`AccessibilityManager`)

Three extraction strategies, tried in order:

1. **Direct AXValue + AXSelectedTextRange** — works for native AppKit apps (TextEdit, Notes, Xcode)
2. **Parameterized AXStringForRange** — more reliable in rich editors that expose it
3. **Ancestor text container walk** — walks up the AX tree to find a parent AXTextArea/AXTextField with AXValue. Required for Chromium/Electron apps (Obsidian, VS Code, Chrome)

### Cursor Rect Resolution — 4-Tier Fallback

`SystemWidePredictor.resolveCursorRect()`:

| Tier | Source | When Used |
|------|--------|-----------|
| 1 | AX bounds from TextContext | Embedded cursor rect in AX data |
| 2 | Independent AX BoundsForRange retry | First fetch failed |
| 3 | Cached last-valid rect | Both AX fetches failed |
| 4 | Computed from window geometry | No valid rect ever cached |

### Overlay Window (`SuggestionOverlayWindowController`)

Floating, transparent, borderless NSWindow:
- `.popUpMenu` window level — above normal apps, doesn't steal focus
- `ignoresMouseEvents = true` — click-through to underlying app
- Collects per-display in `GhostTextStyle`
- Coordinate conversion: AX top-left origin → AppKit bottom-left origin via `DisplayCoordinateConverter`

---

## Cotabby-Sourced Components (Frankenstein Convergence)

Four architectural pillars ported from Cotabby to address specific weaknesses. All marked ⚠️ — ported but requiring live testing.

### 1. String Reconciliation (`SuggestionSessionReconciler` + `SuggestionSessionManager`)

**Files:**
- `SuggestionModels.swift` — Core value types: `ActiveSuggestionSession`, `FocusedInputContext`, `SuggestionOverlayGeometry`, `OverlayState`
- `SuggestionSessionReconciler.swift` — Pure state machine: `advanceIfTypedCharactersMatch()`, `reconcile()`, `nextAcceptanceChunk()`
- `SuggestionSessionManager` (in `SessionViewModel.swift`) — Session lifecycle wrapper

**Purpose:** When the user types characters matching the beginning of visible ghost text, we immediately slice and advance the displayed suggestion locally — bypassing the server round-trip entirely.

**How it works:**
1. When a prediction arrives, `SuggestionSessionManager.startSession()` creates an `ActiveSuggestionSession` with the full prediction text and the AX context snapshot.
2. Each keystroke checks `SuggestionSessionReconciler.advanceIfTypedCharactersMatch()` — if the typed characters match the beginning of `remainingText`, we advance `consumedCharacterCount` locally.
3. If the typed characters *don't* match (user diverges), the reconciler returns nil and we let the normal debounce→prediction flow proceed.
4. `reconcile()` handles live AX state vs. session state — detects field switches, text selection, trailing text changes, post-Tab AX lag tolerance.

**Status:** ⚠️ Code ported and integrated. Needs live testing in Typing Lab and system-wide.

### 2. Focus & Geometry Processing (`AXTextGeometryResolver` + `AXHelper` + `DisplayCoordinateConverter`)

**Files:**
- `AXHelper.swift` — Typed wrapper around C-based Accessibility APIs
- `AXTextGeometryResolver.swift` — 6-branch caret resolution pipeline
- `DisplayCoordinateConverter.swift` — Multi-display Y-flip coordinate math

**Purpose:** Fix ghost overlay positioning drift in third-party apps by using robust AX geometry heuristics.

**Caret Resolution Pipeline (6 branches):**
| Branch | Method | Quality | Use Case |
|--------|--------|---------|----------|
| 1 | BoundsForRange(loc, 0) | exact | Native apps with AX support |
| 1.5 | AXTextMarker caret rect | exact | Chromium/WebKit fallback |
| 2 | BoundsForRange(loc-1, 1) shift to trailing edge | derived | Editors supporting char-level bounds |
| 2.5 | Child text-run proportional estimation | derived | Gmail, Outlook (no BoundsForRange) |
| 3 | AXFrame + text-width estimation | estimated | Minimal AX exposure |
| 4 | Window-frame fallback | estimated | No AX geometry available |

**Coordinate Conversion:**`DisplayCoordinateConverter` bridges CoreGraphics (top-left origin, pixel coordinates) to AppKit (bottom-left origin, point coordinates) on a per-display basis, with Retina scaling heuristics.

**Status:** ⚠️ Code ported. Not yet wired into overlay positioning pipeline.

### 3. Queue-Based Text Insertion (`SuggestionInserter` + `InputSuppressionController`)

**Files:**
- `SuggestionInserter.swift` — CGEvent Unicode keyboard synthesis with char-by-char option
- `InputSuppressionController.swift` — Suppression guard for synthetic keystrokes

**Purpose:** Prevent keystroke drops and layout corruption in heavy editors (VSCode, Obsidian) by inserting characters with controlled delays and suppressing recursive event tap triggers.

**How it works:**
1. `InputSuppressionController.registerSyntheticInsertion()` arms a 1-second suppression window
2. `SuggestionInserter.insert()` posts a single CGEvent keyDown/keyUp pair with Unicode string
3. `SuggestionInserter.insertCharacterByCharacter()` posts individual characters with configurable inter-character delay (default 5ms)
4. The event tap in `SystemWidePredictor.installEventTap()` would normally re-trigger on these synthetic events — the suppression controller consumes them silently

**Status:** ⚠️ Code wired into `SystemWidePredictor` init. Suppression not yet integrated into event tap callback.

### 4. Dynamic Gating (`SuggestionAvailabilityEvaluator`)

**File:** `SuggestionAvailabilityEvaluator.swift`

**Purpose:** Centralized, rule-based app gating with terminal detection.

**Current implementation:** `SuggestionAvailabilityEvaluator.disabledReason()` checks:
- Global enabled/disabled toggle
- Disabled bundle IDs (from app gating settings)
- Terminal app detection via `TerminalAppDetector` (hardcoded bundle ID list)
- Input Monitoring permission

**Future extension:** Cotabby's `CustomRulesCatalog` with regex-based matching for URL schemes, terminal modes, and editing scopes.

**Status:** ⚠️ Code ported. Not yet integrated into `SystemWidePredictor`'s gating checks (still uses internal `shouldProcessApp()`).

---

## Backend Lifecycle

### `BackendManager` (`Keybreeze/Core/BackendManager.swift`)
A `@MainActor` class managing the full lifecycle of LLM backend processes.

**Ollama:**
- Health-checks `localhost:11434`. If unreachable, spawns `ollama serve`. Tracks ownership for cleanup.

**llama.cpp:**
- Spawns `llama-server` via `Process()`. Server flags: `--model`, `--host`, `--port`, `--ctx-size 512`, `--threads 4`, `--ubatch-size 256`, `--flash-attn on`, `--no-jinja`.
- Temperature, top_p, and repeat_penalty are set **per-request** via `CompletionController` (not server flags).
- **Streaming:** Uses SSE streaming to the raw `/completion` endpoint.
- **Flag compatibility (v9310):** `--no-chat-template` was removed upstream. Now uses `--no-jinja` to disable the jinja chat template engine.

**Termination:**
- `terminateAllSync()` is the authoritative teardown path (via `AppKitLifecycle.willTerminateNotification`). Never rely on `deinit`.

---

## Prompt Strategy

### `PromptBuilder` (`Keybreeze/LLM/PromptBuilder.swift`)
Two prompt modes, selected automatically by backend:

| Backend | Mode | Prompt Format | System Prompt |
|---------|------|--------------|---------------|
| Ollama | Chat (`raw: false`) | `{context}\n\nContinue with the next few words only:\n` | Sent as system message in messages array |
| llama.cpp | Raw (`raw: true`) | `{context}` + trailing space if not already present | Not sent (`systemPromptOverride` is ignored in raw mode) |

**Why bare text for llama.cpp:** After extensive testing, wrapping prompts in Gemma's `<start_of_turn>` chat template tokens (D12) forced the instruct model into chatbot mode — producing empty mid-word responses, safety refusals ("I'm sorry, I can't..."), and system prompt leakage. Bare text at low temperature with repeat_penalty produces the most likely natural language continuation. A trailing space is appended for mid-word contexts to prevent the model from struggling with partial-word inputs.

### `ModelOption` — Single Source of Truth
**`Keybreeze/Core/ModelOption.swift`** holds all inference parameter defaults:
- `defaultTemperature: 0.1`
- `defaultTopP: 0.85`
- `defaultRepeatPenalty: 1.15`
- `defaultConfidenceThreshold: 0.25`

All components (`CompletionController`, `SessionViewModel`, `AggressionPreset`) reference these static values. No hardcoded defaults elsewhere.

---

## Architecture Rules for AI Agents

### DO:
- Use `PromptBuilder` for ALL prompt construction.
- Reference `ModelOption.default*` for ALL inference parameter defaults — never hardcode.
- Use `Task { @MainActor in }` for cross-actor UI updates.
- Keep ghost text visual constants in `GhostTextStyle` — never duplicate.
- Use `BackendManager` for all process lifecycle.
- Verify binary version support for flags before updating server configurations.
- Use `<` as stop token for llama.cpp: prevents HTML output without killing mid-word completions.
- DO NOT use `\n` as a stop token: it causes empty mid-word outputs (the model hesitates with newlines).
- When implementing AX text extraction, always add a fallback ancestor walk for Chromium/Electron apps.
- When implementing AX geometry resolution, always gate BoundsForRange on the element advertising support via parameterized attribute names.
- Use `SuggestionSessionReconciler` for session management, not ad-hoc string manipulation.
- Use `InputSuppressionController` when posting synthetic keyboard events.

### DO NOT:
- Create new LLM provider files.
- Add animations to ghost text.
- Modify `NSApplication` lifecycle outside of `AppKitLifecycle.swift`.
- Hardcode inference parameter defaults anywhere except `ModelOption`.
- Use `<start_of_turn>` or `[INST]` chat template tokens in llama.cpp prompts.
- Add instructions/commands like "Continue with..." to llama.cpp raw prompts.
- Call `AXBoundsForRange` on elements that don't advertise `AXBoundsForRangeParameterizedAttribute` — it stalls the main thread.

---

## Known Issues

1. **AX getTextContext returns nil for Chromium/Electron apps (Obsidian, VS Code, Chrome):** The ancestor container walk (`findTextContainer`) was added in this session but needs live testing. The resolved focused element in these apps is often a leaf AX node without AXValue.
2. **Overlay positioning drift:** New `AXTextGeometryResolver` and `DisplayCoordinateConverter` are ported but not yet wired into the overlay positioning chain.
3. **Event tap suppression:** `InputSuppressionController` is wired into `SystemWidePredictor` init but the event tap callback doesn't yet check `consumeIfNeeded()`.
4. **SuggestionSessionManager not yet wired:** The `SuggestionSessionManager` class is defined in SessionViewModel.swift but `handleDraftChanged()` still calls the controller directly without checking if the typed characters can be consumed locally first.