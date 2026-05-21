import Foundation

/// Consolidated application settings.
struct AppSettings: Codable {
    var inference = InferenceSettings()
    var tuning = TuningSettings()
    var appGating = AppGatingSettings()
    var prompt = PromptSettings()

    struct InferenceSettings: Codable {
        var temperature: Double = 0.35
        var topP: Double = 0.85
        var repeatPenalty: Double = 1.02
        var presencePenalty: Double = 0.1
        var confidenceThreshold: Double = 0.25
    }

    struct TuningSettings: Codable {
        var verbosityBias: Double = 0.35
        var continuationBias: Double = 0.45
        var instructionStrictness: Double = 0.88
        var tuningMaxWords: Int = 0
        var midTypeWords: Int = 0
        var pauseWords: Int = 0
    }

    struct AppGatingSettings: Codable {
        var excludedBundleIDs: [String] = []
        var manualOnlyBundleIDs: [String] = []
    }

    struct PromptSettings: Codable {
        var customSystemPrompt: String = ""
        var styleNudge: String = ""
    }

    // MARK: Persistence

    private static let storageKey = "com.keybreeze.appSettings"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }
}