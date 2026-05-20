import Foundation
import OSLog

/// Communicates with a local `llama-server` via its `POST /completion` endpoint.
///
/// Uses **non-streaming** mode (`stream: false`) because llama.cpp's SSE mode
/// keeps the connection open indefinitely after all tokens have been delivered
/// (no terminating event), which makes Swift's `bytes.lines` iterator hang.
/// For short continuations (≤32 tokens) the latency difference is negligible.
///
/// Owns the full lifecycle of the `llama-server` process internally, exposing
/// only a simple `serverState` publisher for UI readiness feedback.
final class LlamaCppService: LLMProvider, @unchecked Sendable {
    /// Observable server state (publishes on the main actor for UI binding).
    enum ServerState: Equatable {
        case stopped
        case starting
        case running(pid: Int32)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private let config: LLMConfig
    private let urlSession: URLSession
    private let lock = NSLock()
    private var activeStream: ActiveStream?
    private let log = Logger(subsystem: "app.keybreeze", category: "llamacpp-svc")

    // -- Process management (main-actor isolated in practice) --
    private var process: Process?
    private let processLock = NSLock()

    /// Published for UI observation. Read via `serverState` property.
    private nonisolated(unsafe) var _serverState = ServerState.stopped {
        didSet { notifyStateChange() }
    }
    /// The current server state. KVO-compatible accessor for consumers.
    var serverState: ServerState {
        lock.lock(); defer { lock.unlock() }
        return _serverState
    }

    private var stateChangeHandler: (@MainActor (ServerState) -> Void)?
    /// Register a callback for server state changes (called on main actor).
    func onStateChange(_ handler: @escaping @MainActor (ServerState) -> Void) {
        stateChangeHandler = handler
    }

    private func notifyStateChange() {
        let state = serverState
        Task { @MainActor in
            stateChangeHandler?(state)
        }
    }

    private final class ActiveStream {
        let task: Task<Void, Error>
        init(task: Task<Void, Error>) { self.task = task }
    }

    init(config: LLMConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    // MARK: - LLMProvider

    func streamCompletion(
        prompt: String,
        model: String,
        modelOption: ModelOption,
        maxWords: Int,
        onToken: @escaping (String) -> Void
    ) async throws {
        cancel()

        let stream = ActiveStream(
            task: Task { [config, urlSession] in
                let url = config.llamaCppBaseURL.appendingPathComponent("completion")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120

                // Compute n_predict from the word cap: ~4 tokens/word average, plus buffer.
                let predictedTokens: Int = min(maxWords * 4 + 8, 128)
                // Stop sequences tell the model when to cease generation.
                let stopSequences: [String] = ["\n", ".", "!", "?"]
                let body = LlamaCppCompletionRequest(
                    prompt: prompt,
                    stream: false,
                    n_predict: predictedTokens,
                    temperature: modelOption.temperature,
                    top_p: modelOption.topP,
                    repeat_penalty: modelOption.repeatPenalty,
                    cache_prompt: false,
                    stop: stopSequences
                )
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await urlSession.data(for: request)
                try Self.validate(response: response)

                let result = try JSONDecoder().decode(LlamaCppCompletionResponse.self, from: data)
                try Task.checkCancellation()

                if let content = result.content, !content.isEmpty {
                    onToken(content)
                }
            }
        )

        lock.lock()
        activeStream = stream
        lock.unlock()

        defer {
            lock.lock()
            if activeStream === stream {
                activeStream = nil
            }
            lock.unlock()
        }

        try await stream.task.value
    }

    func cancel() {
        lock.lock()
        let stream = activeStream
        activeStream = nil
        lock.unlock()
        stream?.task.cancel()
    }

    // MARK: - Model catalog

    /// Scans the configured GGUF directory and returns available models.
    static func scanModels(directory: String) -> [GGUFModel] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: directory)
        let log = Logger(subsystem: "app.keybreeze", category: "llamacpp-catalog")

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

    private static func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name
            .split(separator: "-")
            .map { String($0).capitalized }
            .joined(separator: " ")
    }

    // MARK: - Process lifecycle

    /// Launch `llama-server` with the given GGUF model file.
    /// - Parameter modelPath: Absolute path to a `.gguf` file.
    func startServer(modelPath: String) async throws {
        stopServer()
        Self.killProcessOnPort11345()

        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

        let binary = "/opt/homebrew/bin/llama-server"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            let msg = "llama-server not found at \(binary). Run `brew install llama.cpp`."
            _serverState = .failed(msg)
            throw LlamaCppProcessError.binaryNotFound(msg)
        }

        guard FileManager.default.fileExists(atPath: modelPath) else {
            let msg = "GGUF model not found at \(modelPath)."
            _serverState = .failed(msg)
            throw LlamaCppProcessError.modelNotFound(msg)
        }

        _serverState = .starting
        log.info("Starting llama-server with model \(modelPath)…")

        try await Self.waitForPortAvailable()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
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

        let metalIsolationEnv: [String: String] = [
            "GGML_METAL_NO_RETAIN_MEMORY": "1",
            "GGML_METAL_DEVICE_ID":        "0",
            "GGML_METAL_RESOURCE_CACHE":   "0",
        ]
        proc.environment = (ProcessInfo.processInfo.environment)
            .merging(metalIsolationEnv) { current, _ in current }

        let null = FileHandle.nullDevice
        proc.standardOutput = null
        let logPath = URL(fileURLWithPath: "/tmp/keybreeze-llamaserver-stderr.log")
        try? FileManager.default.removeItem(at: logPath)
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
        proc.standardError = try? FileHandle(forWritingTo: logPath)
        log.info("llama-server stderr → \(logPath.path)")

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.onTermination(p)
            }
        }

        do {
            try proc.run()
        } catch {
            _serverState = .failed(error.localizedDescription)
            log.error("Failed to launch llama-server: \(error.localizedDescription)")
            throw LlamaCppProcessError.launchFailed(error.localizedDescription)
        }

        process = proc
        log.info("llama-server launched (pid \(proc.processIdentifier))")

        try await waitForReady()

        guard let proc = process, proc.isRunning else {
            let msg = "llama-server terminated immediately after launch"
            _serverState = .failed(msg)
            log.error("\(msg) — check /tmp/keybreeze-llamaserver-stderr.log for details")
            throw LlamaCppProcessError.launchFailed(
                "\(msg). Check /tmp/keybreeze-llamaserver-stderr.log for the crash reason."
            )
        }

        _serverState = .running(pid: proc.processIdentifier)
    }

    /// Stop the server gracefully (SIGTERM → SIGKILL after 1s).
    func stopServer() {
        guard let proc = process, proc.isRunning else { return }

        let pid = proc.processIdentifier
        log.info("Stopping llama-server (pid \(pid))…")

        proc.terminate()

        let deadline = DispatchTime.now() + .seconds(1)
        while DispatchTime.now() < deadline, proc.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if proc.isRunning {
            log.warning("llama-server unresponsive after SIGTERM — escalating to SIGKILL")
            kill(pid, SIGKILL)
            Thread.sleep(forTimeInterval: 0.5)
        }

        Self.killProcessOnPort11345()

        process = nil
        _serverState = .stopped
        log.info("llama-server stopped (pid \(pid))")
    }

    // MARK: - Private: process support

    private static func killProcessOnPort11345() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", "tcp:11345"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let pids = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
            let killable = pids.filter { $0 > 1 }
            if !killable.isEmpty {
                Logger(subsystem: "app.keybreeze", category: "llamacpp-proc")
                    .info("Found llama-server PIDs on port 11345, killing: \(killable.map(String.init).joined(separator: ","))")
                for pid in killable {
                    kill(pid, SIGKILL)
                    usleep(1_500_000)
                }
            }
        } catch {
            // lsof not available — just continue
        }
    }

    private static func waitForPortAvailable() async throws {
        let log = Logger(subsystem: "app.keybreeze", category: "llamacpp-proc")
        log.info("Waiting for port 11345 to become available…")
        let backoffs: [UInt64] = [200_000_000, 500_000_000, 1_000_000_000, 2_000_000_000, 3_000_000_000]
        let deadline = DispatchTime.now() + .seconds(30)
        var attempt = 0

        while DispatchTime.now() < deadline {
            let pid = getServerPIDOnPort11345()
            if pid == nil {
                log.info("Port 11345 is now free")
                return
            }
            let remaining = deadline.uptimeNanoseconds - DispatchTime.now().uptimeNanoseconds
            let delay = min(backoffs[attempt % backoffs.count], max(0, UInt64(remaining)))
            attempt += 1
            try await Task.sleep(nanoseconds: delay)
        }

        let msg = "Timed out waiting for port 11345 to become available after 30 s"
        log.error("\(msg)")
        throw LlamaCppProcessError.launchFailed(msg)
    }

    private static func getServerPIDOnPort11345() -> Int32? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", "tcp:11345"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let pids = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
            return pids.filter { $0 > 1 }.first
        } catch {
            return nil
        }
    }

    private func onTermination(_ proc: Process) {
        guard let current = process, current === proc else { return }
        process = nil
        let code = proc.terminationStatus
        if code == 0 || code == 15 || code == 9 || code == 2 {
            _serverState = .stopped
            log.info("llama-server exited cleanly (code \(code))")
        } else {
            _serverState = .failed("llama-server exited with code \(code)")
            log.warning("llama-server exited with code \(code)")
        }
    }

    private func waitForReady() async throws {
        let healthURL = config.llamaCppBaseURL.appendingPathComponent("health")
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 2
        sessionConfig.timeoutIntervalForResource = 60
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }

        for attempt in 1 ... 45 {
            do {
                let (data, resp) = try await session.data(from: healthURL)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                       json["status"] == "ok" {
                        log.info("llama-server ready after \(attempt) health-check(s)")
                        return
                    }
                }
            } catch {
                // Not ready yet – keep polling
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let msg = "llama-server did not become responsive within 22.5 s"
        _serverState = .failed(msg)
        log.error("\(msg)")
        throw LlamaCppProcessError.timeout
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LlamaCppLLMError.unexpectedResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw LlamaCppLLMError.httpStatus(http.statusCode)
        }
    }
}

// MARK: - Errors

enum LlamaCppLLMError: Error, LocalizedError {
    case unexpectedResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "Unexpected response from llama.cpp."
        case .httpStatus(let code):
            if code == 404 {
                "llama.cpp returned HTTP 404 — unknown route or model not loaded. Confirm llama-server is running."
            } else {
                "llama.cpp returned HTTP \(code)."
            }
        }
    }
}

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

// MARK: - DTOs

private struct LlamaCppCompletionRequest: Encodable {
    let prompt: String
    let stream: Bool
    let n_predict: Int
    let temperature: Double
    let top_p: Double
    let repeat_penalty: Double
    let cache_prompt: Bool
    let stop: [String]
}

private struct LlamaCppCompletionResponse: Decodable {
    let content: String?
    let stop: Bool?
}

// MARK: - Public model type (moved from LlamaCppModelCatalog)

/// Represents a single GGUF model file found on disk.
struct GGUFModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let fileSizeMB: Double
    let url: URL
}