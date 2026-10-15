import WidgetKit
import SwiftUI

@main
struct TockWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimersWidget()
    }
}

struct TimersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: Provider()) { entry in
            TimersWidgetView(entry: entry)
        }
        .configurationDisplayName("Timers")
        .description("Your running timers at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Timeline

struct TimersEntry: TimelineEntry {
    let date: Date
    let timers: [TimerItem]

    /// Running timers first (soonest done first), then paused, then finished.
    var sorted: [TimerItem] {
        timers.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.endDate ?? .distantFuture) < (b.endDate ?? .distantFuture)
        }
    }

    func isDone(_ t: TimerItem) -> Bool {
        t.firedAt != nil || (t.endDate.map { $0 <= date } ?? false)
    }

    private func rank(_ t: TimerItem) -> Int {
        if isDone(t) { return 2 }
        return t.endDate != nil ? 0 : 1
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TimersEntry {
        TimersEntry(date: .now, timers: [
            TimerItem(label: "Pasta", duration: 600, endDate: .now.addingTimeInterval(421)),
            TimerItem(label: "Laundry", duration: 2700, endDate: .now.addingTimeInterval(1980)),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TimersEntry) -> Void) {
        let timers = SharedStore.loadTimers()
        completion(context.isPreview && timers.isEmpty ? placeholder(in: context) : TimersEntry(date: .now, timers: timers))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimersEntry>) -> Void) {
        let now = Date.now
        let timers = SharedStore.loadTimers()
        // The countdown text ticks on its own; add an entry at each end date so
        // the widget flips to "Done" at the right moment.
        let endDates = timers.compactMap { $0.firedAt == nil ? $0.endDate : nil }.filter { $0 > now }.sorted()
        let entries = ([now] + endDates).map { TimersEntry(date: $0, timers: timers) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

// MARK: - Views

struct TimersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimersEntry

    var body: some View {
        content.containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                Color(uiColor: .systemBackground)
            }
        }
    }

    @ViewBuilder private var content: some View {
        let timers = entry.sorted
        switch family {
        case .accessoryInline:
            if let t = timers.first {
                HStack { Image(systemName: "timer"); countdown(t) }
            } else {
                Label("No timers", systemImage: "timer")
            }
        case .accessoryCircular:
            if let t = timers.first {
                circular(t)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "timer").font(.title2)
                }
            }
        case .accessoryRectangular:
            if let t = timers.first {
                VStack(alignment: .leading, spacing: 2) {
                    Label(t.displayLabel, systemImage: "timer").font(.headline).lineLimit(1)
                    countdown(t).font(.system(.title2, design: .rounded)).monospacedDigit()
                    progress(t)
                }
            } else {
                Label("No timers", systemImage: "timer")
            }
        case .systemMedium:
            if timers.isEmpty { empty } else { medium(Array(timers.prefix(3))) }
        default:
            if let t = timers.first { small(t, extra: timers.count - 1) } else { empty }
        }
    }

    private func small(_ t: TimerItem, extra: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "timer").foregroundStyle(.orange).font(.headline)
                Spacer()
                if extra > 0 {
                    Text("+\(extra)").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            countdown(t)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(t.displayLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            progress(t)
        }
    }

    private func medium(_ timers: [TimerItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(timers) { t in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.displayLabel).font(.subheadline.weight(.medium)).lineLimit(1)
                        progress(t)
                    }
                    Spacer()
                    countdown(t)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "timer").font(.largeTitle).foregroundStyle(.orange)
            Text("No timers").font(.headline)
            Text("Tap to start one").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func circular(_ t: TimerItem) -> some View {
        if let end = t.endDate, !entry.isDone(t) {
            ProgressView(timerInterval: end.addingTimeInterval(-t.duration)...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .progressViewStyle(.circular)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                if entry.isDone(t) {
                    Image(systemName: "bell.fill").font(.title3)
                } else {
                    Text(DurationFormat.clock(t.remaining(at: entry.date)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    @ViewBuilder private func countdown(_ t: TimerItem) -> some View {
        if entry.isDone(t) {
            Text("Done").foregroundStyle(.red)
        } else if let end = t.endDate {
            Text(timerInterval: entry.date...end, countsDown: true)
        } else {
            Text(DurationFormat.clock(t.remaining(at: entry.date))).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func progress(_ t: TimerItem) -> some View {
        if let end = t.endDate, !entry.isDone(t) {
            ProgressView(timerInterval: end.addingTimeInterval(-t.duration)...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.orange)
        } else {
            ProgressView(value: entry.isDone(t) ? 0 : t.progress(at: entry.date))
                .tint(entry.isDone(t) ? .red : .gray)
        }
    }
}
