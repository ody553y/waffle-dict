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

    @AppStorage("lmStudioHost") private var lmStudioHost = "127.0.0.1"
    @AppStorage("lmStudioPort") private var lmStudioPort = "1234"
    @AppStorage("lmStudioModelID") private var lmStudioModelID = ""
    @AppStorage("lmStudioDefaultTranslationLanguage")
    private var lmStudioDefaultTranslationLanguage = AppLanguageOption.defaultCode

    @State private var lmStudioReachabilityStatus: LMStudioReachabilityStatus = .unknown
    @State private var actionInputModeByRecordID: [Int64: TranscriptActionInputMode] = [:]
    @State private var questionInputByRecordID: [Int64: String] = [:]
    @State private var customPromptInputByRecordID: [Int64: String] = [:]
    @State private var translateLanguageCodeByRecordID: [Int64: String] = [:]
    @State private var translatePopoverRecordID: Int64?
    @State private var streamingTextByRecordID: [Int64: String] = [:]
    @State private var streamingRecordIDs: Set<Int64> = []
    @State private var waitingForFirstTokenRecordIDs: Set<Int64> = []
    @State private var actionErrorByRecordID: [Int64: String] = [:]
    @State private var streamTaskByRecordID: [Int64: Task<Void, Never>] = [:]
    @State private var previousActionsExpandedByRecordID: [Int64: Bool] = [:]
    @State private var expandedPreviousActionResultIDs: Set<Int64> = []
    @State private var timelineEnabledRecordIDs: Set<Int64> = []
    @State private var isDiarizationAvailable = false
    @State private var requestDiarizationForImports = false

    init(transcriptStore: TranscriptStore, modelStore: ModelStore) {
        self._modelStore = ObservedObject(wrappedValue: modelStore)
        self._viewModel = StateObject(
            wrappedValue: TranscriptHistoryViewModel(transcriptStore: transcriptStore)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone

            if isDiarizationAvailable {
                importDiarizationOptionView
            }

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
            await refreshLMStudioReachability()
            await refreshDiarizationAvailability()
        }
        .task(id: lmStudioConnectionSignature) {
            await refreshLMStudioReachability()
        }
        .onChange(of: viewModel.records) { _, newRecords in
            let validIDs = Set(newRecords.compactMap(\.id))
            expandedRecordIDs = expandedRecordIDs.intersection(validIDs)
            viewModel.retainSelection(validIDs: validIDs)
            pruneAIState(validRecordIDs: validIDs)
        }
        .onDisappear {
            cancelAllStreamingTasks()
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
                languageHint: nil,
                requestDiarization: requestDiarizationForImports
            )
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private var importDiarizationOptionView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("Speaker identification", isOn: $requestDiarizationForImports)
                .toggleStyle(.checkbox)
                .font(.caption)
            Text("Adds speaker labels to imported-file timelines and exports.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
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
            languageHint: nil,
            requestDiarization: requestDiarizationForImports
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

                if let recordID = record.id, let segments = record.segments, segments.isEmpty == false {
                    HStack(spacing: 8) {
                        Toggle("Timeline", isOn: timelineEnabledBinding(for: recordID))
                            .toggleStyle(.switch)
                            .font(.caption)

                        if let speakerCount = speakerCount(in: segments), speakerCount > 0 {
                            Text("Speakers: \(speakerCount)")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }

                        Spacer()
                    }

                    if timelineEnabledRecordIDs.contains(recordID) {
                        timelineView(for: segments)
                    } else {
                        Text(record.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(record.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let recordID = record.id, isLMStudioConfigured {
                    Divider()
                    transcriptActionsSection(record: record, recordID: recordID)
                }
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
                stopStreaming(for: recordID)
            } else {
                expandedRecordIDs.insert(recordID)
                viewModel.loadActions(for: recordID)
            }
        }
    }

    @ViewBuilder
    private func transcriptActionsSection(record: TranscriptRecord, recordID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Summarise") {
                    startStreamingAction(.summarise, for: record, recordID: recordID)
                }
                .buttonStyle(.bordered)

                Button("Translate") {
                    translatePopoverRecordID = recordID
                }
                .buttonStyle(.bordered)
                .popover(
                    isPresented: Binding(
                        get: { translatePopoverRecordID == recordID },
                        set: { isPresented in
                            translatePopoverRecordID = isPresented ? recordID : nil
                        }
                    ),
                    arrowEdge: .bottom
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Language", selection: translateLanguageCodeBinding(for: recordID)) {
                            ForEach(AppLanguageOption.all) { option in
                                Text(option.name).tag(option.code)
                            }
                        }

                        Button("Translate") {
                            let languageCode = translateLanguageCodeByRecordID[recordID]
                                ?? lmStudioDefaultTranslationLanguage
                            let targetLanguage = languageName(for: languageCode)
                            startStreamingAction(
                                .translate(targetLanguage: targetLanguage),
                                for: record,
                                recordID: recordID
                            )
                            translatePopoverRecordID = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(areTranscriptActionsEnabled == false)
                    }
                    .padding()
                    .frame(width: 260)
                }

                Button("Ask a Question") {
                    toggleInputMode(.question, for: recordID)
                }
                .buttonStyle(.bordered)

                Button("Custom Prompt") {
                    toggleInputMode(.customPrompt, for: recordID)
                }
                .buttonStyle(.bordered)
            }
            .disabled(areTranscriptActionsEnabled == false)

            if let statusLine = lmStudioStatusLine {
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if actionInputModeByRecordID[recordID] == .question {
                HStack(spacing: 8) {
                    TextField("Ask a question about this transcript", text: questionBinding(for: recordID))
                        .textFieldStyle(.roundedBorder)
                    Button("Ask") {
                        let question = questionInputByRecordID[recordID, default: ""]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard question.isEmpty == false else { return }
                        startStreamingAction(
                            .askQuestion(question: question),
                            for: record,
                            recordID: recordID
                        )
                        actionInputModeByRecordID[recordID] = TranscriptActionInputMode.none
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(areTranscriptActionsEnabled == false)
                }
            }

            if actionInputModeByRecordID[recordID] == .customPrompt {
                HStack(spacing: 8) {
                    TextField("Custom prompt", text: customPromptBinding(for: recordID))
                        .textFieldStyle(.roundedBorder)
                    Button("Run") {
                        let prompt = customPromptInputByRecordID[recordID, default: ""]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard prompt.isEmpty == false else { return }
                        startStreamingAction(
                            .customPrompt(prompt: prompt),
                            for: record,
                            recordID: recordID
                        )
                        actionInputModeByRecordID[recordID] = TranscriptActionInputMode.none
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(areTranscriptActionsEnabled == false)
                }
            }

            if streamingRecordIDs.contains(recordID) || (streamingTextByRecordID[recordID]?.isEmpty == false) {
                VStack(alignment: .leading, spacing: 8) {
                    if waitingForFirstTokenRecordIDs.contains(recordID) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for response…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }

                    if let streamedText = streamingTextByRecordID[recordID], streamedText.isEmpty == false {
                        Text(streamedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if streamingRecordIDs.contains(recordID) {
                        Button("Stop") {
                            stopStreaming(for: recordID)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            if let actionError = actionErrorByRecordID[recordID] {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            previousActionsSection(for: recordID)
        }
    }

    @ViewBuilder
    private func previousActionsSection(for recordID: Int64) -> some View {
        let actions = viewModel.actionHistoryByTranscriptID[recordID] ?? []
        DisclosureGroup(
            isExpanded: previousActionsExpandedBinding(for: recordID)
        ) {
            if actions.isEmpty {
                Text("No previous actions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(actions, id: \.id) { actionRecord in
                        previousActionRow(actionRecord, transcriptID: recordID)
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            Text("Previous Actions")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func previousActionRow(_ actionRecord: TranscriptActionRecord, transcriptID: Int64) -> some View {
        let isExpanded = actionRecord.id.map { expandedPreviousActionResultIDs.contains($0) } ?? false
        let text = actionRecord.resultText
        let preview = previewText(for: text, maxLength: 200)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(actionTypeLabel(for: actionRecord.actionType))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())

                Text(modelDisplayName(for: actionRecord.llmModelID))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(Self.dateFormatter.string(from: actionRecord.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(isExpanded ? text : preview)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let actionID = actionRecord.id, text.count > 200 {
                    Button(isExpanded ? "Collapse" : "Expand") {
                        if isExpanded {
                            expandedPreviousActionResultIDs.remove(actionID)
                        } else {
                            expandedPreviousActionResultIDs.insert(actionID)
                        }
                    }
                    .font(.caption)
                }

                Button("Copy") {
                    viewModel.copyActionText(text)
                }
                .font(.caption)

                if let actionID = actionRecord.id {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteAction(id: actionID, transcriptID: transcriptID)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private func toggleInputMode(_ mode: TranscriptActionInputMode, for recordID: Int64) {
        if actionInputModeByRecordID[recordID] == mode {
            actionInputModeByRecordID[recordID] = TranscriptActionInputMode.none
        } else {
            actionInputModeByRecordID[recordID] = mode
        }
    }

    private func questionBinding(for recordID: Int64) -> Binding<String> {
        Binding(
            get: { questionInputByRecordID[recordID, default: ""] },
            set: { questionInputByRecordID[recordID] = $0 }
        )
    }

    private func customPromptBinding(for recordID: Int64) -> Binding<String> {
        Binding(
            get: { customPromptInputByRecordID[recordID, default: ""] },
            set: { customPromptInputByRecordID[recordID] = $0 }
        )
    }

    private func translateLanguageCodeBinding(for recordID: Int64) -> Binding<String> {
        Binding(
            get: { translateLanguageCodeByRecordID[recordID] ?? lmStudioDefaultTranslationLanguage },
            set: { translateLanguageCodeByRecordID[recordID] = $0 }
        )
    }

    private func timelineEnabledBinding(for recordID: Int64) -> Binding<Bool> {
        Binding(
            get: { timelineEnabledRecordIDs.contains(recordID) },
            set: { isEnabled in
                if isEnabled {
                    timelineEnabledRecordIDs.insert(recordID)
                } else {
                    timelineEnabledRecordIDs.remove(recordID)
                }
            }
        )
    }

    private func previousActionsExpandedBinding(for recordID: Int64) -> Binding<Bool> {
        Binding(
            get: { previousActionsExpandedByRecordID[recordID, default: true] },
            set: { previousActionsExpandedByRecordID[recordID] = $0 }
        )
    }

    private var lmStudioConnectionSignature: String {
        "\(lmStudioHost)|\(lmStudioPort)"
    }

    private var isLMStudioConfigured: Bool {
        let host = lmStudioHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty == false && Int(lmStudioPort) != nil
    }

    private var areTranscriptActionsEnabled: Bool {
        guard case .reachableWithModels = lmStudioReachabilityStatus else {
            return false
        }
        return lmStudioModelID.isEmpty == false
    }

    private var lmStudioStatusLine: String? {
        switch lmStudioReachabilityStatus {
        case .unconfigured:
            return nil
        case .unknown:
            return "Checking LM Studio status…"
        case .reachableWithModels:
            if lmStudioModelID.isEmpty {
                return "Choose a default model in Settings > AI."
            }
            return nil
        case .reachableNoModels:
            return "No models loaded in LM Studio. Load a model first."
        case .unreachable(let message):
            return message
        }
    }

    private func refreshLMStudioReachability() async {
        guard isLMStudioConfigured else {
            lmStudioReachabilityStatus = .unconfigured
            return
        }

        guard let client = makeLMStudioClient() else {
            lmStudioReachabilityStatus = .unreachable("Invalid LM Studio host or port.")
            return
        }

        do {
            let models = try await client.fetchModels()
            lmStudioReachabilityStatus = .reachableWithModels
            if models.contains(where: { $0.id == lmStudioModelID }) == false {
                lmStudioModelID = models.first?.id ?? ""
            }
        } catch LMStudioClientError.noModelsLoaded {
            lmStudioReachabilityStatus = .reachableNoModels
            lmStudioModelID = ""
        } catch {
            lmStudioReachabilityStatus = .unreachable(errorMessage(for: error))
        }
    }

    private func refreshDiarizationAvailability() async {
        do {
            let status = try await WorkerClient().fetchDiarizationStatus()
            isDiarizationAvailable = status.available
        } catch {
            isDiarizationAvailable = false
        }

        if isDiarizationAvailable == false {
            requestDiarizationForImports = false
        }
    }

    private func makeLMStudioClient() -> LMStudioClient? {
        let host = lmStudioHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false else { return nil }
        guard let port = Int(lmStudioPort), port > 0 else { return nil }

        return LMStudioClient(configuration: LMStudioConfiguration(host: host, port: port))
    }

    private func startStreamingAction(_ action: TranscriptAction, for record: TranscriptRecord, recordID: Int64) {
        guard areTranscriptActionsEnabled else {
            actionErrorByRecordID[recordID] = lmStudioStatusLine
                ?? "LM Studio is not available for AI actions."
            return
        }
        guard let modelID = selectedLLMModelID else {
            actionErrorByRecordID[recordID] = "Choose a default model in Settings > AI."
            return
        }
        guard let service = makeTranscriptActionService() else {
            actionErrorByRecordID[recordID] = "LM Studio is not configured."
            return
        }

        stopStreaming(for: recordID)
        actionErrorByRecordID[recordID] = nil
        streamingTextByRecordID[recordID] = ""
        waitingForFirstTokenRecordIDs.insert(recordID)
        streamingRecordIDs.insert(recordID)

        streamTaskByRecordID[recordID] = Task {
            let actionStartedAt = DispatchTime.now().uptimeNanoseconds
            let completionStartedAt = DispatchTime.now().uptimeNanoseconds
            var didRecordTimeToFirstToken = false
            var completeText = ""
            do {
                let stream = service.performStreaming(
                    action: action,
                    on: record,
                    modelID: modelID
                )
                for try await delta in stream {
                    completeText.append(delta)

                    if didRecordTimeToFirstToken == false {
                        didRecordTimeToFirstToken = true
                        PerformanceMetrics.shared.record(
                            "llm.action.ttft",
                            durationSeconds: elapsedDurationSeconds(since: actionStartedAt)
                        )
                    }

                    await MainActor.run {
                        waitingForFirstTokenRecordIDs.remove(recordID)
                        streamingTextByRecordID[recordID, default: ""].append(delta)
                    }
                }
                PerformanceMetrics.shared.record(
                    "llm.action.completion",
                    durationSeconds: elapsedDurationSeconds(since: completionStartedAt)
                )

                await MainActor.run {
                    waitingForFirstTokenRecordIDs.remove(recordID)
                    streamingRecordIDs.remove(recordID)
                    streamTaskByRecordID[recordID] = nil

                    if completeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        viewModel.saveActionResult(
                            transcriptID: recordID,
                            action: action,
                            modelID: modelID,
                            resultText: completeText
                        )
                    }
                }
            } catch {
                PerformanceMetrics.shared.record(
                    "llm.action.completion",
                    durationSeconds: elapsedDurationSeconds(since: completionStartedAt)
                )
                let nsError = error as NSError
                if error is CancellationError || nsError.code == NSURLErrorCancelled {
                    await MainActor.run {
                        waitingForFirstTokenRecordIDs.remove(recordID)
                        streamingRecordIDs.remove(recordID)
                        streamTaskByRecordID[recordID] = nil
                    }
                    return
                }

                await MainActor.run {
                    waitingForFirstTokenRecordIDs.remove(recordID)
                    streamingRecordIDs.remove(recordID)
                    streamTaskByRecordID[recordID] = nil
                    actionErrorByRecordID[recordID] = errorMessage(for: error)
                }
            }
        }
    }

    private func stopStreaming(for recordID: Int64) {
        streamTaskByRecordID[recordID]?.cancel()
        streamTaskByRecordID[recordID] = nil
        waitingForFirstTokenRecordIDs.remove(recordID)
        streamingRecordIDs.remove(recordID)
    }

    private func cancelAllStreamingTasks() {
        for task in streamTaskByRecordID.values {
            task.cancel()
        }
        streamTaskByRecordID.removeAll()
        waitingForFirstTokenRecordIDs.removeAll()
        streamingRecordIDs.removeAll()
    }

    private func pruneAIState(validRecordIDs: Set<Int64>) {
        actionInputModeByRecordID = actionInputModeByRecordID.filter { validRecordIDs.contains($0.key) }
        questionInputByRecordID = questionInputByRecordID.filter { validRecordIDs.contains($0.key) }
        customPromptInputByRecordID = customPromptInputByRecordID.filter { validRecordIDs.contains($0.key) }
        translateLanguageCodeByRecordID = translateLanguageCodeByRecordID.filter { validRecordIDs.contains($0.key) }
        streamingTextByRecordID = streamingTextByRecordID.filter { validRecordIDs.contains($0.key) }
        actionErrorByRecordID = actionErrorByRecordID.filter { validRecordIDs.contains($0.key) }
        previousActionsExpandedByRecordID = previousActionsExpandedByRecordID.filter {
            validRecordIDs.contains($0.key)
        }
        streamTaskByRecordID = streamTaskByRecordID.filter { validRecordIDs.contains($0.key) }
        timelineEnabledRecordIDs = timelineEnabledRecordIDs.intersection(validRecordIDs)
        streamingRecordIDs = streamingRecordIDs.intersection(validRecordIDs)
        waitingForFirstTokenRecordIDs = waitingForFirstTokenRecordIDs.intersection(validRecordIDs)
    }

    private var selectedLLMModelID: String? {
        let trimmed = lmStudioModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeTranscriptActionService() -> TranscriptActionService? {
        guard let client = makeLMStudioClient() else { return nil }
        return TranscriptActionService(lmStudioClient: client)
    }

    private func languageName(for code: String) -> String {
        AppLanguageOption.all.first(where: { $0.code == code })?.name ?? code
    }

    private func actionTypeLabel(for actionType: String) -> String {
        switch actionType {
        case "summarise":
            return "Summary"
        case "translate":
            return "Translate"
        case "question":
            return "Question"
        case "custom":
            return "Custom"
        default:
            return actionType.capitalized
        }
    }

    private func timelineView(for segments: [TranscriptSegment]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    HStack(alignment: .top, spacing: 8) {
                        Button("[\(timelineTimestamp(for: segment.start))]") {
                            viewModel.copyActionText(segment.text)
                        }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            if let speaker = normalizedSpeakerLabel(segment.speaker) {
                                Text("\(speaker):")
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(colorForSpeaker(speaker))
                            }

                            Text(segment.text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
    }

    private func speakerCount(in segments: [TranscriptSegment]) -> Int? {
        let speakers = Set(segments.compactMap { normalizedSpeakerLabel($0.speaker) })
        return speakers.isEmpty ? nil : speakers.count
    }

    private func normalizedSpeakerLabel(_ speaker: String?) -> String? {
        guard let speaker else { return nil }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func colorForSpeaker(_ speaker: String) -> Color {
        let palette = Self.speakerPalette
        guard palette.isEmpty == false else { return .accentColor }

        var hash: UInt64 = 1469598103934665603
        for byte in speaker.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }

    private func timelineTimestamp(for seconds: Double) -> String {
        let totalSeconds = Int(max(seconds, 0))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func elapsedDurationSeconds(since startedAt: UInt64) -> Double {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now > startedAt else { return 0 }
        return Double(now - startedAt) / 1_000_000_000
    }

    private func errorMessage(for error: Error) -> String {
        switch error {
        case LMStudioClientError.connectionRefused:
            return "LM Studio is not running. Start LM Studio to use AI features."
        case LMStudioClientError.noModelsLoaded:
            return "No models loaded in LM Studio. Load a model first."
        case LMStudioClientError.streamParsingFailed:
            return "Received an unreadable streaming response from LM Studio."
        case LMStudioClientError.unexpectedStatusCode:
            return "LM Studio returned an unexpected response."
        case TranscriptActionServiceError.emptyResponse:
            return "The model returned an empty response. Try again or select a different model."
        default:
            let lowercased = error.localizedDescription.lowercased()
            if lowercased.contains("context")
                || lowercased.contains("maximum")
                || lowercased.contains("token")
            {
                return "Transcript is too long for the selected model."
            }
            return error.localizedDescription
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

    private static let speakerPalette: [Color] = [
        .blue,
        .green,
        .orange,
        .pink,
        .teal,
        .indigo,
        .red,
        .brown,
    ]
}

private enum TranscriptActionInputMode {
    case none
    case question
    case customPrompt
}

private enum LMStudioReachabilityStatus {
    case unconfigured
    case unknown
    case reachableWithModels
    case reachableNoModels
    case unreachable(String)
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
        let requestDiarization: Bool
        var status: FileImportStatus
    }

    @Published var searchQuery = ""
    @Published private(set) var records: [TranscriptRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMoreResults = true
    @Published var selectedRecordIDs: Set<Int64> = []
    @Published var errorMessage: String?
    @Published private(set) var importJobs: [FileImportJob] = []
    @Published private(set) var actionHistoryByTranscriptID: [Int64: [TranscriptActionRecord]] = [:]

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
            actionHistoryByTranscriptID[selectedRecordID] = nil
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

    func loadActions(for transcriptID: Int64) {
        do {
            actionHistoryByTranscriptID[transcriptID] = try transcriptStore.fetchActions(
                forTranscriptID: transcriptID
            )
        } catch {
            errorMessage = "Failed to load previous AI actions."
        }
    }

    func saveActionResult(
        transcriptID: Int64,
        action: TranscriptAction,
        modelID: String,
        resultText: String
    ) {
        let (actionType, actionInput) = Self.serialize(action: action)

        do {
            _ = try transcriptStore.saveAction(
                TranscriptActionRecord(
                    transcriptID: transcriptID,
                    createdAt: Date(),
                    actionType: actionType,
                    actionInput: actionInput,
                    llmModelID: modelID,
                    resultText: resultText
                )
            )
            loadActions(for: transcriptID)
        } catch {
            errorMessage = "Failed to save AI action result."
        }
    }

    func deleteAction(id: Int64, transcriptID: Int64) {
        do {
            try transcriptStore.deleteAction(id: id)
            loadActions(for: transcriptID)
        } catch {
            errorMessage = "Failed to delete AI action result."
        }
    }

    func copyActionText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func enqueueImportedFiles(
        _ urls: [URL],
        selectedModelID: String?,
        languageHint: String?,
        requestDiarization: Bool = false
    ) {
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
                        requestDiarization: requestDiarization,
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
                    requestDiarization: requestDiarization,
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
                    languageHint: job.languageHint,
                    requestDiarization: job.requestDiarization
                )

                _ = try transcriptStore.save(
                    TranscriptRecord(
                        createdAt: Date(),
                        sourceType: "file_import",
                        sourceFileName: job.fileName,
                        modelID: job.modelID,
                        languageHint: job.languageHint,
                        durationSeconds: result.durationSeconds,
                        text: result.text,
                        segments: result.segments
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

    static func serialize(action: TranscriptAction) -> (type: String, input: String?) {
        switch action {
        case .summarise:
            return ("summarise", nil)
        case .translate(let targetLanguage):
            return ("translate", targetLanguage)
        case .askQuestion(let question):
            return ("question", question)
        case .customPrompt(let prompt):
            return ("custom", prompt)
        }
    }
}
