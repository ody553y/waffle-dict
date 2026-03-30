import Foundation

/// Manages the lifecycle of the Python worker subprocess.
public final class WorkerProcess: Sendable {
    private let configuration: WorkerConfiguration
    private let pythonPath: String
    private let workerModulePath: String

    public init(
        configuration: WorkerConfiguration = WorkerConfiguration(),
        pythonPath: String = "python3",
        workerModulePath: String? = nil
    ) {
        self.configuration = configuration
        self.pythonPath = pythonPath
        self.workerModulePath = workerModulePath ?? Self.defaultWorkerModulePath()
    }

    /// Spawns the worker, waits for `/health` to respond, and returns the running `Process`.
    public func start(timeout: TimeInterval = 10) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-m", "waffle_worker",
            "--host", configuration.host,
            "--port", String(configuration.port),
        ]
        process.environment = ProcessInfo.processInfo.environment
        process.currentDirectoryURL = URL(fileURLWithPath: workerModulePath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let client = WorkerClient(configuration: configuration)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                let health = try await client.fetchHealth()
                if health.status == "ok" {
                    return process
                }
            } catch {
                // Worker not ready yet — retry.
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        process.terminate()
        throw WorkerProcessError.startupTimeout
    }

    private static func defaultWorkerModulePath() -> String {
        let fileManager = FileManager.default

        // Development path: when running via `swift run`, currentDirectoryPath is repo root.
        let workerInCurrentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("worker", isDirectory: true)
            .path
        if fileManager.fileExists(atPath: workerInCurrentDirectory) {
            return workerInCurrentDirectory
        }

        let bundlePath = Bundle.main.bundlePath
        let workerInBundle = (bundlePath as NSString).appendingPathComponent("Contents/Resources/worker")
        if fileManager.fileExists(atPath: workerInBundle) {
            return workerInBundle
        }

        // Fallback: walk upward from the bundle path and use the first `worker/` directory found.
        var cursor = URL(fileURLWithPath: bundlePath, isDirectory: false)
            .deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = cursor.appendingPathComponent("worker", isDirectory: true).path
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
            cursor.deleteLastPathComponent()
        }

        // Last-resort path for development tooling.
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("worker", isDirectory: true)
            .path
    }
}

public enum WorkerProcessError: Error {
    case startupTimeout
}
