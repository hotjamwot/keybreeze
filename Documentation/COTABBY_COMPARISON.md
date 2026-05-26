# Keybreeze vs. Cotabby: Architectural Responsibilities Comparison
*Last updated: 26 May 2026*

This document maps out the system responsibilities, orchestration loops, design patterns, and engineering tradeoffs of **Keybreeze** versus **Cotabby**. It serves as an architectural blueprint for comparing Keybreeze's implementation against Cotabby's modular structure.

---

## 1. High-Level Architecture & Design Philosophy

| Architectural Dimension | Keybreeze | Cotabby |
| :--- | :--- | :--- |
| **Primary Paradigm** | Centrally coordinated ViewModel/Controller structure with explicit shared singletons. | Highly decoupled, domain-driven architecture with clean separation of pure and stateful side-effects. |
| **Object Lifecycle** | Self-managed singleton-based dependencies (`AccessibilityManager.shared`) initialized on demand. | **Composition Root** pattern (`CotabbyAppEnvironment`) wiring up the long-lived dependency graph once at startup. |
| **Data Propagation** | SwiftUI views and controllers observe published values or bind directly to singletons via Combine/SwiftUI. | Subsystems communicate via delegate protocols or narrow publishers. SwiftUI views only observe, never construct. |

---

## 2. Structural Decomposition by Responsibility

### Responsibility A: App Lifecycle & Dependency Injection (DI)

*   **Keybreeze (`Keybreeze/App/`, `Keybreeze/Core/`):**
    *   **Files:** `KeybreezeApp.swift`, `AppKitLifecycle.swift`, `BackendManager.swift`.
    *   **Approach:** Uses `AppKitLifecycle` to hook traditional NSApplication startup and termination notifications. Orchestration singletons like `BackendManager` and `AccessibilityManager` are self-contained and lazily instantiate.
    *   **Tradeoff:** Simple to reason about, low boilerplate, but dependencies are tightly coupled to static `.shared` accessors, complicating unit testing.
*   **Cotabby (`Cotabby/App/Core/`):**
    *   **Files:** `CotabbyApp.swift`, `AppDelegate.swift`, `CotabbyAppEnvironment.swift`.
    *   **Approach:** Employs `CotabbyAppEnvironment` to construct every service, coordinator, and state manager explicitly at startup. `AppDelegate` acts as the event dispatcher wiring together cross-subsystem subscriptions.
    *   **Tradeoff:** High structural decoupling and high testability (via mockable protocols), but requires more boilerplate during initialization.

---

### Responsibility B: Text Context Extraction & Caret Tracking

*   **Keybreeze (`Keybreeze/Core/`):**
    *   **Files:** `AccessibilityManager.swift`, `SystemWidePredictor.swift`.
    *   **Approach:** Unified `AccessibilityManager` containing nested element resolution (6 levels deep), secure text-field checking, context retrieval via `kAXStringForRangeParameterizedAttribute` with traditional `AXValue` / `AXSelectedTextRange` fallback, and caret bounds retrieval.
    *   **Tradeoff:** Highly cohesive single-file implementation. Includes robust fallback caching (`lastValidCursorRect`) so overlays survive intermittent AX API failures.
*   **Cotabby (`Cotabby/Services/Focus/`, `Cotabby/Support/`):**
    *   **Files:** `FocusTracker.swift`, `FocusSnapshotResolver.swift`, `AXTextGeometryResolver.swift`, `AXHelper.swift`.
    *   **Approach:** Decomposed into specialized pipeline components:
        *   `FocusTracker`: Runs a polling timer to detect active applications.
        *   `FocusSnapshotResolver`: Traverses the accessibility tree and analyzes editor compatibility.
        *   `AXTextGeometryResolver`: Specifically isolates caret box and text range dimensions.
        *   `AXHelper`: Clean low-level C-to-Swift bridging helper.
    *   **Tradeoff:** Strong separation of concerns. If focus resolution fails, the bug is isolated to `FocusSnapshotResolver` rather than polluting general prediction state.

---

### Responsibility C: Suggestion Pipeline Orchestration & Debouncing

*   **Keybreeze (`Keybreeze/Core/`, `Keybreeze/UI/`):**
    *   **Files:** `CompletionController.swift`, `SystemWidePredictor.swift`, `SessionViewModel.swift`.
    *   **Approach:** `SystemWidePredictor` captures global key presses via CGEventTap, executes idle polling (500ms) to detect non-keystroke changes, and updates `CompletionController`. `CompletionController` handles debouncing (45ms), orchestrates the async stream prediction task, and feeds the string back to the overlay.
    *   **Tradeoff:** Direct and highly performant. Combining UI updates and lifecycle in `CompletionController`/`SessionViewModel` makes screen state manipulation fast, but mixes domain logic with rendering.
*   **Cotabby (`Cotabby/App/Coordinators/`, `Cotabby/Services/Suggestion/`):**
    *   **Files:** `SuggestionCoordinator.swift` (and its 4 extension files: `+Lifecycle`, `+Input`, `+Prediction`, `+Acceptance`), `SuggestionWorkController.swift`, `SuggestionInteractionState.swift`, `SuggestionOverlayPresenter.swift`.
    *   **Approach:** The massive coordinator pattern is split across specialized extensions:
        *   `SuggestionWorkController` manages generation tasks, concurrency, and debouncing.
        *   `SuggestionInteractionState` maintains active suggestion buffers and accept/reject/partial-accept metrics.
        *   `SuggestionOverlayPresenter` handles overlay visibility independently.
    *   **Tradeoff:** Avoids the "Massive View Controller/ViewModel" antipattern. Easily extendable, but tracing a complete keypress-to-render flow involves jumping through multiple decoupled components.

---

### Responsibility D: Typing Reconciliation & Text Acceptance

*   **Keybreeze (`Keybreeze/Core/`):**
    *   **Files:** `CompletionController.swift` (using `expectedTextAfterAcceptance` echos), `AccessibilityManager.swift`.
    *   **Approach:** Implements lightweight echo tracking to prevent redundant re-predictions when a suggestion is accepted and inserted. Employs a text-to-keyboard event synthesizer (`insertViaKeyboardEvents`) to type characters one-by-one safely into modern editors (with a clipboard fallback).
    *   **Tradeoff:** Lightweight, focuses on robust insertion across complex editors (like Obsidian and VSCode).
*   **Cotabby (`Cotabby/Support/`, `Cotabby/Services/Suggestion/`):**
    *   **Files:** `SuggestionSessionReconciler.swift`, `SuggestionInserter.swift`, `SuggestionTextNormalizer.swift`.
    *   **Approach:** Uses `SuggestionSessionReconciler` to encapsulate formal mathematical states representing typing progress (e.g., matching typed prefixes, handling partial acceptance word-by-word, and computing the active suffix delta). `SuggestionInserter` coordinates writing operations.
    *   **Tradeoff:** Offers highly granular and deterministic control over multi-character typing matches (ideal for partial acceptance and word-by-word autocomplete UI), though it is more complex.

---

### Responsibility E: LLM Process Lifecycle & Runtime Execution

*   **Keybreeze (`Keybreeze/Core/`, `Keybreeze/LLM/`):**
    *   **Files:** `BackendManager.swift`, `LLMClient.swift`, `PromptBuilder.swift`, `ModelOption.swift`.
    *   **Approach:** Manages host processes for external local runtimes. Launches and monitors standard server processes for **Ollama** (`ollama serve`) and **llama.cpp** (`llama-server` with explicit thread, batch-size, flash-attention, and `--no-jinja` flags). Communicates over local HTTP loops. Prompt configurations (bare text for llama.cpp vs. Chat schema for Ollama) are configured dynamically per-request.
    *   **Tradeoff:** Highly flexible; adapts easily to external, system-installed LLM managers while keeping resource footprints tiny when idling.
*   **Cotabby (`Cotabby/Services/Runtime/`, `Cotabby/Services/Utilities/`):**
    *   **Files:** `LlamaRuntimeManager.swift`, `LlamaRuntimeCore.swift`, `LlamaSuggestionEngine.swift`, `ModelDownloadManager.swift`, `ModelFileValidator.swift`.
    *   **Approach:** Direct on-device integration. Bundles or downloads raw GGUF models via `ModelDownloadManager` and directly invokes a serialized local runtime (`LlamaRuntimeCore`), skipping external network loops. Also provides alternative routing to macOS's native foundation translation engines via `FoundationModelSuggestionEngine`.
    *   **Tradeoff:** Completely self-contained out-of-the-box user experience (no separate Ollama installation required), but requires compiling/linking C++ library dependencies (like `llama.cpp` dynamic runtimes) inside the app wrapper.

---

## 3. Next Steps for Architectural Alignment

When we proceed to align or adapt patterns from Cotabby into Keybreeze:
1.  **Reconciliation Separation:** Consider spinning off a standalone `SuggestionReconciler` helper from `CompletionController` to handle partial acceptance math and input echo logic.
2.  **Focus Isolation:** Decouple context collection inside `AccessibilityManager` from coordinate resolution by establishing a dedicated text geometry mapper.
3.  **Process vs. Lib:** Maintain Keybreeze's process-based `BackendManager` approach, as managing server child processes keeps Keybreeze light, but inspect Cotabby's custom rule engines to allow user-defined trigger exclusions.

To prioritize speed, accuracy, a low memory/CPU footprint, and responsiveness while keeping your external Ollama and llama.cpp backends, you should adopt these four core elements of Cotabby's architecture:

1. Pure String Reconciliation (SuggestionSessionReconciler)
Why it matters for CPU & Speed: Currently, Keybreeze cancels and re-triggers a new LLM prediction on almost every keystroke (with a 45ms debounce). This causes constant server-side context pre-filling, consuming massive GPU/CPU resources.
Adoption: Implement a formal reconciler that checks if the user's new character matches the next character of the active ghost text. If it matches, simply advance the cursor and shift the remaining ghost text inline locally in the UI, without canceling or re-requesting an LLM completion.
Result: Drastically cuts down on redundant server requests, reduces CPU/GPU cycles, and makes suggestions feel instant as you type.
2. Event-Driven AX Querying vs. Per-Keystroke Polling
Why it matters for CPU Footprint: macOS Accessibility (AX) API queries are synchronous, run on the main thread, and are incredibly heavy. Invoking them on every keystroke causes visible typing stutter.
Adoption: Separate the keyboard listener (CGEventTap) from the AX geometry resolver. Cache the current editor's capability state once when focus shifts (FocusTracker). Avoid recalculating the caret bounding box on every character; instead, compute the caret geometry only after a suggestion is returned from the LLM.
Result: Lowers Keybreeze’s CPU usage during fast typing to practically 0%.
3. Context Sanitization and Token Optimization (PromptContextSanitizer)
Why it matters for LLM Speed & Accuracy: Feeding massive or unformatted prefixes into local LLMs increases prefill latency (Time to First Token) and risks context window saturation.
Adoption: Implement a strict sanitizer that strips zero-width joiners, normalizes line endings, and truncates prefix contexts to a hard token/character limit.
Result: Improves TTFT latency and avoids model "drift" (such as repeating text or leaking system instructions).
4. KV-Cache Optimization & Stable Prompting
Why it matters for Latency: To get the best out of Ollama and llama.cpp, you must maximize KV (Key-Value) cache hits inside the backend servers.
Adoption: Ensure the prompt prefix structure is strictly deterministic. Avoid adding dynamic system prompt modifiers on the fly, as altering the prefix invalidates the backend's KV cache, forcing it to re-evaluate the entire context from scratch.
Result: Reduces TTFT to single-digit milliseconds for consecutive completions.