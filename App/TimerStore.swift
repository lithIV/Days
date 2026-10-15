import SwiftUI
import Observation
import UserNotifications
import AudioToolbox
import WidgetKit

struct Preset: Identifiable, Codable, Hashable {
    var label: String
    var duration: TimeInterval
    var id: String { "\(label)|\(Int(duration))" }
}

@MainActor
@Observable
final class TimerStore {
    private(set) var timers: [TimerItem] = []
    private(set) var recents: [Preset] = []

    /// How long a finished timer keeps ringing before going quiet on its own.
    private let ringDuration: TimeInterval = 120
    private static let recentsKey = "recents"

    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var alarm: Task<Void, Never>?

    init() {
        timers = SharedStore.loadTimers()
        if let data = UserDefaults.standard.data(forKey: Self.recentsKey),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            recents = saved
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkFinished()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    var finished: [TimerItem] { timers.filter { $0.status == .finished } }

    private var isRinging: Bool {
        finished.contains { Date.now.timeIntervalSince($0.firedAt ?? .distantPast) < ringDuration }
    }

    // MARK: Actions

    func start(duration: TimeInterval, label: String = "") {
        guard duration > 0 else { return }
        let timer = TimerItem(label: label, duration: duration, endDate: .now.addingTimeInterval(duration))
        timers.append(timer)
        scheduleNotification(for: timer)
        remember(Preset(label: label, duration: duration))
        save()
    }

    func pause(_ id: TimerItem.ID) {
        update(id) { t in
            t.pausedRemaining = t.remaining()
            t.endDate = nil
        }
        cancelNotification(id)
    }

    func resume(_ id: TimerItem.ID) {
        update(id) { t in
            t.endDate = .now.addingTimeInterval(t.pausedRemaining ?? t.duration)
            t.pausedRemaining = nil
        }
        if let t = timers.first(where: { $0.id == id }) { scheduleNotification(for: t) }
    }

    func restart(_ id: TimerItem.ID) {
        update(id) { t in
            t.firedAt = nil
            t.pausedRemaining = nil
            t.endDate = .now.addingTimeInterval(t.duration)
        }
        if let t = timers.first(where: { $0.id == id }) { scheduleNotification(for: t) }
    }

    func addMinute(_ id: TimerItem.ID) {
        update(id) { t in
            t.duration += 60
            switch t.status {
            case .running: t.endDate = t.endDate?.addingTimeInterval(60)
            case .paused: t.pausedRemaining = (t.pausedRemaining ?? 0) + 60
            case .finished:
                t.firedAt = nil
                t.endDate = .now.addingTimeInterval(60)
            }
        }
        if let t = timers.first(where: { $0.id == id }), t.status == .running { scheduleNotification(for: t) }
    }

    func remove(_ id: TimerItem.ID) {
        timers.removeAll { $0.id == id }
        cancelNotification(id)
        save()
    }

    func stopFinished() {
        finished.forEach { cancelNotification($0.id) }
        timers.removeAll { $0.status == .finished }
        save()
    }

    func repeatFinished() {
        finished.forEach { restart($0.id) }
    }

    func forgetRecent(_ preset: Preset) {
        recents.removeAll { $0 == preset }
        saveRecents()
    }

    // MARK: Internals

    private func update(_ id: TimerItem.ID, _ change: (inout TimerItem) -> Void) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        change(&timers[i])
        save()
    }

    private func checkFinished() {
        let now = Date.now
        var changed = false
        for i in timers.indices where timers[i].status == .running {
            if let end = timers[i].endDate, end <= now {
                timers[i].firedAt = end
                changed = true
            }
        }
        if changed { save() }
        if isRinging { startAlarm() }
    }

    private func startAlarm() {
        guard alarm == nil else { return }
        alarm = Task { [weak self] in
            let haptics = UINotificationFeedbackGenerator()
            while let self, !Task.isCancelled, self.isRinging {
                AudioServicesPlayAlertSound(SystemSoundID(1005))
                haptics.notificationOccurred(.warning)
                try? await Task.sleep(for: .seconds(2))
            }
            self?.alarm = nil
        }
    }

    private func remember(_ preset: Preset) {
        recents.removeAll { $0 == preset }
        recents.insert(preset, at: 0)
        recents = Array(recents.prefix(8))
        saveRecents()
    }

    private func save() {
        SharedStore.saveTimers(timers)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: Self.recentsKey)
        }
    }

    // MARK: Notifications

    private func scheduleNotification(for timer: TimerItem) {
        guard let end = timer.endDate else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = timer.displayLabel
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification(_ id: TimerItem.ID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
