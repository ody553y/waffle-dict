import AVFoundation
import Combine
import Foundation

public enum AudioPlayerServiceError: Error, Equatable {
    case fileNotFound
    case failedToLoad
}

@MainActor
protocol AudioPlayerEngine: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    var onPlaybackFinished: (() -> Void)? { get set }

    func play() -> Bool
    func pause()
}

@MainActor
public final class AudioPlayerService: ObservableObject {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public private(set) var isLoaded = false

    private let makeEngine: (URL) throws -> any AudioPlayerEngine
    private let tickPublisher: () -> AnyPublisher<Date, Never>

    private var engine: (any AudioPlayerEngine)?
    private var tickCancellable: AnyCancellable?

    public convenience init() {
        self.init(
            makeEngine: { try AVAudioPlayerEngine(url: $0) },
            tickPublisher: {
                Timer.publish(every: 0.1, on: .main, in: .common)
                    .autoconnect()
                    .eraseToAnyPublisher()
            }
        )
    }

    init(
        makeEngine: @escaping (URL) throws -> any AudioPlayerEngine,
        tickPublisher: @escaping () -> AnyPublisher<Date, Never>
    ) {
        self.makeEngine = makeEngine
        self.tickPublisher = tickPublisher
    }

    public func load(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioPlayerServiceError.fileNotFound
        }

        stopTicking()
        isPlaying = false

        do {
            let loadedEngine = try makeEngine(url)
            loadedEngine.onPlaybackFinished = { [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.stopTicking()
                self.syncFromEngine()
            }

            self.engine = loadedEngine
            self.duration = max(loadedEngine.duration, 0)
            self.currentTime = max(loadedEngine.currentTime, 0)
            self.isLoaded = true
        } catch {
            self.engine = nil
            self.duration = 0
            self.currentTime = 0
            self.isLoaded = false
            throw AudioPlayerServiceError.failedToLoad
        }
    }

    public func play() {
        guard let engine else { return }
        guard engine.play() else { return }
        isPlaying = true
        startTicking()
    }

    public func pause() {
        engine?.pause()
        isPlaying = false
        stopTicking()
        syncFromEngine()
    }

    public func seek(to time: Double) {
        guard let engine else { return }
        let upperBound = duration > 0 ? duration : max(time, 0)
        let clampedTime = max(0, min(time, upperBound))
        engine.currentTime = clampedTime
        currentTime = clampedTime
    }

    public func unload() {
        pause()
        engine = nil
        isLoaded = false
        currentTime = 0
        duration = 0
    }

    private func startTicking() {
        stopTicking()
        tickCancellable = tickPublisher()
            .sink { [weak self] _ in
                self?.syncFromEngine()
            }
    }

    private func stopTicking() {
        tickCancellable?.cancel()
        tickCancellable = nil
    }

    private func syncFromEngine() {
        guard let engine else {
            currentTime = 0
            return
        }
        currentTime = engine.currentTime
        if isPlaying && engine.isPlaying == false {
            isPlaying = false
            stopTicking()
        }
    }
}

@MainActor
private final class AVAudioPlayerEngine: NSObject, AudioPlayerEngine, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onPlaybackFinished: (() -> Void)?

    var duration: TimeInterval { player.duration }

    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }

    var isPlaying: Bool { player.isPlaying }

    init(url: URL) throws {
        self.player = try AVAudioPlayer(contentsOf: url)
        super.init()
        self.player.delegate = self
        guard player.prepareToPlay() else {
            throw AudioPlayerServiceError.failedToLoad
        }
    }

    func play() -> Bool {
        player.play()
    }

    func pause() {
        player.pause()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.onPlaybackFinished?()
        }
    }
}
