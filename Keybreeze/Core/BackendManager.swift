import Foundation
import OSLog

/// Manages the lifecycle of LLM backend processes (Ollama and llama.cpp).
///
/// State machine:
///   idle → starting → ready(ollama) / ready(llamaCpp)
///   ready(X) → stopping → idle → starting → ready(Y)
///   ready(llamaCpp) → switching → ready(llamaCpp)   (model restart)
///
/// Process monitoring runs on a background thread. State mutations
/// are isolated to @MainActor. App termination uses synchronous SIGKILL.
@MainActor
final class BackendManager {
    private let log = Logger(subsystem: "app.keybreeze", category: "backend")

    // MARK: Published State

    @Published private(set) var state: BackendState = .idle
    @Published private(set) var statusMessage = "Idle"

    /// Whether the last boot attempt succeeded.
    @Published private(set) var isReady = false

    /// Human-readable error from the last failure.
    @Published private(set) var lastError: String?

    // MARK: Binary Paths (configurable)

    /// User-configured override paths. If empty, auto-detection is used.
    var customOllamaPath: String = ""
    var customLlamaServerPath: String = ""

    // MARK: Private

    private var ollamaProcess: Process?
    private var llamaProcess: Process?

    /// True only if **we** spawned Ollama (not if it was already running).
    private var didWeSpawnOllama = false

    private var healthCheckTask: Task<Void, Never>?

    // MARK: Binary Resolution

    /// Resolve the Ollama binary path.
    /// Priority: custom → /opt/homebrew/bin → /usr/local/bin
    private func resolveOllamaBinary() -> String? {
        if !customOllamaPath.isEmpty, FileManager.default.isExecutableFile(atPath: customOllamaPath) {
            return customOllamaPath
        }
        let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Resolve the llama-server binary path.
    /// Priority: custom → Homebrew cellar → /opt/homebrew/bin → /usr/local/bin
    private func resolveLlamaServerBinary() -> String? {
        if !customLlamaServerPath.isEmpty, FileManager.default.isExecutableFile(atPath: customLlamaServerPath) {
            return customLlamaServerPath
        }
        // Check Homebrew cellar first (dynamic version directory)
        if let base = try? FileManager.default.contentsOfDirectory(atPath: "/opt/homebrew/Cellar/llama.cpp"),
           let version = base.sorted(by: >).first {
            let path = "/opt/homebrew/Cellar/llama.cpp/\(version)/bin/llama-server"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let candidates = ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: Boot

    /// Boot the given backend. If the backend is already running, this is a no-op.
    /// If a different backend is running, it will be torn down first.
    func boot(backend: LLMBackend, modelPath: String, ggufDirectory: String) {
        // If already running this backend, just ensure health
        switch state {
        case .ready(let current) where current == backend:
            log.info("Backend \(backend.displayName) is already ready — checking health")
            checkHealthAsync(backend: backend)
            return
        case .starting, .stopping:
            log.warning("Boot called while in state \(self.state) — ignoring")
            return
        default:
            break
        }

        // Tear down whatever is currently running
        tearDownSync()

        state = .starting
        statusMessage = "Starting \(backend.displayName)..."
        lastError = nil

        switch backend {
        case .ollama:
            bootOllama()
        case .llamaCpp:
            bootLlamaCpp(modelPath: modelPath)
        }
    }

    /// Boot Ollama — health check first, then spawn if unreachable.
    private func bootOllama() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            // Phase 1: Health check
            if await self.checkOllamaHealth() {
                await MainActor.run {
                    self.didWeSpawnOllama = false
                    self.state = .ready(.ollama)
                    self.isReady = true
                    self.statusMessage = "Ready (Ollama)"
                    self.log.info("Ollama already running — using existing service")
                }
                return
            }

            // Phase 2: Resolve binary
            let binaryPath = await MainActor.run { self.resolveOllamaBinary() }
            guard let binaryPath else {
                await MainActor.run {
                    self.state = .idle
                    self.isReady = false
                    self.lastError = "Ollama binary not found. Install via Homebrew: brew install ollama"
                    self.statusMessage = "Error: Ollama binary not found"
                    self.log.error("Ollama binary not found")
                }
                return
            }

            // Phase 3: Spawn
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["serve"]
            process.standardOutput = Pipe()    // silently consume stdout
            process.standardError = Pipe()

            do {
                try process.run()
                await MainActor.run {
                    self.ollamaProcess = process
                    self.didWeSpawnOllama = true
                    self.log.info("Spawned Ollama serve (PID: \(process.processIdentifier))")
                }

                // Phase 4: Wait for health
                var healthy = false
                for _ in 0..<30 { // up to 15 seconds
                    try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    if await self.checkOllamaHealth() {
                        healthy = true
                        break
                    }
                }

                await MainActor.run {
                    if healthy {
                        self.state = .ready(.ollama)
                        self.isReady = true
                        self.statusMessage = "Ready (Ollama)"
                        self.log.info("Ollama is healthy")
                    } else {
                        self.state = .idle
                        self.isReady = false
                        self.lastError = "Ollama failed to become healthy within 15s"
                        self.statusMessage = "Error: Ollama timeout"
                        self.log.error("Ollama health check timed out")
                    }
                }
            } catch {
                await MainActor.run {
                    self.state = .idle
                    self.isReady = false
                    self.lastError = "Failed to launch Ollama: \(error.localizedDescription)"
                    self.statusMessage = "Error: Ollama launch failed"
                    self.log.error("Ollama launch error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Boot llama.cpp — spawn llama-server with the given GGUF file.
    private func bootLlamaCpp(modelPath: String) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            // Phase 1: Resolve binary
            let binaryPath = await MainActor.run { self.resolveLlamaServerBinary() }
            guard let binaryPath else {
                await MainActor.run {
                    self.state = .idle
                    self.isReady = false
                    self.lastError = "llama-server not found. Install via: brew install llama.cpp"
                    self.statusMessage = "Error: llama-server not found"
                    self.log.error("llama-server binary not found")
                }
                return
            }

            // Phase 2: Verify GGUF exists
            guard FileManager.default.fileExists(atPath: modelPath) else {
                await MainActor.run {
                    self.state = .idle
                    self.isReady = false
                    self.lastError = "GGUF file not found: \(modelPath)"
                    self.statusMessage = "Error: Model file not found"
                    self.log.error("GGUF not found at \(modelPath)")
                }
                return
            }

            // Phase 3: Spawn with tuned flags
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = [
                "--model", modelPath,
                "--host", "127.0.0.1",
                "--port", "11345",
                "--ctx-size", "512",
                "--threads", "4",
                "--ubatch-size", "256",
                "--flash-attn", "on",
                "--no-chat-template",
                "--temp", "0.0",
                "--top-p", "0.1",
            ]
            process.standardOutput = Pipe() // silently consume stdout

            // Monitor stderr for readiness — llama-server prints "starting server" when ready
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
                await MainActor.run {
                    self.llamaProcess = process
                    self.log.info("Spawned llama-server (PID: \(process.processIdentifier))")
                }

                // Phase 4: Monitor stderr for startup confirmation
                let fileHandle = stderrPipe.fileHandleForReading
                var isReady = false

                // Read stderr in chunks until we see the ready message or timeout
                let startTime = Date()
                let timeout: TimeInterval = 30.0
                let chunkSize = 1024

                while Date().timeIntervalSince(startTime) < timeout, !isReady {
                    let data = fileHandle.availableData
                    if data.isEmpty {
                        // No data yet — wait a bit
                        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
                        continue
                    }
                    if let output = String(data: data, encoding: .utf8) {
                        self.log.debug("llama-server stderr: \(output)")
                        // Detect readiness — look for common start messages
                        if output.contains("starting server") ||
                           output.contains("model loaded") ||
                           output.contains("build info") {
                            isReady = true
                        }
                    }
                }

                // Fallback: if we didn't catch the ready message, try health check
                if !isReady {
                    // Wait a bit more, then check via HTTP
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                    isReady = await self.checkLlamaCppHealth()
                }

                await MainActor.run {
                    if isReady {
                        self.state = .ready(.llamaCpp)
                        self.isReady = true
                        self.statusMessage = "Ready (llama.cpp)"
                        self.log.info("llama-server is ready")
                    } else {
                        // Process might have crashed — check
                        if !process.isRunning {
                            let reason = process.terminationReason == .exit
                                ? "exit code \(process.terminationStatus)"
                                : "uncaught signal"
                            self.lastError = "llama-server terminated early: \(reason)"
                            self.statusMessage = "Error: llama-server crashed"
                            self.log.error("llama-server terminated: \(reason)")
                        } else {
                            self.lastError = "llama-server failed to become healthy within timeout"
                            self.statusMessage = "Error: llama-server timeout"
                            self.log.error("llama-server health check timed out")
                        }
                        self.state = .idle
                        self.isReady = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.state = .idle
                    self.isReady = false
                    self.lastError = "Failed to launch llama-server: \(error.localizedDescription)"
                    self.statusMessage = "Error: llama-server launch failed"
                    self.log.error("llama-server launch error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Model Switching (llama.cpp only)

    /// Switch the model for the llama.cpp backend. Terminates the current
    /// llama-server and spawns a new one with the given GGUF path.
    /// For Ollama, this is a no-op (model switching is done via API payload).
    func switchModel(to modelPath: String, ggufDirectory: String) {
        guard case .ready(let backend) = state else {
            log.warning("switchModel called but backend not ready")
            return
        }

        switch backend {
        case .ollama:
            log.info("Ollama model switch is a no-op — model string is set in API payload")
            // The LLMClient already uses the model ID from the request — no process action needed
        case .llamaCpp:
            log.info("Switching llama.cpp model to \(modelPath)")
            // Terminate current, respawn with new model
            tearDownSync()
            bootLlamaCpp(modelPath: modelPath)
        }
    }

    // MARK: Backend Switching

    /// Switch from the current backend to a new one. Tears down the current
    /// process and boots the new one.
    func switchBackend(to newBackend: LLMBackend, modelPath: String, ggufDirectory: String) {
        log.info("Switching backend from \(self.state.displayName) to \(newBackend.displayName)")

        switch state {
        case .starting, .stopping:
            log.warning("Backend switch called while in state \(self.state) — forcing teardown first")
            tearDownSync()
        case .ready(let current) where current == newBackend:
            log.info("Already running \(newBackend.displayName) — no switch needed")
            return
        default:
            tearDownSync()
        }

        boot(backend: newBackend, modelPath: modelPath, ggufDirectory: ggufDirectory)
    }

    // MARK: Health Checks

    /// Periodic health check for the active backend.
    private func checkHealthAsync(backend: LLMBackend) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let healthy: Bool
            switch backend {
            case .ollama:
                healthy = await self.checkOllamaHealth()
            case .llamaCpp:
                healthy = await self.checkLlamaCppHealth()
            }
            if !healthy {
                await MainActor.run {
                    self.log.warning("Health check failed for \(backend.displayName)")
                    self.isReady = false
                    self.statusMessage = "Unhealthy — reconnect?"
                }
            }
        }
    }

    private func checkOllamaHealth() async -> Bool {
        let url = URL(string: "http://127.0.0.1:11434")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func checkLlamaCppHealth() async -> Bool {
        let url = URL(string: "http://127.0.0.1:11345/health")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            // llama-server may not have a /health endpoint — fall back to root
            let fallback = URL(string: "http://127.0.0.1:11345")!
            if let (_, fallbackResponse) = try? await URLSession.shared.data(from: fallback) {
                return (fallbackResponse as? HTTPURLResponse)?.statusCode == 200
            }
            return false
        }
    }

    // MARK: Termination

    /// Graceful async termination — sends SIGTERM, waits 3s, then SIGKILL.
    func terminateAll() async {
        log.info("Terminating all backend processes...")
        if let proc = ollamaProcess, didWeSpawnOllama {
            terminateProcess(proc, name: "Ollama")
            ollamaProcess = nil
            didWeSpawnOllama = false
        }
        if let proc = llamaProcess {
            terminateProcess(proc, name: "llama-server")
            llamaProcess = nil
        }
        await MainActor.run {
            self.state = .idle
            self.isReady = false
            self.statusMessage = "Terminated"
        }
    }

    /// Synchronous emergency termination — SIGKILL immediately.
    /// Used from NSApplication.willTerminateNotification where async is unsafe.
    func terminateAllSync() {
        log.info("Emergency termination of all backend processes...")

        if let proc = ollamaProcess, didWeSpawnOllama {
            killProcess(proc, name: "Ollama")
            ollamaProcess = nil
            didWeSpawnOllama = false
        }
        if let proc = llamaProcess {
            killProcess(proc, name: "llama-server")
            llamaProcess = nil
        }

        // Also pkill as a safety net for orphaned processes
        // Fire-and-forget — this is the last thing before app exit
        Task.detached(priority: .background) {
            do {
                try await Process.run(
                    URL(fileURLWithPath: "/usr/bin/pkill"),
                    arguments: ["-9", "-f", "llama-server"]
                )
            } catch {
                // Best-effort safety net — ignore failures at shutdown
            }
        }

        state = .idle
        isReady = false
        statusMessage = "Terminated"
    }

    // MARK: Private Helpers

    /// Synchronous teardown of all processes. Blocks until processes exit.
    private func tearDownSync() {
        if let proc = ollamaProcess {
            if didWeSpawnOllama {
                terminateProcess(proc, name: "Ollama")
            }
            ollamaProcess = nil
            didWeSpawnOllama = false
        }
        if let proc = llamaProcess {
            terminateProcess(proc, name: "llama-server")
            llamaProcess = nil
        }
        state = .idle
        isReady = false
        statusMessage = "Idle"
    }

    /// Send SIGTERM, wait up to 3 seconds, then SIGKILL.
    private func terminateProcess(_ process: Process, name: String) {
        guard process.isRunning else { return }
        log.info("Terminating \(name) (PID: \(process.processIdentifier))")

        process.interrupt() // SIGTERM
        process.terminate()

        // Wait for exit with timeout
        let deadline = DispatchTime.now() + .seconds(3)
        while process.isRunning, DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            log.warning("\(name) did not exit gracefully — force killing")
            killProcess(process, name: name)
        }
    }

    /// Immediately SIGKILL the process.
    private func killProcess(_ process: Process, name: String) {
        guard process.isRunning else { return }
        log.warning("Force killing \(name) (PID: \(process.processIdentifier))")
        kill(process.processIdentifier, SIGKILL)
    }
}

// MARK: - State

enum BackendState: Equatable, CustomStringConvertible {
    case idle
    case starting
    case ready(LLMBackend)
    case stopping

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .starting: return "Starting..."
        case .ready(let backend): return "Ready (\(backend.displayName))"
        case .stopping: return "Stopping..."
        }
    }

    var description: String {
        displayName
    }
}
