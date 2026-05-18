import Combine
import Foundation

/// Phase 2 harness: simulated typing field wired to the prediction scheduler.
@MainActor
final class PredictionSessionViewModel: ObservableObject {
    @Published var draftText: String = "The night was unusually quiet and he noticed "
    @Published private(set) var suggestion: String = ""
    @Published private(set) var statusMessage: String = "Scheduler stopped"
    @Published private(set) var isPredicting: Bool = false
    @Published var isSchedulerActive: Bool = false {
        didSet {
            if isSchedulerActive {
                scheduler.start()
                pushEditorState()
            } else {
                scheduler.stop()
                suggestion = ""
                isPredicting = false
                statusMessage = "Scheduler stopped"
            }
        }
    }

    private let appState: AppState
    private let scheduler: PredictionScheduler

    init(appState: AppState, engine: PredictionEngine? = nil) {
        self.appState = appState
        let sharedEngine = engine ?? PredictionEngine()
        self.scheduler = PredictionScheduler(engine: sharedEngine) { [weak appState] in
            appState?.selectedModel ?? ModelRegistry.defaultModel
        }

        scheduler.onSuggestionChange = { [weak self] text in
            self?.suggestion = text
        }
        scheduler.onRunningChange = { [weak self] running in
            self?.isPredicting = running
        }
        scheduler.onStatusChange = { [weak self] status in
            self?.statusMessage = status
        }
    }

    func draftTextChanged() {
        guard isSchedulerActive else { return }
        pushEditorState()
    }

    private func pushEditorState() {
        let state = EditorState(textBeforeCursor: draftText, textAfterCursor: "")
        scheduler.editorStateChanged(state)
    }
}
