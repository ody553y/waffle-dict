import Foundation
import Testing
@testable import WaffleApp

@Suite
struct StatisticsSettingsViewTests {
    @Test func formatTotalDurationCoversMinutesAndHours() {
        #expect(StatisticsViewMetrics.formatTotalDuration(seconds: 45) == "0m")
        #expect(StatisticsViewMetrics.formatTotalDuration(seconds: 90) == "1m")
        #expect(StatisticsViewMetrics.formatTotalDuration(seconds: 9_240) == "2h 34m")
    }

    @Test func formatAverageDurationCoversSubMinuteAndMinuteValues() {
        #expect(StatisticsViewMetrics.formatAverageDuration(seconds: 45) == "0m 45s")
        #expect(StatisticsViewMetrics.formatAverageDuration(seconds: 125) == "2m 5s")
    }

    @Test func modelUsagePercentageReturnsExpectedRatios() {
        #expect(StatisticsViewMetrics.modelUsagePercentage(count: 3, total: 10) == 0.3)
        #expect(StatisticsViewMetrics.modelUsagePercentage(count: 1, total: 0) == 0)
        #expect(StatisticsViewMetrics.modelUsagePercentage(count: 12, total: 10) == 1)
    }

    @Test func last30DayPointsFillsMissingDaysWithZeroCount() {
        let referenceDate = Date(timeIntervalSince1970: 1_774_828_800) // 2026-03-30 00:00:00 UTC
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let threeDaysAgo = formatter.string(from: referenceDate.addingTimeInterval(-3 * 86_400))
        let oneDayAgo = formatter.string(from: referenceDate.addingTimeInterval(-1 * 86_400))
        let points = StatisticsViewMetrics.last30DayPoints(
            from: [threeDaysAgo: 4, oneDayAgo: 2],
            referenceDate: referenceDate
        )

        #expect(points.count == 30)
        #expect(points.first?.count == 0)
        #expect(points.first(where: { $0.dayKey == threeDaysAgo })?.count == 4)
        #expect(points.first(where: { $0.dayKey == oneDayAgo })?.count == 2)
        #expect(points.first(where: { $0.dayKey == formatter.string(from: referenceDate) })?.count == 0)
    }
}
