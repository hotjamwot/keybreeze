# Keybreeze — App Targets

This document describes the specific behaviour, configuration, and known quirks for each app that Keybreeze targets for system-wide prediction.

AI agents working on SystemWidePredictor, SuggestionOverlayWindowController, or per-app prompt profiles should consult this document first.

Each entry records: the app's bundle ID, the AX access level available, the recommended system prompt style, any known AX or overlay quirks, and the priority level for this target.

Last updated: 25 May 2026

---

## Scrivener
- **Bundle ID:** TBD — needs testing
- **AX access level:** Standard
- **Overlay positioning:** TBD — needs testing
- **Recommended prompt style:** Prose
- **Known issues:** TBD — needs testing
- **Priority:** High

## Obsidian  
- **Bundle ID:** TBD — needs testing
- **AX access level:** Electron / WebView
- **Overlay positioning:** TBD — needs testing
- **Recommended prompt style:** Markdown / Brief
- **Known issues:** Electron accessibility limitations
- **Priority:** High

## WhatsApp (macOS)
- **Bundle ID:** TBD — needs testing
- **AX access level:** Limited
- **Overlay positioning:** TBD — needs testing
- **Recommended prompt style:** Casual
- **Known issues:** TBD — needs testing
- **Priority:** Medium

## Google Docs (Chrome/Safari)
- **Bundle ID:** TBD — needs testing
- **AX access level:** Web View
- **Overlay positioning:** TBD — needs testing
- **Recommended prompt style:** Formal
- **Known issues:** Canvas-based rendering in Docs is notoriously hard for AX
- **Priority:** Medium

## Gmail (Chrome/Safari)
- **Bundle ID:** TBD — needs testing
- **AX access level:** Web View
- **Overlay positioning:** TBD — needs testing
- **Recommended prompt style:** Brief
- **Known issues:** TBD — needs testing
- **Priority:** Medium
