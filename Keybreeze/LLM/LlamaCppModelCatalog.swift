import Foundation
import OSLog

/// Scans a directory of GGUF model files and provides a list of available models.
struct LlamaCppModelCatalog {
    private static let log = Logger(subsystem: "app.keybreeze", category: "llamacpp-catalog")

    /// Scans `directory` for `.gguf` files recursively and returns their metadata.
    /// - Parameter directory: Absolute path to the folder containing GGUF files.
    /// - Returns: An array of `GGUFModel` instances, sorted by filename.
    static func scanDirectory(_ directory: String) -> [GGUFModel] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: directory)

        guard fm.fileExists(atPath: directory) else {
            log.warning("GGUF directory does not exist: \(directory)")
            return []
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            log.warning("Could not enumerate GGUF directory: \(directory)")
            return []
        }

        var models: [GGUFModel] = []

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true,
                  fileURL.pathExtension.lowercased() == "gguf"
            else { continue }

            let fileSize = resourceValues.fileSize ?? 0
            let sizeMB = Double(fileSize) / 1_000_000.0
            let displayName = Self.displayName(for: fileURL)

            models.append(GGUFModel(
                id: fileURL.path,
                displayName: displayName,
                fileSizeMB: sizeMB,
                url: fileURL
            ))
        }

        models.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        log.info("Found \(models.count) GGUF model(s) in \(directory)")
        return models
    }

    /// Derive a human-readable display name from the filename.
    /// E.g. "gemma-4-E2B-i1-Q4_K_M.gguf" → "Gemma 4 E2B i1 Q4_K_M"
    private static func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        // Split on hyphens and capitalise each part
        return name
            .split(separator: "-")
            .map { String($0).capitalized }
            .joined(separator: " ")
    }
}

/// Represents a single GGUF model file found on disk.
struct GGUFModel: Identifiable, Hashable, Sendable {
    let id: String // The full file path
    let displayName: String
    let fileSizeMB: Double
    let url: URL
}