import Foundation
import Testing
@testable import ScreamerCore

@Suite(.serialized)
struct PerformanceMetricsTests {
    @Test func measureRecordsTimingData() {
        let metrics = PerformanceMetrics.shared
        metrics.reset()

        let value: Int = metrics.measure("test.measure") {
            usleep(20_000)
            return 42
        }

        #expect(value == 42)

        let summary = metrics.summary(for: "test.measure")
        #expect(summary?.sampleCount == 1)
        #expect((summary?.meanDurationSeconds ?? 0) > 0)
        #expect((summary?.maxDurationSeconds ?? 0) >= (summary?.minDurationSeconds ?? 0))
    }

    @Test func reportIncludesFormattedMetricRows() {
        let metrics = PerformanceMetrics.shared
        metrics.reset()
        metrics.record("alpha.metric", durationSeconds: 0.150)
        metrics.record("alpha.metric", durationSeconds: 0.050)
        metrics.record("beta.metric", durationSeconds: 0.250)

        let report = metrics.report()

        #expect(report.contains("Performance Metrics"))
        #expect(report.contains("alpha.metric"))
        #expect(report.contains("beta.metric"))
        #expect(report.contains("count=2"))
        #expect(report.contains("mean="))
    }
}
