import Foundation
import ScreamerCore
import SwiftUI

struct SpeakerProfilesSection: View {
    @AppStorage("speakerMatchThreshold") private var speakerMatchThreshold = 0.85

    @State private var profiles: [SpeakerProfile] = []
    @State private var pendingDeleteProfile: SpeakerProfile?
    @State private var mergeContext: MergeContext?
    @State private var mergeTargetID: UUID?
    @State private var mergeKeepName = ""
    @State private var errorMessage: String?

    private let speakerProfileStore: SpeakerProfileStore?

    init(transcriptStore: TranscriptStore?) {
        if let transcriptStore {
            self.speakerProfileStore = SpeakerProfileStore(databaseQueue: transcriptStore.databaseQueue)
        } else {
            self.speakerProfileStore = nil
        }
    }

    var body: some View {
        Section(
            localized(
                "settings.ai.speakerProfiles.section",
                default: "Speaker Profiles",
                comment: "Section title for speaker profile management settings"
            )
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(
                        localized(
                            "settings.ai.speakerProfiles.matchSensitivity",
                            default: "Match sensitivity",
                            comment: "Label for speaker profile match sensitivity slider"
                        )
                    )
                    Slider(
                        value: Binding(
                            get: { min(max(speakerMatchThreshold, 0.70), 0.99) },
                            set: { speakerMatchThreshold = min(max($0, 0.70), 0.99) }
                        ),
                        in: 0.70 ... 0.99,
                        step: 0.01
                    )
                    Text(String(format: "%.2f", speakerMatchThreshold))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                Text(
                    localized(
                        "settings.ai.speakerProfiles.matchSensitivity.hint",
                        default: "Higher = stricter matching",
                        comment: "Hint text below speaker match sensitivity slider"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let speakerProfileStore {
                if profiles.isEmpty {
                    Text(
                        localized(
                            "settings.ai.speakerProfiles.empty",
                            default: "No speaker profiles yet. Profiles are created when diarized transcripts include embeddings.",
                            comment: "Empty-state message for speaker profiles settings section"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        SpeakerProfileRow(
                            profile: profile,
                            onRename: { updatedName in
                                do {
                                    try speakerProfileStore.rename(id: profile.id, displayName: updatedName)
                                    loadProfiles()
                                } catch {
                                    errorMessage = localized(
                                        "error.settings.speakerProfiles.renameFailed",
                                        default: "Failed to rename speaker profile.",
                                        comment: "Error shown when renaming a speaker profile fails"
                                    )
                                }
                            },
                            onMerge: {
                                mergeContext = MergeContext(primary: profile)
                                mergeTargetID = profiles.first(where: { $0.id != profile.id })?.id
                                mergeKeepName = profile.displayName
                                errorMessage = nil
                            },
                            onDelete: {
                                pendingDeleteProfile = profile
                            }
                        )
                    }
                }
            } else {
                Text(
                    localized(
                        "settings.ai.speakerProfiles.unavailable",
                        default: "Speaker profiles are unavailable because the transcript database could not be opened.",
                        comment: "Message shown when speaker profile management cannot be loaded"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task {
            loadProfiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            loadProfiles()
        }
        .alert(
            pendingDeleteProfile?.displayName
                ?? localized(
                    "settings.ai.speakerProfiles.delete.fallback",
                    default: "Delete profile?",
                    comment: "Fallback title for delete-speaker-profile confirmation alert"
                ),
            isPresented: Binding(
                get: { pendingDeleteProfile != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeleteProfile = nil
                    }
                }
            )
        ) {
            Button(
                localized(
                    "action.delete",
                    default: "Delete",
                    comment: "Action title for deleting selected transcripts"
                ),
                role: .destructive
            ) {
                guard let pendingDeleteProfile, let speakerProfileStore else { return }
                do {
                    try speakerProfileStore.delete(id: pendingDeleteProfile.id)
                    loadProfiles()
                } catch {
                    errorMessage = localized(
                        "error.settings.speakerProfiles.deleteFailed",
                        default: "Failed to delete speaker profile.",
                        comment: "Error shown when deleting a speaker profile fails"
                    )
                }
                self.pendingDeleteProfile = nil
            }
            Button(
                localized(
                    "action.cancel",
                    default: "Cancel",
                    comment: "Generic action title for canceling a dialog"
                ),
                role: .cancel
            ) {
                pendingDeleteProfile = nil
            }
        } message: {
            if let profile = pendingDeleteProfile {
                Text(
                    localizedFormat(
                        "settings.ai.speakerProfiles.delete.message",
                        default: "Delete \"%@\"? Future recordings will not be auto-matched to this profile. Existing speaker names in transcripts are unchanged.",
                        comment: "Confirmation message shown before deleting a speaker profile",
                        profile.displayName
                    )
                )
            }
        }
        .sheet(item: $mergeContext) { context in
            mergeSheet(for: context)
        }
    }

    private func mergeSheet(for context: MergeContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                localized(
                    "settings.ai.speakerProfiles.merge.title",
                    default: "Merge Speaker Profiles",
                    comment: "Sheet title for merging two speaker profiles"
                )
            )
            .font(.headline)

            Picker(
                localized(
                    "settings.ai.speakerProfiles.merge.target",
                    default: "Merge with",
                    comment: "Picker label for selecting secondary profile to merge"
                ),
                selection: Binding(
                    get: {
                        mergeTargetID
                            ?? profiles.first(where: { $0.id != context.primary.id })?.id
                            ?? context.primary.id
                    },
                    set: { mergeTargetID = $0 }
                )
            ) {
                ForEach(profiles.filter { $0.id != context.primary.id }) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }

            if let targetProfile = profiles.first(where: { $0.id == mergeTargetID }) {
                Picker(
                    localized(
                        "settings.ai.speakerProfiles.merge.keepName",
                        default: "Keep name",
                        comment: "Picker label for choosing which profile name to keep after merge"
                    ),
                    selection: $mergeKeepName
                ) {
                    Text(context.primary.displayName).tag(context.primary.displayName)
                    Text(targetProfile.displayName).tag(targetProfile.displayName)
                }
                .pickerStyle(.segmented)
            }

            Text(
                localized(
                    "settings.ai.speakerProfiles.merge.warning",
                    default: "Merging is irreversible.",
                    comment: "Warning text shown in merge speaker profiles sheet"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(
                    localized(
                        "action.cancel",
                        default: "Cancel",
                        comment: "Generic action title for canceling a dialog"
                    )
                ) {
                    mergeContext = nil
                }
                .buttonStyle(.bordered)

                Button(
                    localized(
                        "action.merge",
                        default: "Merge",
                        comment: "Action title for merging two items"
                    )
                ) {
                    applyMerge(for: context)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 220)
    }

    private func applyMerge(for context: MergeContext) {
        guard
            let speakerProfileStore,
            let targetID = mergeTargetID,
            targetID != context.primary.id
        else {
            return
        }

        do {
            try speakerProfileStore.mergeProfiles(
                primaryID: context.primary.id,
                secondaryID: targetID,
                keepDisplayName: mergeKeepName
            )
            loadProfiles()
            mergeContext = nil
        } catch {
            errorMessage = localized(
                "error.settings.speakerProfiles.mergeFailed",
                default: "Failed to merge speaker profiles.",
                comment: "Error shown when merging speaker profiles fails"
            )
        }
    }

    private func loadProfiles() {
        guard let speakerProfileStore else {
            profiles = []
            return
        }
        do {
            profiles = try speakerProfileStore.fetchAll()
            errorMessage = nil
        } catch {
            profiles = []
            errorMessage = localized(
                "error.settings.speakerProfiles.loadFailed",
                default: "Failed to load speaker profiles.",
                comment: "Error shown when loading speaker profiles fails"
            )
        }
    }
}

private struct SpeakerProfileRow: View {
    let profile: SpeakerProfile
    let onRename: (String) -> Void
    let onMerge: () -> Void
    let onDelete: () -> Void

    @State private var nameDraft: String
    @FocusState private var isNameFocused: Bool

    init(
        profile: SpeakerProfile,
        onRename: @escaping (String) -> Void,
        onMerge: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.profile = profile
        self.onRename = onRename
        self.onMerge = onMerge
        self.onDelete = onDelete
        _nameDraft = State(initialValue: profile.displayName)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(String(profile.displayName.prefix(1)).uppercased())
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                TextField(
                    localized(
                        "settings.ai.speakerProfiles.name",
                        default: "Name",
                        comment: "Text field placeholder for speaker profile display name"
                    ),
                    text: $nameDraft
                )
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit {
                    commitRename()
                }
                .onChange(of: isNameFocused) { oldValue, newValue in
                    if oldValue, newValue == false {
                        commitRename()
                    }
                }

                Text(
                    localizedFormat(
                        "settings.ai.speakerProfiles.metadata",
                        default: "%d transcripts • Last seen %@",
                        comment: "Metadata text showing transcript count and last seen relative date for a speaker profile",
                        profile.transcriptCount,
                        Self.relativeFormatter.localizedString(for: profile.lastSeenAt, relativeTo: Date())
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                localized(
                    "settings.ai.speakerProfiles.merge.button",
                    default: "Merge…",
                    comment: "Button title for merging a speaker profile with another profile"
                )
            ) {
                onMerge()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(
                localized(
                    "action.delete",
                    default: "Delete",
                    comment: "Action title for deleting selected transcripts"
                ),
                role: .destructive
            ) {
                onDelete()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onChange(of: profile.displayName) { _, newValue in
            if isNameFocused == false {
                nameDraft = newValue
            }
        }
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != profile.displayName else {
            nameDraft = profile.displayName
            return
        }
        onRename(trimmed)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct MergeContext: Identifiable {
    let primary: SpeakerProfile

    var id: UUID {
        primary.id
    }
}
