Keybreeze vs AutoComp-Main Architecture Comparison
Overview
Keybreeze: macOS menu bar app providing local, low-latency text continuation (autocomplete) using Ollama or llama.cpp over HTTP. Includes Typing Lab - a permanent dev environment with live playground, diagnostics, prediction history, prompt editing, and runtime tuning.
AutoComp: macOS 14+ menu bar autocomplete app for Apple Silicon Macs that watches the active accessible text field, requests a short completion from a configured remote OpenAI-compatible endpoint, displays it inline or in a mirror window, and lets the user accept text with Tab.
Architectural Differences
1. LLM Backend Approach
Keybreeze:
Single LLMClient class that speaks OpenAI-compatible API (/v1/chat/completions)
Supports both Ollama (primary) and llama.cpp (secondary/experimental)
Deliberately thin LLM layer - no provider protocols or service abstraction
Model catalog: Ollama via GET /api/tags, llama.cpp via GGUF file scanning
Non-streaming for llama.cpp (SSE mode never sends terminating event)
AutoComp:
Remote OpenAI-compatible completion backend configurable from Settings > Model
Uses CompletionProvider protocol with implementations like RemoteCompletionProvider
Configuration service handles API keys, base URLs, and model selection
Secure storage of API keys in Keychain
Focuses exclusively on remote backends (no local model support mentioned)
2. Prediction/Completion Engine
Keybreeze:
CompletionController as prediction orchestrator
Receives EditorState, debounces (45ms), builds prompts via PromptBuilder
Calls LLMClient.streamCompletion(), measures TTFT and total latency
Records prediction history via onRecordPrediction callback
Strong focus on latency tracking and typing feel over raw intelligence
AutoComp:
SuggestionEngine as the core completion orchestrator
Uses debounce timer (0.25s) and periodic refresh timer (0.28s)
Complex state management for acceptance, leaked shortcuts, and various grace periods
Multiple completion providers via protocol (CompletionProvider)
Advanced text context handling with fallback mechanisms (screen OCR, etc.)
Rich acceptance state tracking for handling Tab vs backtick acceptance
3. Text Context Acquisition
Keybreeze:
Relies on AccessibilityManager for text context extraction
Simpler approach - gets text context directly via Accessibility API
No OCR or fallback mechanisms mentioned
Focuses on standard text fields
AutoComp:
Sophisticated AXTextContextService with multiple fallback mechanisms:
Primary: Accessibility API
Fallbacks: Screen OCR for Google Docs, special handling for Codex/ProseMirror
Complex geometry calculations for caret positioning in various editors
Handles weak text, zero-width characters, and special editor implementations
4. UI Architecture
Keybreeze:
Two surfaces: Menu bar dropdown (compact) and Typing Lab window (full dev environment)
Menu bar uses .menuBarExtraStyle(.menu) (not .window)
Typing Lab has 4 tabs: Playground, Apps, Diagnostics, History
Ghost text rendering via GhostTextModifier (static overlay, no animations)
Strong separation of concerns - menu bar for controls, Typing Lab for development/tuning
AutoComp:
Menu bar app with onboarding and settings windows
Menu bar uses .menuBarExtraStyle(.window) (different from Keybreeze)
Settings window with sections: Permissions, Apps, Privacy, Shortcuts, Model
Inline overlay and mirror-window suggestion modes
Tab accepts next suggestion word; backtick accepts full suggestion
More traditional macOS app structure with multiple windows
5. State Management & Architecture Patterns
Keybreeze:
Clear separation: AppState (config/model catalog), SessionViewModel (UI/prediction bridge)
Uses Combine for parameter syncing ($temperature, $topP → updateControllerFromAppState())
Explicit actor isolation with @MainActor on major classes
Strict rules about sendable closures and @MainActor transitions
Prediction history as ring buffer (200 records) with TTFT/total time tracking
AutoComp:
AppController as central coordinator owning all services
Uses Combine for some reactive updates (permission monitoring)
Complex state machines for acceptance states, leaked shortcuts, etc.
Multiple private state structs (AcceptanceState, CompletedAcceptAllState, LeakedShortcut)
Periodic timers rather than pure reactive streams for some functionality
6. Features & Focus Areas
Keybreeze:
Local-first approach with Ollama/llama.cpp
Typing Lab as permanent development environment
Relentless focus on typing feel and latency measurements
Prompt engineering and runtime tuning capabilities
Prediction history and diagnostics
Model-specific presets (temperature, topP, etc.)
Aggression presets (Conservative/Balanced/Aggressive)
AutoComp:
Remote-first approach (OpenAI-compatible endpoints)
Rich app compatibility system (compatibility catalog, overrides)
Advanced text field handling with OCR fallbacks
Sophisticated acceptance state management
Privacy controls with encrypted local personalization
Emoji suggestions after :
Google Docs special handling and setup detection
Which Does What Better?
Keybreeze Strengths:
Local LLM Integration - Better for privacy-focused users who want to run models locally
Development Environment - Typing Lab provides excellent tuning and diagnostics capabilities
Latency Focus - Strong emphasis on measuring and optimizing TTFT and total latency
Simplicity - Cleaner separation of concerns with fewer moving parts
Predictability - More deterministic behavior due to simpler state management
AutoComp Strengths:
Text Context Handling - Superior handling of complex editors, OCR fallbacks, and special cases
Compatibility System - Robust app-specific compatibility overrides and detection
Acceptance State Management - More sophisticated handling of partial acceptance and leaked states
Remote Backend Flexibility - Easy configuration of various OpenAI-compatible endpoints
Feature Richness - More polished end-user features like emoji suggestions, mirror windows, etc.
Recommendations for Making Keybreeze More Elegant
Based on the comparison, here are suggestions for improving Keybreeze's architecture:

Enhanced Text Context Fallbacks (Inspired by AutoComp):
Consider adding optional OCR fallback for difficult-to-access text fields
Implement special handling for known problematic editors (like AutoComp's Google Docs/Codex support)
Improve caret positioning calculations for various text systems
More Sophisticated Acceptance State Tracking (Inspired by AutoComp):
Consider implementing richer acceptance state to handle complex editing scenarios
Add better leak detection and recovery mechanisms
Improve handling of partial word acceptance scenarios
Modular Backend Approach (Keeping Keybreeze's simplicity but adding flexibility):
While maintaining the single LLMClient approach, consider making it easier to add new backend types
Keep the thin layer philosophy but improve extensibility
Enhanced Diagnostics and Monitoring (Building on Keybreeze's strength):
Expand on the existing diagnostics panel with more detailed metrics
Consider adding visualization of latency trends over time
Enhance the prediction history with more analytical capabilities
User Experience Improvements (Learning from AutoComp's polish):
Consider adding mirror window option alongside inline ghost text
Improve onboarding and first-run experience
Add more user-configurable behaviors and preferences
Better Error Handling and Recovery (Inspired by AutoComp's robustness):
Implement more graceful degradation when accessibility fails
Add better recovery mechanisms from problematic states
Improve logging and diagnostics for troubleshooting
Let me now create the markdown file for Keybreeze documentation as requested