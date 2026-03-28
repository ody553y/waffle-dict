import AppKit
import ApplicationServices

/// Checks and prompts for macOS permissions required by Screamer.
public struct PermissionsService: Sendable {
    public init() {}

    // MARK: - Accessibility (for CGEventPost paste-into-app)

    /// Returns true if the app has Accessibility permission.
    public var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission via System Settings.
    /// Shows the system dialog with a prompt pointing to Privacy & Security.
    public func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Microphone

    public var microphoneStatus: MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public enum MicrophonePermission: Sendable {
        case granted
        case denied
        case notDetermined
    }
}

import AVFoundation
