import Foundation
import SwiftUI
import WaffleCore

@MainActor
final class ReviewQueueViewModel: ObservableObject {
    @Published var transcripts: [TranscriptRecord] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false

    var current: TranscriptRecord? { transcripts[safe: currentIndex] }

    var remaining: Int {
        transcripts.filter { $0.reviewStatus == nil }.count
    }

    func load(store: TranscriptStore) throws {
        isLoading = true
        defer { isLoading = false }
        transcripts = try store.fetchUnreviewed(limit: 50)
        currentIndex = 0
    }

    func approve(store: TranscriptStore) throws {
        try updateCurrentStatus(to: ReviewStatus.approved, store: store)
    }

    func dismiss(store: TranscriptStore) throws {
        try updateCurrentStatus(to: ReviewStatus.dismissed, store: store)
    }

    func skip() {
        guard transcripts.isEmpty == false else { return }
        currentIndex = min(currentIndex + 1, transcripts.count - 1)
    }

    func back() {
        guard transcripts.isEmpty == false else { return }
        currentIndex = max(currentIndex - 1, 0)
    }

    private func updateCurrentStatus(to status: String, store: TranscriptStore) throws {
        guard let transcript = current, let id = transcript.id else { return }
        try store.setReviewStatus(id: id, status: status)
        transcripts.remove(at: currentIndex)
        if transcripts.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, transcripts.count - 1)
        }
    }
}

@MainActor
final class ReviewQueueMenuState: ObservableObject {
    @Published var isQueuePresented = false
    @Published var unreviewedCount = 0

    private let store: TranscriptStore?

    init(store: TranscriptStore?) {
        self.store = store
    }

    func refreshBadgeCount() {
        guard let store else {
            unreviewedCount = 0
            return
        }
        unreviewedCount = (try? store.unreviewedCount()) ?? 0
    }

    func handleOpenQueueNotification(_ notification: Notification) {
        isQueuePresented = true
    }

    var reviewButtonTitle: String {
        if unreviewedCount > 0 {
            return "Review (\(unreviewedCount))"
        }
        return "Review"
    }
}

struct ReviewQueueView: View {
    let store: TranscriptStore
    let onOpenInHistory: (Int64) -> Void
    let onQueueChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ReviewQueueViewModel()
    @State private var errorMessage: String?

    init(
        store: TranscriptStore,
        onOpenInHistory: @escaping (Int64) -> Void,
        onQueueChanged: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onOpenInHistory = onOpenInHistory
        self.onQueueChanged = onQueueChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if viewModel.transcripts.isEmpty {
                    Text("All caught up!")
                        .font(.headline)
                } else {
                    Text("\(viewModel.currentIndex + 1) of \(viewModel.transcripts.count)")
                        .font(.headline)
                }
                Spacer()
            }

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let transcript = viewModel.current {
                transcriptCard(for: transcript)
                actionButtons
            } else {
                VStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("All caught up!")
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Open in History") {
                    guard let transcriptID = viewModel.current?.id else { return }
                    onOpenInHistory(transcriptID)
                    dismiss()
                }
                .disabled(viewModel.current?.id == nil)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 440)
        .task {
            do {
                try viewModel.load(store: store)
                onQueueChanged()
            } catch {
                errorMessage = "Failed to load review queue."
            }
        }
    }

    @ViewBuilder
    private func transcriptCard(for transcript: TranscriptRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(transcript.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transcript.modelID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let durationSeconds = transcript.durationSeconds {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(durationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let speakerCount = speakerCount(for: transcript) {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(speakerCount) speaker\(speakerCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView {
                Text(transcript.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button("Approve") {
                do {
                    try viewModel.approve(store: store)
                    errorMessage = nil
                    onQueueChanged()
                } catch {
                    errorMessage = "Failed to approve transcript."
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)

            Button("Dismiss") {
                do {
                    try viewModel.dismiss(store: store)
                    errorMessage = nil
                    onQueueChanged()
                } catch {
                    errorMessage = "Failed to dismiss transcript."
                }
            }
            .keyboardShortcut("d", modifiers: .command)
            .buttonStyle(.bordered)

            Button("Skip") {
                viewModel.skip()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .buttonStyle(.bordered)

            Button("Back") {
                viewModel.back()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .buttonStyle(.bordered)
        }
        .disabled(viewModel.current == nil)
    }

    private func speakerCount(for transcript: TranscriptRecord) -> Int? {
        if let speakerMap = transcript.speakerMap, speakerMap.isEmpty == false {
            return speakerMap.count
        }

        guard let segments = transcript.segments else { return nil }
        let speakers: Set<String> = Set(
            segments.compactMap { segment in
                let trimmed = segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let trimmed, trimmed.isEmpty == false else { return nil }
                return trimmed
            }
        )
        return speakers.isEmpty ? nil : speakers.count
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
