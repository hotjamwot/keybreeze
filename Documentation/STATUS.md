# Keybreeze — Live Status

This is the single source of truth for what is currently working, broken, or in progress. It is updated at the end of every development session.

AI agents must read this file before starting any work. Do not assume something is working unless it is marked ✅ here. Do not assume something is not implemented unless it is marked ❌ here.

## Status Key
- ✅ Working — implemented and confirmed working in current build
- ⚠️ Broken — implemented but has known bugs (see notes)
- 🔄 Partial — partially implemented, some cases work
- ❌ Not started — not yet implemented
- 🚫 Blocked — cannot proceed until a dependency is resolved
- 🎯 Planned — clear integration plan exists (see ACTIVE TASKS below)

Last updated: 1 June 2026

---

## Backends

| # | Backend | Status | Notes |
|---|---------|--------|-------|
| A | Ollama | ✅ | Working end-to-end. Uses chat completions endpoint with system prompt. |
| B | llama.cpp (v9310) | ⚠️ | Server boots with `--no-jinja`. Raw `/completion` endpoint with bare text prompts. Mid-word completions still intermittent. |

## Features

| # | Outcome | Status | Notes |
|---|---------|--------|-------|
| 1 | Invisible ghost text overlay | ⚠️ | Works in Typing Lab; external overlay now has position stabilization (8pt deadzone prevents jumping). AXTextGeometryResolver wired (TASK 4) — needs testing in Chromium/Electron apps. |
| 2 | Streaming prediction display | ✅ | Context-sensitive gate: mid-word shows immediately, between-words waits for full word or 10+ chars. |
| 3 | Tab accepts word-by-word | ✅ | |
| 4 | Full prediction acceptance (Backtick key) | ⚠️ | SuggestionInserter + InputSuppressionController wired into event tap (TASK 2). Needs end-to-end testing. |
| 5 | Prediction invalidation | ✅ | SuggestionSessionReconciler wired into readAndPredict flow. Session reset on app switch, cursor move, focus loss. |
| 6 | Backspace correction | 🔄 | Reconciler wired (TASK 1). Backspace detection in SessionViewModel ready. Needs testing. |
| 7 | Corrected word acceptance | 🔄 | Depends on reconciler (wired). Needs testing. |
| 8 | Keystroke response < 8ms | ✅ | SuggestionSessionManager + Reconciler wired. Local advancement skips server round-trip when user types matching ghost text. |
| 9 | Prediction appears within 40-140ms | ✅ | Avg TTFT ~60-80ms with llama.cpp + Gemma 4 E2B. |
| 10 | System-wide prediction | ⚠️ | Works, but requires full AX permissions and reliable cursor tracking. |
| 11 | Tab acceptance in external apps | ⚠️ | InputSuppressionController wired into event tap (TASK 2). Synthetic keystrokes now suppressed. Needs end-to-end testing. |
| 12 | App gating | ✅ | SuggestionAvailabilityEvaluator wired into shouldProcessApp(). Terminal detection active (Slack removed from terminal list). |
| 13 | Stable UI | ⚠️ | Mostly stable, occasional edge-case flicker. |
| 14 | IME safety | ⚠️ | Needs verification with different input sources. |
| 15 | Latency monitoring | ✅ | |
| 16 | Acceptance history | ✅ | |
| 17 | Dock + Cmd+Tab behavior | ⚠️ | Intermittent ViewBridge errors. |
| 18 | Settings window close stability | 🔄 | Mitigated, still rare intermittency. |
| 19 | Ghost overlay for third-party apps | ⚠️ | AXTextGeometryResolver wired into resolveCursorRect(). 6-branch resolver tries first, falls back to 4-tier chain. Position stabilization added (8pt deadzone). Needs testing in Chromium/Electron apps. |
| 20 | Post-generation candidate filtering | ✅ | filterSuggestion() strips multi-line, garbage chars, HTML tags, duplicate after-cursor text, excessively long predictions, pure numbers ("2", "100%"), and single-character junk. |
| 21 | Prompt sectioning (after-cursor context) | ✅ | PromptBuilder.continuationPrompt() now accepts textAfterCursor. Raw mode: appends `[AFTER:text]` bracket marker. Chat mode: adds explicit "do not repeat" instruction. Prevents model from generating duplicate content. |
| 22 | Per-app compatibility overrides | ✅ | Data-driven TargetOverride table in AppCompatibility.swift. Suppresses terminals (6), code editors (13, VSCode excluded per user request), password managers (5), system utilities (5). Flags pasteboard insertion for web surfaces (7) and messaging (6). Wired into shouldProcessApp(). |
| 23 | Sectioned/budgeted prompting (D19) | ✅ | PromptBuilder restructured with named sections (completionInstructions, generalInfo, afterCursor, styleNudge, customInstructions, beforeCursor), each with priority and min/max token budgets. `beforeCursor` always last for natural continuation. Trailing whitespace trimmed to prevent double-space artifacts. Token budget enforced via ~4 chars/token approximation within 2048 token limit. Per-app environment context gating strips app metadata for code editors/terminals. |
| 24 | NSPanel overlay (non-activating) | ✅ | Overlay switched from NSWindow to NSPanel with `.nonactivatingPanel` style mask. Panel never activates Keybreeze or steals focus from the host app. Matches KeyType's GhostTextOverlayWindow recipe (D19). |
| 25 | Caret-height font resolution | ✅ | `resolveFont()` sizes the field's typeface from the caret height rather than hardcoded 14pt. Reads AX font family, applies per-app `fontSizeAdjustmentFactor`. Trusted caret height clamping prevents oversized AX rects. Falls back to system font estimation (D19). |
| 26 | Per-app overlay tuning (D19) | ✅ | `TargetOverride` extended with `overlayPreference` (inline/textMirror/hidden), `fontSizeAdjustmentFactor`, `verticalAlignmentOffset`. Public API: `overlayPreference(for:)`, `fontSizeAdjustmentFactor(for:)`, `verticalAlignmentOffset(for:)`. Per-app preferences applied in overlay `show()` calls (D19). |
| 27 | Per-app custom prompt instructions | ✅ | `AppCompatibility.customPromptSuffix()` wired into `PromptBuilder.continuationPrompt()` via `CompletionController`. Per-app instructions appear as a section in the prompt (D19). |

---

## Known Issues

1. **Mid-word completions still unreliable**: Gemma 4 E2B at temperature 0.1 struggles with partial-word inputs. The trailing space trick helps but doesn't fully solve it.
2. **Word repetition at low temperature with repeat_penalty 1.15**: May need to go to 1.25.
2a. **Duplication of after-cursor text**: Mitigated by TASK 7 (after-cursor context in prompt) and TASK 6 (post-generation filtering). Model now receives `[AFTER:text]` bracket marker in raw mode. Still acceptable as a known model limitation — may need tuning per model.
3. **No `\n` stop token causes multi-line predictions**: Mitigated by post-generation filtering (TASK 6) — newlines are now truncated before display. Still acceptable as a known model limitation.

---

## ACTIVE TASKS — Wire Ported Components (Tier 1)

These are the four highest-ROI tasks. All code already exists in the codebase — it just needs to be connected. Each task is self-contained and can be done independently.

---

### TASK 1: Wire SuggestionSessionReconciler into the prediction flow

**Goal:** When the user types characters that match the beginning of the visible ghost text, advance the session locally — providing instant response without waiting for a server round-trip. This cuts redundant LLM requests by ~60-80%.

**Why it matters:** Currently, every keystroke triggers a full debounce → LLM request cycle, even when the user is just typing the exact text that Keybreeze already predicted. The reconciler detects this and skips the server call.

**Files involved:**
- `Keybreeze/UI/SessionViewModel.swift` — Contains `SuggestionSessionManager` (lines 13-85). This class already has `advanceWithTypedCharacters(_:)` which calls `SuggestionSessionReconciler.advanceIfTypedCharactersMatch()`. It returns `true` if the typed characters matched and the session was advanced locally.
- `Keybreeze/Core/SystemWidePredictor.swift` — The `readAndPredict()` method (line 266) is where text changes are detected and fed to the controller. This is where the reconciler check should be inserted.
- `Keybreeze/Core/SuggestionSessionReconciler.swift` — The pure reconciliation logic. Already complete.
- `Keybreeze/Core/SuggestionModels.swift` — Value types (`ActiveSuggestionSession`, `FocusedInputContext`, etc.). Already complete.

**Exact integration steps:**

1. **In `SystemWidePredictor`, add a `SuggestionSessionManager` property:**
   - Add `private let sessionManager = SuggestionSessionManager()` to the class properties (near line 31).

2. **In `SystemWidePredictor.readAndPredict()`, BEFORE the `controller.editorStateChanged()` call at line 366:**
   - After the "Check for meaningful change" guard (line 345), and after `lastTextBeforeCursor` is updated (line 360):
   - Check if the typed characters match the active session:
     ```swift
     // Try to advance the session locally before hitting the server.
     let typedDelta = String(context.prefix.dropLast(lastTextBeforeCursor.count))
     if !typedDelta.isEmpty, sessionManager.advanceWithTypedCharacters(typedDelta) {
         // Session advanced locally — update overlay, skip server request.
         log.debug("Reconciler: advanced session locally for typed delta '\(typedDelta)'")
         if sessionManager.isExhausted {
             self.controller.suggestion = ""
             self.overlay.hide()
         } else {
             self.controller.suggestion = sessionManager.visibleSuggestion
             self.overlay.show(text: sessionManager.visibleSuggestion, at: self.lastCursorRect)
         }
         lastTextBeforeCursor = context.prefix
         lastTextAfterCursor = context.suffix
         return
     }
     ```

3. **When a new prediction arrives from the controller, start a session:**
   - In the `controller.$suggestion` sink (line 119), when a non-empty suggestion arrives, start a session:
     ```swift
     if suggestion.isEmpty {
         self.sessionManager.reset()
         self.overlay.hide()
     } else {
         self.sessionManager.startSession(
             with: suggestion,
             baseContext: FocusedInputContext(
                 caretRect: self.lastCursorRect,
                 // ... other fields from the current AX context
             ),
             latency: 0
         )
         self.overlay.show(text: suggestion, at: self.lastCursorRect)
     }
     ```

4. **Reset the session on app switch, focus loss, or cursor movement:**
   - In the app-switch detection (line 308), add `sessionManager.reset()`.
   - In `handleNoFocus()` (line 512), add `sessionManager.reset()`.
   - In the cursor-moved invalidation (line 349), add `sessionManager.reset()`.

**Testing:** Type text in an external app (e.g., TextEdit). When Keybreeze shows a ghost suggestion, keep typing the exact suggested text. The overlay should advance character-by-character without any flicker or server round-trip. The "Predicting..." status should NOT appear during local advancement.

---

### TASK 2: Wire InputSuppressionController into the event tap

**Goal:** Prevent synthetic keyboard events (from SuggestionInserter) from being captured by the CGEventTap and triggering infinite prediction loops.

**Why it matters:** When Keybreeze inserts text via keyboard synthesis, the event tap sees those keystrokes as real user input and triggers a new prediction. This can cause infinite loops or double-insertion.

**Files involved:**
- `Keybreeze/Core/SystemWidePredictor.swift` — The `installEventTap()` method (line 199) and `handleKeyDown()` (line 235). The event tap callback is defined at line 202.
- `Keybreeze/Core/InputSuppressionController.swift` — Has `consumeIfNeeded() -> Bool` which returns `true` if the event should be suppressed (it's a synthetic keystroke from our inserter).
- `Keybreeze/Core/SuggestionInserter.swift` — Calls `suppressionController.registerSyntheticInsertion()` before posting events.

**Exact integration steps:**

1. **In the event tap callback (line 202-211), add suppression check:**
   - The callback currently calls `predictor.handleKeyDown()` unconditionally. Change it to:
     ```swift
     let callback: CGEventTapCallBack = { proxy, type, event, refcon in
         guard type == .keyDown,
               let refcon else {
             return Unmanaged.passUnretained(event)
         }
         let predictor = Unmanaged<SystemWidePredictor>.fromOpaque(refcon).takeUnretainedValue()
         // If this event is a synthetic keystroke from our inserter, suppress it.
         if predictor.suppressionController.consumeIfNeeded() {
             return nil  // Consume the event — don't let it through to the app.
         }
         predictor.handleKeyDown()
         return Unmanaged.passUnretained(event)
     }
     ```

2. **Make `suppressionController` accessible from the callback:**
   - It's already a `private let` property. The callback accesses it via `predictor.suppressionController`. Since `SystemWidePredictor` is `@MainActor`, you may need to make `suppressionController` non-private or add a public accessor. The simplest fix: change `private let suppressionController` to `let suppressionController` (or `internal let`).

**Testing:** Accept a suggestion in an external app (via Backtick key). The text should insert without triggering a new prediction cycle. The overlay should update cleanly.

---

### TASK 3: Wire SuggestionAvailabilityEvaluator into app gating

**Goal:** Replace the ad-hoc `shouldProcessApp()` method with the centralized, extensible `SuggestionAvailabilityEvaluator`.

**Why it matters:** The current `shouldProcessApp()` only checks the excluded/manualOnly lists. The evaluator adds terminal detection, permission checks, and URL scheme gating. It also provides a clean API for future per-app overrides (Tier 2).

**Files involved:**
- `Keybreeze/Core/SystemWidePredictor.swift` — The `shouldProcessApp(_:)` method (line 491) and `shouldProcessCurrentApp()` (line 462).
- `Keybreeze/Core/SuggestionAvailabilityEvaluator.swift` — The `disabledReason()` and `shouldSchedulePrediction()` static methods.

**Exact integration steps:**

1. **Replace `shouldProcessApp(_:)` with evaluator call:**
   - The current method (line 491-508) checks excludedBundleIDs, manualOnlyBundleIDs, and Keybreeze itself. Replace the body:
     ```swift
     private func shouldProcessApp(_ bundleID: String) -> Bool {
         if bundleID == "app.keybreeze.Keybreeze" {
             setPaused(reason: "Keybreeze focused")
             return false
         }
         
         if let reason = SuggestionAvailabilityEvaluator.disabledReason(
             globallyEnabled: true,
             disabledAppBundleIdentifiers: Set(excludedBundleIDs),
             inputMonitoringGranted: true,  // TODO: wire real permission state
             bundleIdentifier: bundleID,
             applicationName: appName(for: bundleID) ?? bundleID
         ) {
             setPaused(reason: reason)
             return false
         }
         
         // Keep manual-only check as a Keybreeze-specific override
         if manualOnlyBundleIDs.contains(bundleID) && !predictInManualOnly {
             setPaused(reason: "Manual-only app")
             return false
         }
         
         return true
     }
     ```

2. **Expand `TerminalAppDetector.terminalBundleIdentifiers`:**
   - The current list (line 61-79) includes Slack as a terminal app, which is wrong. Remove `"com.tinyspeck.slackmacgap"` from the terminal list and add it to a separate messaging apps list or handle it via per-app overrides (Tier 2).

**Testing:** Open Terminal.app — Keybreeze should show "Keybreeze is not available in terminal apps" in the pause reason. Open a normal text editor — predictions should work normally.

---

### TASK 4: Wire AXTextGeometryResolver into overlay positioning

**Goal:** Replace the basic 4-tier cursor rect fallback with the sophisticated 6-branch caret resolution pipeline from the ported geometry resolver.

**Why it matters:** The current 4-tier fallback often fails in Chromium/Electron apps (Obsidian, VS Code, Chrome) because the AX cursor rect is nil. The ported resolver has 6 branches including text-marker ranges, child-text-run estimation, and proportional estimation — it works across many more apps.

**Files involved:**
- `Keybreeze/Core/SystemWidePredictor.swift` — The `resolveCursorRect(from:)` method (line 374) and `computeFallbackCursorRect()` (line 403).
- `Keybreeze/Utils/AXTextGeometryResolver.swift` — The ported 6-branch resolver. Has `resolveCaretGeometry(for:)` which returns a `CaretGeometry?` with `CGRect` and quality info.
- `Keybreeze/Utils/AXHelper.swift` — Low-level AX helpers used by the resolver.
- `Keybreeze/Utils/DisplayCoordinateConverter.swift` — Converts AX coordinates to AppKit coordinates.

**Exact integration steps:**

1. **Replace `resolveCursorRect(from:)` with resolver call:**
   - The current method (line 374-398) uses a 4-tier chain. Replace with:
     ```swift
     private func resolveCursorRect(from context: TextContext) {
         // Try the ported 6-branch resolver first.
         if let focusedElement = accessibility.focusedAXElement(),
            let geometry = geometryResolver.resolveCaretGeometry(for: focusedElement) {
             let rect = DisplayCoordinateConverter.convertToAppKit(geometry.caretRect)
             log.debug("Cursor rect: Resolver branch \(geometry.quality) — (\(rect.origin.x), \(rect.origin.y), \(rect.size.width)x\(rect.size.height))")
             lastCursorRect = rect
             lastValidCursorRect = rect
             return
         }
         
         // Fallback to the existing 4-tier chain.
         let axCursorRect = context.cursorRect
         if axCursorRect.width >= 0, axCursorRect.height > 0 {
             lastCursorRect = axCursorRect
             lastValidCursorRect = axCursorRect
         } else if let independentRect = accessibility.getCursorRect(),
                   independentRect.width >= 0, independentRect.height > 0 {
             lastCursorRect = independentRect
             lastValidCursorRect = independentRect
         } else if lastValidCursorRect != .zero {
             lastCursorRect = lastValidCursorRect
         } else {
             lastCursorRect = computeFallbackCursorRect()
         }
     }
     ```

2. **Check `AXTextGeometryResolver` API:**
   - Read `Keybreeze/Utils/AXTextGeometryResolver.swift` to confirm the exact method signature for `resolveCaretGeometry(for:)` and what it returns. The integration above assumes it takes an `AXUIElement` and returns `CaretGeometry?` with a `caretRect: CGRect` and `quality: String`.
   - If the API is different, adapt the integration accordingly.

**Testing:** Open Chrome, navigate to a text field (e.g., Gmail compose), and type. The ghost text should appear at the correct cursor position. Previously it would drift or not appear at all.

---

## FUTURE TASKS (Tier 2 — not started)

These are documented in COMPETITIVE_COMPARISON.md Section 13, Tier 2. Do not start these until Tier 1 tasks are complete and tested.

### TASK 5: Add per-app compatibility overrides (data-driven) ✅
- **Status:** ✅ Implemented. `AppCompatibility.swift` provides a `TargetOverride` struct with 4 fields (`predictionEnabled`, `environmentContextDisabled`, `usePasteboardInsertion`, `customPromptSuffix`) and a data-driven override table covering 40+ apps across 6 categories. Wired into `SystemWidePredictor.shouldProcessApp()` — suppresses terminals, code editors, password managers, system utilities. `usePasteboardInsertion` and `environmentContextDisabled` flags are data-ready for future inserter/prompt builder wiring.

### TASK 6: Add post-generation candidate filtering ✅
- **Status:** ✅ Implemented. `CompletionController.filterSuggestion()` is a `nonisolated static` method with 8 filter stages: (1) multi-line truncation, (2) garbage character + HTML stripping, (3) empty check, (4) word count guard, (5) duplicate after-cursor prefix stripping, (6) punctuation/ellipsis rejection, (7) pure number/numeric garbage rejection, (8) single-character junk rejection. Wired into the streaming gate in `onToken` closure.

### TASK 7: Add basic prompt sectioning ✅
- **Status:** ✅ Implemented. `PromptBuilder.continuationPrompt()` now accepts `textAfterCursor` parameter. Raw mode (llama.cpp): appends `[AFTER:{text}]` bracket marker so the model sees full context and predicts bridge text instead of duplicating. Chat mode (Ollama): adds explicit instruction "Do not repeat or include the text after the cursor." `CompletionController.runPrediction()` passes `state.textAfterCursor` to the prompt builder. Build verified.

### TASK 8: Add a prediction log
- Write every generation result and acceptance status to `~/Library/Application Support/Keybreeze/Logs/predictions.log`.
- Reference: KeyType `KeyType/Logic/Telemetry/PredictionLog.swift`.

---

## Cotabby Porting Status (from D17)

All four ported subsystems have been **wired into the active code paths** as of 31 May 2026. ✅

### 1. Pure String Reconciliation (`SuggestionSessionReconciler`)
- **Files:** `Keybreeze/Core/SuggestionModels.swift`, `Keybreeze/Core/SuggestionSessionReconciler.swift`, `SuggestionSessionManager` (in `SessionViewModel.swift`)
- **Status:** ✅ Wired. `SuggestionSessionManager` added to `SystemWidePredictor`. Local advancement fires in `readAndPredict()` before server calls. Session lifecycle managed (start on new prediction, reset on app switch/cursor move/focus loss).
- **Target Features:** #8 (instant local advancement), #6 (backspace correction), #7 (corrected word acceptance)

### 2. Focus & Geometry Processing (`AXTextGeometryResolver`, `DisplayCoordinateConverter`, `AXHelper`)
- **Files:** `Keybreeze/Utils/AXHelper.swift`, `Keybreeze/Utils/AXTextGeometryResolver.swift`, `Keybreeze/Utils/DisplayCoordinateConverter.swift`
- **Status:** ✅ Wired. `resolveCursorRect()` now tries the 6-branch resolver first via `resolveFocusedAXElement()`, then falls back to the 4-tier chain.
- **Target Features:** #1 (overlay positioning), #19 (ghost overlay for third-party apps)

### 3. Queue-Based Text Insertion (`SuggestionInserter`, `InputSuppressionController`)
- **Files:** `Keybreeze/Core/InputSuppressionController.swift`, `Keybreeze/Core/SuggestionInserter.swift`
- **Status:** ✅ Wired. Event tap callback now checks `suppressionController.consumeIfNeeded()` — synthetic keystrokes from the inserter are consumed and don't trigger prediction loops.
- **Target Features:** #11 (Tab acceptance in external apps), #4 (full acceptance)

### 4. Dynamic Gating (`SuggestionAvailabilityEvaluator`, `TerminalAppDetector`)
- **Files:** `Keybreeze/Core/SuggestionAvailabilityEvaluator.swift`
- **Status:** ✅ Wired. `shouldProcessApp()` now delegates to `SuggestionAvailabilityEvaluator.disabledReason()`. Slack removed from terminal list.
- **Target Features:** #12 (app gating)
