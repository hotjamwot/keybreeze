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

    /// Environment variables injected into the spawned `llama-server` process to
    /// isolate it from Ollama's Metal GPU context. These three knobs instruct
    /// ggml-metal to flush its resource-set allocator on every alloc/free cycle
    /// so stale Metal resource state never persists across process boundaries.
    ///
    /// - `GGML_METAL_NO_RETAIN_MEMORY=1` — do not hold Metal buffers resident
    ///   in GPU memory across context boundaries.
    /// - `GGML_METAL_DEVICE_ID=0` — pin to GPU device 0 so cross-device aliasing
    ///   between Keybreeze and a co-running Ollama is deterministic.
    /// - `GGML_METAL_RESOURCE_CACHE=0` — start from a cold resource cache every
    ///   launch; prevents on-disk or in-memory cache reuse from bleeding
    ///   allocations into the next invocation.
    private static let metalIsolationEnv: [String: String] = [
        "GGML_METAL_NO_RETAIN_MEMORY": "1",
        "GGML_METAL_DEVICE_ID":        "0",
        "GGML_METAL_RESOURCE_CACHE":   "0",
    ]

    init(configuration: LlamaCppConfiguration) {
        self.configuration = configuration
    }

    /// Forcefully kill whatever is listening on port 11345, if anything.
    /// This is a belt-and-suspenders approach in case a previous llama-server
    /// crashed and `stop()` couldn't kill it (because the Process handle was lost).
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
                    usleep(200_000) // 200ms per kill, let port release
                }
            }
        } catch {
            // lsof might not be available — just continue
        }
    }

    /// Launch `llama-server` with the given GGUF model file.
    /// - Parameter modelPath: Absolute path to a `.gguf` file.
    /// - Throws: `LlamaCppProcessError` if the binary is missing or the server
    ///   doesn't become ready within the timeout.
    func start(modelPath: String) async throws {
        // Ensure any lingering process on port 11345 is fully gone.
        // This is critical because llama.cpp can exit with code 1 on a prior
        // attempt, leaving `process = nil` — so stop() won't find anything to kill.
        stop()
        Self.killProcessOnPort11345()
        // Give the port a moment to fully release
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

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

        // Let llama-server use the GGUF's built-in chat template.
        // For Gemma 4, this only prepends <bos>, which the model needs
        // to begin generation. No user/model turn wrapping is added,
        // so the prompt is treated as raw text continuation.
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

        // Inject Metal isolation env-vars so ggml-metal starts from a clean
        // state and never leaves stale resource-set allocations behind when
        // this process is killed by VS Code or the OS.
        proc.environment = (ProcessInfo.processInfo.environment)
            .merging(Self.metalIsolationEnv) { current, _ in current }

        // Capture stderr to a file so we can diagnose crashes.
        // stdout goes to /dev/null to avoid clutter.
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
            state = .failed(error.localizedDescription)
            log.error("Failed to launch llama-server: \(error.localizedDescription)")
            throw LlamaCppProcessError.launchFailed(error.localizedDescription)
        }

        process = proc
        log.info("llama-server launched (pid \(proc.processIdentifier))")

        // Wait for the HTTP /health endpoint to become responsive.
        try await waitForReady()

        // waitForReady() can succeed against a stale server left over from a
        // previous session — it polls the port, not our process.  Verify that
        // the process we just spawned is still alive before declaring success.
        guard let proc = process, proc.isRunning else {
            let msg = "llama-server terminated immediately after launch"
            state = .failed(msg)
            log.error("\(msg) — check /tmp/keybreeze-llamaserver-stderr.log for details")
            throw LlamaCppProcessError.launchFailed(
                "\(msg). Check /tmp/keybreeze-llamaserver-stderr.log for the crash reason."
            )
        }

        // Only mark as running after the health check confirms the server is ready
        // to serve predictions. This prevents the readiness gate from passing too early.
        state = .running(pid: proc.processIdentifier)
    }

    /// Stop the server. Tries SIGTERM first (fast, lets `mlock` pages flush),
    /// then immediately escalates to SIGKILL if the process doesn't die within
    /// 1 second. The short drain window prevents Metal buffers from crossing the
    /// process boundary and poisoning the next llama.cpp invocation.
    func stop() {
        guard let proc = process, proc.isRunning else { return }

        let pid = proc.processIdentifier
        log.info("Stopping llama-server (pid \(pid))…")

        // Attempt a graceful SIGTERM first so the server can do its own
        // Metal context teardown (dealloc buffers, release rsets).
        proc.terminate()

        // Tlenient drain: 1 second before SIGKILL.
        let deadline = DispatchTime.now() + .seconds(1)
        while DispatchTime.now() < deadline, proc.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if proc.isRunning {
            log.warning("llama-server unresponsive after SIGTERM — escalating to SIGKILL")
            kill(pid, SIGKILL)
            // Give the OS a moment to tear down the task and release its
            // Metal device residency before we mark the port free.
            Thread.sleep(forTimeInterval: 0.5)
        }

        // As a final safety net, byte-sweep any process that still holds
        // port 11345 (covers the case where this killed a zombie but the
        // port is still in TIME_WAIT).
        Self.killProcessOnPort11345()

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