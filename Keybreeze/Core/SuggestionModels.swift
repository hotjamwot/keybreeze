import Foundation
import CoreGraphics

// MARK: - Core Value Types (ported from Cotabby)

/// Describes how trustworthy the resolved caret rect is.
enum CaretGeometryQuality: Equatable, Sendable {
    case exact
    case derived
    case estimated

    var label: String {
        switch self {
        case .exact: return "exact"
        case .derived: return "derived"
        case .estimated: return "estimated"
        }
    }
}

/// The stable context used across debounce and generation boundaries.
struct FocusedInputContext: Equatable, Sendable {
    let applicationName: String
    let bundleIdentifier: String
    let processIdentifier: Int32
    let elementIdentifier: String
    let role: String
    let subrole: String?
    let caretRect: CGRect
    let inputFrameRect: CGRect?
    let caretQuality: CaretGeometryQuality
    let observedCharWidth: CGFloat?
    let precedingText: String
    let trailingText: String
    let selection: NSRange
    let isSecure: Bool
    let generation: UInt64
}

/// One active inline-completion session after the model has produced a suggestion.
/// A suggestion is no longer "fire once and forget" — it becomes durable interaction
/// state that can be partially consumed over time.
struct ActiveSuggestionSession: Equatable, Sendable {
    let baseContext: FocusedInputContext
    let fullText: String
    let consumedCharacterCount: Int
    let latency: TimeInterval

    init(
        baseContext: FocusedInputContext,
        fullText: String,
        consumedCharacterCount: Int = 0,
        latency: TimeInterval
    ) {
        self.baseContext = baseContext
        self.fullText = fullText
        self.consumedCharacterCount = min(max(consumedCharacterCount, 0), fullText.count)
        self.latency = latency
    }

    var acceptedText: String {
        String(fullText.prefix(max(consumedCharacterCount, 0)))
    }

    var remainingText: String {
        String(fullText.dropFirst(max(consumedCharacterCount, 0)))
    }

    var acceptedCount: Int {
        consumedCharacterCount
    }

    var remainingCount: Int {
        remainingText.count
    }

    var isExhausted: Bool {
        remainingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func advancing(by consumedCharacters: Int) -> ActiveSuggestionSession {
        ActiveSuggestionSession(
            baseContext: baseContext,
            fullText: fullText,
            consumedCharacterCount: self.consumedCharacterCount + max(consumedCharacters, 0),
            latency: latency
        )
    }

    func withConsumedCharacters(_ consumedCharacters: Int) -> ActiveSuggestionSession {
        ActiveSuggestionSession(
            baseContext: baseContext,
            fullText: fullText,
            consumedCharacterCount: consumedCharacters,
            latency: latency
        )
    }
}

// MARK: - Reconciliation Types

struct SuggestionSessionAdvancement: Equatable, Sendable {
    let stage: String
    let message: String
    let actionSummary: String
    let exhaustionStage: String
    let exhaustionMessage: String
}

enum SuggestionSessionReconciliation: Equatable, Sendable {
    case valid(
        session: ActiveSuggestionSession,
        advancement: SuggestionSessionAdvancement?,
        nextPendingInsertionConsumedCount: Int?
    )
    case invalid(String)
}

// MARK: - Geometry

struct SuggestionOverlayGeometry: Equatable, Sendable {
    let caretRect: CGRect
    let inputFrameRect: CGRect?
    let caretQuality: CaretGeometryQuality
    let observedCharWidth: CGFloat?
    let isRightToLeft: Bool

    init(
        caretRect: CGRect,
        inputFrameRect: CGRect?,
        caretQuality: CaretGeometryQuality,
        observedCharWidth: CGFloat?,
        isRightToLeft: Bool = false
    ) {
        self.caretRect = caretRect
        self.inputFrameRect = inputFrameRect
        self.caretQuality = caretQuality
        self.observedCharWidth = observedCharWidth
        self.isRightToLeft = isRightToLeft
    }
}

enum OverlayState: Equatable {
    case hidden(reason: String)
    case visible(text: String, geometry: SuggestionOverlayGeometry)

    var isVisible: Bool {
        if case .visible = self { return true }
        return false
    }

    var visibleText: String? {
        guard case let .visible(text, _) = self else { return nil }
        return text
    }
}

// MARK: - Input Event

struct CapturedInputEvent: Equatable {
    enum Kind: String, Equatable {
        case acceptance
        case fullAcceptance
        case textMutation
        case navigation
        case shortcutMutation
        case dismissal
        case other
    }

    let kind: Kind
    let keyCode: UInt16
    let characters: String
    let flags: CGEventFlags
}

// MARK: - Gamma Support

struct DisplayGeometry: Equatable {
    let appKitFrame: CGRect
    let visibleFrame: CGRect
    let coreGraphicsBounds: CGRect
    let backingScaleFactor: CGFloat
}