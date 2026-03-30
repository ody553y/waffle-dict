import AVFoundation
import Foundation

// MARK: - Types

public struct AudioDevice: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public struct RecordingConfig: Sendable {
    public var sampleRate: Double
    public var channels: Int
    public var preferredDeviceID: String?

    public init(sampleRate: Double = 16000, channels: Int = 1, preferredDeviceID: String? = nil) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.preferredDeviceID = preferredDeviceID
    }
}

// MARK: - Errors

public enum AudioCaptureError: Error {
    case permissionDenied
    case noInputDevice
    case recordingFailed(String)
}

// MARK: - Service

public final class AudioCaptureService: NSObject, @unchecked Sendable {
    private let fileManager: FileManager
    private let scratchDirectory: URL
    private let audioFilesDirectory: URL
    private var recorder: AVAudioRecorder?
    private var activeSessionURL: URL?

    public init(
        fileManager: FileManager = .default,
        appSupportDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let appSupport = appSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let screamerDirectory = appSupport
            .appendingPathComponent("Screamer", isDirectory: true)
        self.scratchDirectory = screamerDirectory
            .appendingPathComponent("Scratch", isDirectory: true)
        self.audioFilesDirectory = screamerDirectory
            .appendingPathComponent("AudioFiles", isDirectory: true)
        super.init()
        try? fileManager.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: audioFilesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Device listing

    public func listInputDevices() -> [AudioDevice] {
        #if os(macOS)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        return discoverySession.devices.map { device in
            AudioDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultDevice?.uniqueID
            )
        }
        #else
        return []
        #endif
    }

    // MARK: - Permission

    public var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    /// Starts recording to a crash-safe temp file. Returns the file URL.
    public func startRecording(config: RecordingConfig = RecordingConfig()) throws -> URL {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }

        let filename = "\(UUID().uuidString)_\(ISO8601DateFormatter().string(from: Date())).wav"
        let fileURL = scratchDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: config.sampleRate,
            AVNumberOfChannelsKey: config.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder.delegate = self
        guard audioRecorder.record() else {
            throw AudioCaptureError.recordingFailed("AVAudioRecorder.record() returned false")
        }

        self.recorder = audioRecorder
        self.activeSessionURL = fileURL
        return fileURL
    }

    /// Stops the current recording and returns the temp file URL.
    public func stopRecording() -> URL? {
        guard let recorder = recorder else { return nil }
        recorder.stop()
        let url = activeSessionURL
        self.recorder = nil
        self.activeSessionURL = nil
        return url
    }

    /// Cancels and deletes the current recording.
    public func cancelRecording() {
        recorder?.stop()
        recorder?.deleteRecording()
        self.recorder = nil
        self.activeSessionURL = nil
    }

    // MARK: - Crash recovery

    /// Returns any orphaned recordings from a previous crash.
    public func recoverOrphanedRecordings() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: scratchDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        // Anything in Scratch/ that isn't the active session is orphaned.
        return files.filter { $0 != activeSessionURL }
    }

    /// Removes a scratch file after transcript is confirmed saved.
    public func cleanupScratchFile(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    /// Archives a scratch recording to Application Support and removes the scratch file on success.
    @discardableResult
    public func archiveRecording(from scratchURL: URL, transcriptID: Int64) throws -> URL {
        let destinationURL = try makeArchiveDestinationURL(transcriptID: transcriptID)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: scratchURL, to: destinationURL)
        try fileManager.removeItem(at: scratchURL)
        return destinationURL
    }

    /// Archives an existing file without deleting the source (used for imported files).
    @discardableResult
    public func archiveAudioCopy(from sourceURL: URL, transcriptID: Int64) throws -> URL {
        let destinationURL = try makeArchiveDestinationURL(transcriptID: transcriptID)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    public func deleteAudioFile(at path: String) throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else { return }

        let fileURL = URL(fileURLWithPath: trimmedPath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    public func recordingDurationSeconds(for fileURL: URL) -> Double? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
            return nil
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else {
            return nil
        }

        return Double(audioFile.length) / sampleRate
    }
}

private extension AudioCaptureService {
    func makeArchiveDestinationURL(transcriptID: Int64) throws -> URL {
        try fileManager.createDirectory(at: audioFilesDirectory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(transcriptID)_\(timestamp).wav"
        return audioFilesDirectory.appendingPathComponent(filename, isDirectory: false)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioCaptureService: AVAudioRecorderDelegate {
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("[AudioCaptureService] Recording did not finish successfully")
        }
    }

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            print("[AudioCaptureService] Encode error: \(error)")
        }
    }
}
