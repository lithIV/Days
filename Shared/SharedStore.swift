import Foundation

enum DurationFormat {
    /// "04:59" or "1:04:59". Rounds up like the iOS Clock app.
    static func clock(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Storage shared between the app and the widget through the App Group.
/// Falls back to the app's own defaults when the group isn't available
/// (e.g. under LiveContainer), so the app still works on its own.
enum SharedStore {
    static let appGroup = "group.dev.lithiv.tock"

    static let defaults: UserDefaults = {
        let shared = UserDefaults(suiteName: resolvedAppGroup) ?? .standard
        // Earlier builds always used the un-renamed group, which on re-signed
        // installs was just a private file. Carry that data over once.
        if resolvedAppGroup != appGroup, let legacy = UserDefaults(suiteName: appGroup) {
            for key in ["countdowns"] where shared.object(forKey: key) == nil {
                if let value = legacy.object(forKey: key) { shared.set(value, forKey: key) }
            }
        }
        return shared
    }()

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
}
