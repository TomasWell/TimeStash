import SwiftUI
import WidgetKit

struct TimeStashWidget: Widget {
    let kind = "TimeStashWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimeStashProvider()) { entry in
            TimeStashWidgetView(entry: entry)
        }
        .configurationDisplayName("widget_display_name")
        .description("widget_description")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TimeStashWidgetView: View {
    let entry: VaultEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemSmall {
            smallView
        } else {
            mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("widget_title")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(VaultFormat.compactDuration(entry.totalSavedSeconds))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("widget_saved_today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            Text(VaultFormat.compactDuration(entry.todaySavedSeconds))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
        }
        .padding(2)
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text("widget_title")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("widget_saved_today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(VaultFormat.compactDuration(entry.todaySavedSeconds))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.tint)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("widget_total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(VaultFormat.duration(entry.totalSavedSeconds))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }
        }
        .padding(2)
    }
}
