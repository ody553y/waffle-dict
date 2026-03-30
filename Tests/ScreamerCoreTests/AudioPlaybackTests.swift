import Combine
import Foundation
import Testing
@testable import ScreamerCore

@Suite(.serialized)
struct AudioPlaybackTests {
    @Test func archiveRecordingCopiesFileAndRemovesScratchFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = AudioCaptureService(appSupportDirectory: root)
        let scratchURL = root.appendingPathComponent("scratch.wav")
        let payload = Data("scratch-audio".utf8)
        try payload.write(to: scratchURL, options: .atomic)

        let archivedURL = try service.archiveRecording(from: scratchURL, transcriptID: 42)

        #expect(FileManager.default.fileExists(atPath: archivedURL.path))
        #expect(FileManager.default.fileExists(atPath: scratchURL.path) == false)
        #expect(try Data(contentsOf: archivedURL) == payload)
    }

    @Test @MainActor func audioPlayerServiceLoadPlayPauseSeekTransitionsState() throws {
        let ticks = PassthroughSubject<Date, Never>()
        let engine = MockAudioPlayerEngine(duration: 135)
        let service = AudioPlayerService(
            makeEngine: { _ in engine },
            tickPublisher: { ticks.eraseToAnyPublisher() }
        )

        let fileURL = try makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try service.load(url: fileURL)
        #expect(service.isLoaded)
        #expect(service.duration == 135)
        #expect(service.currentTime == 0)

        service.play()
        #expect(service.isPlaying)
        #expect(engine.playCallCount == 1)

        engine.currentTime = 12.4
        ticks.send(Date())
        #expect(service.currentTime == 12.4)

        service.seek(to: 32.0)
        #expect(engine.currentTime == 32.0)
        #expect(service.currentTime == 32.0)

        service.pause()
        #expect(service.isPlaying == false)
        #expect(engine.pauseCallCount == 1)
    }

    @Test @MainActor func audioPlayerServiceCurrentTimeStopsUpdatingAfterPause() throws {
        let ticks = PassthroughSubject<Date, Never>()
        let engine = MockAudioPlayerEngine(duration: 60)
        let service = AudioPlayerService(
            makeEngine: { _ in engine },
            tickPublisher: { ticks.eraseToAnyPublisher() }
        )

        let fileURL = try makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try service.load(url: fileURL)
        service.play()

        engine.currentTime = 5.0
        ticks.send(Date())
        #expect(service.currentTime == 5.0)

        service.pause()
        let pausedTime = service.currentTime

        engine.currentTime = 9.0
        ticks.send(Date())
        #expect(service.currentTime == pausedTime)
    }

    @Test @MainActor func audioPlayerServiceMissingFilePathThrowsFileNotFound() throws {
        let service = AudioPlayerService(
            makeEngine: { _ in MockAudioPlayerEngine(duration: 1) },
            tickPublisher: { Empty<Date, Never>().eraseToAnyPublisher() }
        )

        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).wav")

        #expect(throws: AudioPlayerServiceError.fileNotFound) {
            try service.load(url: missingURL)
        }
        #expect(service.isLoaded == false)
        #expect(service.duration == 0)
    }

    @Test func currentSegmentIndexHandlesBoundariesAndGaps() {
        let segments = [
            TranscriptSegment(start: 0.0, end: 1.0, text: "A"),
            TranscriptSegment(start: 1.5, end: 2.0, text: "B"),
            TranscriptSegment(start: 2.0, end: 3.0, text: "C"),
        ]

        #expect(TranscriptPlaybackSynchronizer.currentSegmentIndex(for: -0.1, in: segments) == nil)
        #expect(TranscriptPlaybackSynchronizer.currentSegmentIndex(for: 0.0, in: segments) == 0)
        #expect(TranscriptPlaybackSynchronizer.currentSegmentIndex(for: 0.8, in: segments) == 0)
        #expect(TranscriptPlaybackSynchronizer.currentSegmentIndex(for: 1.0, in: segments) == nil)
        #expect(TranscriptPlaybackSynchronizer.currentSegmentIndex(for: 1.6, in: segments) == 1)
        #expect(TranscriptPlaybackSynchronizer.currentSegmentIndex(for: 2.0, in: segments) == 2)
        #expect(TranscriptPlaybackSynchronizer.currentSegmentIndex(for: 3.0, in: segments) == nil)
    }

    private func makeTempFileURL() throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-player-\(UUID().uuidString).wav")
        try Data("fake-audio".utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }
}

@MainActor
private final class MockAudioPlayerEngine: AudioPlayerEngine {
    let duration: TimeInterval
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var onPlaybackFinished: (() -> Void)?
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    init(duration: TimeInterval) {
        self.duration = duration
    }

    func play() -> Bool {
        playCallCount += 1
        isPlaying = true
        return true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }
}
