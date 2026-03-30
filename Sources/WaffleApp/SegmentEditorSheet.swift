import Foundation
import SwiftUI
import WaffleCore

struct EditableSegment: Identifiable, Equatable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var text: String
    var speaker: String?

    init(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        text: String,
        speaker: String?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }

    init(segment: TranscriptSegment) {
        self.init(
            start: segment.start,
            end: segment.end,
            text: segment.text,
            speaker: segment.speaker
        )
    }

    var transcriptSegment: TranscriptSegment {
        TranscriptSegment(
            start: start,
            end: end,
            text: text,
            speaker: Self.normalizedSpeaker(speaker)
        )
    }

    static func normalizedSpeaker(_ speaker: String?) -> String? {
        guard let speaker else { return nil }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SegmentEditorSheet: View {
    let transcript: TranscriptRecord
    let onSave: (Int64, [TranscriptSegment]) throws -> Void

    @State private var editableSegments: [EditableSegment]
    @State private var editingSpeakerSegmentID: UUID?
    @State private var isSaving = false
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    init(
        transcript: TranscriptRecord,
        onSave: @escaping (Int64, [TranscriptSegment]) throws -> Void
    ) {
        self.transcript = transcript
        self.onSave = onSave
        _editableSegments = State(initialValue: (transcript.segments ?? []).map(EditableSegment.init(segment:)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                localized(
                    "history.segmentEditor.description",
                    default: "Edit segment text and speaker labels for this transcript.",
                    comment: "Description text shown at top of segment editor sheet"
                )
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(
                localized(
                    "history.segmentEditor.speaker.note",
                    default: "Speaker changes here apply only to this transcript and do not rename global speaker profiles.",
                    comment: "Clarifies segment speaker edits are local to the transcript"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach($editableSegments) { $segment in
                        segmentRow(segment: $segment)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button(
                    localized(
                        "action.cancel",
                        default: "Cancel",
                        comment: "Generic action title for canceling a dialog"
                    )
                ) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(
                    localized(
                        "action.save",
                        default: "Save",
                        comment: "Generic action title for saving edits"
                    )
                ) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || editableSegments.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 520)
        .navigationTitle(
            localized(
                "history.segmentEditor.title",
                default: "Edit Segments",
                comment: "Title for segment editor sheet"
            )
        )
    }

    @ViewBuilder
    private func segmentRow(segment: Binding<EditableSegment>) -> some View {
        let segmentID = segment.wrappedValue.id

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(Self.timeRangeText(start: segment.wrappedValue.start, end: segment.wrappedValue.end))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if editingSpeakerSegmentID == segmentID {
                    TextField(
                        localized(
                            "history.segmentEditor.speaker.placeholder",
                            default: "Speaker label",
                            comment: "Placeholder for segment speaker label text field"
                        ),
                        text: Binding(
                            get: { segment.wrappedValue.speaker ?? "" },
                            set: { segment.wrappedValue.speaker = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit {
                        segment.wrappedValue.speaker = EditableSegment.normalizedSpeaker(segment.wrappedValue.speaker)
                        editingSpeakerSegmentID = nil
                    }
                } else if let speaker = EditableSegment.normalizedSpeaker(segment.wrappedValue.speaker) {
                    Button(speaker) {
                        editingSpeakerSegmentID = segmentID
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(
                        localized(
                            "history.segmentEditor.speaker.add",
                            default: "Add Speaker",
                            comment: "Action title for adding a speaker label to a segment"
                        )
                    ) {
                        segment.wrappedValue.speaker = ""
                        editingSpeakerSegmentID = segmentID
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }

            TextEditor(text: segment.text)
                .font(.body)
                .frame(minHeight: 68, maxHeight: 120)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
    }

    private func save() {
        guard isSaving == false else { return }
        guard let transcriptID = transcript.id else {
            saveError = localized(
                "error.history.segmentEditor.missingTranscriptID",
                default: "Unable to save edits for this transcript.",
                comment: "Error shown when segment editor cannot resolve transcript ID"
            )
            return
        }

        isSaving = true
        saveError = nil

        do {
            try onSave(transcriptID, editableSegments.map(\.transcriptSegment))
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }

    nonisolated static func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(seconds, 0))
        if totalSeconds >= 60 {
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }
        return "\(totalSeconds)s"
    }

    nonisolated static func timeRangeText(start: Double, end: Double) -> String {
        "\(formatTime(start)) - \(formatTime(end))"
    }
}
