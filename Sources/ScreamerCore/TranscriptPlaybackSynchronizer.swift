import Foundation

public enum TranscriptPlaybackSynchronizer {
    public static func currentSegmentIndex(
        for time: Double,
        in segments: [TranscriptSegment]
    ) -> Int? {
        segments.indices.first { index in
            let segment = segments[index]
            return segment.start <= time && time < segment.end
        }
    }
}
