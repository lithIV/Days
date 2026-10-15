import WidgetKit
import SwiftUI

struct CountdownsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.countdownWidgetKind, provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Countdowns")
        .description("Days until the things you're waiting for.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let countdowns: [Countdown]

    /// Upcoming first; past ones only if nothing is upcoming.
    var shown: [Countdown] {
        let sorted = SharedStore.sortedCountdowns(countdowns, at: date)
        let upcoming = sorted.filter { $0.phase(at: date) != .past }
        return upcoming.isEmpty ? sorted : upcoming
    }
}

struct CountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        let cal = Calendar.current
        return CountdownEntry(date: .now, countdowns: [
            Countdown(title: "Vacation", date: cal.date(byAdding: .day, value: 12, to: .now)!, symbol: "airplane", colorName: "blue"),
            Countdown(title: "Birthday", date: cal.date(byAdding: .day, value: 40, to: .now)!, symbol: "birthday.cake.fill", colorName: "pink"),
            Countdown(title: "Payday", date: cal.date(byAdding: .day, value: 5, to: .now)!, symbol: "dollarsign.circle.fill", colorName: "green"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        let saved = SharedStore.loadCountdowns()
        completion(context.isPreview && saved.isEmpty ? placeholder(in: context) : CountdownEntry(date: .now, countdowns: saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let now = Date.now
        let cal = Calendar.current
        let saved = SharedStore.loadCountdowns()
        // Day counts change at midnight; timed countdowns also flip when they hit zero.
        let today = cal.startOfDay(for: now)
        let midnights = (1...3).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let horizon = midnights.last ?? now.addingTimeInterval(86_400)
        let targets = saved.map { $0.target(from: now) }.filter { $0 > now && $0 < horizon }
        let dates = Set([now] + midnights + targets).sorted()
        completion(Timeline(entries: dates.map { CountdownEntry(date: $0, countdowns: saved) }, policy: .atEnd))
    }
}

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    var body: some View {
        let shown = entry.shown
        content(shown)
            .containerBackground(for: .widget) {
                if family == .systemSmall, let first = shown.first {
                    Rectangle().fill(first.color.gradient)
                } else if family == .systemMedium || family == .systemLarge || family == .systemSmall {
                    Color(uiColor: .systemBackground)
                }
            }
    }

    @ViewBuilder private func content(_ shown: [Countdown]) -> some View {
        switch family {
        case .accessoryInline:
            if let c = shown.first {
                Label("\(c.title) · \(phrase(c))", systemImage: c.symbol)
            } else {
                Label("No countdowns", systemImage: "calendar")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let c = shown.first {
                    VStack(spacing: -2) {
                        Image(systemName: c.symbol).font(.caption)
                        bigValue(c).font(.system(size: 18, weight: .bold, design: .rounded)).minimumScaleFactor(0.4)
                        Text(c.headline(at: entry.date).unit.isEmpty ? " " : unitShort(c))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(4)
                } else {
                    Image(systemName: "calendar").font(.title2)
                }
            }
        case .accessoryRectangular:
            if let c = shown.first {
                VStack(alignment: .leading, spacing: 0) {
                    Label(c.title, systemImage: c.symbol).font(.headline).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        bigValue(c).font(.system(.title, design: .rounded, weight: .bold))
                        Text(c.headline(at: entry.date).unit).font(.caption)
                    }
                    Text(c.dateText(at: entry.date)).font(.caption2).lineLimit(1)
                }
            } else {
                Label("No countdowns", systemImage: "calendar")
            }
        case .systemSmall:
            if let c = shown.first { small(c) } else { empty }
        case .systemLarge:
            if shown.isEmpty { empty } else { list(Array(shown.prefix(6))) }
        default:
            if shown.isEmpty { empty } else { list(Array(shown.prefix(3))) }
        }
    }

    private func small(_ c: Countdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: c.symbol).font(.title3)
            Spacer(minLength: 0)
            bigValue(c)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            if !c.headline(at: entry.date).unit.isEmpty {
                Text(c.headline(at: entry.date).unit).font(.subheadline.weight(.semibold)).opacity(0.85)
            }
            Text(c.title).font(.caption.weight(.medium)).lineLimit(1).opacity(0.9)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func list(_ items: [Countdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { c in
                HStack(spacing: 10) {
                    Image(systemName: c.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(c.color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(c.dateText(at: entry.date)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: -2) {
                        bigValue(c)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(c.color)
                            .multilineTextAlignment(.trailing)
                        Text(c.headline(at: entry.date).unit).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 100, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock").font(.largeTitle).foregroundStyle(.orange)
            Text("No countdowns").font(.headline)
            Text("Tap to add one").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The big number. Under a day away it ticks live instead.
    @ViewBuilder private func bigValue(_ c: Countdown) -> some View {
        let target = c.target(from: entry.date)
        if c.phase(at: entry.date) == .upcoming && c.days(from: entry.date) == 0 {
            Text(timerInterval: entry.date...target, countsDown: true).monospacedDigit()
        } else {
            Text(c.headline(at: entry.date).value).monospacedDigit()
        }
    }

    private func unitShort(_ c: Countdown) -> String {
        switch c.headline(at: entry.date).unit {
        case "days", "day": "days"
        case "days ago", "day ago": "ago"
        default: c.headline(at: entry.date).unit
        }
    }

    private func phrase(_ c: Countdown) -> String {
        let h = c.headline(at: entry.date)
        if h.unit.isEmpty { return h.value }
        if h.unit == "left" { return "\(h.value) left" }
        return h.unit.hasSuffix("ago") ? "\(h.value) \(h.unit)" : "in \(h.value) \(h.unit)"
    }
}
