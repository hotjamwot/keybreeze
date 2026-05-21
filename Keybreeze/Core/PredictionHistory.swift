import Foundation

/// Resolution of a prediction — what happened to it.
enum PredictionResolution: String, CaseIterable, Sendable {
    case accepted
    case ignored
    case invalidated
    case cancelled
    case rejected
}

/// A single prediction record for history tracking.
struct PredictionRecord: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let modelDisplayName: String
    let mode: String
    let resolution: PredictionResolution
    let timeToFirstToken: TimeInterval?
    let totalTime: TimeInterval
    let typedContext: String
    let generatedContinuation: String
}

/// Ring-buffer prediction history (max 200 records).
final class PredictionHistory: @unchecked Sendable {
    private var records: [PredictionRecord] = []
    private let maxRecords = 200

    var allRecords: [PredictionRecord] { records }

    func add(_ record: PredictionRecord) {
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
    }

    func clear() {
        records.removeAll()
    }

    func count(resolution: PredictionResolution) -> Int {
        records.filter { $0.resolution == resolution }.count
    }

    var acceptanceRate: Double {
        let total = Double(records.count)
        guard total > 0 else { return 0 }
        let accepted = Double(count(resolution: .accepted))
        return accepted / total
    }

    var averageTimeToFirstToken: TimeInterval {
        let withTTFT = records.compactMap { $0.timeToFirstToken }
        guard !withTTFT.isEmpty else { return 0 }
        return withTTFT.reduce(0, +) / Double(withTTFT.count)
    }

    var averageTotalTime: TimeInterval {
        guard !records.isEmpty else { return 0 }
        return records.map(\.totalTime).reduce(0, +) / Double(records.count)
    }
}

/// Correction state for backspace-correction UX.
struct CorrectionState {
    let originalWord: String
    let suggestedCorrection: String
}

/// Aggression preset for batch-setting sampling parameters.
enum AggressionPreset: String, CaseIterable, Sendable {
    case conservative = "Conservative"
    case balanced = "Balanced"
    case aggressive = "Aggressive"

    var temperature: Double {
        switch self {
        case .conservative: return 0.15
        case .balanced: return 0.35
        case .aggressive: return 0.60
        }
    }

    var topP: Double {
        switch self {
        case .conservative: return 0.75
        case .balanced: return 0.85
        case .aggressive: return 0.95
        }
    }

    var repeatPenalty: Double {
        switch self {
        case .conservative: return 1.10
        case .balanced: return 1.02
        case .aggressive: return 0.95
        }
    }

    var confidenceThreshold: Double {
        switch self {
        case .conservative: return 0.40
        case .balanced: return 0.25
        case .aggressive: return 0.10
        }
    }
}