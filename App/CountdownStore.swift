import SwiftUI
import Observation
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class CountdownStore {
    private(set) var countdowns: [Countdown] = SharedStore.loadCountdowns()

    func sorted(at now: Date = .now) -> [Countdown] {
        SharedStore.sortedCountdowns(countdowns, at: now)
    }

    func save(_ countdown: Countdown) {
        if let i = countdowns.firstIndex(where: { $0.id == countdown.id }) {
            countdowns[i] = countdown
        } else {
            countdowns.append(countdown)
        }
        scheduleNotification(for: countdown)
        persist()
    }

    func delete(_ id: Countdown.ID) {
        countdowns.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        persist()
    }

    private func persist() {
        SharedStore.saveCountdowns(countdowns)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.countdownWidgetKind)
    }

    /// Notifies when the countdown hits zero (9 AM on the day for all-day ones).
    private func scheduleNotification(for c: Countdown) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [c.id.uuidString])

        var parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: c.target())
        if c.allDay { parts.hour = 9; parts.minute = 0 }
        if c.repeatsYearly { parts.year = nil }
        if !c.repeatsYearly, let when = Calendar.current.date(from: parts), when <= .now { return }

        let content = UNMutableNotificationContent()
        content.title = c.title
        content.body = c.allDay ? "It's today!" : "The countdown is over!"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: c.repeatsYearly)
        center.add(UNNotificationRequest(identifier: c.id.uuidString, content: content, trigger: trigger))
    }
}
