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
            "-m", "screamer_worker",
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
        let bundlePath = Bundle.main.bundlePath
        let workerInBundle = (bundlePath as NSString).appendingPathComponent("Contents/Resources/worker")
        if FileManager.default.fileExists(atPath: workerInBundle) {
            return workerInBundle
        }
        // Fallback: assume worker/ is next to the Package.swift during development.
        return (bundlePath as NSString)
            .deletingLastPathComponent
            .appending("/worker")
    }
}

public enum WorkerProcessError: Error {
    case startupTimeout
}
