# Keybreeze — Live Status

This is the single source of truth for what is currently working, broken, or in progress. It is updated at the end of every development session.

AI agents must read this file before starting any work. Do not assume something is working unless it is marked ✅ here. Do not assume something is not implemented unless it is marked ❌ here.

## Status Key
- ✅ Working — implemented and confirmed working in current build
- ⚠️ Broken — implemented but has known bugs (see notes)
- 🔄 Partial — partially implemented, some cases work
- ❌ Not started — not yet implemented
- 🚫 Blocked — cannot proceed until a dependency is resolved

Last updated: 26 May 2026

## Backends

| # | Backend | Status | Notes |
|---|---------|--------|-------|
| A | Ollama | ✅ | Working end-to-end. Uses chat completions endpoint with system prompt. |
| B | llama.cpp (v9310) | ⚠️ | Server boots with `--no-jinja`. Raw `/completion` endpoint with bare text prompts (no chat template tokens). Mid-word completions still intermittent — the trailing space trick helps but the model hesitates on partial inputs at low temperature. See open issues below. |

## Features

| # | Outcome | Status | Notes |
|---|---------|--------|-------|
| 1 | Invisible ghost text overlay | ⚠️ | Works in Typing Lab; external overlay has positioning quirks. AXTextGeometryResolver + DisplayCoordinateConverter ported but untested. Multi-monitor Y-flip, Chromium AXTextMarker, and child-text-run estimation now in codebase. |
| 2 | Streaming prediction display | ✅ | Streaming works. Context-sensitive gate: mid-word shows immediately, between-words waits for full word or 10+ chars. |
| 3 | Tab accepts word-by-word | ✅ | |
| 4 | Full prediction acceptance (Backtick key) | 🔄 | SuggestionInserter + InputSuppressionController ported and integrated in code. Not yet wired to UI / hotkey. |
| 5 | Prediction invalidation | 🔄 | SuggestionSessionReconciler ported with process-level invalidation. Needs testing against live AX polling to confirm correctness. |
| 6 | Backspace correction | 🔄 | Detection logic and UI wiring exist. Reconciliation state machine can be extended to integrate with correction pipeline (not wired yet). |
| 7 | Corrected word acceptance | ❌ | Correction state UI exists but needs native typing-over-suggestion handling via reconciliation. |
| 8 | Keystroke response < 8ms | ⚠️ | SuggestionSessionManager + SuggestionSessionReconciler provides instant local advancement when typed characters match ghost text — bypassing server round-trips. Code ported but needs live testing. |
| 9 | Prediction appears within 40-140ms | ✅ | Avg TTFT ~60-80ms with llama.cpp + Gemma 4 E2B. |
| 10 | System-wide prediction | ⚠️ | Works, but requires full AX permissions and reliable cursor tracking. |
| 11 | Tab acceptance in external apps | ⚠️ | SuggestionInserter with InputSuppressionController ported for robust keyboard synthesis. Character-by-character insertion available. New code needs testing. |
| 12 | App gating | ⚠️ | Logic exists. SuggestionAvailabilityEvaluator + TerminalAppDetector ported with centralized gating rules. Needs testing. |
| 13 | Stable UI | ⚠️ | Mostly stable, occasional edge-case flicker. |
| 14 | IME safety | ⚠️ | Needs verification with different input sources. |
| 15 | Latency monitoring | ✅ | Implemented with runtime values from SessionViewModel (not ModelOption static defaults). |
| 16 | Acceptance history | ✅ | Implemented, reads from SessionViewModel runtime values. |
| 17 | Dock + Cmd+Tab behavior | ⚠️ | Intermittent ViewBridge errors. |
| 18 | Settings window close stability | 🔄 | Mitigated, still rare intermittency. |
| 19 | Ghost overlay for third-party apps | ⚠️ | AXTextGeometryResolver with 6-branch caret resolution ported. Needs live testing against Chrome, Safari, Obsidian, etc. |

## Known Issues (Post-Session)

1. **Mid-word completions still unreliable**: Gemma 4 E2B at temperature 0.1 struggles with partial-word inputs. The trailing space trick helps but doesn't fully solve it — the model often generates a newline as a "hesitation" token. Potential mitigations:
   - Try temperature 0.0 (as originally specified in D11)
   - Increase n_predict from 20 (maxWords*4) to 40-64 to give the model more room
   - Try a small positive frequency_penalty alongside repeat_penalty

2. **Word repetition at low temperature with repeat_penalty 1.15**: Still needs tuning. The model sometimes echoes the last word or generates "very, very, very..." patterns. 1.15 is an improvement over 1.02 but may need to go to 1.25.

3. **No `\n` stop token causes multi-line predictions**: The model sometimes generates newlines mid-prediction, causing the suggestion to span multiple lines. This is acceptable for now — better than empty outputs — but may want a post-processing filter later.

4. **Diagnostics panel now reads runtime values correctly**: Fixed in this session. Displays the actual session-level values.

---

## Cotabby Architectural Synthesis — Porting Status

### 1. Pure String Reconciliation (`SuggestionSessionReconciler`)
- **Files:** `SuggestionModels.swift`, `SuggestionSessionReconciler.swift`, `SuggestionSessionManager` (in SessionViewModel)
- **Status:** ⚠️ Code ported and integrated. Needs testing against live typing flow.
- **Target Features:** #8 (instant local advancement), #6 (backspace correction), #7 (corrected word acceptance)

### 2. Focus & Geometry Processing (`AXTextGeometryResolver`, `DisplayCoordinateConverter`, `AXHelper`)
- **Files:** `AXHelper.swift`, `AXTextGeometryResolver.swift`, `DisplayCoordinateConverter.swift`
- **Status:** ⚠️ Code ported. Needs integration into `SystemWidePredictor`'s cursor rect resolution and overlay positioning.
- **Target Features:** #1 (overlay positioning), #5 (prediction invalidation via cursor tracking)

### 3. Queue-Based Text Insertion (`SuggestionInserter`, `InputSuppressionController`)
- **Files:** `InputSuppressionController.swift`, `SuggestionInserter.swift`
- **Status:** ⚠️ Code ported and wired into `SystemWidePredictor`. Needs testing in heavy editors (VSCode, Obsidian).
- **Target Features:** #11 (Tab acceptance in external apps), #4 (full acceptance)

### 4. Dynamic Gating (`SuggestionAvailabilityEvaluator`, `TerminalAppDetector`)
- **Files:** `SuggestionAvailabilityEvaluator.swift`
- **Status:** ⚠️ Code ported. Needs integration into existing gating pipeline.
- **Target Features:** #12 (app gating)