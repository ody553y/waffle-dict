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
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .recording:
            Text("Recording…")
                .font(.headline)
            RecordingWaveformView()
                .frame(height: 26)
            Text("Press Esc to cancel")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .transcribing:
            ProgressView()
                .controlSize(.small)
            Text("Transcribing…")
                .font(.headline)

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            Text("Done")
                .font(.headline)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            Text("Could not complete dictation")
                .font(.headline)

        case .idle:
            EmptyView()
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
