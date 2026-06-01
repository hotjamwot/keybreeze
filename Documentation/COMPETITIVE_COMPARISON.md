# Keybreeze vs. KeyType: Competitive Analysis
*Last updated: 1 June 2026*

This document compares Keybreeze against KeyType — the two open-source macOS menu-bar apps most relevant to Keybreeze's development. It covers architecture, generation strategy, context capture, prompting, UX, and identifies where Keybreeze is strong, where it's behind, and the highest-leverage improvements to adopt.

*Cotabby was previously included in this comparison but has been removed. While Cotabby has good architectural patterns (and Keybreeze already ported 4 of its components in D17), it is less mature than KeyType and lacks KeyType's constrained generation, per-app compatibility, and KV cache optimization. KeyType is the stronger reference implementation.*

---

## 1. Product Identity

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Tagline** | Local-first cognitive flow amplifier | Open-source, on-device, system-wide tab-autocomplete |
| **License** | Proprietary (TBD) | MIT |
| **Status** | Active development (beta) | Shipping (mature, 50+ ADRs) |
| **Install** | Build from Xcode | DMG from GitHub Releases |
| **Min macOS** | Not specified | 14.0+ |
| **Unique pitch** | Latency-first, thin-client to external LLM servers | Constrained multi-branch generation + per-app intelligence |

---

## 2. Architecture & Design Philosophy

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Primary paradigm** | Centrally coordinated ViewModel/Controller with singletons | Modular SwiftPM packages with protocol-based contracts |
| **Object lifecycle** | Self-managed singletons (`AccessibilityManager.shared`) | Module graph wired in single `KeyTypeModuleGraph.swift` |
| **Testability** | Difficult (tightly coupled to `.shared` accessors) | High (each package individually testable, `StubModelRuntime`) |
| **Code organization** | Flat: `App/`, `Core/`, `LLM/`, `UI/`, `Utils/` | Package-per-responsibility (10 local SwiftPM packages) |
| **Documentation** | ARCHITECTURE.md, BRIEF.md, BEHAVIOR.md | 9 detailed docs (00–08), 50+ ADRs in decisions log |

### Key Insight
KeyType has the most mature and maintainable architecture. Its package-per-responsibility approach means each concern (context capture, prompting, generation, UI, insertion) can be developed, tested, and reasoned about independently. Keybreeze's singleton-based approach is simpler to start with but harder to test and evolve.

---

## 3. LLM Backend Strategy

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Runtime model** | **Process-based thin client** — spawns Ollama or llama.cpp server processes | **In-process** — llama.cpp prebuilt xcframework |
| **Primary backend** | Ollama (HTTP `/v1/chat/completions`) | llama.cpp xcframework (direct GGUF loading) |
| **Secondary backend** | llama.cpp server (HTTP `/completion`) | N/A (single runtime) |
| **Model management** | User installs Ollama/llama.cpp externally | In-app model download + ACPF profile generation |
| **Model options** | Any model Ollama/llama.cpp supports | Curated GGUFs with per-model token profiles |
| **KV cache optimization** | ❌ None (full re-prefill per request) | ✅ Sophisticated — append-only reuse, snapshot/restore per branch, 12× cold→warm |
| **CPU/GPU footprint** | Low when idle (process sleeps), spikes on request | Lowest per-keystroke (KV reuse, batched beam decoding) |

### Key Insight
Keybreeze's process-based approach is its **biggest architectural advantage for lightweight operation** — no C++ compilation, no in-process model memory, no xcframework linking. The tradeoff is that Ollama/llama.cpp must be installed separately, and there's no KV cache optimization across requests. KeyType's in-process approach with KV reuse gives the best latency but requires more infrastructure.

---

## 4. Generation Quality & Decoding

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Generation strategy** | Single-pass greedy streaming via HTTP | **Multi-branch constrained beam search** |
| **Constrained decoding** | ❌ None — raw LLM output | ✅ Trie admissibility, required-prefix enforcement, logit masking |
| **Fill-in-the-middle (FIM)** | ❌ | ✅ Native FIM tokens with prefix/suffix windowing |
| **Typo guard** | ❌ | ✅ `CurrentWordTypoGuard` — drops misspelled branches mid-search |
| **Sentence boundary** | ❌ (uses `<` stop token) | ✅ Context-aware (`1.`/`Mr.`/`e.g.` don't truncate) |
| **Suffix reranking** | ❌ | ✅ Round-trip join score for mid-line candidates |
| **Mid-word charset guard** | ❌ | ✅ Drops branches with garbage symbols in open words |
| **Candidate filtering** | Basic (word cap, confidence threshold) | Sophisticated (`SuppressionReason` taxonomy, 10+ filter types) |
| **Output control** | Stop token `<` for llama.cpp, word cap | Max 4 tokens default, display-width limit, required-prefix bytes |
| **Streaming** | ✅ SSE streaming with mid-word/between-word gate | ❌ Non-streaming (batch decode, returns after full generation) |

### Key Insight
KeyType's constrained generation is its **killer feature**. By controlling the decoding process at the token level (trie admissibility, typo guards, sentence boundaries, FIM), it produces much higher-quality completions from the same small models. Keybreeze relies on raw LLM output filtered post-hoc, which means more suppression and less precise completions. However, Keybreeze's streaming approach gives a more responsive feel (mid-word suggestions appear immediately).

---

## 5. Context Capture & Accessibility

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Architecture** | Unified `AccessibilityManager` (single file) | `AccessibilityContextTracker` (AX-notification-driven) + `FocusedFieldReader` |
| **Focus detection** | CGEventTap + idle polling (500ms) | AX-notification-driven with low-frequency safety poll |
| **Text extraction** | 3-tier fallback (direct, parameterized, ancestor walk) | Full `TextFieldContext` (before/after cursor, selection, caret rect, EOL, RTL, app, window, domain, labels, language) |
| **Caret resolution** | 6-branch resolver + 4-tier fallback (AXTextGeometryResolver wired) | Ported `AXCaretGeometryResolver` from Red Dot — multi-branch with quality ranking (exact/derived/estimated) |
| **Chromium/Electron** | Ancestor container walk (needs testing) | Supported with browser web-area focus resolution |
| **Web fields (Google Docs etc.)** | Limited | Text-mirror/multiline fallbacks (ADR-029) |
| **Secure field exclusion** | Basic | Per-app `secureFieldExclusion` in `TargetOverride` |

### Key Insight
KeyType's AX-notification-driven approach is the most efficient (avoids polling overhead). Keybreeze's unified `AccessibilityManager` is simpler but mixes concerns. The ported `AXTextGeometryResolver` from Cotabby brings Keybreeze closer to KeyType's capability.

---

## 6. Prompting Strategy

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Prompt structure** | Sectioned: context + after-cursor context + instruction suffix (✅ after-cursor added) | **Sectioned/budgeted** — 9 named sections with priority/min/max token budgets |
| **Tokenizer-backed budgeting** | ❌ (character-based word cap) | ✅ Real tokenizer counts via `ModelRuntime` |
| **Base vs. chat** | Branches per backend (raw for llama.cpp, chat for Ollama) | Base continuation (default) + ChatML fallback |
| **Caret-boundary sanitization** | ❌ | ✅ Trims trailing whitespace, reconciles leading separator |
| **Per-app prompt gating** | ❌ | ✅ `environmentContextDisabled` for code editors/terminals |
| **Personalization** | ❌ | ✅ Local writing history samples in prompt |
| **Custom instructions** | ❌ | ✅ Global + per-app/per-domain |

### Key Insight
KeyType's prompting is dramatically more sophisticated. The sectioned budgeted approach ensures the model gets the right context within its token budget, and per-app gating prevents code-editor metadata from biasing prose predictions. Keybreeze's simple prompting works but misses significant quality gains from context engineering.

---

## 7. Suggestion Reconciliation & Acceptance

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Reconciliation** | `SuggestionSessionReconciler` ✅ wired — local advancement skips server round-trip | N/A (short completions, different model) |
| **Acceptance key** | Tab (word-by-word), Backtick (full) | Tab (word-by-word), Shift+Tab (full string) |
| **Partial acceptance** | Planned (reconciler supports it) | Not needed (completions are short) |

### Key Insight
Keybreeze's reconciler (ported from Cotabby) enables a UX that KeyType doesn't need — partial acceptance of longer predictions. This is a genuine advantage when using larger models via Ollama.

---

## 8. Text Insertion

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Strategy** | CGEvent Unicode synthesis (char-by-char with delay) | **Pasteboard-based** with save/restore + ⌘V/paste-and-match-style |
| **Input suppression** | `InputSuppressionController` ✅ wired into event tap — synthetic keystrokes consumed | Tagged synthetic events so key taps ignore them |
| **Per-app workarounds** | ❌ | ✅ Paste-and-match-style, NBSP workaround, chunked injection, backspace-after-paste |
| **Clipboard safety** | N/A | ✅ Save/restore pasteboard around insertion |

### Key Insight
KeyType's pasteboard-based approach with save/restore is more reliable across apps than keyboard event synthesis. KeyType's per-app workarounds are essential for apps like WeChat, Google Docs, and terminals.

---

## 9. App Compatibility & Gating

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Approach** | Basic bundle ID list + terminal detection | **Data-driven `TargetOverride` table** with 15+ fields per target |
| **Per-app rules** | Disabled apps list | Comprehensive seed table (terminals, password managers, code editors, web surfaces) |
| **Overlay tuning** | Fixed (`.popUpMenu` level) | Per-app: `.inline` / `.textMirror` / `.hidden` + font size adjustment |
| **Insertion tuning** | ❌ | Per-app: chunk size, NBSP, paste-and-match, backspace-after-paste |
| **Prompt tuning** | ❌ | Per-app custom instructions + environment context gating |
| **Domain overrides** | ❌ | ✅ Browser domain matching (works across Chrome/Safari/Arc) |

### Key Insight
KeyType's data-driven per-app compatibility is essential for a system-wide tool. Different apps have wildly different behaviors for paste, Tab, overlay positioning, and text field capabilities. Keybreeze's current basic gating will cause issues in real-world use.

---

## 10. Testing & Quality Assurance

| Dimension | Keybreeze | KeyType |
|:---|:---|:---|
| **Test coverage** | ❌ No tests visible | ✅ Tests per package + release-build benchmarks |
| **Observability** | Basic latency logging | Comprehensive prediction log (every generation, acceptance, suppression reason) |
| **Debug tools** | Typing Lab (diagnostics panel) | Prediction log + caret debug overlay + quality playbook |

### Key Insight
KeyType's prediction log and quality playbook are invaluable for iterating on completion quality. Knowing *why* a suggestion was suppressed or accepted is critical for tuning.

---

## 11. Unique Strengths

### Keybreeze Strengths 🟢
1. **Thin-client process architecture** — No C++ compilation, no in-process model memory. Lightweight when idle. User brings their own Ollama/llama.cpp installation.
2. **Dual-backend flexibility** — Ollama (easy install, model management) + llama.cpp (more control, raw prompts). KeyType only supports llama.cpp.
3. **PredictionMode (midType vs pause)** — Unique two-speed prediction: fast 4-word mid-type predictions + richer 8-word pause predictions. KeyType doesn't have this.
4. **Streaming with mid-word gate** — Shows partial words immediately, waits for full words between boundaries. More responsive feel than KeyType's batch approach.
5. **Ported + wired Cotabby components** — Reconciler, geometry resolver, inserter, evaluator are all ported and wired into active code paths.
6. **Simpler codebase** — Easier to understand and modify than KeyType's 10-package architecture.
7. **Reconciler-enabled partial acceptance** — Can offer longer predictions from larger models and let users accept word-by-word. KeyType doesn't need this because it generates short completions.

### KeyType Strengths 🟢
1. **Constrained multi-branch generation** — Token-level control produces dramatically better completions from small models.
2. **Most mature codebase** — 50+ ADRs, comprehensive docs, per-package tests, production-shipped.
3. **Best prompting** — Sectioned budgeted prompts with tokenizer-backed counting, FIM support, per-app gating.
4. **Most comprehensive app compatibility** — Data-driven per-app overrides with 15+ fields per target.
5. **KV cache optimization** — Append-only reuse, snapshot/restore per branch, batched beam decoding.
6. **Personalization** — Local writing history, clipboard context, screen OCR, custom instructions.

---

## 12. Where Keybreeze is Behind 🔴

| Gap | Severity | Why It Matters |
|:---|:---|:---|
| ~~**Ported components not wired**~~ | ~~High~~ | ✅ All 4 ported components now wired (reconciler, geometry resolver, inserter suppression, evaluator) |
| **No per-app compatibility overrides** | High | Tab/paste/overlay will break in many apps |
| ~~**No post-generation candidate filtering**~~ | ~~Medium~~ | ✅ Implemented — `filterSuggestion()` strips multi-line, garbage, duplicates |
| **No tokenizer-backed prompt budgeting** | Medium | Character-based word caps don't map to actual token limits |
| **No FIM support** | Medium | Mid-line predictions duplicate trailing text |
| **No tests** | Medium | No safety net for regressions |
| **No prediction log** | Medium | Can't debug why suggestions are bad |
| **No KV cache optimization** | Medium | Full re-prefill per request wastes GPU cycles |
| **No personalization** | Low | Writing history, clipboard, custom instructions |

---

## 13. Recommended Improvements for Keybreeze (Lightweight + Reliable)

Prioritized by impact-to-effort ratio. Focus on what can be adopted without a full rewrite.

### Tier 1: Wire What's Already Ported ✅ COMPLETE

1. **Wire `SuggestionSessionReconciler` into `handleDraftChanged()`** ✅
   - Check if typed characters match the active suggestion before triggering a new LLM request.
   - Cuts redundant server requests by ~60-80% during normal typing.

2. **Wire `InputSuppressionController` into the event tap callback** ✅
   - Call `consumeIfNeeded()` in `SystemWidePredictor.installEventTap()` to suppress synthetic keystrokes.
   - Prevents infinite loops when inserting suggestions.

3. **Wire `SuggestionAvailabilityEvaluator` into `SystemWidePredictor`** ✅
   - Replace internal `shouldProcessApp()` with the ported evaluator.
   - Adds terminal detection and centralized gating.

4. **Wire `AXTextGeometryResolver` into overlay positioning** ✅
   - Replace the current 4-tier cursor rect fallback with the ported 6-branch resolver.
   - Fixes overlay positioning in Chromium/Electron apps.

### Tier 2: Adopt KeyType's Best Ideas (Medium Effort, High Impact)

5. **Add per-app compatibility overrides (data-driven)**
   - Create a `TargetOverride` struct and a default overrides table.
   - Start with: terminals (suppress), password managers (suppress), code editors (disable environment context).
   - Reference: KeyType `AppCompatibility` package.

6. **Add post-generation candidate filtering** ✅
   - Before showing a suggestion, check: duplicates after-cursor text? Too long? Contains garbage characters?
   - Simpler than constrained generation but captures ~60% of the benefit.
   - Implemented: `CompletionController.filterSuggestion()` strips multi-line, garbage chars, HTML tags, duplicate after-cursor text, excessively long predictions, and garbage punctuation.

7. **Add basic prompt sectioning** ✅
   - Split the prompt into sections: `[before cursor]` at the end, optional `[after cursor]` to prevent duplication.
   - Even without tokenizer-backed budgeting, this structure prevents the most common prompt failures.
   - Implemented: `PromptBuilder.continuationPrompt()` accepts `textAfterCursor`. Raw mode appends `[AFTER:{text}]` bracket marker. Chat mode adds explicit "do not repeat" instruction. `CompletionController` passes `state.textAfterCursor`.

8. **Add a prediction log**
   - Write every generation result and acceptance status to a log file.
   - Essential for debugging completion quality. KeyType's format is excellent.

### Tier 3: Longer-Term (Lower Priority)

9. **Add Apple Intelligence support (macOS 26+)**
   - Use `FoundationModels` framework as a zero-install backend.

10. **Add visual context (OCR)**
    - Capture a screenshot around the focused field for context.

11. **Add personalization**
    - Local writing history samples in the prompt.

---

## 14. What NOT to Adopt from KeyType

| Don't Adopt | Why |
|:---|:---|
| **In-process llama.cpp xcframework** | Requires C++ compilation, increases app size dramatically, couples you to llama.cpp ABI. Keybreeze's process-based approach is the right call for lightweight operation. |
| **Multi-branch constrained generation** | Extraordinary complexity (456-line engine, token profiles, trie admissibility, beam search). The ROI only justifies itself for very small models. With Ollama serving models at 1B+ parameters, raw output quality is already high. |
| **10-package architecture** | Overkill for Keybreeze's scope. Adopt the *ideas* (protocol-based contracts, per-package testing) without the full structural overhead. |
| **ACPF token profiles** | Requires tight coupling to the llama.cpp runtime. Not applicable to Keybreeze's process-based model. |

---

## 15. Strategic Positioning

| Factor | Keybreeze's Position | Recommendation |
|:---|:---|:---|
| **Ease of setup** | Requires Ollama/llama.cpp install | Lean into it — document the setup clearly, position as "works with your existing LLM setup" |
| **Model flexibility** | Any model via Ollama | This is a strength — highlight the ability to use any GGUF via Ollama |
| **Latency** | Process-based adds ~10-50ms HTTP overhead | Accept this tradeoff. Focus on reducing redundant requests via reconciliation |
| **Quality** | Raw LLM output + post-generation filtering (✅ TASK 6) + after-cursor prompt sectioning (✅ TASK 7) — captures most of the benefit without constrained generation complexity | Constrained generation, typo guard, sentence boundary |
| **App compatibility** | Basic | Add per-app overrides (Tier 2) — this is table stakes for a system-wide tool |
| **Unique value** | PredictionMode (mid-type vs pause), thin-client flexibility, larger model support | Double down on these — KeyType can't match them due to its in-process architecture |

---

## 16. Summary: The Lightweight + Reliable Path

For Keybreeze to compete effectively while staying lightweight and reliable:

1. **Wire the 4 ported components** ✅ — all done.
2. **Add per-app overrides** — data-driven, extensible, essential for real-world use.
3. **Add post-generation filtering** ✅ — implemented in `CompletionController.filterSuggestion()`.
4. **Add after-cursor prompt sectioning** ✅ — implemented in `PromptBuilder.continuationPrompt()` with `[AFTER:]` bracket marker.
5. **Add a prediction log** — essential for debugging and iteration.
6. **Keep the thin-client architecture** — this is Keybreeze's structural advantage for being lightweight.
7. **Don't try to match KeyType's constrained generation** — it's brilliant but orthogonal to Keybreeze's design goals.

The goal is not to become KeyType. The goal is to be the **lightest, most responsive** system-wide autocomplete that works with the LLM infrastructure the user already has — and that can leverage larger models that KeyType's in-process architecture simply cannot run.