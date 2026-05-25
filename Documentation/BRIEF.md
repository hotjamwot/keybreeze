# Keybreeze — Project Brief
Last updated: 25 May 2026

*The purpose of this document is to outline the high-level vision, mission, and "soul" of Keybreeze. It serves as the primary reference for the project's philosophy. Any developer or AI agent working on Keybreeze should consult this document to understand the "why" behind the project.*

*For the full behavioral specification, see **[BEHAVIOR.md](./BEHAVIOR.md)**. For technical architecture, file-by-file ground truth, and AI agent rules, see **[ARCHITECTURE.md](./ARCHITECTURE.md)**.*

---

## Product Definition

Keybreeze is a local-first macOS menu bar app that continuously predicts the next words you are about to type, serving them as inline ghost text without interrupting your flow.

**Core promise:** *Create uninterrupted writing flow.* Not autocomplete spam. Not AI authorship. Cognitive acceleration through anticipatory language completion.

The soul of Keybreeze is: **Keybreeze is a local-first cognitive flow amplifier that predicts and removes low-friction language work without stealing authorship or interrupting momentum. It removes friction between thought and typing.**

---

## Behavioral Summary

### Core UX Philosophy
The assistant must feel:
* Invisible
* Immediate
* Non-intrusive
* Forgiving
* Cognitively lightweight
* Always one thought ahead
* Never "thinking"

Latency is the primary feature, not intelligence.

### Prediction Display
- Inline ghost text immediately after the caret, using the same baseline as the surrounding text.
- Visual style: Grey, slightly translucent, lower contrast than committed text.
- No popup by default.
- Display strategy: Only display once a minimum confidence threshold is reached or the first full word is completed (to prevent "dancing" predictions).

### Acceptance Behavior
- **Tab key:** Accepts the next predicted word only (word-by-word), creating high trust and fine-grained control.
- **Backtick key:** Accepts the full visible prediction instantly, inserting the text and moving the caret to the end.


### Per-App Behaviour
App-specific prompt profiles and context strategies are planned for:
- Scrivener
- Obsidian
- WhatsApp
- Google Docs
- Gmail

---

## Backend Architecture

- **Primary Backend:** Ollama (via `LLMClient`)
- **Secondary Backend:** llama.cpp (via `LLMClient`)

Keybreeze follows a thin-client architecture. The `LLMClient` class handles the communication with the backend service. Process lifecycle management for both backends is handled exclusively by the `BackendManager`.

- **llama.cpp Integration:** Uses SSE streaming to the raw `/completion` endpoint.
- **Ollama Integration:** Uses SSE streaming to the `/v1/chat/completions` endpoint.

Configuration is centralized in a single `LLMConfig` struct to avoid fragmented settings.
