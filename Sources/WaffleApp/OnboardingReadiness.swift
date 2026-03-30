struct OnboardingReadiness: Sendable {
    let microphoneGranted: Bool
    let hasInstalledModel: Bool

    var isReadyToTranscribe: Bool {
        microphoneGranted && hasInstalledModel
    }
}
