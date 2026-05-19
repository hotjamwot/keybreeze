import SwiftUI

/// Panel for managing app-level prediction behavior.
/// Excluded apps: auto-trigger disabled entirely.
/// Manual-only apps: auto-trigger disabled, but manual trigger works.
struct AppGatingPanelView: View {
    @EnvironmentObject private var predictionSession: PredictionSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Gating")
                .font(.subheadline.weight(.semibold))

            Text("Prevent autocomplete in apps where it would be invasive or interfere with native completions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Excluded Apps (auto-trigger disabled)")
                    .font(.caption.weight(.medium))

                BundleIDListView(
                    bundleIDs: $predictionSession.excludedBundleIDs,
                    placeholder: "No excluded apps"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Manual-Only Apps (manual trigger only)")
                    .font(.caption.weight(.medium))

                BundleIDListView(
                    bundleIDs: $predictionSession.manualOnlyBundleIDs,
                    placeholder: "No manual-only apps"
                )
            }

            Button("Reset to Defaults") {
                predictionSession.excludedBundleIDs = .defaultExcluded
                predictionSession.manualOnlyBundleIDs = .defaultManualOnly
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Convenience extensions

private extension Array where Element == String {
    static var defaultExcluded: [String] {
        AccessibilityManager.defaultExcludedBundleIDs
    }

    static var defaultManualOnly: [String] {
        AccessibilityManager.defaultManualOnlyBundleIDs
    }
}

struct BundleIDListView: View {
    @Binding var bundleIDs: [String]
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(bundleIDs, id: \.self) { id in
                HStack {
                    Text(id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { bundleIDs.removeAll { $0 == id } }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }

            if bundleIDs.isEmpty {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }
}