import Foundation
import os

public struct PerformanceMetricSummary: Equatable, Sendable {
    public let label: String
    public let sampleCount: Int
    public let totalDurationSeconds: Double
    public let minDurationSeconds: Double
    public let maxDurationSeconds: Double

    public var meanDurationSeconds: Double {
        guard sampleCount > 0 else { return 0 }
        return totalDurationSeconds / Double(sampleCount)
    }
}

public final class PerformanceMetrics: @unchecked Sendable {
    public static let shared = PerformanceMetrics()

    private struct MutableMetric: Sendable {
        var sampleCount: Int = 0
        var totalDurationSeconds: Double = 0
        var minDurationSeconds: Double = .greatestFiniteMagnitude
        var maxDurationSeconds: Double = 0

        mutating func append(_ durationSeconds: Double) {
            sampleCount += 1
            totalDurationSeconds += durationSeconds
            minDurationSeconds = min(minDurationSeconds, durationSeconds)
            maxDurationSeconds = max(maxDurationSeconds, durationSeconds)
        }

        func immutable(label: String) -> PerformanceMetricSummary {
            PerformanceMetricSummary(
                label: label,
                sampleCount: sampleCount,
                totalDurationSeconds: totalDurationSeconds,
                minDurationSeconds: sampleCount > 0 ? minDurationSeconds : 0,
                maxDurationSeconds: sampleCount > 0 ? maxDurationSeconds : 0
            )
        }
    }

    private let lock = NSLock()
    private var metricsByLabel: [String: MutableMetric] = [:]
    private let signpostLog = OSLog(subsystem: "com.waffle.app", category: "Performance")

    public init() {}

    public func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "metric", signpostID: signpostID, "%{public}s", label)
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            let value = try block()
            finishMeasurement(label: label, startedAt: startedAt, signpostID: signpostID)
            return value
        } catch {
            finishMeasurement(label: label, startedAt: startedAt, signpostID: signpostID)
            throw error
        }
    }

    public func measureAsync<T>(
        _ label: String,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "metric", signpostID: signpostID, "%{public}s", label)
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            let value = try await block()
            finishMeasurement(label: label, startedAt: startedAt, signpostID: signpostID)
            return value
        } catch {
            finishMeasurement(label: label, startedAt: startedAt, signpostID: signpostID)
            throw error
        }
    }

    public func record(_ label: String, durationSeconds: Double) {
        let normalizedDuration = max(durationSeconds, 0)

        lock.lock()
        var metric = metricsByLabel[label, default: MutableMetric()]
        metric.append(normalizedDuration)
        metricsByLabel[label] = metric
        lock.unlock()
    }

    public func summary(for label: String) -> PerformanceMetricSummary? {
        lock.lock()
        let summary = metricsByLabel[label]?.immutable(label: label)
        lock.unlock()
        return summary
    }

    public func snapshot() -> [PerformanceMetricSummary] {
        lock.lock()
        let summaries = metricsByLabel.map { key, value in
            value.immutable(label: key)
        }
        lock.unlock()
        return summaries.sorted { $0.label < $1.label }
    }

    public func report() -> String {
        let summaries = snapshot()
        guard summaries.isEmpty == false else {
            return "Performance Metrics\n(no samples recorded)"
        }

        var lines = ["Performance Metrics"]
        for summary in summaries {
            lines.append(
                "\(summary.label): count=\(summary.sampleCount) "
                    + "mean=\(formatMilliseconds(summary.meanDurationSeconds)) "
                    + "min=\(formatMilliseconds(summary.minDurationSeconds)) "
                    + "max=\(formatMilliseconds(summary.maxDurationSeconds)) "
                    + "total=\(String(format: "%.3fs", summary.totalDurationSeconds))"
            )
        }
        return lines.joined(separator: "\n")
    }

    public func reset() {
        lock.lock()
        metricsByLabel.removeAll()
        lock.unlock()
    }
}

private extension PerformanceMetrics {
    func finishMeasurement(label: String, startedAt: UInt64, signpostID: OSSignpostID) {
        let elapsedSeconds = elapsedTimeSeconds(since: startedAt)
        record(label, durationSeconds: elapsedSeconds)
        os_signpost(
            .end,
            log: signpostLog,
            name: "metric",
            signpostID: signpostID,
            "%{public}s %{public}.2fms",
            label,
            elapsedSeconds * 1000
        )
    }

    func elapsedTimeSeconds(since startedAt: UInt64) -> Double {
        let now = DispatchTime.now().uptimeNanoseconds
        if now <= startedAt {
            return 0
        }
        return Double(now - startedAt) / 1_000_000_000
    }

    func formatMilliseconds(_ durationSeconds: Double) -> String {
        String(format: "%.1fms", durationSeconds * 1_000)
    }
}
