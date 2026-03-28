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
    private let scratchDirectory: URL
    private var recorder: AVAudioRecorder?
    private var activeSessionURL: URL?

    public override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.scratchDirectory = appSupport
            .appendingPathComponent("Screamer", isDirectory: true)
            .appendingPathComponent("Scratch", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
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
        guard let files = try? FileManager.default.contentsOfDirectory(
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
        try? FileManager.default.removeItem(at: url)
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
