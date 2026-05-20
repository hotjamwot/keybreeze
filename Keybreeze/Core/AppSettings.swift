import Foundation

/// Consolidated application settings for PredictionSessionViewModel.
/// Single `save()` / `load()` contact point with `UserDefaults`.
/// Organised into nested Codable structs matching the plan's target shape.
struct AppSettings: Codable {
    var inference = InferenceSettings()
    var tuning = TuningSettings()
    var appGating = AppGatingSettings()
    var prompt = PromptSettings()

    // MARK: - Nested Settings Groups

    struct InferenceSettings: Codable {
        var temperature: Double = ModelOption.defaultTemperature
        var topP: Double = ModelOption.defaultTopP
        var repeatPenalty: Double = ModelOption.defaultRepeatPenalty
        var presencePenalty: Double = ModelOption.defaultPresencePenalty
        var confidenceThreshold: Double = ModelOption.defaultConfidenceThreshold
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
        var excludedBundleIDs: [String] = AccessibilityManager.defaultExcludedBundleIDs
        var manualOnlyBundleIDs: [String] = AccessibilityManager.defaultManualOnlyBundleIDs
    }

    struct PromptSettings: Codable {
        var customSystemPrompt: String = ""
        var styleNudge: String = ""
    }

    // MARK: - Persistence

    private static let storageKey = "com.keybreeze.appSettings"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            print("[AppSettings] Failed to encode settings")
            return
        }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func load() -> AppSettings {
        // First try to read from the consolidated store
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            return settings
        }

        // No consolidated data — try migrating from legacy flat keys.
        // If legacy keys exist, migrate and persist the new format.
        let hasLegacyKeys = UserDefaults.standard.array(forKey: "excludedBundleIDs") != nil
                         || UserDefaults.standard.array(forKey: "manualOnlyBundleIDs") != nil

        if hasLegacyKeys {
            var settings = AppSettings()

            if let saved = UserDefaults.standard.array(forKey: "excludedBundleIDs") as? [String] {
                settings.appGating.excludedBundleIDs = saved
            }
            if let saved = UserDefaults.standard.array(forKey: "manualOnlyBundleIDs") as? [String] {
                settings.appGating.manualOnlyBundleIDs = saved
            }

            // Remove legacy keys
            UserDefaults.standard.removeObject(forKey: "excludedBundleIDs")
            UserDefaults.standard.removeObject(forKey: "manualOnlyBundleIDs")

            // Persist consolidated format immediately
            settings.save()

            return settings
        }

        // No legacy data either — return fresh defaults
        return AppSettings()
    }
}