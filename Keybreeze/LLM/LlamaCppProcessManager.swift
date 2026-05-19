import Foundation
import OSLog

/// Manages the lifecycle of a local `llama-server` process.
///
/// On `start(modelPath:)` the manager spawns `llama-server`, waits for it to
/// become responsive at `/health`, and tracks its state. `stop()` kills the
/// process forcefully with SIGKILL so the port is released immediately.
/// Switching models is done by calling `restart(modelPath:)`.
@MainActor
final class LlamaCppProcessManager: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running(pid: Int32)
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    private var process: Process?
    private let log = Logger(subsystem: "app.keybreeze", category: "llamacpp-proc")

    let configuration: LlamaCppConfiguration

    /// The path to the `llama-server` binary (set by Homebrew).
    private static let serverBinary = "/opt/homebrew/bin/llama-server"

    init(configuration: LlamaCppConfiguration) {
        self.configuration = configuration
    }

    /// Launch `llama-server` with the given GGUF model file.
    /// - Parameter modelPath: Absolute path to a `.gguf` file.
    /// - Throws: `LlamaCppProcessError` if the binary is missing or the server
    ///   doesn't become ready within the timeout.
    func start(modelPath: String) async throws {
        // Ensure any lingering process on port 11345 is fully gone
        stop()

        guard FileManager.default.isExecutableFile(atPath: Self.serverBinary) else {
            let msg = "llama-server not found at \(Self.serverBinary). Run `brew install llama.cpp`."
            state = .failed(msg)
            throw LlamaCppProcessError.binaryNotFound(msg)
        }

        guard FileManager.default.fileExists(atPath: modelPath) else {
            let msg = "GGUF model not found at \(modelPath)."
            state = .failed(msg)
            throw LlamaCppProcessError.modelNotFound(msg)
        }

        state = .starting
        log.info("Starting llama-server with model \(modelPath)…")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.serverBinary)
        proc.arguments = [
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", "11345",
            "--ctx-size", "2048",
            "--n-predict", "-1",
            "--parallel", "1",
            "--cont-batching",
            "--mlock",
        ]

        // Pipe stdout/stderr to /dev/null to avoid cluttering console logs.
        let null = FileHandle.nullDevice
        proc.standardOutput = null
        proc.standardError = null

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.onTermination(p)
            }
        }

        do {
            try proc.run()
        } catch {
            state = .failed(error.localizedDescription)
            log.error("Failed to launch llama-server: \(error.localizedDescription)")
            throw LlamaCppProcessError.launchFailed(error.localizedDescription)
        }

        process = proc
        state = .running(pid: proc.processIdentifier)
        log.info("llama-server launched (pid \(proc.processIdentifier))")

        // Wait for the HTTP /health endpoint to become responsive.
        try await waitForReady()
    }

    /// Stop the server forcefully and wait for the port to be released.
    func stop() {
        guard let proc = process, proc.isRunning else { return }

        let pid = proc.processIdentifier
        log.info("Stopping llama-server (pid \(pid))…")

        // Force kill so the port is released immediately.
        proc.terminate()

        // Wait up to 3 seconds for the process to actually die.
        let start = DispatchTime.now()
        while DispatchTime.now() < start + .seconds(3) {
            if !proc.isRunning { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        // If still alive, SIGKILL
        if proc.isRunning {
            kill(pid, SIGKILL)
            Thread.sleep(forTimeInterval: 0.5)
        }

        process = nil
        state = .stopped
        log.info("llama-server stopped (pid \(pid))")
    }

    /// Convenience: stop + start with a new model.
    func restart(modelPath: String) async throws {
        try await start(modelPath: modelPath)
    }

    // MARK: - Private

    private func onTermination(_ proc: Process) {
        // Only clear state if this is still our tracked process.
        guard let current = process, current === proc else { return }
        process = nil
        let code = proc.terminationStatus
        if code == 0 || code == 15 || code == 9 || code == 2 {
            state = .stopped
            log.info("llama-server exited cleanly (code \(code))")
        } else {
            state = .failed("llama-server exited with code \(code)")
            log.warning("llama-server exited with code \(code)")
        }
    }

    /// Poll the server `/health` endpoint until it returns `{"status":"ok"}` or the timeout expires.
    private func waitForReady() async throws {
        let healthURL = configuration.baseURL.appendingPathComponent("health")
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 2
        sessionConfig.timeoutIntervalForResource = 60
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }

        for attempt in 1 ... 45 { // 45 * 0.5s = 22.5s timeout
            do {
                let (data, resp) = try await session.data(from: healthURL)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    // Decode to check for {"status":"ok"}
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                       json["status"] == "ok" {
                        log.info("llama-server ready after \(attempt) health-check(s)")
                        return
                    }
                }
            } catch {
                // Not ready yet – keep polling.
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
        }

        let msg = "llama-server did not become responsive within 22.5 s"
        state = .failed(msg)
        log.error("\(msg)")
        throw LlamaCppProcessError.timeout
    }
}

// MARK: - Errors

enum LlamaCppProcessError: Error, LocalizedError {
    case binaryNotFound(String)
    case modelNotFound(String)
    case launchFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let msg):      return msg
        case .modelNotFound(let msg):       return msg
        case .launchFailed(let msg):        return "Failed to launch llama-server: \(msg)"
        case .timeout:                      return "llama-server did not become ready in time."
        }
    }
}