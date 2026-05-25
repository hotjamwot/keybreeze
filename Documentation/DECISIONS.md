# Keybreeze — Architectural Decisions

This document is the authoritative record of every significant architectural and product decision made during the development of Keybreeze.

## How to use this document

- Every significant decision — technical, architectural, or product — must be 
  recorded here at the time it is made
- AI agents working on this codebase must read this document before proposing 
  any structural changes
- If a proposed change would reverse or contradict a recorded decision, the 
  agent must flag this explicitly and ask for confirmation before proceeding
- Decisions have a Status field: Active (currently in force), Superseded (replaced by a later decision), or Deferred (agreed but not yet implemented)
- Do not silently re-litigate Active decisions. If you believe a decision 
  should change, record a new decision that supersedes the old one.

## Format

Each entry uses this structure:

### D[number] — [Short title]
- **Date:** 
- **Status:** Active | Superseded | Deferred
- **Context:** What problem or situation prompted this decision
- **Decision:** What was chosen
- **Alternatives considered:** What was rejected and why
- **Consequences:** What this decision constrains or enables going forward

---

### D1 — Backend Strategy
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Need for stable, efficient local LLM inference.
- **Decision:** Use llama.cpp as primary backend for Gemma 4 E2B; use Ollama as primary fallback/general backend.
- **Alternatives considered:** Native Swift-based inference (too high maintenance), cloud APIs (violates local-first requirement).
- **Consequences:** Requires handling two distinct backend process lifecycles and HTTP protocols.

### D2 — LLM Abstraction
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Complexity of managing different LLM backends.
- **Decision:** Single `LLMClient` abstraction for both Ollama and llama.cpp.
- **Alternatives considered:** Separate client classes per provider.
- **Consequences:** Simplifies codebase, unified configuration, but requires `LLMClient` to handle dual endpoint logic.

### D3 — Backend Lifecycle Management
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Need for robust backend process management and cleanup.
- **Decision:** Use `BackendManager` separate from `LLMClient`.
- **Alternatives considered:** Managing processes within `LLMClient` or `AppState`.
- **Consequences:** Centralizes lifecycle logic; avoids zombies; ensures termination via `AppKitLifecycle`.

### D4 — Debounce Timing
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Balancing responsiveness with resource usage.
- **Decision:** 45ms debounce.
- **Alternatives considered:** Higher (sluggish) or lower (flicker).
- **Consequences:** Standardized across `CompletionController`.

### D5 — Context Truncation
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Large documents causing latency and semantic drift.
- **Decision:** 800-character context truncation.
- **Alternatives considered:** Full document context.
- **Consequences:** Faster inference; forces local-focus; limits global reasoning.

### D6 — Ghost Text Display
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Integrating predictions into host apps.
- **Decision:** Use a floating transparent overlay window rather than native AX text insertion.
- **Alternatives considered:** Native AX insertion (unreliable, destructive).
- **Consequences:** Non-destructive; requires robust window positioning logic.

### D7 — Sandboxing
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Need to access local files (GGUF) and spawn child processes.
- **Decision:** Disable app sandboxing.
- **Alternatives considered:** Enabling sandboxing with strict entitlements.
- **Consequences:** Increased security surface; necessary for backend infrastructure.

### D8 — UI Animation
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Avoiding "flashy" or distracting UI.
- **Decision:** No-animation rule for ghost text.
- **Consequences:** Instant appearance/disappearance; consistent with low-latency requirement.

### D9 — Styling Consistency
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Avoiding duplicated visual code.
- **Decision:** GhostTextStyle shared constants file.
- **Consequences:** Centralizes design changes (opacity, fonts, padding).

### D10 — Teardown Strategy
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** Avoiding zombie processes during quit.
- **Decision:** AppKitLifecycle notification-based teardown (not deinit).
- **Consequences:** Ensures predictable shutdown on all exit paths.

### D11 — Production Parameters
- **Date:** 2026-05-25
- **Status:** Superseded — superseded by D15 (Parameter Centralization)
- **Context:** Requirement for deterministic prediction behavior.
- **Decision:** Temperature 0.0 as production default.
- **Alternatives considered:** Higher temperature (0.7+).
- **Consequences:** Repetitive but consistent predictions; "autocomplete" feel.

### D12 — Gemma 4 E2B llama.cpp Prompt Strategy (SUPERSEDED)
- **Date:** 2026-05-25
- **Status:** Superseded — superseded by D14 (Raw Text Completion)
- **Context:** Gemma 4 E2B is an instruct-tuned model. With `--no-jinja` active (disabling the server's jinja chat template engine), raw text prompts cause the model to fall back to its training distribution (HTML, code, creative fiction) and produce nonsense.
- **Decision:** Manually wrap the prompt in Gemma's native chat template tokens.
- **Alternatives considered:** See D14 for why this was abandoned.
- **Consequences:** Replaced by D14.

### D13 — Prompt Anti-patterns Catalog (llama.cpp)
- **Date:** 2026-05-25
- **Status:** Active
- **Context:** During debugging of Gemma 4 E2B output quality, we tried several prompt configurations that produced catastrophic failure modes. This decision catalogs them so they are never re-attempted.
- **Decision:** The following prompt approaches are **confirmed failures** and must not be reintroduced:
  1. **Appending instructions to the user message in chat completions**: e.g. `{context}\n\nContinue with the next few words only:\n`. The model thinks the user literally typed "Continue with the next few words only:" and echoes it back verbatim.
  2. **Using `/v1/chat/completions` with Gemma 4 E2B without jinja**: Even with proper system/user message separation, the chat completions endpoint makes the model respond as a chatbot. Mid-word contexts produce empty responses.
  3. **Removing `--no-jinja` from llama-server**: The server's jinja template engine applies the model's chat template, which produces the same chatbot behavior.
  4. **Using raw prefix completion without any instruction framing**: With `--no-jinja`, the `/completion` endpoint treats the prompt as bare text. Without behavioral framing tokens, instruct models produce HTML/code/creative fiction instead of text continuations.
  5. **Using Gemma `<start_of_turn>` chat template tokens in raw /completion endpoint**: Forces the instruct model into chatbot mode. Mid-word inputs are meaningless as "user messages" and produce empty responses. Full-sentence contexts trigger safety refusals ("I'm sorry, I can't..."). The model leaks the system prompt as its response.
  6. **Using `\n` as a stop token**: The model frequently generates a newline as a "hesitation" token before meaningful output. A `\n` stop token immediately terminates the stream, producing empty continuations for mid-word inputs.
- **Consequences:** All approaches have been tried and failed. The only workable approach is documented in D14.

### D14 — Raw Text Completion for llama.cpp
- **Date:** 2026-05-26
- **Status:** Active
- **Context:** The chat template approach (D12) forced Gemma 4 E2B into chatbot mode, producing empty mid-word responses, safety refusals, and system prompt leakage. We need a prompt strategy that works for autocomplete.
- **Decision:** For llama.cpp raw `/completion` endpoint with `--no-jinja`:
  - Send the bare context text with a trailing space appended if not already present.
  - No system prompt, no chat template tokens, no instructions.
  - The trailing space converts mid-word contexts ("best b") into clean word-boundary contexts ("best b "), preventing the model from struggling with partial-word inputs at low temperature.
  - Stop tokens: `["<"]` only. The `<` stop token prevents HTML formatted output. No `\n` stop token — newlines are common hesitation tokens that would truncate the stream before meaningful output.
  - Repeat penalty: forwarded via API per-request (default 1.15 to prevent word echoing).
  - Temperature: forwarded via API per-request (default 0.1 for deterministic but not frozen output).
- **Alternatives considered:** See D13 for exhaustive list of failures.
- **Consequences:** Produces clean natural language continuations. Mid-word inputs now generate predictions (trailing space trick). Word repetition controlled by repeat_penalty. No chatbot refusals.

### D15 — Parameter Centralization
- **Date:** 2026-05-26
- **Status:** Active
- **Context:** Inference parameters (temperature, topP, repeatPenalty, etc.) were scattered across ModelOption, CompletionController, SessionViewModel, LLMClient, AggressionPreset, and DiagnosticsPanelView with hardcoded defaults in each location. This caused confusion during debugging and made it impossible to change defaults in one place.
- **Decision:** `ModelOption` is the single source of truth for all inference parameter defaults. All components reference `ModelOption.defaultTemperature`, `ModelOption.defaultTopP`, `ModelOption.defaultRepeatPenalty`, and `ModelOption.defaultConfidenceThreshold`. No hardcoded default values elsewhere.
- **Alternatives considered:** Centralizing in a separate Constants struct (adds indirection), or in AppSettings (blurs persistence vs. default distinction).
- **Consequences:** Changing defaults in one place (ModelOption) propagates everywhere. The diagnostics panel now reads from SessionViewModel (runtime values) rather than ModelOption static defaults. The actual values sent to the API are always the session-level values set via the UI sliders or presets.

### D16 — Streaming Gate for Mid-Word
- **Date:** 2026-05-26
- **Status:** Active
- **Context:** The streaming gate in `CompletionController` was too strict, blocking all mid-word completions and making it appear as though the model was producing empty output.
- **Decision:** Context-sensitive streaming gate:
  - **Mid-word** (draft ends without trailing space): Show tokens immediately — the model is completing the current word, every token is relevant.
  - **Between-words** (draft ends with trailing space): Wait until accumulated tokens contain a space (full word) or at least 10 characters before showing. Prevents flickering partial tokens.
- **Consequences:** Mid-word completions appear instantly. Between-word gating prevents dancing.