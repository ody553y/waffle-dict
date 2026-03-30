import AppKit
import Carbon.HIToolbox
import Foundation
import WaffleCore
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptHistoryView: View {
    @ObservedObject private var modelStore: ModelStore
    @StateObject private var viewModel: TranscriptHistoryViewModel
    @StateObject private var audioPlayer = AudioPlayerService()
    @State private var expandedRecordIDs: Set<Int64> = []
    @State private var isDropTargeted = false

    @AppStorage("lmStudioHost") private var lmStudioHost = "127.0.0.1"
    @AppStorage("lmStudioPort") private var lmStudioPort = "1234"
    @AppStorage("lmStudioModelID") private var lmStudioModelID = ""
    @AppStorage("lmStudioDefaultTranslationLanguage")
    private var lmStudioDefaultTranslationLanguage = AppLanguageOption.defaultCode
    @AppStorage("speakerMatchThreshold") private var speakerMatchThreshold = 0.85

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
    @State private var speakerNameDraftsByRecordID: [Int64: [String: String]] = [:]
    @State private var speakerSuggestionsByRecordID: [Int64: [TranscriptHistoryViewModel.SpeakerSuggestion]] = [:]
    @State private var dismissedSuggestionLabelsByRecordID: [Int64: Set<String>] = [:]
    @State private var speakerProfileSaveFeedbackByRecordID: [Int64: [String: String]] = [:]
    @State private var notesDraftByRecordID: [Int64: String] = [:]
    @State private var notesSaveTaskByRecordID: [Int64: Task<Void, Never>] = [:]
    @State private var pendingBatchDeleteSummary: TranscriptHistoryViewModel.DeleteSelectionSummary?
    @State private var archiveImportSummary: TranscriptArchiveImportResult?
    @State private var archiveImportErrorMessage: String?
    @State private var pendingExternalSelectionID: Int64?
    @State private var isDiarizationAvailable = false
    @State private var requestDiarizationForImports = false
    @State private var keyboardFocusedRecordID: Int64?
    @State private var loadedAudioRecordID: Int64?
    @State private var audioScrubberTime: Double = 0
    @State private var isAudioScrubbing = false
    @State private var audioErrorByRecordID: [Int64: String] = [:]
    @State private var promptTemplates: [PromptTemplate] = []
    @State private var isSavePromptTemplateSheetPresented = false
    @State private var savePromptTemplateTargetRecordID: Int64?
    @State private var savePromptTemplateName = ""
    @State private var savePromptTemplatePrompt = ""
    @State private var savePromptTemplateError: String?
    @State private var segmentEditorTranscript: TranscriptRecord?
    @State private var customPromptTemplateFeedbackByRecordID: [Int64: String] = [:]
    @State private var keyDownMonitor: Any?
    @FocusState private var focusedSpeakerField: SpeakerRenameField?
    @FocusState private var focusedNotesRecordID: Int64?
    @FocusState private var historyKeyboardFocus: HistoryKeyboardFocus?
    private let promptTemplateStore = PromptTemplateStore()

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

            TextField(
                localized(
                    "history.search.placeholder",
                    default: "Search transcripts",
                    comment: "Placeholder text for transcript history search field"
                ),
                text: $viewModel.searchQuery
            )
                .textFieldStyle(.roundedBorder)
                .focused($historyKeyboardFocus, equals: .search)
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.reloadForSearchQuery()
                }
                .accessibilityLabel(
                    localized(
                        "history.search.accessibility",
                        default: "Search transcripts",
                        comment: "Accessibility label for transcript history search field"
                    )
                )

            filterBar

            Text(
                localized(
                    "history.tip.multiSelect",
                    default: "Tip: Command-click transcript rows to multi-select for batch export and delete. Keyboard shortcuts are listed in Settings > General.",
                    comment: "Tip text describing multi-select behavior and keyboard shortcut location"
                )
            )
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(
                localized(
                    "history.storage.localOnly",
                    default: "All transcript history is stored locally on this device.",
                    comment: "Informational text about transcript history being stored locally"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selectedModel = modelStore.selectedEntry, selectedModel.family == .parakeet {
                Text(
                    localized(
                        "history.parakeet.wavHint",
                        default: "Parakeet currently works best with WAV files for imported audio.",
                        comment: "Hint shown when Parakeet model is selected"
                    )
                )
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
                        ? localized(
                            "history.empty.title",
                            default: "No transcripts yet",
                            comment: "Empty-state title when transcript history has no items"
                        )
                        : localized(
                            "history.empty.noResults.title",
                            default: "No results",
                            comment: "Empty-state title when search filters return no results"
                        ),
                    systemImage: "waveform.and.magnifyingglass",
                    description: Text(
                        viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? localized(
                                "history.empty.description",
                                default: "Start a dictation or import audio to build your history.",
                                comment: "Empty-state description when no transcripts exist"
                            )
                            : localized(
                                "history.empty.noResults.description",
                                default: "Try a different search term.",
                                comment: "Empty-state description when search has no matches"
                            )
                    )
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(viewModel.records.enumerated()), id: \.offset) { index, record in
                                transcriptRow(record)
                                    .id(rowScrollID(for: record, index: index))
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
                    .onChange(of: keyboardFocusedRecordID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(rowScrollID(for: newValue), anchor: .center)
                        }
                    }
                    .onTapGesture {
                        historyKeyboardFocus = .list
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 540)
        .toolbar {
            ToolbarItemGroup {
                Button(
                    localized(
                        "history.toolbar.importFile",
                        default: "Import File…",
                        comment: "Toolbar button title for importing audio files"
                    )
                ) {
                    presentImportFilePanel()
                }
                .help(
                    localized(
                        "history.toolbar.importFile.help",
                        default: "Import File",
                        comment: "Tooltip for import file toolbar button"
                    )
                )

                Button(
                    localized(
                        "history.toolbar.importArchive",
                        default: "Import Archive…",
                        comment: "Toolbar button title for importing transcript archive files"
                    )
                ) {
                    presentImportArchivePanel()
                }
                .help(
                    localized(
                        "history.toolbar.importArchive.help",
                        default: "Import transcript archive",
                        comment: "Tooltip for import archive toolbar button"
                    )
                )

                Button(
                    localized(
                        "history.toolbar.copyText",
                        default: "Copy Text",
                        comment: "Toolbar button title for copying selected transcript text"
                    )
                ) {
                    viewModel.copySelectedToPasteboard()
                }
                .disabled(viewModel.selectedRecord == nil)
                .help(
                    localized(
                        "history.toolbar.copyText.help",
                        default: "Copy Text (\u{2318}C)",
                        comment: "Tooltip for copy text toolbar button with shortcut"
                    )
                )

                Button(
                    localized(
                        "action.export",
                        default: "Export",
                        comment: "Action title for exporting transcripts"
                    )
                ) {
                    viewModel.exportSelection()
                }
                .disabled(viewModel.selectedRecords.isEmpty)
                .help(
                    localized(
                        "history.toolbar.export.help",
                        default: "Export (\u{2318}E)",
                        comment: "Tooltip for export toolbar button with shortcut"
                    )
                )

                Button(
                    localized(
                        "history.toolbar.share",
                        default: "Share",
                        comment: "Toolbar button title for sharing selected transcripts as an archive"
                    )
                ) {
                    viewModel.shareSelection()
                }
                .disabled(viewModel.selectedRecords.isEmpty)
                .help(
                    localized(
                        "history.toolbar.share.help",
                        default: "Share selected transcripts as a Waffle archive",
                        comment: "Tooltip for share toolbar button"
                    )
                )

                Button(
                    localized(
                        "action.delete",
                        default: "Delete",
                        comment: "Action title for deleting selected transcripts"
                    ),
                    role: .destructive
                ) {
                    guard let summary = viewModel.makeDeleteSelectionSummary() else { return }
                    if summary.transcriptCount > 1 {
                        pendingBatchDeleteSummary = summary
                    } else {
                        applyDelete(summary: summary)
                    }
                }
                .disabled(viewModel.selectedRecords.isEmpty)
                .help(
                    localized(
                        "history.toolbar.delete.help",
                        default: "Delete (\u{2318}\u{232b})",
                        comment: "Tooltip for delete toolbar button with shortcut"
                    )
                )
            }
        }
        .task {
            modelStore.refreshCatalog()
            viewModel.loadInitial()
            loadPromptTemplates()
            await refreshLMStudioReachability()
            await refreshDiarizationAvailability()
        }
        .onAppear {
            installKeyDownMonitorIfNeeded()
            loadPromptTemplates()
            if historyKeyboardFocus == nil {
                historyKeyboardFocus = .list
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            loadPromptTemplates()
        }
        .task(id: lmStudioConnectionSignature) {
            await refreshLMStudioReachability()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waffleSelectTranscriptInHistory)) { notification in
            let transcriptID: Int64?
            if let value = notification.userInfo?["transcriptID"] as? Int64 {
                transcriptID = value
            } else if let value = notification.userInfo?["transcriptID"] as? Int {
                transcriptID = Int64(value)
            } else if let value = notification.userInfo?["transcriptID"] as? NSNumber {
                transcriptID = value.int64Value
            } else {
                transcriptID = nil
            }

            if let transcriptID {
                pendingExternalSelectionID = transcriptID
                selectTranscriptFromExternalNavigation(transcriptID)
            }
        }
        .onChange(of: viewModel.records) { _, newRecords in
            let validIDs = Set(newRecords.compactMap(\.id))
            expandedRecordIDs = expandedRecordIDs.intersection(validIDs)
            viewModel.retainSelection(validIDs: validIDs)
            pruneAIState(validRecordIDs: validIDs)
            pruneSpeakerDraftState(validRecordIDs: validIDs)
            pruneNotesState(validRecordIDs: validIDs)
            pruneAudioState(validRecordIDs: validIDs)
            if let keyboardFocusedRecordID, validIDs.contains(keyboardFocusedRecordID) == false {
                self.keyboardFocusedRecordID = nil
            }
            if let keyboardFocusedRecordID,
               viewModel.selectedRecordIDs.contains(keyboardFocusedRecordID) == false {
                self.keyboardFocusedRecordID = viewModel.selectedRecordIDs.sorted().first
            }
            if let pendingExternalSelectionID,
               validIDs.contains(pendingExternalSelectionID) {
                selectTranscriptFromExternalNavigation(pendingExternalSelectionID)
                self.pendingExternalSelectionID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .waffleImportTranscriptArchive)) { notification in
            if let urls = TranscriptArchiveImportNotification.urls(from: notification),
               urls.isEmpty == false {
                importArchiveURLs(urls)
            } else {
                presentImportArchivePanel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .waffleImportAudioFiles)) { _ in
            presentImportFilePanel()
        }
        .onChange(of: speakerMatchThreshold) { _, _ in
            for recordID in expandedRecordIDs {
                refreshSpeakerSuggestions(for: recordID)
            }
        }
        .onChange(of: focusedSpeakerField) { oldValue, newValue in
            guard oldValue != newValue, let oldValue else { return }
            persistSpeakerNameDraft(for: oldValue.recordID, speaker: oldValue.speaker)
            refreshSpeakerSuggestions(for: oldValue.recordID)
        }
        .onChange(of: focusedNotesRecordID) { oldValue, newValue in
            guard oldValue != newValue, let oldValue else { return }
            flushNotesSave(for: oldValue)
        }
        .onDisappear {
            cancelAllStreamingTasks()
            flushAllNotesSaves()
            removeKeyDownMonitor()
            pauseAndResetAudioPlayer()
        }
        .focusedValue(
            \.historySelectionActions,
            HistorySelectionActions(
                focusSearch: { historyKeyboardFocus = .search },
                copySelection: { viewModel.copySelectedToPasteboard() },
                exportSelection: { viewModel.exportSelection() },
                deleteSelection: { performDeleteSelection() },
                selectAllVisible: {
                    viewModel.selectAllVisible()
                    keyboardFocusedRecordID = viewModel.selectedRecordIDs.sorted().first
                    historyKeyboardFocus = .list
                }
            )
        )
        .sheet(isPresented: $isSavePromptTemplateSheetPresented) {
            savePromptTemplateSheet
        }
        .sheet(item: $segmentEditorTranscript) { transcript in
            SegmentEditorSheet(transcript: transcript) { recordID, updatedSegments in
                try viewModel.updateSegments(recordID: recordID, segments: updatedSegments)
                refreshSpeakerSuggestions(for: recordID)
            }
        }
        .alert(
            pendingBatchDeleteSummary?.alertTitle
                ?? localized(
                    "history.delete.alert.title.fallback",
                    default: "Delete transcripts?",
                    comment: "Fallback delete confirmation alert title"
                ),
            isPresented: batchDeleteAlertBinding
        ) {
            Button(
                localized(
                    "action.delete",
                    default: "Delete",
                    comment: "Action title for deleting selected transcripts"
                ),
                role: .destructive
            ) {
                guard let summary = pendingBatchDeleteSummary else { return }
                applyDelete(summary: summary)
                pendingBatchDeleteSummary = nil
            }
            Button(
                localized(
                    "action.cancel",
                    default: "Cancel",
                    comment: "Generic action title for canceling a dialog"
                ),
                role: .cancel
            ) {
                pendingBatchDeleteSummary = nil
            }
        } message: {
            if let summary = pendingBatchDeleteSummary {
                Text(summary.alertMessage)
            }
        }
        .alert(
            localized(
                "history.importArchive.summary.title",
                default: "Archive Import Complete",
                comment: "Title for transcript archive import summary alert"
            ),
            isPresented: archiveImportSummaryAlertBinding
        ) {
            Button(
                localized(
                    "action.ok",
                    default: "OK",
                    comment: "Generic action title for confirming an alert"
                )
            ) {
                archiveImportSummary = nil
            }
        } message: {
            if let summary = archiveImportSummary {
                Text(
                    localizedFormat(
                        "history.importArchive.summary.message",
                        default: "Imported %d transcripts with %d AI actions. Skipped %d duplicates.",
                        comment: "Summary message shown after importing transcript archives",
                        summary.importedTranscriptCount,
                        summary.importedActionCount,
                        summary.skippedDuplicateCount
                    )
                )
            }
        }
        .alert(
            localized(
                "history.importArchive.error.title",
                default: "Import Failed",
                comment: "Title for archive import failure alert"
            ),
            isPresented: archiveImportErrorAlertBinding
        ) {
            Button(
                localized(
                    "action.ok",
                    default: "OK",
                    comment: "Generic action title for confirming an alert"
                ),
                role: .cancel
            ) {
                archiveImportErrorMessage = nil
            }
        } message: {
            if let archiveImportErrorMessage {
                Text(archiveImportErrorMessage)
            }
        }
    }

    private var batchDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingBatchDeleteSummary != nil },
            set: { isPresented in
                if isPresented == false {
                    pendingBatchDeleteSummary = nil
                }
            }
        )
    }

    private var archiveImportSummaryAlertBinding: Binding<Bool> {
        Binding(
            get: { archiveImportSummary != nil },
            set: { isPresented in
                if isPresented == false {
                    archiveImportSummary = nil
                }
            }
        )
    }

    private var archiveImportErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { archiveImportErrorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    archiveImportErrorMessage = nil
                }
            }
        )
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(
                    localized(
                        "history.import.dropZone.title",
                        default: "Drop audio files here",
                        comment: "Title for audio file drop zone in transcript history"
                    )
                )
                    .font(.headline)
                Spacer()
                Text(
                    localized(
                        "history.import.dropZone.formats",
                        default: "WAV, MP3, M4A, FLAC, OGG",
                        comment: "Supported file format hint for drop zone"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(
                localized(
                    "history.import.dropZone.description",
                    default: "Imports are processed one file at a time and saved to history.",
                    comment: "Description under audio file drop zone"
                )
            )
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
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedFileProviders(providers)
        }
    }

    private var importDiarizationOptionView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle(
                localized(
                    "history.import.diarization.toggle",
                    default: "Speaker identification",
                    comment: "Toggle label to request diarization when importing files"
                ),
                isOn: $requestDiarizationForImports
            )
                .toggleStyle(.checkbox)
                .font(.caption)
            Text(
                localized(
                    "history.import.diarization.description",
                    default: "Adds speaker labels to imported-file timelines and exports.",
                    comment: "Description for diarization import toggle"
                )
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    viewModel.isFiltersExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text(
                            localized(
                                "history.filters.button",
                                default: "Filters",
                                comment: "Button title that expands and collapses transcript filters"
                            )
                        )
                        if viewModel.activeFilterCount > 0 {
                            Text("\(viewModel.activeFilterCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    localized(
                        "history.filters.button.accessibility",
                        default: "Filters",
                        comment: "Accessibility label for filters button"
                    )
                )
                .accessibilityValue(
                    localizedFormat(
                        "history.filters.activeCount",
                        default: "%d filters active",
                        comment: "Accessibility value announcing count of active filters",
                        viewModel.activeFilterCount
                    )
                )

                Spacer()

                if viewModel.activeFilterCount > 0 {
                    Button(
                        localized(
                            "history.filters.clear",
                            default: "Clear Filters",
                            comment: "Action title to clear all transcript filters"
                        )
                    ) {
                        viewModel.clearFilters()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            if viewModel.isFiltersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        optionalDateFilterControl(
                            title: localized(
                                "history.filters.from",
                                default: "From",
                                comment: "Label for start date filter"
                            ),
                            date: $viewModel.filterDateFrom
                        )

                        optionalDateFilterControl(
                            title: localized(
                                "history.filters.to",
                                default: "To",
                                comment: "Label for end date filter"
                            ),
                            date: $viewModel.filterDateTo
                        )

                        Picker(
                            localized(
                                "history.filters.source",
                                default: "Source",
                                comment: "Picker label for transcript source filter"
                            ),
                            selection: Binding(
                                get: { viewModel.sourceTypeFilter },
                                set: { newValue in
                                    viewModel.sourceTypeFilter = newValue
                                    viewModel.reloadForSearchQuery()
                                }
                            )
                        ) {
                            ForEach(TranscriptHistoryViewModel.SourceTypeFilterOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }

                    HStack(spacing: 12) {
                        Picker(
                            localized(
                                "history.filters.model",
                                default: "Model",
                                comment: "Picker label for transcript model filter"
                            ),
                            selection: Binding(
                                get: { viewModel.selectedModelFilterID },
                                set: { newValue in
                                    viewModel.selectedModelFilterID = newValue
                                    viewModel.reloadForSearchQuery()
                                }
                            )
                        ) {
                            Text(
                                localized(
                                    "history.filters.model.all",
                                    default: "All Models",
                                    comment: "Option label for including all models in filter"
                                )
                            ).tag("")
                            ForEach(viewModel.availableModelFilterIDs, id: \.self) { modelID in
                                Text(modelDisplayName(for: modelID)).tag(modelID)
                            }
                        }
                        .frame(width: 260)

                        Toggle(
                            localized(
                                "history.filters.hasSpeakers",
                                default: "Has speakers",
                                comment: "Toggle label for filtering transcripts with speaker diarization"
                            ),
                            isOn: Binding(
                                get: { viewModel.hasSpeakersFilterEnabled },
                                set: { newValue in
                                    viewModel.hasSpeakersFilterEnabled = newValue
                                    viewModel.reloadForSearchQuery()
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.05))
                )
            }
        }
    }

    private func optionalDateFilterControl(
        title: String,
        date: Binding<Date?>
    ) -> some View {
        HStack(spacing: 6) {
            Toggle(
                title,
                isOn: Binding(
                    get: { date.wrappedValue != nil },
                    set: { isEnabled in
                        date.wrappedValue = isEnabled ? (date.wrappedValue ?? Date()) : nil
                        viewModel.reloadForSearchQuery()
                    }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)

            DatePicker(
                "",
                selection: Binding(
                    get: { date.wrappedValue ?? Date() },
                    set: { newDate in
                        date.wrappedValue = newDate
                        viewModel.reloadForSearchQuery()
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .disabled(date.wrappedValue == nil)
            .frame(width: 130)
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
                            .accessibilityHidden(true)
                        Text(
                            localizedFormat(
                                "history.import.job.queued",
                                default: "Queued: %@",
                                comment: "Status line for queued transcript import job",
                                job.fileName
                            )
                        )
                            .font(.caption)
                    case .transcribing:
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            localizedFormat(
                                "history.import.job.transcribing",
                                default: "Transcribing: %@",
                                comment: "Status line for in-progress transcript import job",
                                job.fileName
                            )
                        )
                            .font(.caption)
                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                localizedFormat(
                                    "history.import.job.failed",
                                    default: "Import failed: %@",
                                    comment: "Status line for failed transcript import job",
                                    job.fileName
                                )
                            )
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

    private func presentImportArchivePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = TranscriptHistoryViewModel.supportedArchiveContentTypes

        guard panel.runModal() == .OK else { return }
        importArchiveURLs(panel.urls)
    }

    private func handleDroppedFileProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard fileURLProviders.isEmpty == false else { return false }

        loadDroppedFileURLs(from: fileURLProviders) { urls in
            handleDroppedFileURLs(urls)
        }
        return true
    }

    private func loadDroppedFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        final class URLAccumulator: @unchecked Sendable {
            private let lock = NSLock()
            private var urls: [URL] = []

            func append(_ url: URL) {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }

            func snapshot() -> [URL] {
                lock.lock()
                defer { lock.unlock() }
                return urls
            }
        }

        let group = DispatchGroup()
        let accumulator = URLAccumulator()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                let droppedURL: URL?
                if let url = item as? URL {
                    droppedURL = url
                } else if let data = item as? Data {
                    droppedURL = URL(dataRepresentation: data, relativeTo: nil)
                } else if let string = item as? String {
                    droppedURL = URL(string: string)
                } else {
                    droppedURL = nil
                }

                guard let droppedURL else { return }
                accumulator.append(droppedURL)
            }
        }

        group.notify(queue: .main) {
            completion(accumulator.snapshot())
        }
    }

    private func handleDroppedFileURLs(_ urls: [URL]) {
        guard urls.isEmpty == false else { return }

        let archiveURLs = urls.filter { TranscriptHistoryViewModel.isSupportedArchiveFile($0) }
        let audioURLs = urls.filter { TranscriptHistoryViewModel.isSupportedAudioFile($0) }

        if archiveURLs.isEmpty == false {
            importArchiveURLs(archiveURLs)
        }

        if audioURLs.isEmpty == false {
            viewModel.enqueueImportedFiles(
                audioURLs,
                selectedModelID: modelStore.resolvedSelectedModelID,
                languageHint: nil,
                requestDiarization: requestDiarizationForImports
            )
        }
    }

    private func importArchiveURLs(_ urls: [URL]) {
        guard urls.isEmpty == false else { return }

        var aggregate = TranscriptArchiveImportResult(
            importedTranscriptCount: 0,
            importedActionCount: 0,
            skippedDuplicateCount: 0,
            firstImportedTranscriptID: nil
        )

        do {
            for url in urls {
                let result = try viewModel.importArchive(from: url)
                aggregate.importedTranscriptCount += result.importedTranscriptCount
                aggregate.importedActionCount += result.importedActionCount
                aggregate.skippedDuplicateCount += result.skippedDuplicateCount
                if aggregate.firstImportedTranscriptID == nil {
                    aggregate.firstImportedTranscriptID = result.firstImportedTranscriptID
                }
            }

            archiveImportSummary = aggregate
            archiveImportErrorMessage = nil

            if let firstImportedID = aggregate.firstImportedTranscriptID {
                selectTranscriptFromExternalNavigation(firstImportedID)
            }
        } catch {
            archiveImportSummary = nil
            archiveImportErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func transcriptRow(_ record: TranscriptRecord) -> some View {
        let isExpanded = record.id.map { expandedRecordIDs.contains($0) } ?? false
        let isSelected = record.id.map { viewModel.selectedRecordIDs.contains($0) } ?? false
        let isKeyboardFocused = record.id.map { keyboardFocusedRecordID == $0 && historyKeyboardFocus == .list } ?? false

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

                if let recordID = record.id, record.audioFilePath != nil {
                    audioPlaybackSection(record: record, recordID: recordID)
                }

                if let recordID = record.id, let segments = record.segments, segments.isEmpty == false {
                    HStack(spacing: 8) {
                        Toggle(
                            localized(
                                "history.row.timeline.toggle",
                                default: "Timeline",
                                comment: "Toggle label for switching transcript row to timeline mode"
                            ),
                            isOn: timelineEnabledBinding(for: recordID)
                        )
                            .toggleStyle(.switch)
                            .font(.caption)

                        if let speakerCount = speakerCount(in: segments), speakerCount > 0 {
                            Text(
                                localizedFormat(
                                    "history.row.speakers.count",
                                    default: "Speakers: %d",
                                    comment: "Badge showing count of unique speakers in transcript",
                                    speakerCount
                                )
                            )
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }

                        Spacer()
                    }

                    if timelineEnabledRecordIDs.contains(recordID) {
                        timelineView(for: record, recordID: recordID, segments: segments)
                    } else {
                        Text(record.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    speakerRenameSection(record: record, recordID: recordID, segments: segments)
                } else {
                    Text(record.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let recordID = record.id {
                    transcriptTransferSection(record: record, recordID: recordID)
                    transcriptNotesSection(record: record, recordID: recordID)
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
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isKeyboardFocused ? Color.accentColor.opacity(0.7) : Color.clear,
                    lineWidth: isKeyboardFocused ? 1.5 : 0
                )
        )
        .accessibilityElement(
            children: Self.usesCombinedAccessibilityChildren(isExpanded: isExpanded) ? .combine : .contain
        )
        .accessibilityLabel(transcriptRowAccessibilityLabel(record))
        .accessibilityHint(
            isExpanded
                ? "Double-tap to collapse transcript."
                : localized(
                    "history.row.accessibility.hint.expandCollapse",
                    default: "Double-tap to expand transcript",
                    comment: "Accessibility hint for transcript row expand and collapse action"
                )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(
            named: Text(
                expandedRecordIDs.contains(record.id ?? -1)
                    ? localized(
                        "history.row.accessibility.action.collapse",
                        default: "Collapse",
                        comment: "Accessibility action name for collapsing an expanded transcript row"
                    )
                    : localized(
                        "history.row.accessibility.action.expand",
                        default: "Expand",
                        comment: "Accessibility action name for expanding a transcript row"
                    )
            )
        ) {
            guard let recordID = record.id else { return }
            toggleTranscriptExpansion(recordID)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let recordID = record.id else { return }
            let additiveSelection = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            viewModel.selectRecord(id: recordID, additive: additiveSelection)
            keyboardFocusedRecordID = recordID
            historyKeyboardFocus = .list
            toggleTranscriptExpansion(recordID)
        }
        .contextMenu {
            if let recordID = record.id {
                Button(
                    localized(
                        "history.row.contextMenu.share",
                        default: "Share…",
                        comment: "Context menu action for sharing a transcript archive"
                    )
                ) {
                    viewModel.shareRecord(id: recordID)
                }

                Button(
                    localized(
                        "history.row.contextMenu.export",
                        default: "Export…",
                        comment: "Context menu action for exporting a transcript"
                    )
                ) {
                    viewModel.exportRecord(id: recordID)
                }
            }
        }
    }

    private func transcriptTransferSection(record: TranscriptRecord, recordID: Int64) -> some View {
        HStack(spacing: 8) {
            Button(
                localized(
                    "history.row.export",
                    default: "Export…",
                    comment: "Button title for exporting a single expanded transcript"
                )
            ) {
                viewModel.exportRecord(id: recordID)
            }
            .buttonStyle(.bordered)

            Button(
                localized(
                    "history.row.share",
                    default: "Share…",
                    comment: "Button title for sharing a single expanded transcript archive"
                )
            ) {
                viewModel.shareRecord(id: recordID)
            }
            .buttonStyle(.bordered)

            if let segments = record.segments, segments.isEmpty == false {
                Button(
                    localized(
                        "history.row.editSegments",
                        default: "Edit Segments",
                        comment: "Button title for opening the segment editor sheet"
                    )
                ) {
                    segmentEditorTranscript = record
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    private func transcriptRowAccessibilityLabel(_ record: TranscriptRecord) -> String {
        let date = Self.dateFormatter.string(from: record.createdAt)
        let source = sourceAccessibilityName(for: record)
        let wordCount = record.text.split(whereSeparator: \.isWhitespace).count
        return localizedFormat(
            "history.row.accessibility.label",
            default: "Transcript from %@, %@, %d words",
            comment: "Accessibility label for a transcript history row including date, source, and word count",
            date,
            source,
            wordCount
        )
    }

    private func toggleTranscriptExpansion(_ recordID: Int64) {
        if expandedRecordIDs.contains(recordID) {
            collapseTranscript(recordID)
        } else {
            expandTranscript(recordID)
        }
    }

    private func expandTranscript(_ recordID: Int64) {
        if let loadedAudioRecordID, loadedAudioRecordID != recordID {
            pauseAndResetAudioPlayer()
        }
        expandedRecordIDs.insert(recordID)
        viewModel.loadActions(for: recordID)
        refreshSpeakerSuggestions(for: recordID)
        loadAudioForExpandedTranscript(recordID)
    }

    private func collapseTranscript(_ recordID: Int64) {
        expandedRecordIDs.remove(recordID)
        stopStreaming(for: recordID)
        speakerProfileSaveFeedbackByRecordID[recordID] = nil
        if loadedAudioRecordID == recordID {
            pauseAndResetAudioPlayer()
        }
    }

    @ViewBuilder
    private func audioPlaybackSection(record: TranscriptRecord, recordID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let audioError = audioErrorByRecordID[recordID] {
                HStack(spacing: 8) {
                    Text(audioError)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(
                        localized(
                            "action.dismiss",
                            default: "Dismiss",
                            comment: "Action title for dismissing inline status messages"
                        )
                    ) {
                        audioErrorByRecordID[recordID] = nil
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } else if loadedAudioRecordID == recordID, audioPlayer.isLoaded {
                HStack(spacing: 8) {
                    Button {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.play()
                        }
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        audioPlayer.isPlaying
                            ? localized(
                                "history.audio.pause",
                                default: "Pause audio",
                                comment: "Accessibility label for pausing transcript audio"
                            )
                            : localized(
                                "history.audio.play",
                                default: "Play audio",
                                comment: "Accessibility label for playing transcript audio"
                            )
                    )

                    Slider(
                        value: playbackSliderBinding(for: recordID),
                        in: 0 ... max(audioPlayer.duration, 0.1),
                        onEditingChanged: { isEditing in
                            if isEditing {
                                isAudioScrubbing = true
                                audioScrubberTime = audioPlayer.currentTime
                            } else {
                                isAudioScrubbing = false
                                audioPlayer.seek(to: audioScrubberTime)
                            }
                        }
                    )

                    Text(
                        "\(playbackTimestamp(for: displayedPlaybackTime(for: recordID))) / \(playbackTimestamp(for: audioPlayer.duration))"
                    )
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            } else if record.audioFilePath != nil {
                Text(
                    localized(
                        "history.audio.loading",
                        default: "Loading audio…",
                        comment: "Status text while loading retained transcript audio"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func playbackSliderBinding(for recordID: Int64) -> Binding<Double> {
        Binding(
            get: {
                guard loadedAudioRecordID == recordID else { return 0 }
                return isAudioScrubbing ? audioScrubberTime : audioPlayer.currentTime
            },
            set: { newValue in
                audioScrubberTime = newValue
            }
        )
    }

    private func displayedPlaybackTime(for recordID: Int64) -> Double {
        guard loadedAudioRecordID == recordID else { return 0 }
        return isAudioScrubbing ? audioScrubberTime : audioPlayer.currentTime
    }

    @ViewBuilder
    private func transcriptActionsSection(record: TranscriptRecord, recordID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(
                    localized(
                        "history.actions.summarise",
                        default: "Summarise",
                        comment: "Button title to summarize a transcript via AI"
                    )
                ) {
                    startStreamingAction(.summarise, for: record, recordID: recordID)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    localized(
                        "history.actions.summarise.accessibility",
                        default: "Summarise transcript",
                        comment: "Accessibility label for transcript summarization action"
                    )
                )

                Button(
                    localized(
                        "history.actions.translate",
                        default: "Translate",
                        comment: "Button title to translate a transcript via AI"
                    )
                ) {
                    translatePopoverRecordID = recordID
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    localized(
                        "history.actions.translate.accessibility",
                        default: "Translate transcript",
                        comment: "Accessibility label for transcript translation action"
                    )
                )
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
                        Picker(
                            localized(
                                "history.actions.translate.language",
                                default: "Language",
                                comment: "Picker label for translation target language"
                            ),
                            selection: translateLanguageCodeBinding(for: recordID)
                        ) {
                            ForEach(AppLanguageOption.all) { option in
                                Text(option.name).tag(option.code)
                            }
                        }

                        Button(
                            localized(
                                "history.actions.translate",
                                default: "Translate",
                                comment: "Button title to confirm transcript translation"
                            )
                        ) {
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

                Button(
                    localized(
                        "history.actions.askQuestion",
                        default: "Ask a Question",
                        comment: "Button title to ask a question about transcript via AI"
                    )
                ) {
                    toggleInputMode(.question, for: recordID)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    localized(
                        "history.actions.askQuestion.accessibility",
                        default: "Ask a question about transcript",
                        comment: "Accessibility label for ask-question AI action"
                    )
                )

                Button(
                    localized(
                        "history.actions.customPrompt",
                        default: "Custom Prompt",
                        comment: "Button title to run a custom prompt on transcript"
                    )
                ) {
                    toggleInputMode(.customPrompt, for: recordID)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    localized(
                        "history.actions.customPrompt.accessibility",
                        default: "Run custom prompt on transcript",
                        comment: "Accessibility label for custom-prompt AI action"
                    )
                )
            }
            .disabled(areTranscriptActionsEnabled == false)

            if let statusLine = lmStudioStatusLine {
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if actionInputModeByRecordID[recordID] == .question {
                HStack(spacing: 8) {
                    TextField(
                        localized(
                            "history.actions.askQuestion.placeholder",
                            default: "Ask a question about this transcript",
                            comment: "Placeholder for transcript question input"
                        ),
                        text: questionBinding(for: recordID)
                    )
                        .textFieldStyle(.roundedBorder)
                    Button(
                        localized(
                            "action.ask",
                            default: "Ask",
                            comment: "Action title for submitting transcript question"
                        )
                    ) {
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Menu(
                            localized(
                                "history.actions.customPrompt.useTemplate",
                                default: "Use template…",
                                comment: "Menu button title for selecting a saved prompt template"
                            )
                        ) {
                            if promptTemplates.isEmpty {
                                Text(
                                    localized(
                                        "history.actions.customPrompt.noTemplates",
                                        default: "No templates saved",
                                        comment: "Empty-state text shown in custom prompt template picker"
                                    )
                                )
                                .disabled(true)
                            } else {
                                ForEach(promptTemplates) { template in
                                    Button(template.name) {
                                        customPromptInputByRecordID[recordID] = template.prompt
                                        customPromptTemplateFeedbackByRecordID[recordID] = nil
                                    }
                                }
                            }
                        }

                        Button(
                            localized(
                                "history.actions.customPrompt.saveTemplate",
                                default: "Save as template…",
                                comment: "Button title for saving current custom prompt as a template"
                            )
                        ) {
                            preparePromptTemplateSave(for: recordID)
                        }
                        .disabled(
                            customPromptInputByRecordID[recordID, default: ""]
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }

                    TextEditor(text: customPromptBinding(for: recordID))
                        .frame(minHeight: 84, maxHeight: 160)
                        .font(.body)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button(
                            localized(
                                "action.run",
                                default: "Run",
                                comment: "Action title for executing custom prompt"
                            )
                        ) {
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

                        Button(
                            localized(
                                "action.cancel",
                                default: "Cancel",
                                comment: "Generic action title for canceling a dialog"
                            )
                        ) {
                            actionInputModeByRecordID[recordID] = TranscriptActionInputMode.none
                        }
                        .buttonStyle(.bordered)
                    }

                    if let message = customPromptTemplateFeedbackByRecordID[recordID] {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if streamingRecordIDs.contains(recordID) || (streamingTextByRecordID[recordID]?.isEmpty == false) {
                VStack(alignment: .leading, spacing: 8) {
                    if waitingForFirstTokenRecordIDs.contains(recordID) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(
                                localized(
                                    "history.actions.waitingResponse",
                                    default: "Waiting for response…",
                                    comment: "Status text while waiting for first streamed AI token"
                                )
                            )
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
                        Button(
                            localized(
                                "action.stop",
                                default: "Stop",
                                comment: "Action title for stopping an in-progress AI action stream"
                            )
                        ) {
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
                Text(
                    localized(
                        "history.actions.previous.empty",
                        default: "No previous actions yet.",
                        comment: "Message shown when transcript has no prior AI actions"
                    )
                )
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
            Text(
                localized(
                    "history.actions.previous.section",
                    default: "Previous Actions",
                    comment: "Disclosure title for previous AI actions"
                )
            )
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
                Text(actionLabel(for: actionRecord))
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
                    Button(
                        isExpanded
                            ? localized(
                                "action.collapse",
                                default: "Collapse",
                                comment: "Action title for collapsing expanded content"
                            )
                            : localized(
                                "action.expand",
                                default: "Expand",
                                comment: "Action title for expanding truncated content"
                            )
                    ) {
                        if isExpanded {
                            expandedPreviousActionResultIDs.remove(actionID)
                        } else {
                            expandedPreviousActionResultIDs.insert(actionID)
                        }
                    }
                    .font(.caption)
                }

                Button(
                    localized(
                        "action.copy",
                        default: "Copy",
                        comment: "Generic action title for copying text"
                    )
                ) {
                    viewModel.copyActionText(text)
                }
                .font(.caption)

                if let actionID = actionRecord.id {
                    Button(
                        localized(
                            "action.delete",
                            default: "Delete",
                            comment: "Action title for deleting an item"
                        ),
                        role: .destructive
                    ) {
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

    private var savePromptTemplateSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    localized(
                        "history.actions.customPrompt.saveTemplate.sheetTitle",
                        default: "Save Prompt Template",
                        comment: "Sheet title for saving a custom prompt template"
                    )
                )
                .font(.headline)

                TextField(
                    localized(
                        "history.actions.customPrompt.saveTemplate.name",
                        default: "Template name",
                        comment: "Input label for naming a saved custom prompt template"
                    ),
                    text: $savePromptTemplateName
                )
                .textFieldStyle(.roundedBorder)

                TextEditor(text: $savePromptTemplatePrompt)
                    .frame(minHeight: 100)
                    .font(.body)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                if let savePromptTemplateError {
                    Text(savePromptTemplateError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()

                    Button(
                        localized(
                            "action.cancel",
                            default: "Cancel",
                            comment: "Generic action title for canceling a dialog"
                        )
                    ) {
                        dismissPromptTemplateSaveSheet()
                    }
                    .buttonStyle(.bordered)

                    Button(
                        localized(
                            "action.save",
                            default: "Save",
                            comment: "Generic action title for saving data"
                        )
                    ) {
                        savePromptTemplateFromSheet()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 260, idealHeight: 340)
    }

    private func loadPromptTemplates() {
        promptTemplates = promptTemplateStore.load()
    }

    private func preparePromptTemplateSave(for recordID: Int64) {
        let prompt = customPromptInputByRecordID[recordID, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else { return }

        savePromptTemplateTargetRecordID = recordID
        savePromptTemplatePrompt = prompt
        savePromptTemplateName = defaultTemplateName(from: prompt)
        savePromptTemplateError = nil
        isSavePromptTemplateSheetPresented = true
    }

    private func dismissPromptTemplateSaveSheet() {
        isSavePromptTemplateSheetPresented = false
        savePromptTemplateTargetRecordID = nil
        savePromptTemplateName = ""
        savePromptTemplatePrompt = ""
        savePromptTemplateError = nil
    }

    private func savePromptTemplateFromSheet() {
        let trimmedName = savePromptTemplateName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = savePromptTemplatePrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false else {
            savePromptTemplateError = localized(
                "history.actions.customPrompt.saveTemplate.error.nameRequired",
                default: "Template name is required.",
                comment: "Validation error shown when template name is empty"
            )
            return
        }

        guard trimmedName.count <= 40 else {
            savePromptTemplateError = localized(
                "history.actions.customPrompt.saveTemplate.error.nameLength",
                default: "Template name must be 40 characters or fewer.",
                comment: "Validation error shown when template name exceeds max length"
            )
            return
        }

        guard trimmedPrompt.isEmpty == false else {
            savePromptTemplateError = localized(
                "history.actions.customPrompt.saveTemplate.error.promptRequired",
                default: "Prompt text is required.",
                comment: "Validation error shown when prompt template text is empty"
            )
            return
        }

        guard promptTemplates.count < PromptTemplateStore.maxTemplateCount else {
            savePromptTemplateError = localizedFormat(
                "history.actions.customPrompt.saveTemplate.error.limit",
                default: "You can save up to %d templates.",
                comment: "Validation error shown when prompt template max limit is reached",
                PromptTemplateStore.maxTemplateCount
            )
            return
        }

        _ = promptTemplateStore.add(name: trimmedName, prompt: trimmedPrompt)
        loadPromptTemplates()

        if let recordID = savePromptTemplateTargetRecordID {
            customPromptTemplateFeedbackByRecordID[recordID] = localized(
                "history.actions.customPrompt.saveTemplate.success",
                default: "Template saved",
                comment: "Inline status text shown when a custom prompt template is saved"
            )
        }

        dismissPromptTemplateSaveSheet()
    }

    private func defaultTemplateName(from prompt: String) -> String {
        let compact = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.isEmpty == false else {
            return localized(
                "history.actions.customPrompt.saveTemplate.defaultName",
                default: "New Template",
                comment: "Default name for a newly saved prompt template"
            )
        }
        return String(compact.prefix(30))
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
            return localized(
                "history.actions.lmStudio.checking",
                default: "Checking LM Studio status…",
                comment: "Status line while checking LM Studio connectivity for transcript actions"
            )
        case .reachableWithModels:
            if lmStudioModelID.isEmpty {
                return localized(
                    "history.actions.lmStudio.chooseDefaultModel",
                    default: "Choose a default model in Settings > AI.",
                    comment: "Status line when LM Studio is reachable but no default model is selected"
                )
            }
            return nil
        case .reachableNoModels:
            return localized(
                "history.actions.lmStudio.noModels",
                default: "No models loaded in LM Studio. Load a model first.",
                comment: "Status line when LM Studio is reachable but has no loaded model"
            )
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
            lmStudioReachabilityStatus = .unreachable(
                localized(
                    "error.lmStudio.invalidHostPort",
                    default: "Invalid LM Studio host or port.",
                    comment: "Error shown when LM Studio host or port values are invalid"
                )
            )
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
                ?? localized(
                    "error.lmStudio.notAvailableActions",
                    default: "LM Studio is not available for AI actions.",
                    comment: "Error shown when transcript AI action service cannot be used"
                )
            return
        }
        guard let modelID = selectedLLMModelID else {
            actionErrorByRecordID[recordID] = localized(
                "history.actions.lmStudio.chooseDefaultModel",
                default: "Choose a default model in Settings > AI.",
                comment: "Error shown when transcript AI action is requested without default model"
            )
            return
        }
        guard let service = makeTranscriptActionService() else {
            actionErrorByRecordID[recordID] = localized(
                "error.lmStudio.notConfigured",
                default: "LM Studio is not configured.",
                comment: "Error shown when transcript AI action is requested without LM Studio configuration"
            )
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
        customPromptTemplateFeedbackByRecordID = customPromptTemplateFeedbackByRecordID.filter {
            validRecordIDs.contains($0.key)
        }
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

    private func pruneSpeakerDraftState(validRecordIDs: Set<Int64>) {
        speakerNameDraftsByRecordID = speakerNameDraftsByRecordID.filter { validRecordIDs.contains($0.key) }
        speakerSuggestionsByRecordID = speakerSuggestionsByRecordID.filter { validRecordIDs.contains($0.key) }
        dismissedSuggestionLabelsByRecordID = dismissedSuggestionLabelsByRecordID.filter {
            validRecordIDs.contains($0.key)
        }
        speakerProfileSaveFeedbackByRecordID = speakerProfileSaveFeedbackByRecordID.filter {
            validRecordIDs.contains($0.key)
        }
        if let focusedSpeakerField, validRecordIDs.contains(focusedSpeakerField.recordID) == false {
            self.focusedSpeakerField = nil
        }
    }

    private func pruneNotesState(validRecordIDs: Set<Int64>) {
        notesDraftByRecordID = notesDraftByRecordID.filter { validRecordIDs.contains($0.key) }
        for (recordID, task) in notesSaveTaskByRecordID where validRecordIDs.contains(recordID) == false {
            task.cancel()
            notesSaveTaskByRecordID[recordID] = nil
        }
        if let focusedNotesRecordID, validRecordIDs.contains(focusedNotesRecordID) == false {
            self.focusedNotesRecordID = nil
        }
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
            return localized(
                "history.actions.type.summary",
                default: "Summary",
                comment: "Label for previously saved summary AI action"
            )
        case "translate":
            return localized(
                "history.actions.type.translate",
                default: "Translate",
                comment: "Label for previously saved translation AI action"
            )
        case "question":
            return localized(
                "history.actions.type.question",
                default: "Question",
                comment: "Label for previously saved question AI action"
            )
        case "custom_prompt", "custom":
            return localized(
                "history.actions.type.custom",
                default: "Custom",
                comment: "Label for previously saved custom prompt AI action"
            )
        case "auto_summarise":
            return localized(
                "history.actions.type.autoSummary",
                default: "Auto-Summary",
                comment: "Label for automatically generated transcript summary action"
            )
        default:
            return actionType.capitalized
        }
    }

    private func actionLabel(for actionRecord: TranscriptActionRecord) -> String {
        if actionRecord.actionType == "pipeline_step" {
            let name = actionRecord.actionInput?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, name.isEmpty == false {
                return localizedFormat(
                    "history.actions.type.pipelineStep.named",
                    default: "Pipeline: %@",
                    comment: "Label for a pipeline-step transcript action that includes the step name",
                    name
                )
            }

            return localized(
                "history.actions.type.pipelineStep",
                default: "Pipeline Step",
                comment: "Label for a pipeline-step transcript action without a step name"
            )
        }

        return actionTypeLabel(for: actionRecord.actionType)
    }

    @ViewBuilder
    private func speakerRenameSection(record: TranscriptRecord, recordID: Int64, segments: [TranscriptSegment]) -> some View {
        let speakers = uniqueSpeakers(in: segments)
        if speakers.isEmpty == false {
            DisclosureGroup(
                localized(
                    "history.speakers.rename.section",
                    default: "Rename Speakers",
                    comment: "Disclosure title for transcript speaker renaming controls"
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(speakers, id: \.self) { speaker in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(speaker)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)

                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                TextField(
                                    localized(
                                        "history.speakers.rename.placeholder",
                                        default: "Name",
                                        comment: "Placeholder for custom speaker display name"
                                    ),
                                    text: speakerNameBinding(
                                        for: recordID,
                                        speaker: speaker,
                                        currentSpeakerMap: record.speakerMap
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .focused(
                                    $focusedSpeakerField,
                                    equals: SpeakerRenameField(recordID: recordID, speaker: speaker)
                                )
                                .onSubmit {
                                    persistSpeakerNameDraft(for: recordID, speaker: speaker)
                                    refreshSpeakerSuggestions(for: recordID)
                                }
                            }

                            if
                                let speakerName = currentSpeakerDisplayName(
                                    for: recordID,
                                    speaker: speaker,
                                    currentSpeakerMap: record.speakerMap
                                ),
                                viewModel.hasStoredEmbedding(recordID: recordID, speakerLabel: speaker)
                            {
                                HStack(spacing: 8) {
                                    Button(
                                        localizedFormat(
                                            "history.speakers.profile.saveFromName",
                                            default: "Save \"%@\" as speaker profile",
                                            comment: "Link title for saving a renamed speaker as a reusable speaker profile",
                                            speakerName
                                        )
                                    ) {
                                        saveSpeakerProfileFromName(
                                            recordID: recordID,
                                            speakerLabel: speaker,
                                            displayName: speakerName
                                        )
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption2)

                                    if let feedback = speakerProfileSaveFeedbackByRecordID[recordID]?[speaker] {
                                        Text(feedback)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    let suggestions = suggestions(for: recordID)
                    if suggestions.isEmpty == false {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(suggestions) { suggestion in
                                HStack(spacing: 8) {
                                    Text(
                                        localizedFormat(
                                            "history.speakers.suggestion.row",
                                            default: "%@ \u{2192} Suggested: %@",
                                            comment: "Suggestion banner text mapping speaker labels to suggested profile names",
                                            suggestion.speakerLabel,
                                            suggestion.profileDisplayName
                                        )
                                    )
                                    .font(.caption)

                                    Spacer()

                                    Button(
                                        localized(
                                            "action.accept",
                                            default: "Accept",
                                            comment: "Generic action title for accepting a suggestion"
                                        )
                                    ) {
                                        acceptSpeakerSuggestion(recordID: recordID, suggestion: suggestion)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)

                                    Button(
                                        localized(
                                            "action.dismiss",
                                            default: "Dismiss",
                                            comment: "Action title for dismissing inline status messages"
                                        )
                                    ) {
                                        dismissSpeakerSuggestion(recordID: recordID, suggestion: suggestion)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.10))
                                )
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button(
                            localized(
                                "history.speakers.rename.reset",
                                default: "Reset Names",
                                comment: "Action title to clear custom speaker names"
                            )
                        ) {
                            resetSpeakerNames(for: recordID)
                            refreshSpeakerSuggestions(for: recordID)
                        }
                        .disabled((record.speakerMap ?? [:]).isEmpty)
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
    }

    private func transcriptNotesSection(record: TranscriptRecord, recordID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                localized(
                    "history.notes.section",
                    default: "Notes",
                    comment: "Section title for transcript notes editor"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: notesBinding(for: recordID, currentNotes: record.notes))
                    .font(.body)
                    .frame(minHeight: 62, maxHeight: 110)
                    .scrollContentBackground(.hidden)
                    .focused($focusedNotesRecordID, equals: recordID)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)

                if notesText(for: recordID, currentNotes: record.notes)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                {
                    Text(
                        localized(
                            "history.notes.placeholder",
                            default: "Add notes…",
                            comment: "Placeholder text for transcript notes editor"
                        )
                    )
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.leading, 8)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.secondary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func timelineView(
        for record: TranscriptRecord,
        recordID: Int64,
        segments: [TranscriptSegment]
    ) -> some View {
        let highlightedSegmentIndex = currentlyHighlightedSegmentIndex(
            for: recordID,
            segments: segments
        )

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        let isHighlighted = highlightedSegmentIndex == index
                        HStack(alignment: .top, spacing: 8) {
                            Button("[\(timelineTimestamp(for: segment.start))]") {
                                viewModel.copyActionText(segment.text)
                            }
                            .buttonStyle(.plain)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                timelineSegmentAccessibilityLabel(segment: segment, record: record)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                if let speaker = record.resolvedSpeaker(for: segment) {
                                    Text("\(speaker):")
                                        .font(.system(.caption, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(
                                            colorForSpeaker(normalizedSpeakerLabel(segment.speaker) ?? speaker)
                                        )
                                }

                                Text(segment.text)
                                    .font(.body)
                                    .fontWeight(isHighlighted ? .semibold : .regular)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    isHighlighted
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear
                                )
                        )
                        .id(TimelineSegmentID(recordID: recordID, index: index))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard loadedAudioRecordID == recordID, audioPlayer.isLoaded else { return }
                            audioPlayer.seek(to: segment.start)
                            if isAudioScrubbing == false {
                                audioScrubberTime = audioPlayer.currentTime
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.1), value: highlightedSegmentIndex)
            }
            .onChange(of: highlightedSegmentIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(TimelineSegmentID(recordID: recordID, index: newIndex), anchor: .center)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    private func currentlyHighlightedSegmentIndex(
        for recordID: Int64,
        segments: [TranscriptSegment]
    ) -> Int? {
        guard loadedAudioRecordID == recordID, audioPlayer.isLoaded else { return nil }
        return TranscriptPlaybackSynchronizer.currentSegmentIndex(for: audioPlayer.currentTime, in: segments)
    }

    private func loadAudioForExpandedTranscript(_ recordID: Int64) {
        guard let record = viewModel.record(withID: recordID) else { return }
        guard let audioFilePath = record.audioFilePath else { return }

        let trimmedPath = audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else { return }
        let fileURL = URL(fileURLWithPath: trimmedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            audioErrorByRecordID[recordID] = localized(
                "history.audio.fileNotFound",
                default: "Audio file not found.",
                comment: "Inline status shown when linked retained audio file no longer exists"
            )
            return
        }

        do {
            try audioPlayer.load(url: fileURL)
            loadedAudioRecordID = recordID
            audioScrubberTime = audioPlayer.currentTime
            isAudioScrubbing = false
            audioErrorByRecordID[recordID] = nil
        } catch {
            loadedAudioRecordID = nil
            audioErrorByRecordID[recordID] = localized(
                "history.audio.failedToLoad",
                default: "Could not load audio file.",
                comment: "Inline status shown when retained audio fails to load"
            )
        }
    }

    private func pauseAndResetAudioPlayer() {
        audioPlayer.pause()
        audioPlayer.unload()
        loadedAudioRecordID = nil
        audioScrubberTime = 0
        isAudioScrubbing = false
    }

    private func pruneAudioState(validRecordIDs: Set<Int64>) {
        audioErrorByRecordID = audioErrorByRecordID.filter { validRecordIDs.contains($0.key) }
        if let loadedAudioRecordID, validRecordIDs.contains(loadedAudioRecordID) == false {
            pauseAndResetAudioPlayer()
        }
    }

    private func speakerCount(in segments: [TranscriptSegment]) -> Int? {
        let speakers = Set(segments.compactMap { normalizedSpeakerLabel($0.speaker) })
        return speakers.isEmpty ? nil : speakers.count
    }

    private func uniqueSpeakers(in segments: [TranscriptSegment]) -> [String] {
        Array(Set(segments.compactMap { normalizedSpeakerLabel($0.speaker) })).sorted()
    }

    private func suggestions(for recordID: Int64) -> [TranscriptHistoryViewModel.SpeakerSuggestion] {
        let currentSuggestions = speakerSuggestionsByRecordID[recordID] ?? []
        guard let record = viewModel.record(withID: recordID) else { return currentSuggestions }

        return currentSuggestions.filter { suggestion in
            let mappedName = record.speakerMap?[suggestion.speakerLabel]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return mappedName?.isEmpty != false
        }
    }

    private func refreshSpeakerSuggestions(for recordID: Int64) {
        let dismissed = dismissedSuggestionLabelsByRecordID[recordID] ?? []
        speakerSuggestionsByRecordID[recordID] = viewModel.loadSpeakerSuggestions(
            recordID: recordID,
            threshold: Float(min(max(speakerMatchThreshold, 0.70), 0.99)),
            dismissedSpeakerLabels: dismissed
        )
    }

    private func acceptSpeakerSuggestion(
        recordID: Int64,
        suggestion: TranscriptHistoryViewModel.SpeakerSuggestion
    ) {
        viewModel.acceptSpeakerSuggestion(recordID: recordID, suggestion: suggestion)
        speakerNameDraftsByRecordID[recordID, default: [:]][suggestion.speakerLabel] = suggestion.profileDisplayName
        dismissedSuggestionLabelsByRecordID[recordID, default: []].remove(suggestion.speakerLabel)
        refreshSpeakerSuggestions(for: recordID)
    }

    private func dismissSpeakerSuggestion(
        recordID: Int64,
        suggestion: TranscriptHistoryViewModel.SpeakerSuggestion
    ) {
        dismissedSuggestionLabelsByRecordID[recordID, default: []].insert(suggestion.speakerLabel)
        refreshSpeakerSuggestions(for: recordID)
    }

    private func currentSpeakerDisplayName(
        for recordID: Int64,
        speaker: String,
        currentSpeakerMap: [String: String]?
    ) -> String? {
        let value = speakerNameDraftsByRecordID[recordID]?[speaker]
            ?? currentSpeakerMap?[speaker]
            ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func saveSpeakerProfileFromName(
        recordID: Int64,
        speakerLabel: String,
        displayName: String
    ) {
        do {
            try viewModel.createSpeakerProfileFromSpeakerName(
                recordID: recordID,
                speakerLabel: speakerLabel,
                displayName: displayName
            )
            speakerProfileSaveFeedbackByRecordID[recordID, default: [:]][speakerLabel] = localized(
                "history.speakers.profile.saved",
                default: "Profile saved",
                comment: "Inline confirmation shown after saving a speaker profile from rename UI"
            )
            refreshSpeakerSuggestions(for: recordID)
        } catch {
            speakerProfileSaveFeedbackByRecordID[recordID, default: [:]][speakerLabel] = localized(
                "history.speakers.profile.saveFailed",
                default: "Could not save profile",
                comment: "Inline error shown when saving a speaker profile from rename UI fails"
            )
        }
    }

    private func speakerNameBinding(
        for recordID: Int64,
        speaker: String,
        currentSpeakerMap: [String: String]?
    ) -> Binding<String> {
        Binding(
            get: {
                speakerNameDraftsByRecordID[recordID]?[speaker]
                    ?? currentSpeakerMap?[speaker]
                    ?? ""
            },
            set: { newValue in
                var recordDrafts = speakerNameDraftsByRecordID[recordID, default: [:]]
                recordDrafts[speaker] = newValue
                speakerNameDraftsByRecordID[recordID] = recordDrafts
            }
        )
    }

    private func persistSpeakerNameDraft(for recordID: Int64, speaker: String) {
        guard let record = viewModel.record(withID: recordID) else { return }

        let existingName = record.speakerMap?[speaker] ?? ""
        let draftName = (speakerNameDraftsByRecordID[recordID]?[speaker] ?? existingName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedMap = record.speakerMap ?? [:]

        if draftName.isEmpty == false {
            updatedMap[speaker] = draftName
            speakerNameDraftsByRecordID[recordID, default: [:]][speaker] = draftName
        } else {
            updatedMap.removeValue(forKey: speaker)
            speakerNameDraftsByRecordID[recordID, default: [:]][speaker] = ""
        }

        viewModel.updateSpeakerMap(
            recordID: recordID,
            speakerMap: updatedMap.isEmpty ? nil : updatedMap
        )
    }

    private func resetSpeakerNames(for recordID: Int64) {
        speakerNameDraftsByRecordID[recordID] = [:]
        viewModel.updateSpeakerMap(recordID: recordID, speakerMap: nil)
    }

    private func notesBinding(for recordID: Int64, currentNotes: String?) -> Binding<String> {
        Binding(
            get: { notesText(for: recordID, currentNotes: currentNotes) },
            set: { newValue in
                notesDraftByRecordID[recordID] = newValue
                scheduleNotesSave(for: recordID)
            }
        )
    }

    private func notesText(for recordID: Int64, currentNotes: String?) -> String {
        notesDraftByRecordID[recordID] ?? currentNotes ?? ""
    }

    private func scheduleNotesSave(for recordID: Int64) {
        notesSaveTaskByRecordID[recordID]?.cancel()
        notesSaveTaskByRecordID[recordID] = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            guard Task.isCancelled == false else { return }
            await MainActor.run {
                viewModel.updateNotes(recordID: recordID, notes: notesDraftByRecordID[recordID])
                notesSaveTaskByRecordID[recordID] = nil
            }
        }
    }

    private func flushNotesSave(for recordID: Int64) {
        notesSaveTaskByRecordID[recordID]?.cancel()
        notesSaveTaskByRecordID[recordID] = nil
        let notesToPersist = notesDraftByRecordID[recordID] ?? viewModel.record(withID: recordID)?.notes
        viewModel.updateNotes(recordID: recordID, notes: notesToPersist)
    }

    private func flushAllNotesSaves() {
        for (recordID, task) in notesSaveTaskByRecordID {
            task.cancel()
            viewModel.updateNotes(recordID: recordID, notes: notesDraftByRecordID[recordID])
        }
        notesSaveTaskByRecordID.removeAll()
    }

    private func applyDelete(summary: TranscriptHistoryViewModel.DeleteSelectionSummary) {
        for recordID in summary.transcriptIDs {
            stopStreaming(for: recordID)
            expandedRecordIDs.remove(recordID)
            speakerNameDraftsByRecordID[recordID] = nil
            speakerSuggestionsByRecordID[recordID] = nil
            dismissedSuggestionLabelsByRecordID[recordID] = nil
            speakerProfileSaveFeedbackByRecordID[recordID] = nil
            notesSaveTaskByRecordID[recordID]?.cancel()
            notesSaveTaskByRecordID[recordID] = nil
            notesDraftByRecordID[recordID] = nil
            audioErrorByRecordID[recordID] = nil
            if loadedAudioRecordID == recordID {
                pauseAndResetAudioPlayer()
            }
        }
        viewModel.deleteRecords(ids: summary.transcriptIDs)
    }

    private func performDeleteSelection() {
        guard let summary = viewModel.makeDeleteSelectionSummary() else { return }
        if summary.transcriptCount > 1 {
            pendingBatchDeleteSummary = summary
        } else {
            applyDelete(summary: summary)
        }
    }

    private func selectTranscriptFromExternalNavigation(_ transcriptID: Int64) {
        guard viewModel.record(withID: transcriptID) != nil else {
            if viewModel.activeFilterCount > 0 || viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                viewModel.searchQuery = ""
                viewModel.clearFilters()
            } else {
                viewModel.reloadForSearchQuery()
            }
            return
        }
        viewModel.selectRecord(id: transcriptID, additive: false)
        keyboardFocusedRecordID = transcriptID
        expandTranscript(transcriptID)
        historyKeyboardFocus = .list
    }

    private func rowScrollID(for record: TranscriptRecord, index: Int) -> String {
        if let recordID = record.id {
            return rowScrollID(for: recordID)
        }
        return "record-index-\(index)"
    }

    private func rowScrollID(for recordID: Int64) -> String {
        "record-\(recordID)"
    }

    private func installKeyDownMonitorIfNeeded() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyDown(event) {
                return nil
            }
            return event
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard NSApp.keyWindow?.title == localized(
            "history.window.title",
            default: "History",
            comment: "Window title for transcript history"
        ) else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        if hasCommand { return false }
        if focusedSpeakerField != nil || focusedNotesRecordID != nil { return false }

        switch Int(event.keyCode) {
        case kVK_UpArrow:
            moveSelection(delta: -1)
            return true
        case kVK_DownArrow:
            moveSelection(delta: 1)
            return true
        case kVK_Return:
            toggleExpansionForKeyboardSelection()
            return true
        case kVK_Escape:
            handleEscapeCascade()
            return true
        default:
            return false
        }
    }

    private func moveSelection(delta: Int) {
        guard historyKeyboardFocus == .list else { return }
        let ids = viewModel.records.compactMap(\.id)
        guard ids.isEmpty == false else { return }

        let currentID = keyboardFocusedRecordID ?? viewModel.selectedRecordIDs.sorted().first
        let currentIndex = currentID.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        let nextIndex = max(0, min(ids.count - 1, currentIndex + delta))
        let nextID = ids[nextIndex]
        viewModel.selectRecord(id: nextID, additive: false)
        keyboardFocusedRecordID = nextID
    }

    private func toggleExpansionForKeyboardSelection() {
        guard historyKeyboardFocus == .list else { return }
        let targetID = keyboardFocusedRecordID ?? viewModel.selectedRecordIDs.sorted().first
        guard let targetID else { return }
        if expandedRecordIDs.contains(targetID) {
            collapseTranscript(targetID)
        } else {
            expandTranscript(targetID)
        }
    }

    private func handleEscapeCascade() {
        let trimmedSearch = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty == false {
            viewModel.searchQuery = ""
            viewModel.reloadForSearchQuery()
            historyKeyboardFocus = .search
            return
        }

        if viewModel.selectedRecordIDs.isEmpty == false {
            viewModel.clearSelection()
            keyboardFocusedRecordID = nil
            historyKeyboardFocus = .list
            return
        }

        NSApp.keyWindow?.performClose(nil)
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

    private func playbackTimestamp(for seconds: Double) -> String {
        let totalSeconds = Int(max(seconds, 0))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func elapsedDurationSeconds(since startedAt: UInt64) -> Double {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now > startedAt else { return 0 }
        return Double(now - startedAt) / 1_000_000_000
    }

    private func errorMessage(for error: Error) -> String {
        switch error {
        case LMStudioClientError.connectionRefused:
            return localized(
                "error.lmStudio.notRunning",
                default: "LM Studio is not running. Start LM Studio to use AI features.",
                comment: "Error shown when LM Studio is offline while running transcript AI actions"
            )
        case LMStudioClientError.noModelsLoaded:
            return localized(
                "error.lmStudio.noModelsLoaded",
                default: "No models loaded in LM Studio. Load a model first.",
                comment: "Error shown when LM Studio has no loaded models for transcript AI actions"
            )
        case LMStudioClientError.streamParsingFailed:
            return localized(
                "error.lmStudio.streamUnreadable",
                default: "Received an unreadable streaming response from LM Studio.",
                comment: "Error shown when streamed LM Studio response cannot be parsed"
            )
        case LMStudioClientError.unexpectedStatusCode:
            return localized(
                "error.lmStudio.unexpectedResponse",
                default: "LM Studio returned an unexpected response.",
                comment: "Error shown when LM Studio returns an unexpected response"
            )
        case TranscriptActionServiceError.emptyResponse:
            return localized(
                "error.lmStudio.emptyResponse",
                default: "The model returned an empty response. Try again or select a different model.",
                comment: "Error shown when transcript AI action returns empty result"
            )
        default:
            let lowercased = error.localizedDescription.lowercased()
            if lowercased.contains("context")
                || lowercased.contains("maximum")
                || lowercased.contains("token")
            {
                return localized(
                    "error.lmStudio.contextTooLong",
                    default: "Transcript is too long for the selected model.",
                    comment: "Error shown when transcript exceeds model context limits"
                )
            }
            return error.localizedDescription
        }
    }

    private func sourceBadge(for record: TranscriptRecord) -> some View {
        let label: String
        if record.sourceType == "dictation" {
            label = localized(
                "history.source.dictation",
                default: "Dictation",
                comment: "Badge label for dictation-sourced transcripts"
            )
        } else if let sourceFileName = record.sourceFileName, sourceFileName.isEmpty == false {
            label = sourceFileName
        } else {
            label = localized(
                "history.source.importedFile",
                default: "Imported File",
                comment: "Badge label for imported-file transcripts"
            )
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

    private func timelineSegmentAccessibilityLabel(
        segment: TranscriptSegment,
        record: TranscriptRecord
    ) -> String {
        let timestamp = timelineTimestamp(for: segment.start)
        let speaker = record.resolvedSpeaker(for: segment) ?? localized(
            "history.timeline.speaker.unknown",
            default: "Unknown speaker",
            comment: "Fallback speaker label for timeline accessibility"
        )
        return localizedFormat(
            "history.timeline.segment.accessibility",
            default: "%@ %@: %@",
            comment: "Accessibility label for a timeline transcript segment",
            timestamp,
            speaker,
            segment.text
        )
    }

    private func sourceAccessibilityName(for record: TranscriptRecord) -> String {
        if record.sourceType == "dictation" {
            return localized(
                "history.source.dictation",
                default: "Dictation",
                comment: "Accessibility source name for dictation transcripts"
            )
        }
        if let sourceFileName = record.sourceFileName, sourceFileName.isEmpty == false {
            return sourceFileName
        }
        return localized(
            "history.source.importedFile",
            default: "Imported File",
            comment: "Accessibility source name for imported transcripts"
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    nonisolated static func usesCombinedAccessibilityChildren(isExpanded: Bool) -> Bool {
        isExpanded == false
    }

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

private struct SpeakerRenameField: Hashable {
    let recordID: Int64
    let speaker: String
}

private struct TimelineSegmentID: Hashable {
    let recordID: Int64
    let index: Int
}

private enum HistoryKeyboardFocus: Hashable {
    case search
    case list
}

struct HistorySelectionActions {
    let focusSearch: () -> Void
    let copySelection: () -> Void
    let exportSelection: () -> Void
    let deleteSelection: () -> Void
    let selectAllVisible: () -> Void
}

private struct HistorySelectionActionsKey: FocusedValueKey {
    typealias Value = HistorySelectionActions
}

extension FocusedValues {
    var historySelectionActions: HistorySelectionActions? {
        get { self[HistorySelectionActionsKey.self] }
        set { self[HistorySelectionActionsKey.self] = newValue }
    }
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

    struct DeleteSelectionSummary: Equatable {
        let transcriptIDs: [Int64]
        let transcriptCount: Int
        let associatedActionCount: Int

        var alertTitle: String {
            localizedFormat(
                "history.delete.alert.title",
                default: "Delete %d transcripts?",
                comment: "Delete confirmation title showing transcript count",
                transcriptCount
            )
        }

        var alertMessage: String {
            let actionLabel = associatedActionCount == 1
                ? localized(
                    "history.delete.alert.actionLabel.singular",
                    default: "AI action",
                    comment: "Singular phrase for one associated AI action in delete confirmation"
                )
                : localized(
                    "history.delete.alert.actionLabel.plural",
                    default: "AI actions",
                    comment: "Plural phrase for associated AI actions in delete confirmation"
                )
            return localizedFormat(
                "history.delete.alert.message",
                default: "This action cannot be undone. %d associated %@ will also be deleted.",
                comment: "Delete confirmation message including cascade deletion count",
                associatedActionCount,
                actionLabel
            )
        }
    }

    enum SourceTypeFilterOption: String, CaseIterable, Identifiable {
        case all
        case dictation
        case imported

        var id: String { rawValue }

        var sourceTypeValue: String? {
            switch self {
            case .all:
                return nil
            case .dictation:
                return "dictation"
            case .imported:
                return "file_import"
            }
        }

        var label: String {
            switch self {
            case .all:
                return localized(
                    "history.filters.source.option.all",
                    default: "All",
                    comment: "Filter option label for all transcript sources"
                )
            case .dictation:
                return localized(
                    "history.filters.source.option.dictation",
                    default: "Dictation",
                    comment: "Filter option label for dictation transcript source"
                )
            case .imported:
                return localized(
                    "history.filters.source.option.imported",
                    default: "Imported",
                    comment: "Filter option label for imported-file transcript source"
                )
            }
        }
    }

    struct SpeakerSuggestion: Identifiable, Equatable {
        let speakerLabel: String
        let profileID: UUID
        let profileDisplayName: String
        let similarityScore: Float

        var id: String {
            "\(speakerLabel)|\(profileID.uuidString)"
        }
    }

    @Published var searchQuery = ""
    @Published var isFiltersExpanded = false
    @Published var filterDateFrom: Date?
    @Published var filterDateTo: Date?
    @Published var sourceTypeFilter: SourceTypeFilterOption = .all
    @Published var selectedModelFilterID = ""
    @Published var hasSpeakersFilterEnabled = false
    @Published private(set) var records: [TranscriptRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMoreResults = true
    @Published private(set) var availableModelFilterIDs: [String] = []
    @Published var selectedRecordIDs: Set<Int64> = []
    @Published var errorMessage: String?
    @Published private(set) var importJobs: [FileImportJob] = []
    @Published private(set) var actionHistoryByTranscriptID: [Int64: [TranscriptActionRecord]] = [:]

    private let transcriptStore: TranscriptStore
    private let fileTranscriptionService: FileTranscriptionService
    private let audioCaptureService: AudioCaptureService
    private let speakerProfileStore: SpeakerProfileStore
    private let transcriptArchiver: TranscriptArchiver
    private let webhookService: WebhookService
    private let backupService: iCloudBackupService
    private let pageSize = 50
    private var offset = 0
    private var isProcessingImportQueue = false
    private var sessionTranscriptIDsWithEmbeddings: Set<Int64> = []

    init(
        transcriptStore: TranscriptStore,
        fileTranscriptionService: FileTranscriptionService = FileTranscriptionService(),
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        speakerProfileStore: SpeakerProfileStore? = nil,
        transcriptArchiver: TranscriptArchiver = TranscriptArchiver(),
        webhookService: WebhookService = WebhookService(),
        backupService: iCloudBackupService = iCloudBackupService()
    ) {
        self.transcriptStore = transcriptStore
        self.fileTranscriptionService = fileTranscriptionService
        self.audioCaptureService = audioCaptureService
        self.transcriptArchiver = transcriptArchiver
        self.webhookService = webhookService
        self.backupService = backupService
        self.speakerProfileStore = speakerProfileStore
            ?? SpeakerProfileStore(databaseQueue: transcriptStore.databaseQueue)
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

    var activeFilterCount: Int {
        var count = 0
        if filterDateFrom != nil { count += 1 }
        if filterDateTo != nil { count += 1 }
        if sourceTypeFilter != .all { count += 1 }
        if selectedModelFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { count += 1 }
        if hasSpeakersFilterEnabled { count += 1 }
        return count
    }

    func record(withID id: Int64) -> TranscriptRecord? {
        records.first(where: { $0.id == id })
    }

    func loadInitial() {
        offset = 0
        fetch(reset: true)
    }

    func reloadForSearchQuery() {
        offset = 0
        fetch(reset: true)
    }

    func loadMoreIfNeeded(currentIndex: Int) {
        guard isLoading == false else { return }
        guard hasMoreResults else { return }
        guard currentIndex >= max(records.count - 5, 0) else { return }

        fetch(reset: false)
    }

    func copySelectedToPasteboard() {
        guard let selectedRecord else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedRecord.text, forType: .string)
    }

    func exportSelection() {
        exportRecords(selectedRecords)
    }

    func exportRecord(id: Int64) {
        guard let record = record(withID: id) else { return }
        exportRecords([record])
    }

    func shareSelection() {
        shareRecords(selectedRecords)
    }

    func shareRecord(id: Int64) {
        guard let record = record(withID: id) else { return }
        shareRecords([record])
    }

    func importArchive(from url: URL) throws -> TranscriptArchiveImportResult {
        let archive = try transcriptArchiver.read(from: url)
        let result = try transcriptStore.importArchive(archive)
        reloadForSearchQuery()
        errorMessage = nil
        return result
    }

    func deleteSelected() {
        guard let summary = makeDeleteSelectionSummary() else { return }
        deleteRecords(ids: summary.transcriptIDs)
    }

    func makeDeleteSelectionSummary() -> DeleteSelectionSummary? {
        let ids = selectedRecords.compactMap(\.id)
        guard ids.isEmpty == false else { return nil }

        do {
            let actionCount = try transcriptStore.countActions(forTranscriptIDs: ids)
            return DeleteSelectionSummary(
                transcriptIDs: ids,
                transcriptCount: ids.count,
                associatedActionCount: actionCount
            )
        } catch {
            errorMessage = localized(
                "error.history.deleteConfirmationFailed",
                default: "Failed to prepare delete confirmation.",
                comment: "Error shown when preparing delete confirmation fails"
            )
            return nil
        }
    }

    func deleteRecords(ids: [Int64]) {
        guard ids.isEmpty == false else { return }

        do {
            let audioPathsToDelete = ids.compactMap { id in
                record(withID: id)?.audioFilePath
                    ?? (try? transcriptStore.fetchOne(id: id))?.audioFilePath
            }

            if ids.count == 1, let id = ids.first {
                try transcriptStore.delete(id: id)
            } else {
                try transcriptStore.delete(ids: ids)
            }

            for audioPath in audioPathsToDelete {
                try? audioCaptureService.deleteAudioFile(at: audioPath)
            }

            for id in ids {
                actionHistoryByTranscriptID[id] = nil
            }
            selectedRecordIDs.subtract(ids)
            reloadForSearchQuery()
            errorMessage = nil
        } catch {
            errorMessage = ids.count > 1
                ? localized(
                    "error.history.deleteSelectionFailed",
                    default: "Failed to delete selected transcripts.",
                    comment: "Error shown when deleting multiple transcripts fails"
                )
                : localized(
                    "error.history.deleteSingleFailed",
                    default: "Failed to delete transcript.",
                    comment: "Error shown when deleting a single transcript fails"
                )
        }
    }

    func updateSegments(recordID: Int64, segments: [TranscriptSegment]) throws {
        try transcriptStore.updateSegments(id: recordID, segments: segments)
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].segments = segments
            records[index].text = segments.map(\.text).joined(separator: " ")
        }
        errorMessage = nil
    }

    func updateSpeakerMap(recordID: Int64, speakerMap: [String: String]?) {
        let normalizedMap = speakerMap?
            .reduce(into: [String: String]()) { partialResult, entry in
                let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard key.isEmpty == false, value.isEmpty == false else { return }
                partialResult[key] = value
            }
        do {
            try transcriptStore.updateSpeakerMap(
                id: recordID,
                speakerMap: normalizedMap?.isEmpty == false ? normalizedMap : nil
            )
            if let index = records.firstIndex(where: { $0.id == recordID }) {
                records[index].speakerMap = normalizedMap?.isEmpty == false ? normalizedMap : nil
            }
            errorMessage = nil
        } catch {
            errorMessage = localized(
                "error.history.saveSpeakerNamesFailed",
                default: "Failed to save speaker names.",
                comment: "Error shown when persisting custom speaker names fails"
            )
        }
    }

    func updateNotes(recordID: Int64, notes: String?) {
        let normalizedNotes: String?
        if let notes {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedNotes = trimmed.isEmpty ? nil : notes
        } else {
            normalizedNotes = nil
        }

        do {
            try transcriptStore.updateNotes(id: recordID, notes: normalizedNotes)
            if let index = records.firstIndex(where: { $0.id == recordID }) {
                records[index].notes = normalizedNotes
            }
            errorMessage = nil
        } catch {
            errorMessage = localized(
                "error.history.saveNotesFailed",
                default: "Failed to save notes.",
                comment: "Error shown when persisting transcript notes fails"
            )
        }
    }

    func hasStoredEmbedding(recordID: Int64, speakerLabel: String) -> Bool {
        guard let record = record(withID: recordID), let transcriptID = record.id else { return false }
        let normalizedLabel = speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedLabel.isEmpty == false else { return false }

        do {
            let embeddings = try transcriptStore.fetchEmbeddings(transcriptID: transcriptID)
            guard let embedding = embeddings[normalizedLabel] else { return false }
            return embedding.isEmpty == false
        } catch {
            return false
        }
    }

    func loadSpeakerSuggestions(
        recordID: Int64,
        threshold: Float,
        dismissedSpeakerLabels: Set<String> = []
    ) -> [SpeakerSuggestion] {
        guard let record = record(withID: recordID), let transcriptID = record.id else { return [] }
        guard sessionTranscriptIDsWithEmbeddings.contains(transcriptID) else { return [] }
        guard let segments = record.segments, segments.isEmpty == false else { return [] }

        do {
            let embeddings = try transcriptStore.fetchEmbeddings(transcriptID: transcriptID)
            guard embeddings.isEmpty == false else { return [] }
            let normalizedThreshold = min(max(threshold, 0.70), 0.99)

            var suggestions: [SpeakerSuggestion] = []
            for speakerLabel in Self.uniqueSpeakerLabels(in: segments) {
                if dismissedSpeakerLabels.contains(speakerLabel) {
                    continue
                }
                if let mapped = record.speakerMap?[speakerLabel],
                   mapped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    continue
                }
                guard let embedding = embeddings[speakerLabel], embedding.isEmpty == false else {
                    continue
                }
                guard let matchedProfile = try speakerProfileStore.findMatch(
                    for: embedding,
                    threshold: normalizedThreshold
                ) else {
                    continue
                }
                suggestions.append(
                    SpeakerSuggestion(
                        speakerLabel: speakerLabel,
                        profileID: matchedProfile.id,
                        profileDisplayName: matchedProfile.displayName,
                        similarityScore: cosineSimilarity(embedding, matchedProfile.averageEmbedding)
                    )
                )
            }

            return suggestions.sorted {
                if $0.similarityScore == $1.similarityScore {
                    return $0.speakerLabel < $1.speakerLabel
                }
                return $0.similarityScore > $1.similarityScore
            }
        } catch {
            return []
        }
    }

    func acceptSpeakerSuggestion(recordID: Int64, suggestion: SpeakerSuggestion) {
        guard let record = record(withID: recordID), let transcriptID = record.id else { return }

        var updatedMap = record.speakerMap ?? [:]
        updatedMap[suggestion.speakerLabel] = suggestion.profileDisplayName
        updateSpeakerMap(recordID: recordID, speakerMap: updatedMap)

        do {
            let embeddings = try transcriptStore.fetchEmbeddings(transcriptID: transcriptID)
            if let embedding = embeddings[suggestion.speakerLabel], embedding.isEmpty == false {
                try speakerProfileStore.updateAverageEmbedding(
                    id: suggestion.profileID,
                    newEmbedding: embedding
                )
            }
        } catch {
            errorMessage = localized(
                "error.history.speakerSuggestionAcceptFailed",
                default: "Failed to apply speaker suggestion.",
                comment: "Error shown when accepting a speaker-name suggestion fails"
            )
        }
    }

    func createSpeakerProfileFromSpeakerName(
        recordID: Int64,
        speakerLabel: String,
        displayName: String
    ) throws {
        guard let record = record(withID: recordID), let transcriptID = record.id else { return }
        let normalizedSpeakerLabel = speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSpeakerLabel.isEmpty == false else { return }
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else { return }

        let embeddings = try transcriptStore.fetchEmbeddings(transcriptID: transcriptID)
        guard let embedding = embeddings[normalizedSpeakerLabel], embedding.isEmpty == false else { return }

        if let existing = try speakerProfileStore
            .fetchAll()
            .first(where: { $0.displayName.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            try speakerProfileStore.updateAverageEmbedding(id: existing.id, newEmbedding: embedding)
            return
        }

        let now = Date()
        try speakerProfileStore.save(
            SpeakerProfile(
                displayName: normalizedName,
                createdAt: now,
                lastSeenAt: now,
                averageEmbedding: embedding,
                transcriptCount: 1
            )
        )
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

    func clearSelection() {
        selectedRecordIDs.removeAll()
    }

    func selectAllVisible() {
        selectedRecordIDs = Set(records.compactMap(\.id))
    }

    func clearFilters() {
        filterDateFrom = nil
        filterDateTo = nil
        sourceTypeFilter = .all
        selectedModelFilterID = ""
        hasSpeakersFilterEnabled = false
        reloadForSearchQuery()
    }

    func retainSelection(validIDs: Set<Int64>) {
        selectedRecordIDs = selectedRecordIDs.intersection(validIDs)
    }

    func loadActions(for transcriptID: Int64) {
        do {
            let fetched = try transcriptStore.fetchActions(forTranscriptID: transcriptID)
            actionHistoryByTranscriptID[transcriptID] = fetched.sorted { lhs, rhs in
                let lhsAuto = lhs.actionType == "auto_summarise"
                let rhsAuto = rhs.actionType == "auto_summarise"
                if lhsAuto != rhsAuto {
                    return lhsAuto
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }
        } catch {
            errorMessage = localized(
                "error.history.loadPreviousActionsFailed",
                default: "Failed to load previous AI actions.",
                comment: "Error shown when loading previous transcript AI actions fails"
            )
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
            errorMessage = localized(
                "error.history.saveActionResultFailed",
                default: "Failed to save AI action result.",
                comment: "Error shown when saving transcript AI action result fails"
            )
        }
    }

    func deleteAction(id: Int64, transcriptID: Int64) {
        do {
            try transcriptStore.deleteAction(id: id)
            loadActions(for: transcriptID)
        } catch {
            errorMessage = localized(
                "error.history.deleteActionResultFailed",
                default: "Failed to delete AI action result.",
                comment: "Error shown when deleting transcript AI action result fails"
            )
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
            errorMessage = localized(
                "error.model.missing",
                default: "No model installed. Open Settings > Models to download one.",
                comment: "Error shown when importing files without an installed model"
            )
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
                        status: .failed(
                            localized(
                                "error.import.unsupportedFileType",
                                default: "Unsupported file type. Use WAV, MP3, M4A, FLAC, or OGG.",
                                comment: "Error shown when importing unsupported audio file type"
                            )
                        )
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

                let savedRecord = try transcriptStore.save(
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
                if let transcriptID = savedRecord.id {
                    do {
                        try processSpeakerEmbeddings(
                            result.speakerEmbeddings,
                            transcriptID: transcriptID
                        )
                    } catch {
                        print("[Waffle] Failed to process speaker embeddings: \(error)")
                    }
                }

                if
                    UserDefaults.standard.bool(forKey: "retainAudioRecordings"),
                    job.fileURL.pathExtension.lowercased() == "wav",
                    let transcriptID = savedRecord.id
                {
                    do {
                        let archivedURL = try audioCaptureService.archiveAudioCopy(
                            from: job.fileURL,
                            transcriptID: transcriptID
                        )
                        try transcriptStore.updateAudioFilePath(id: transcriptID, path: archivedURL.path)
                    } catch {
                        print("[Waffle] Failed to retain imported audio copy: \(error)")
                    }
                }

                triggerWebhookDeliveryIfNeeded(for: savedRecord)
                triggerICloudBackupIfNeeded(for: savedRecord)

                importJobs.removeAll { $0.id == job.id }
                reloadForSearchQuery()
                errorMessage = nil
            } catch {
                if let index = importJobs.firstIndex(where: { $0.id == job.id }) {
                    importJobs[index].status = .failed(
                        localized(
                            "error.import.transcriptionFailed",
                            default: "Transcription failed. Please try again.",
                            comment: "Error shown when file import transcription fails"
                        )
                    )
                }
            }

            isProcessingImportQueue = false
            processImportQueueIfNeeded()
        }
    }

    private func processSpeakerEmbeddings(
        _ rawEmbeddings: [String: [Float]]?,
        transcriptID: Int64
    ) throws {
        guard let rawEmbeddings else { return }

        let normalized = rawEmbeddings.reduce(into: [String: [Float]]()) { partialResult, entry in
            let label = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.isEmpty == false else { return }
            guard entry.value.isEmpty == false else { return }
            partialResult[label] = entry.value
        }
        guard normalized.isEmpty == false else { return }

        try transcriptStore.saveEmbeddings(normalized, transcriptID: transcriptID)
        sessionTranscriptIDsWithEmbeddings.insert(transcriptID)

        let threshold = Self.loadSpeakerMatchThreshold()
        for embedding in normalized.values {
            _ = try speakerProfileStore.matchOrCreateProfile(for: embedding, threshold: threshold)
        }
    }

    private func triggerWebhookDeliveryIfNeeded(for transcript: TranscriptRecord) {
        let configuration = WebhookConfiguration.load()
        guard configuration.isDeliveryEnabled else { return }

        Task.detached(priority: .background) { [webhookService] in
            await webhookService.deliver(transcript: transcript, config: configuration)
        }
    }

    private func triggerICloudBackupIfNeeded(for transcript: TranscriptRecord) {
        guard Self.boolValue(for: "iCloudBackupEnabled", defaultValue: false) else { return }
        guard let transcriptID = transcript.id else { return }

        let transcriptStore = transcriptStore
        let backupService = self.backupService

        Task.detached(priority: .utility) {
            let actions = (try? transcriptStore.fetchActions(forTranscriptID: transcriptID)) ?? []
            try? backupService.backup(transcript: transcript, actions: actions)
        }
    }

    private func fetch(reset: Bool) {
        isLoading = true

        do {
            let currentOffset = reset ? 0 : offset
            let fetched = try transcriptStore.fetchFiltered(currentFilter, limit: pageSize, offset: currentOffset)

            if reset {
                records = fetched
                offset = fetched.count
            } else {
                records.append(contentsOf: fetched)
                offset += fetched.count
            }

            hasMoreResults = fetched.count == pageSize
            availableModelFilterIDs = try transcriptStore.fetchDistinctModelIDs()

            errorMessage = nil
        } catch {
            if reset {
                records = []
            }
            hasMoreResults = false
            errorMessage = localized(
                "error.history.loadFailed",
                default: "Failed to load transcript history.",
                comment: "Error shown when transcript history fetch fails"
            )
        }

        isLoading = false
    }

    private var currentFilter: TranscriptFilter {
        TranscriptFilter(
            searchText: searchQuery,
            dateFrom: normalizedDateFrom,
            dateTo: normalizedDateTo,
            sourceType: sourceTypeFilter.sourceTypeValue,
            modelID: selectedModelFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : selectedModelFilterID,
            hasSpeakers: hasSpeakersFilterEnabled ? true : nil
        )
    }

    private static func boolValue(for key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private var normalizedDateFrom: Date? {
        guard let filterDateFrom else { return nil }
        return Calendar.current.startOfDay(for: filterDateFrom)
    }

    private var normalizedDateTo: Date? {
        guard let filterDateTo else { return nil }
        let dayStart = Calendar.current.startOfDay(for: filterDateTo)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart)
    }

    private static func loadSpeakerMatchThreshold() -> Float {
        let defaults = UserDefaults.standard
        let key = "speakerMatchThreshold"
        if defaults.object(forKey: key) == nil {
            return 0.85
        }
        let stored = defaults.double(forKey: key)
        return Float(min(max(stored, 0.70), 0.99))
    }

    private static func uniqueSpeakerLabels(in segments: [TranscriptSegment]) -> [String] {
        Array(
            Set(
                segments.compactMap { segment in
                    guard let speaker = segment.speaker else { return nil }
                    let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            )
        )
        .sorted()
    }

    private func exportRecords(_ records: [TranscriptRecord]) {
        guard records.isEmpty == false else { return }

        if records.count > 1 {
            guard
                let selection = presentExportPanel(
                    allowedFormats: TranscriptExportFormat.allCases,
                    defaultFormat: .json,
                    defaultFilename: defaultBatchExportFilename()
                )
            else {
                return
            }

            do {
                let data = try TranscriptExporter.export(records: records, format: selection.format)
                try data.write(to: selection.url, options: .atomic)
                errorMessage = nil
            } catch {
                errorMessage = localized(
                    "error.history.exportSelectionFailed",
                    default: "Failed to export selected transcripts.",
                    comment: "Error shown when batch transcript export fails"
                )
            }
            return
        }

        guard let record = records.first else { return }
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
                outputData = Data(
                    TranscriptExporter.exportAsPlainText(record, speakerMap: record.speakerMap).utf8
                )
            case .markdown:
                outputData = Data(
                    TranscriptExporter.exportAsMarkdown(record, speakerMap: record.speakerMap).utf8
                )
            case .json:
                outputData = try TranscriptExporter.exportAsJSON([record], speakerMap: record.speakerMap)
            case .srt:
                outputData = Data(
                    TranscriptExporter.exportAsSRT(
                        record,
                        segments: record.segments,
                        speakerMap: record.speakerMap
                    ).utf8
                )
            case .vtt:
                outputData = Data(
                    TranscriptExporter.exportAsVTT(
                        record,
                        segments: record.segments,
                        speakerMap: record.speakerMap
                    ).utf8
                )
            }
            try outputData.write(to: selection.url, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = localized(
                "error.history.exportSingleFailed",
                default: "Failed to export transcript.",
                comment: "Error shown when single transcript export fails"
            )
        }
    }

    private func shareRecords(_ records: [TranscriptRecord]) {
        guard records.isEmpty == false else { return }
        guard let destinationURL = presentArchiveSavePanel(defaultFilename: defaultArchiveFilename(for: records))
        else {
            return
        }

        do {
            let data = try transcriptArchiver.export(transcripts: records, store: transcriptStore)
            let archive = try transcriptArchiver.import(from: data)
            try transcriptArchiver.write(archive, to: destinationURL)
            errorMessage = nil
        } catch {
            errorMessage = localized(
                "error.history.shareArchiveFailed",
                default: "Failed to share transcript archive.",
                comment: "Error shown when sharing transcript archives fails"
            )
        }
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

    private func defaultArchiveFilename(for records: [TranscriptRecord]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        if records.count == 1, let record = records.first {
            let date = formatter.string(from: record.createdAt)
            let modelID = sanitizedFilenameComponent(record.modelID)
            return "\(date)_\(modelID)-transcript.waffle"
        }

        let today = formatter.string(from: Date())
        return "waffle-export-\(today)-\(records.count)transcripts.waffle"
    }

    private func presentArchiveSavePanel(defaultFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = Self.supportedArchiveContentTypes
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, var url = panel.url else {
            return nil
        }

        if url.pathExtension.lowercased() != "waffle" {
            url = url.deletingPathExtension().appendingPathExtension("waffle")
        }

        return url
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "model" }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mappedScalars = trimmed.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = mappedScalars.joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "model" : collapsed
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

        let label = NSTextField(
            labelWithString: localized(
                "history.export.format.label",
                default: "Format:",
                comment: "Label shown in export save panel for selecting export format"
            )
        )
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

    static var supportedArchiveContentTypes: [UTType] {
        var types: [UTType] = []
        if let waffleType = UTType(filenameExtension: "waffle") {
            types.append(waffleType)
        }
        if types.contains(.json) == false {
            types.append(.json)
        }
        return types
    }

    static func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["wav", "mp3", "m4a", "flac", "ogg"].contains(ext)
    }

    static func isSupportedArchiveFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "waffle" || ext == "json"
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
            return ("custom_prompt", prompt)
        }
    }
}
