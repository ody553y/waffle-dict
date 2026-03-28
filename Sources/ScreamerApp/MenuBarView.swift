import SwiftUI
import ScreamerCore

struct MenuBarView: View {
    @State private var workerStatus: String = "Checking…"
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("Worker: \(workerStatus)")
                    .font(.caption)
            }

            Divider()

            Button(isRecording ? "Stop Recording" : "Start Recording") {
                isRecording.toggle()
            }
            .keyboardShortcut("r")

            Divider()

            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 220)
        .task {
            await checkWorker()
        }
    }

    private var statusColor: Color {
        switch workerStatus {
        case "OK": return .green
        case "Checking…": return .yellow
        default: return .red
        }
    }

    private func checkWorker() async {
        let client = WorkerClient()
        do {
            let health = try await client.fetchHealth()
            workerStatus = health.status == "ok" ? "OK" : health.status
        } catch {
            workerStatus = "Offline"
        }
    }
}
