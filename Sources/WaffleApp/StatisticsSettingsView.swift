import Foundation
import SwiftUI
import WaffleCore

struct StatisticsSettingsView: View {
    let store: TranscriptStore
    @ObservedObject var modelStore: ModelStore

    @State private var stats: TranscriptStatistics?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(
                    localized(
                        "settings.statistics.title",
                        default: "Usage Statistics",
                        comment: "Title for settings statistics view"
                    )
                )
                .font(.title3.weight(.semibold))

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(
                    localized(
                        "settings.statistics.refresh",
                        default: "Refresh",
                        comment: "Action title for refreshing statistics"
                    )
                ) {
                    Task {
                        await loadStatistics()
                    }
                }
                .disabled(isLoading)
            }

            if isLoading && stats == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let stats {
                if stats.transcriptCount == 0 {
                    ContentUnavailableView(
                        localized(
                            "settings.statistics.empty.title",
                            default: "No data yet",
                            comment: "Empty-state title when no transcripts are available for statistics"
                        ),
                        systemImage: "chart.bar",
                        description: Text(
                            localized(
                                "settings.statistics.empty.description",
                                default: "Start dictating or import audio files to populate usage statistics.",
                                comment: "Empty-state description when no transcripts exist"
                            )
                        )
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            summarySection(stats: stats)
                            modelUsageSection(stats: stats)
                            frequencySection(stats: stats)
                        }
                        .padding(.bottom, 4)
                    }
                }
            } else {
                Text(
                    localized(
                        "settings.statistics.loadFailed",
                        default: "Unable to load statistics right now.",
                        comment: "Fallback message when statistics loading fails"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task {
            await loadStatistics()
        }
    }

    private func summarySection(stats: TranscriptStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                localized(
                    "settings.statistics.summary.section",
                    default: "Summary",
                    comment: "Section title for statistics summary cards"
                )
            )
            .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                summaryCard(
                    title: localized(
                        "settings.statistics.summary.totalRecordings",
                        default: "Total Recordings",
                        comment: "Label for total transcript count metric"
                    ),
                    value: stats.transcriptCount.formatted()
                )

                summaryCard(
                    title: localized(
                        "settings.statistics.summary.totalWords",
                        default: "Total Words",
                        comment: "Label for total word count metric"
                    ),
                    value: stats.totalWords.formatted()
                )

                summaryCard(
                    title: localized(
                        "settings.statistics.summary.totalDuration",
                        default: "Total Duration",
                        comment: "Label for total duration metric"
                    ),
                    value: StatisticsViewMetrics.formatTotalDuration(seconds: stats.totalDurationSeconds)
                )

                summaryCard(
                    title: localized(
                        "settings.statistics.summary.averageDuration",
                        default: "Average Duration",
                        comment: "Label for average duration metric"
                    ),
                    value: StatisticsViewMetrics.formatAverageDuration(seconds: stats.averageDurationSeconds)
                )
            }
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modelUsageSection(stats: TranscriptStatistics) -> some View {
        let rows = stats.byModel
            .map { key, value in (modelID: key, count: value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.modelID < rhs.modelID
                }
                return lhs.count > rhs.count
            }

        return VStack(alignment: .leading, spacing: 8) {
            Text(
                localized(
                    "settings.statistics.models.section",
                    default: "Model Usage",
                    comment: "Section title for model usage breakdown"
                )
            )
            .font(.headline)

            ForEach(rows, id: \.modelID) { row in
                let percentage = StatisticsViewMetrics.modelUsagePercentage(
                    count: row.count,
                    total: stats.transcriptCount
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(modelDisplayName(for: row.modelID))
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(row.count) (\(Int((percentage * 100).rounded()))%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(4, geometry.size.width * percentage))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    private func frequencySection(stats: TranscriptStatistics) -> some View {
        let points = StatisticsViewMetrics.last30DayPoints(from: stats.dailyCounts)
        let maxCount = max(points.map(\.count).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text(
                localized(
                    "settings.statistics.frequency.section",
                    default: "Recording Frequency (Last 30 Days)",
                    comment: "Section title for last-30-days recording frequency chart"
                )
            )
            .font(.headline)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(
                                width: 8,
                                height: StatisticsViewMetrics.barHeight(
                                    count: point.count,
                                    maxCount: maxCount,
                                    maxHeight: 86
                                )
                            )

                        Text(index.isMultiple(of: 7) ? StatisticsViewMetrics.weekdayLabel(for: point.date) : " ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private func modelDisplayName(for modelID: String) -> String {
        modelStore.catalog.first(where: { $0.id == modelID })?.displayName ?? modelID
    }

    private func loadStatistics() async {
        isLoading = true
        let loadedStats = try? await Task.detached(priority: .utility) { [store] in
            try store.statistics()
        }.value
        stats = loadedStats
        isLoading = false
    }
}

struct StatisticsDailyPoint: Equatable {
    let date: Date
    let dayKey: String
    let count: Int
}

enum StatisticsViewMetrics {
    static func formatTotalDuration(seconds: Double) -> String {
        let totalSeconds = Int(max(seconds, 0))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func formatAverageDuration(seconds: Double) -> String {
        let totalSeconds = Int(max(seconds, 0))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    static func modelUsagePercentage(count: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(count) / Double(total), 0), 1)
    }

    static func last30DayPoints(
        from dailyCounts: [String: Int],
        referenceDate: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [StatisticsDailyPoint] {
        let utcCalendar = calendarWithUTC(from: calendar)
        let end = utcCalendar.startOfDay(for: referenceDate)
        guard let start = utcCalendar.date(byAdding: .day, value: -29, to: end) else { return [] }
        let formatter = dayKeyFormatter()

        return (0..<30).compactMap { offset in
            guard let date = utcCalendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            let dayKey = formatter.string(from: date)
            return StatisticsDailyPoint(
                date: date,
                dayKey: dayKey,
                count: dailyCounts[dayKey] ?? 0
            )
        }
    }

    static func barHeight(count: Int, maxCount: Int, maxHeight: CGFloat) -> CGFloat {
        guard maxCount > 0 else { return 2 }
        let normalized = Double(max(count, 0)) / Double(maxCount)
        return max(2, CGFloat(normalized) * maxHeight)
    }

    static func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendarWithUTC(from: Calendar(identifier: .gregorian))
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private static func dayKeyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendarWithUTC(from: Calendar(identifier: .gregorian))
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func calendarWithUTC(from calendar: Calendar) -> Calendar {
        var adjusted = calendar
        adjusted.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return adjusted
    }
}
