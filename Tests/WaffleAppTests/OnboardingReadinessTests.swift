import Testing
@testable import WaffleApp

struct OnboardingReadinessTests {
    @Test func readyWhenMicrophoneGrantedAndModelInstalled() {
        let readiness = OnboardingReadiness(
            microphoneGranted: true,
            hasInstalledModel: true
        )

        #expect(readiness.isReadyToTranscribe)
    }

    @Test func notReadyWhenMicrophoneMissing() {
        let readiness = OnboardingReadiness(
            microphoneGranted: false,
            hasInstalledModel: true
        )

        #expect(readiness.isReadyToTranscribe == false)
    }

    @Test func notReadyWhenModelMissing() {
        let readiness = OnboardingReadiness(
            microphoneGranted: true,
            hasInstalledModel: false
        )

        #expect(readiness.isReadyToTranscribe == false)
    }
}
