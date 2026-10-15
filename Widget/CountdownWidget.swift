import WidgetKit
import SwiftUI
import AppIntents

struct CountdownsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedStore.countdownWidgetKind,
                               intent: CountdownWidgetIntent.self,
                               provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Countdowns")
        .description("Days until the things you're waiting for. Long-press → Edit Widget to pick one.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Configuration

struct CountdownEntity: AppEntity {
    let id: UUID
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Countdown"
    static var defaultQuery = CountdownQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ countdown: Countdown) {
        id = countdown.id
        title = countdown.title
    }
}

struct CountdownQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CountdownEntity] {
        SharedStore.loadCountdowns().filter { identifiers.contains($0.id) }.map(CountdownEntity.init)
    }

    func suggestedEntities() async throws -> [CountdownEntity] {
        SharedStore.sortedCountdowns(SharedStore.loadCountdowns()).map(CountdownEntity.init)
    }
}

enum CountdownLayout: String, AppEnum {
    case single, list

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static var caseDisplayRepresentations: [CountdownLayout: DisplayRepresentation] = [
        .single: "One countdown, full widget",
        .list: "List of upcoming",
    ]
}

struct CountdownWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Countdown"
    static var description = IntentDescription("Choose what this widget shows.")

    @Parameter(title: "Countdown", description: "Leave empty to always show the next one.")
    var countdown: CountdownEntity?

    @Parameter(title: "Layout", default: .single)
    var layout: CountdownLayout

    @Parameter(title: "Show hours, minutes & seconds", default: true)
    var showTicker: Bool
}

// MARK: - Timeline

struct CountdownEntry: TimelineEntry {
    let date: Date
    let countdowns: [Countdown]
    var selectedID: UUID?
    var layout: CountdownLayout = .single
    var showTicker = true

    /// The picked countdown first, then upcoming ones (past only if nothing is upcoming).
    var shown: [Countdown] {
        let sorted = SharedStore.sortedCountdowns(countdowns, at: date)
        let upcoming = sorted.filter { $0.phase(at: date) != .past }
        var list = upcoming.isEmpty ? sorted : upcoming
        if let id = selectedID, let picked = countdowns.first(where: { $0.id == id }) {
            list.removeAll { $0.id == id }
            list.insert(picked, at: 0)
        }
        return list
    }
}

struct CountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        let cal = Calendar.current
        return CountdownEntry(date: .now, countdowns: [
            Countdown(title: "Vacation", date: cal.date(byAdding: .day, value: 12, to: .now)!, symbol: "airplane", colorName: "blue"),
            Countdown(title: "Birthday", date: cal.date(byAdding: .day, value: 40, to: .now)!, symbol: "birthday.cake.fill", colorName: "pink"),
            Countdown(title: "Payday", date: cal.date(byAdding: .day, value: 5, to: .now)!, symbol: "dollarsign.circle.fill", colorName: "green"),
        ])
    }

    func snapshot(for configuration: CountdownWidgetIntent, in context: Context) async -> CountdownEntry {
        let saved = SharedStore.loadCountdowns()
        if context.isPreview && saved.isEmpty { return placeholder(in: context) }
        return CountdownEntry(date: .now, countdowns: saved,
                              selectedID: configuration.countdown?.id, layout: configuration.layout,
                           showTicker: configuration.showTicker)
    }

    func timeline(for configuration: CountdownWidgetIntent, in context: Context) async -> Timeline<CountdownEntry> {
        let now = Date.now
        let cal = Calendar.current
        let saved = SharedStore.loadCountdowns()
        // Day counts change at midnight; timed countdowns also flip when they hit zero.
        let today = cal.startOfDay(for: now)
        let midnights = (1...3).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let horizon = midnights.last ?? now.addingTimeInterval(86_400)
        let targets = saved.map { $0.target(from: now) }.filter { $0 > now && $0 < horizon }
        // The live h:m:s ticker rolls over every 24 hours before each target.
        let dayBoundaries = saved.flatMap { c in
            (1...4).flatMap { k -> [Date] in
                let boundary = c.target(from: now).addingTimeInterval(-Double(k) * 86_400)
                return [boundary, boundary.addingTimeInterval(3600), boundary.addingTimeInterval(600)]
            }
        }.filter { $0 > now && $0 < horizon }
        let dates = Set([now] + midnights + targets + dayBoundaries).sorted()
        let entries = dates.map {
            CountdownEntry(date: $0, countdowns: saved,
                           selectedID: configuration.countdown?.id, layout: configuration.layout,
                           showTicker: configuration.showTicker)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Views

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    private var isSystem: Bool {
        family == .systemSmall || family == .systemMedium || family == .systemLarge
    }

    var body: some View {
        let shown = entry.shown
        let single = entry.layout == .single || family == .systemSmall
        content(shown, single: single)
            .containerBackground(for: .widget) {
                if isSystem, single, let c = shown.first {
                    CountdownBackground(countdown: c)
                } else if isSystem {
                    Color(uiColor: .systemBackground)
                } else {
                    Color.clear
                }
            }
    }

    @ViewBuilder private func content(_ shown: [Countdown], single: Bool) -> some View {
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
                        accessoryIcon(c, size: 12)
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
                    HStack(spacing: 4) {
                        accessoryIcon(c, size: 14)
                        Text(c.title).font(.headline).lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        bigValue(c).font(.system(.title, design: .rounded, weight: .bold))
                        Text(c.headline(at: entry.date).unit).font(.caption)
                    }
                    Text(c.dateText(at: entry.date)).font(.caption2).lineLimit(1)
                }
            } else {
                Label("No countdowns", systemImage: "calendar")
            }
        default:
            if shown.isEmpty {
                empty
            } else if single {
                switch family {
                case .systemSmall: small(shown[0])
                case .systemLarge: large(shown[0])
                default: medium(shown[0])
                }
            } else {
                list(Array(shown.prefix(family == .systemLarge ? 6 : 3)))
            }
        }
    }

    // MARK: Single countdown, whole widget

    private func small(_ c: Countdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CountdownIcon(countdown: c, size: 28 * min(c.iconSize, 1.6), style: .onCard)
            Spacer(minLength: 0)
            bigValue(c)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            unitText(c).font(.subheadline.weight(.semibold)).opacity(0.85)
            ticker(c).font(.caption.weight(.semibold)).opacity(0.85)
            Text(c.title).font(.caption.weight(.medium)).lineLimit(1).opacity(0.9)
        }
        .foregroundStyle(c.cardForeground)
        .shadow(color: .black.opacity(c.hasBackgroundImage ? 0.4 : 0), radius: 6, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ c: Countdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 12) {
                CountdownIcon(countdown: c, size: 40 * c.iconSize, style: .onCard)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: -4) {
                    bigValue(c)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.35)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                    unitText(c).font(.headline).opacity(0.85)
                }
                .frame(maxWidth: 180, alignment: .trailing)
                // Big digits sit below their line's top edge. Shift only the
                // number up (offset doesn't move the icon) so their tops line up.
                .offset(y: -13)
            }
            Spacer(minLength: 0)
            Text(c.title).font(.title3.weight(.bold)).lineLimit(1)
            // Date and live ticker share one line so they sit on the same baseline.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(c.dateText(at: entry.date)).font(.caption).opacity(0.8).lineLimit(1)
                Spacer(minLength: 0)
                ticker(c, alignment: .trailing).font(.subheadline.weight(.semibold)).opacity(0.85)
            }
        }
        .foregroundStyle(c.cardForeground)
        .shadow(color: .black.opacity(c.hasBackgroundImage ? 0.4 : 0), radius: 6, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func large(_ c: Countdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                CountdownIcon(countdown: c, size: 64 * c.iconSize, style: .onCard)
                Spacer()
                if c.repeatsYearly {
                    Image(systemName: "repeat").font(.headline).opacity(0.8)
                }
            }
            Spacer(minLength: 0)
            bigValue(c)
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
            unitText(c).font(.title2.weight(.semibold)).opacity(0.85)
            ticker(c).font(.title3.weight(.semibold)).opacity(0.85)
            Spacer(minLength: 0)
            Text(c.title).font(.title.weight(.bold)).lineLimit(2)
            Text(c.dateText(at: entry.date)).font(.subheadline).opacity(0.8)
        }
        .foregroundStyle(c.cardForeground)
        .shadow(color: .black.opacity(c.hasBackgroundImage ? 0.4 : 0), radius: 6, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: List

    private func list(_ items: [Countdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { c in
                HStack(spacing: 10) {
                    CountdownIcon(countdown: c, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(c.dateText(at: entry.date)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: -2) {
                        bigValue(c)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(c.accent)
                            .multilineTextAlignment(.trailing)
                        unitText(c).font(.caption2).foregroundStyle(.secondary)
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

    // MARK: Pieces

    /// The big number. Under a day away it ticks live instead.
    @ViewBuilder private func bigValue(_ c: Countdown) -> some View {
        let target = c.target(from: entry.date)
        if c.phase(at: entry.date) == .upcoming && c.days(from: entry.date) == 0 {
            Text(timerInterval: entry.date...target, countsDown: true).monospacedDigit()
        } else {
            Text(c.headline(at: entry.date).value).monospacedDigit()
        }
    }

    /// Live "35d 4:22:31" line. Skipped on the last day, when the big number
    /// itself is already ticking.
    @ViewBuilder private func ticker(_ c: Countdown, alignment: TextAlignment = .leading) -> some View {
        if entry.showTicker, c.phase(at: entry.date) == .upcoming, c.days(from: entry.date) > 0,
           let parts = c.tickerParts(at: entry.date) {
            // One concatenated Text so it sizes to its content; a bare timer
            // Text in a widget stretches to fill the row.
            (Text(parts.days > 0 ? "\(parts.days)d " : "") + Text(hourPadding(until: parts.until))
                + Text(timerInterval: entry.date...parts.until, countsDown: true))
                .monospacedDigit()
                .lineLimit(1)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
        }
    }

    /// iOS timer text drops the hours under an hour ("42:44", "9:59").
    /// Pad it back to "0:42:44" / "0:09:59"; the timeline adds entries at the
    /// 1-hour and 10-minute marks so the padding switches on time.
    private func hourPadding(until: Date) -> String {
        let left = until.timeIntervalSince(entry.date)
        if left < 600 { return "0:0" }
        if left < 3600 { return "0:" }
        return ""
    }

    @ViewBuilder private func unitText(_ c: Countdown) -> some View {
        let unit = c.headline(at: entry.date).unit
        if !unit.isEmpty { Text(unit) }
    }

    @ViewBuilder private func accessoryIcon(_ c: Countdown, size: CGFloat) -> some View {
        if let file = c.iconFile, let image = IconStore.image(file) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: c.symbol).font(.system(size: size))
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
