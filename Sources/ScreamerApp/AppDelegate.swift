import AppKit
import ScreamerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var workerProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let wp = WorkerProcess()
                workerProcess = try await wp.start()
            } catch {
                print("[Screamer] Worker failed to start: \(error)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        workerProcess?.terminate()
    }
}
