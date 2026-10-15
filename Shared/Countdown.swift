import SwiftUI

/// A countdown to a date: a birthday, a trip, a launch.
struct Countdown: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var allDay = true
    var repeatsYearly = false
    var symbol = "star.fill"
    var colorName = "orange"
    /// File name of a custom icon in `IconStore`, used instead of `symbol`.
    var iconFile: String?
    /// Optional photo behind the countdown on its card and widget.
    var backgroundFile: String?
    var backgroundDim: Double?
    var backgroundBlur: Double?

    var dim: Double { backgroundDim ?? 0.2 }
    var blur: Double { backgroundBlur ?? 0 }
    var hasBackgroundImage: Bool { backgroundFile != nil }

    enum Phase { case upcoming, today, past }

    /// The moment being counted to. All-day countdowns aim at the start of
    /// their day; yearly ones roll over to the next occurrence once passed.
    func target(from now: Date = .now) -> Date {
        let cal = Calendar.current
        let base = allDay ? cal.startOfDay(for: date) : date
        guard repeatsYearly else { return base }
        // An all-day countdown stays on "Today" for its whole day.
        let cutoff = allDay ? cal.startOfDay(for: now) : now
        if base >= cutoff { return base }
        let parts = cal.dateComponents([.month, .day, .hour, .minute], from: base)
        return cal.nextDate(after: cutoff.addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTime) ?? base
    }

    func phase(at now: Date = .now) -> Phase {
        let t = target(from: now)
        if allDay && Calendar.current.isDate(t, inSameDayAs: now) { return .today }
        return t > now ? .upcoming : .past
    }

    /// Calendar days from today to the target day (negative when past).
    func days(from now: Date = .now) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: target(from: now))).day ?? 0
    }

    /// Big number + unit for list rows and widgets, e.g. ("12", "days").
    func headline(at now: Date = .now) -> (value: String, unit: String) {
        let d = days(from: now)
        switch phase(at: now) {
        case .today:
            return ("Today", "")
        case .upcoming:
            if d == 0 { return (DurationFormat.clock(target(from: now).timeIntervalSince(now)), "left") }
            return ("\(d)", d == 1 ? "day" : "days")
        case .past:
            if d == 0 { return ("Now", "") }
            return ("\(-d)", -d == 1 ? "day ago" : "days ago")
        }
    }

    /// "12d 04:22:31" style breakdown until the target.
    func breakdown(at now: Date = .now) -> String {
        let total = Int(max(0, target(from: now).timeIntervalSince(now)))
        let d = total / 86_400, h = (total % 86_400) / 3600, m = (total % 3600) / 60, s = total % 60
        let clock = String(format: "%02d:%02d:%02d", h, m, s)
        return d > 0 ? "\(d)d \(clock)" : clock
    }

    func dateText(at now: Date = .now) -> String {
        let t = target(from: now)
        return allDay
            ? t.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            : t.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year().hour().minute())
    }

    var color: Color { Self.palette.first { $0.name == colorName }?.color ?? .orange }

    /// "No color": just the icon, no colored background anywhere.
    static let noColor = "none"
    var isColorless: Bool { colorName == Self.noColor }

    /// Color for numbers and accents on a neutral background.
    var accent: Color { isColorless ? .primary : color }

    /// Background for cards and single-countdown widgets.
    var cardBackground: AnyShapeStyle {
        isColorless ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) : AnyShapeStyle(color.gradient)
    }

    /// Text color on top of `cardBackground`.
    var cardForeground: Color { isColorless && !hasBackgroundImage ? .primary : .white }

    static let palette: [(name: String, color: Color)] = [
        ("orange", .orange), ("red", .red), ("pink", .pink), ("purple", .purple),
        ("indigo", .indigo), ("blue", .blue), ("teal", .teal), ("mint", .mint),
        ("green", .green), ("yellow", .yellow), ("brown", .brown), ("gray", .gray),
    ]

    static let symbols = [
        "star.fill", "birthday.cake.fill", "gift.fill", "heart.fill",
        "airplane", "car.fill", "house.fill", "graduationcap.fill",
        "party.popper.fill", "music.note", "gamecontroller.fill", "briefcase.fill",
        "sun.max.fill", "snowflake", "tree.fill", "dollarsign.circle.fill",
        "figure.run", "stethoscope", "pawprint.fill", "sparkles",
    ]
}

extension SharedStore {
    static let countdownWidgetKind = "TockCountdowns"
    private static let countdownsKey = "countdowns"

    static func loadCountdowns() -> [Countdown] {
        guard let data = defaults.data(forKey: countdownsKey) else { return [] }
        return (try? JSONDecoder().decode([Countdown].self, from: data)) ?? []
    }

    static func saveCountdowns(_ countdowns: [Countdown]) {
        if let data = try? JSONEncoder().encode(countdowns) {
            defaults.set(data, forKey: countdownsKey)
        }
    }

    /// Upcoming/today first (soonest first), then past (most recent first).
    static func sortedCountdowns(_ countdowns: [Countdown], at now: Date = .now) -> [Countdown] {
        countdowns.sorted { a, b in
            let pa = a.phase(at: now) == .past, pb = b.phase(at: now) == .past
            if pa != pb { return !pa }
            return pa ? a.target(from: now) > b.target(from: now) : a.target(from: now) < b.target(from: now)
        }
    }
}
