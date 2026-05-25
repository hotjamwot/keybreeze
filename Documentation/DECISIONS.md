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
- **Status:** Active
- **Context:** Requirement for deterministic prediction behavior.
- **Decision:** Temperature 0.0 as production default.
- **Alternatives considered:** Higher temperature (0.7+).
- **Consequences:** Repetitive but consistent predictions; "autocomplete" feel.
