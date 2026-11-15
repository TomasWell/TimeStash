import SwiftUI
import Charts

/// The charts.
///
/// Three questions, three charts:
/// am I getting faster? → where is the time coming from? → what have I earned?
struct StatsView: View {
    @EnvironmentObject private var store: VaultStore

    private var series: [(day: Date, seconds: Int)] {
        store.dailySeries(days: 14)
    }

    private var categoryData: [(category: VaultCategory, seconds: Int)] {
        VaultCategory.allCases.compactMap { category in
            guard let seconds = store.savedByCategory[category], seconds > 0 else { return nil }
            return (category, seconds)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    trendCard
                    categoryCard
                    milestoneCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("tab_stats")
        }
    }

    // MARK: - Trend

    private var trendCard: some View {
        card {
            Text(L("stats_trend_title"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if series.allSatisfy({ $0.seconds == 0 }) {
                Text(L("stats_trend_empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            } else {
                Chart(series, id: \.day) { point in
                    BarMark(
                        x: .value("day", point.day, unit: .day),
                        y: .value("seconds", point.seconds)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    // ⚠️ 默认轴标签在 zh-Hans 下会挤成「11月..」被截断（2026-11-16 巡检）。
                    // 日期值本身已按天聚合，只留网格线，标签由 Swift Charts
                    // 自动抽稀（我们改用短格式 + 限宽）。
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Int.self) {
                                Text(VaultFormat.compactDuration(seconds))
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Category

    private var categoryCard: some View {
        card {
            Text(L("stats_category_title"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if categoryData.isEmpty {
                Text(L("stats_category_empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            } else {
                Chart(categoryData, id: \.category) { item in
                    BarMark(
                        x: .value("seconds", item.seconds),
                        // ⚠️ 轴值/图例用 rawValue（英文）会让中文界面整列变英文
                        // （2026-11-16 巡检：zh-Hans 界面显示 work/study/life/other）。
                        // 分类的显示名必须走本地化表。
                        y: .value("category", L("category_\(item.category.rawValue)"))
                    )
                    .foregroundStyle(by: .value("category", L("category_\(item.category.rawValue)")))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(VaultFormat.compactDuration(item.seconds))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Int.self) {
                                Text(VaultFormat.compactDuration(seconds))
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(1, categoryData.count)) * 38 + 20)
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Milestones

    private var milestoneCard: some View {
        let progress = store.milestones
        return card {
            Text(L("stats_milestone_title"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                ForEach(VaultMilestone.all) { milestone in
                    HStack(spacing: 12) {
                        Image(systemName: milestone.symbolName)
                            .foregroundStyle(progress.earned.contains(milestone) ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: 22)
                        Text(L(milestone.titleKey))
                            .font(.subheadline)
                            .foregroundStyle(progress.earned.contains(milestone) ? .primary : .secondary)
                        Spacer(minLength: 0)
                        Text(VaultFormat.compactDuration(milestone.thresholdSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: progress.earned.contains(milestone) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(progress.earned.contains(milestone) ? Color.green : Color.secondary.opacity(0.4))
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}
