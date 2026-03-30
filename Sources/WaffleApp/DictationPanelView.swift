import SwiftUI

struct DictationPanelView: View {
    let state: DictationController.State

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(panelAccessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .recording:
            Text(
                localized(
                    "dictation.panel.state.recording",
                    default: "Recording…",
                    comment: "Dictation panel state label shown while actively recording"
                )
            )
                .font(.headline)
            RecordingWaveformView()
                .frame(height: 26)
            Text(
                localized(
                    "dictation.panel.recording.escapeHint",
                    default: "Press Esc to cancel",
                    comment: "Hint shown in dictation panel while recording"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

        case .transcribing:
            ProgressView()
                .controlSize(.small)
            Text(
                localized(
                    "dictation.panel.state.transcribing",
                    default: "Transcribing…",
                    comment: "Dictation panel state label shown while transcribing audio"
                )
            )
                .font(.headline)

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
                .accessibilityHidden(true)
            Text(
                localized(
                    "dictation.panel.state.done",
                    default: "Done",
                    comment: "Dictation panel state label shown after successful transcription"
                )
            )
                .font(.headline)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
                .accessibilityHidden(true)
            Text(
                localized(
                    "dictation.panel.state.error",
                    default: "Could not complete dictation",
                    comment: "Dictation panel state label shown when dictation fails"
                )
            )
                .font(.headline)

        case .idle:
            EmptyView()
        }
    }

    private var panelAccessibilityLabel: String {
        switch state {
        case .idle:
            return localized(
                "dictation.panel.accessibility.idle",
                default: "Dictation panel idle",
                comment: "Accessibility label for dictation panel when idle"
            )
        case .recording:
            return localized(
                "dictation.panel.accessibility.recording",
                default: "Recording in progress",
                comment: "Accessibility label for dictation panel when recording"
            )
        case .transcribing:
            return localized(
                "dictation.panel.accessibility.transcribing",
                default: "Transcription in progress",
                comment: "Accessibility label for dictation panel when transcribing"
            )
        case .success:
            return localized(
                "dictation.panel.accessibility.success",
                default: "Dictation completed successfully",
                comment: "Accessibility label for dictation panel when dictation succeeds"
            )
        case .error:
            return localized(
                "dictation.panel.accessibility.error",
                default: "Dictation failed",
                comment: "Accessibility label for dictation panel when dictation fails"
            )
        }
    }
}

private struct RecordingWaveformView: View {
    private let barCount = 7

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = t * 4.2 + Double(index) * 0.55
                    let amplitude = 0.35 + 0.65 * abs(sin(phase))
                    let height = 8 + (amplitude * 16)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 4, height: height)
                }
            }
            .frame(height: 26)
        }
    }
}
