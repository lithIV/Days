import Foundation

/// One countdown. A timer is running while `endDate` is set, paused while
/// `pausedRemaining` is set, and finished once `firedAt` is set.
struct TimerItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var duration: TimeInterval
    var endDate: Date?
    var pausedRemaining: TimeInterval?
    var firedAt: Date?

    enum Status { case running, paused, finished }

    var status: Status {
        if firedAt != nil { return .finished }
        if endDate != nil { return .running }
        return .paused
    }

    func remaining(at now: Date = .now) -> TimeInterval {
        switch status {
        case .finished: return 0
        case .running: return max(0, (endDate ?? now).timeIntervalSince(now))
        case .paused: return pausedRemaining ?? duration
        }
    }

    /// Fraction of the timer still left, 1 → 0.
    func progress(at now: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
    }

    var displayLabel: String {
        label.trimmingCharacters(in: .whitespaces).isEmpty ? DurationFormat.words(duration) : label
    }
}

enum DurationFormat {
    /// "04:59" or "1:04:59". Rounds up like the iOS Clock app.
    static func clock(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "1 hr 5 min", "30 sec".
    static func words(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) sec") }
        return parts.joined(separator: " ")
    }

    /// Compact preset title: "5m", "1h", "1h 30m", "45s".
    static func short(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 || parts.isEmpty { parts.append("\(s)s") }
        return parts.joined(separator: " ")
    }
}

/// Storage shared between the app and the widget through the App Group.
/// Falls back to the app's own defaults when the group isn't available
/// (e.g. under LiveContainer), so the app still works on its own.
enum SharedStore {
    static let appGroup = "group.dev.lithiv.tock"
    static let widgetKind = "TockTimers"
    private static let timersKey = "timers"

    static let defaults: UserDefaults = UserDefaults(suiteName: resolvedAppGroup) ?? .standard

    /// SideStore/AltStore rename App Groups when re-signing (they append the
    /// team ID), so find the group this install was actually given.
    static let resolvedAppGroup: String = {
        let candidates = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? [])
            + provisionedAppGroups() + [appGroup]
        let usable = candidates.filter {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
        return usable.first { $0.hasPrefix(appGroup) } ?? usable.first ?? appGroup
    }()

    /// App Groups listed in the bundle's embedded provisioning profile.
    private static func provisionedAppGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    static func loadTimers() -> [TimerItem] {
        guard let data = defaults.data(forKey: timersKey) else { return [] }
        return (try? JSONDecoder().decode([TimerItem].self, from: data)) ?? []
    }

    static func saveTimers(_ timers: [TimerItem]) {
        if let data = try? JSONEncoder().encode(timers) {
            defaults.set(data, forKey: timersKey)
        }
    }
}
