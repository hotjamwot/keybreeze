import Foundation

/// Coalesces rapid events (keystrokes) into a single delayed action. MainActor-only for scheduler integration.
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
