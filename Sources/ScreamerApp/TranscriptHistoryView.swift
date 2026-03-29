import AppKit
import Foundation
import ScreamerCore
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptHistoryView: View {
    @ObservedObject private var modelStore: ModelStore
    @StateObject private var viewModel: TranscriptHistoryViewModel
    @State private var expandedRecordIDs: Set<Int64> = []
    @State private var isDropTargeted = false

    init(transcriptStore: TranscriptStore, modelStore: ModelStore) {
        self._modelStore = ObservedObject(wrappedValue: modelStore)
        self._viewModel = StateObject(
            wrappedValue: TranscriptHistoryViewModel(transcriptStore: transcriptStore)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone

            TextField("Search transcripts", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.reloadForSearchQuery()
                }

            Text("Tip: Command-click transcript rows to multi-select for JSON batch export.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("All transcript history is stored locally on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selectedModel = modelStore.selectedEntry, selectedModel.family == .parakeet {
                Text("Parakeet currently works best with WAV files for imported audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.importJobs.isEmpty == false {
                importJobsView
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.records.isEmpty, viewModel.isLoading == false {
                ContentUnavailableView(
                    viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No transcripts yet"
                        : "No results",
                    systemImage: "waveform.and.magnifyingglass",
                    description: Text(
                        viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Start a dictation or import audio to build your history."
                            : "Try a different search term."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(viewModel.records.enumerated()), id: \.offset) { index, record in
                            transcriptRow(record)
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(currentIndex: index)
                                }
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 540)
        .toolbar {
            ToolbarItemGroup {
                Button("Import File…") {
                    presentImportFilePanel()
                }

                Button("Copy Text") {
                    viewModel.copySelectedToPasteboard()
                }
                .disabled(viewModel.selectedRecord == nil)

                Button("Export") {
                    viewModel.exportSelection()
                }
                .disabled(viewModel.selectedRecords.isEmpty)

                Button("Delete", role: .destructive) {
                    let deletedID = viewModel.selectedRecord?.id
                    viewModel.deleteSelected()
                    if let deletedID {
                        expandedRecordIDs.remove(deletedID)
                    }
                }
                .disabled(viewModel.selectedRecord == nil)
            }
        }
        .task {
            modelStore.refreshCatalog()
            viewModel.loadInitial()
        }
        .onChange(of: viewModel.records) { _, newRecords in
            let validIDs = Set(newRecords.compactMap(\.id))
            expandedRecordIDs = expandedRecordIDs.intersection(validIDs)
            viewModel.retainSelection(validIDs: validIDs)
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                Text("Drop audio files here")
                    .font(.headline)
                Spacer()
                Text("WAV, MP3, M4A, FLAC, OGG")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Imports are processed one file at a time and saved to history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .dropDestination(for: URL.self) { droppedURLs, _ in
            guard droppedURLs.isEmpty == false else { return false }
            viewModel.enqueueImportedFiles(
                droppedURLs,
                selectedModelID: modelStore.resolvedSelectedModelID,
                languageHint: nil
            )
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private var importJobsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.importJobs) { job in
                HStack(spacing: 8) {
                    switch job.status {
                    case .queued:
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Queued: \(job.fileName)")
                            .font(.caption)
                    case .transcribing:
                        ProgressView()
                            .controlSize(.small)
                        Text("Transcribing: \(job.fileName)")
                            .font(.caption)
                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import failed: \(job.fileName)")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.07))
                )
            }
        }
    }

    private func presentImportFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = TranscriptHistoryViewModel.supportedContentTypes

        guard panel.runModal() == .OK else { return }

        viewModel.enqueueImportedFiles(
            panel.urls,
            selectedModelID: modelStore.resolvedSelectedModelID,
            languageHint: nil
        )
    }

    @ViewBuilder
    private func transcriptRow(_ record: TranscriptRecord) -> some View {
        let isExpanded = record.id.map { expandedRecordIDs.contains($0) } ?? false
        let isSelected = record.id.map { viewModel.selectedRecordIDs.contains($0) } ?? false

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(Self.dateFormatter.string(from: record.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                sourceBadge(for: record)

                Spacer(minLength: 12)

                Text(modelDisplayName(for: record.modelID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(previewText(for: record.text, maxLength: 120))
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if isExpanded {
                Divider()
                Text(record.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.07))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard let recordID = record.id else { return }
            let additiveSelection = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            viewModel.selectRecord(id: recordID, additive: additiveSelection)
            if expandedRecordIDs.contains(recordID) {
                expandedRecordIDs.remove(recordID)
            } else {
                expandedRecordIDs.insert(recordID)
            }
        }
    }

    private func sourceBadge(for record: TranscriptRecord) -> some View {
        let label: String
        if record.sourceType == "dictation" {
            label = "Dictation"
        } else if let sourceFileName = record.sourceFileName, sourceFileName.isEmpty == false {
            label = sourceFileName
        } else {
            label = "Imported File"
        }

        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func modelDisplayName(for modelID: String) -> String {
        modelStore.catalog.first(where: { $0.id == modelID })?.displayName ?? modelID
    }

    private func previewText(for text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        return "\(String(text.prefix(maxLength)))…"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
final class TranscriptHistoryViewModel: ObservableObject {
    enum FileImportStatus: Equatable {
        case queued
        case transcribing
        case failed(String)
    }

    struct FileImportJob: Identifiable, Equatable {
        let id: UUID
        let fileURL: URL
        let fileName: String
        let modelID: String
        let languageHint: String?
        var status: FileImportStatus
    }

    @Published var searchQuery = ""
    @Published private(set) var records: [TranscriptRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMoreResults = true
    @Published var selectedRecordIDs: Set<Int64> = []
    @Published var errorMessage: String?
    @Published private(set) var importJobs: [FileImportJob] = []

    private let transcriptStore: TranscriptStore
    private let fileTranscriptionService: FileTranscriptionService
    private let pageSize = 50
    private var offset = 0
    private var searchLimit = 50
    private var isProcessingImportQueue = false

    init(
        transcriptStore: TranscriptStore,
        fileTranscriptionService: FileTranscriptionService = FileTranscriptionService()
    ) {
        self.transcriptStore = transcriptStore
        self.fileTranscriptionService = fileTranscriptionService
    }

    var selectedRecord: TranscriptRecord? {
        guard selectedRecordIDs.count == 1, let selectedID = selectedRecordIDs.first else {
            return nil
        }
        return records.first(where: { $0.id == selectedID })
    }

    var selectedRecords: [TranscriptRecord] {
        records.filter { record in
            guard let id = record.id else { return false }
            return selectedRecordIDs.contains(id)
        }
    }

    func loadInitial() {
        offset = 0
        searchLimit = pageSize
        fetch(reset: true)
    }

    func reloadForSearchQuery() {
        offset = 0
        searchLimit = pageSize
        fetch(reset: true)
    }

    func loadMoreIfNeeded(currentIndex: Int) {
        guard isLoading == false else { return }
        guard hasMoreResults else { return }
        guard currentIndex >= max(records.count - 5, 0) else { return }

        if isSearching {
            searchLimit += pageSize
            fetch(reset: true)
        } else {
            fetch(reset: false)
        }
    }

    func copySelectedToPasteboard() {
        guard let selectedRecord else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedRecord.text, forType: .string)
    }

    func exportSelection() {
        let selected = selectedRecords
        guard selected.isEmpty == false else { return }

        if selected.count > 1 {
            guard
                let selection = presentExportPanel(
                    allowedFormats: [.json],
                    defaultFormat: .json,
                    defaultFilename: defaultBatchExportFilename()
                )
            else {
                return
            }

            do {
                let data = try TranscriptExporter.exportAsJSON(selected)
                try data.write(to: selection.url, options: .atomic)
                errorMessage = nil
            } catch {
                errorMessage = "Failed to export selected transcripts."
            }
            return
        }

        guard let record = selected.first else { return }
        let defaultFormat: TranscriptExportFormat = .plainText
        guard
            let selection = presentExportPanel(
                allowedFormats: TranscriptExportFormat.allCases,
                defaultFormat: defaultFormat,
                defaultFilename: defaultExportFilename(for: record, format: defaultFormat)
            )
        else {
            return
        }

        do {
            let outputData: Data
            switch selection.format {
            case .plainText:
                outputData = Data(TranscriptExporter.exportAsPlainText(record).utf8)
            case .markdown:
                outputData = Data(TranscriptExporter.exportAsMarkdown(record).utf8)
            case .json:
                outputData = try TranscriptExporter.exportAsJSON([record])
            case .srt:
                outputData = Data(TranscriptExporter.exportAsSRT(record).utf8)
            case .vtt:
                outputData = Data(TranscriptExporter.exportAsVTT(record).utf8)
            }
            try outputData.write(to: selection.url, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to export transcript."
        }
    }

    func deleteSelected() {
        guard let selectedRecord else { return }
        guard let selectedRecordID = selectedRecord.id else { return }

        do {
            try transcriptStore.delete(id: selectedRecordID)
            selectedRecordIDs.removeAll()
            reloadForSearchQuery()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to delete transcript."
        }
    }

    func selectRecord(id: Int64, additive: Bool) {
        if additive {
            if selectedRecordIDs.contains(id) {
                selectedRecordIDs.remove(id)
            } else {
                selectedRecordIDs.insert(id)
            }
            return
        }

        selectedRecordIDs = [id]
    }

    func retainSelection(validIDs: Set<Int64>) {
        selectedRecordIDs = selectedRecordIDs.intersection(validIDs)
    }

    func enqueueImportedFiles(_ urls: [URL], selectedModelID: String?, languageHint: String?) {
        guard let selectedModelID else {
            errorMessage = "No model installed. Open Settings > Models to download one."
            return
        }

        for url in urls {
            if Self.isSupportedAudioFile(url) == false {
                importJobs.append(
                    FileImportJob(
                        id: UUID(),
                        fileURL: url,
                        fileName: url.lastPathComponent,
                        modelID: selectedModelID,
                        languageHint: languageHint,
                        status: .failed("Unsupported file type. Use WAV, MP3, M4A, FLAC, or OGG.")
                    )
                )
                continue
            }

            importJobs.append(
                FileImportJob(
                    id: UUID(),
                    fileURL: url,
                    fileName: url.lastPathComponent,
                    modelID: selectedModelID,
                    languageHint: languageHint,
                    status: .queued
                )
            )
        }

        processImportQueueIfNeeded()
    }

    private var isSearching: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func processImportQueueIfNeeded() {
        guard isProcessingImportQueue == false else { return }
        guard let nextJobIndex = importJobs.firstIndex(where: { $0.status == .queued }) else { return }

        isProcessingImportQueue = true
        importJobs[nextJobIndex].status = .transcribing
        let job = importJobs[nextJobIndex]

        Task {
            do {
                let result = try await fileTranscriptionService.transcribe(
                    fileURL: job.fileURL,
                    modelID: job.modelID,
                    languageHint: job.languageHint
                )

                _ = try transcriptStore.save(
                    TranscriptRecord(
                        createdAt: Date(),
                        sourceType: "file_import",
                        sourceFileName: job.fileName,
                        modelID: job.modelID,
                        languageHint: job.languageHint,
                        durationSeconds: result.durationSeconds,
                        text: result.text
                    )
                )

                importJobs.removeAll { $0.id == job.id }
                reloadForSearchQuery()
                errorMessage = nil
            } catch {
                if let index = importJobs.firstIndex(where: { $0.id == job.id }) {
                    importJobs[index].status = .failed("Transcription failed. Please try again.")
                }
            }

            isProcessingImportQueue = false
            processImportQueueIfNeeded()
        }
    }

    private func fetch(reset: Bool) {
        isLoading = true

        do {
            let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedQuery.isEmpty {
                let currentOffset = reset ? 0 : offset
                let fetched = try transcriptStore.fetchAll(limit: pageSize, offset: currentOffset)

                if reset {
                    records = fetched
                    offset = fetched.count
                } else {
                    records.append(contentsOf: fetched)
                    offset += fetched.count
                }

                hasMoreResults = fetched.count == pageSize
            } else {
                let fetched = try transcriptStore.search(query: trimmedQuery, limit: searchLimit)
                records = fetched
                hasMoreResults = fetched.count == searchLimit
            }

            errorMessage = nil
        } catch {
            if reset {
                records = []
            }
            hasMoreResults = false
            errorMessage = "Failed to load transcript history."
        }

        isLoading = false
    }

    private func defaultExportFilename(for record: TranscriptRecord, format: TranscriptExportFormat) -> String {
        let sourceName: String
        if record.sourceType == "dictation" {
            sourceName = "dictation"
        } else if let sourceFileName = record.sourceFileName, sourceFileName.isEmpty == false {
            sourceName = (sourceFileName as NSString).deletingPathExtension
        } else {
            sourceName = "import"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: record.createdAt)
        let sanitizedSource = sourceName.replacingOccurrences(of: " ", with: "_")
        return "\(sanitizedSource)_\(timestamp).\(format.fileExtension)"
    }

    private func defaultBatchExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "transcripts_\(timestamp).json"
    }

    private func presentExportPanel(
        allowedFormats: [TranscriptExportFormat],
        defaultFormat: TranscriptExportFormat,
        defaultFilename: String
    ) -> (url: URL, format: TranscriptExportFormat)? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = allowedFormats.compactMap(Self.utType(for:))

        let popup = NSPopUpButton(frame: .init(x: 0, y: 0, width: 220, height: 24), pullsDown: false)
        for format in allowedFormats {
            popup.addItem(withTitle: format.displayName)
            popup.lastItem?.representedObject = format.rawValue
        }
        if let defaultIndex = allowedFormats.firstIndex(of: defaultFormat) {
            popup.selectItem(at: defaultIndex)
        }

        let label = NSTextField(labelWithString: "Format:")
        let accessory = NSStackView(views: [label, popup])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, var url = panel.url else {
            return nil
        }

        let selectedFormatRawValue = popup.selectedItem?.representedObject as? String ?? defaultFormat.rawValue
        let selectedFormat = TranscriptExportFormat(rawValue: selectedFormatRawValue) ?? defaultFormat

        if url.pathExtension.lowercased() != selectedFormat.fileExtension {
            url = url.deletingPathExtension().appendingPathExtension(selectedFormat.fileExtension)
        }

        return (url, selectedFormat)
    }

    static var supportedContentTypes: [UTType] {
        ["wav", "mp3", "m4a", "flac", "ogg"]
            .compactMap { UTType(filenameExtension: $0) }
    }

    static func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["wav", "mp3", "m4a", "flac", "ogg"].contains(ext)
    }

    static func utType(for format: TranscriptExportFormat) -> UTType? {
        switch format {
        case .plainText:
            return .plainText
        case .markdown:
            return UTType(filenameExtension: "md")
        case .json:
            return .json
        case .srt:
            return UTType(filenameExtension: "srt")
        case .vtt:
            return UTType(filenameExtension: "vtt")
        }
    }
}
