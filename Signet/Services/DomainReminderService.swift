import AppKit
import Foundation
import UserNotifications

/// Settings > Notifications: whether Signet reminds the user before a Tezos Domains name one
/// of their accounts owns expires. On by default; in UserDefaults.
enum DomainReminderSettings {
    static let key = "domainExpiryReminders"
    static let shownKey = "domainExpiryRemindersShown"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}

/// Puts `DomainReminders` into macOS notifications. The reminders still to come are scheduled
/// with the system (they appear at 9:00 on their day whether or not Signet is running), each
/// scan replacing the previous set, so a renewal moves them and a name that changed hands
/// loses them. A reminder already due when a name is first seen is shown at once, once. The
/// system keeps a limited number per app, so the earliest 60 are scheduled and later scans top
/// them up. Clicking one opens the name on Tezos Domains. Never used under the test host.
@MainActor
final class DomainReminderService: NSObject, UNUserNotificationCenterDelegate {
    /// One name to remind about: what it is called, when it expires, and whose it is.
    struct OwnedName: Sendable {
        let name: String
        let expires: Date
        let owner: String
    }

    /// The one the app uses; made on first use (never under the test host).
    static let shared = DomainReminderService()

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    /// What the last scan found the system allows (shown in Settings).
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        center.delegate = self
    }

    /// Replaces every scheduled domain reminder with those for `names`; with the setting off it
    /// only removes them.
    func update(_ names: [OwnedName], now: Date = Date()) async {
        await removeScheduled()
        guard DomainReminderSettings.isOn(defaults), !names.isEmpty else { return }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        authorization = status
        guard status == .authorized || status == .provisional else { return }

        var shown = Set(defaults.stringArray(forKey: DomainReminderSettings.shownKey) ?? [])
        let owners = Dictionary(names.map { ($0.name, $0.owner) }, uniquingKeysWith: { first, _ in first })
        let plan = DomainReminders.plan(names.map { ($0.name, $0.expires) }, shown: shown, now: now)
        for reminder in plan.upcoming {
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content(reminder, owner: owners[reminder.name] ?? ""), trigger: trigger))
        }
        for reminder in plan.overdue {
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content(reminder, owner: owners[reminder.name] ?? ""), trigger: nil))
            shown.insert(reminder.id)
        }
        // Keep the record of shown reminders small: only names still owned matter.
        let live = Set(names.map(\.name))
        defaults.set(Array(shown.filter { id in live.contains { id.hasPrefix("domain-expiry|\($0)|") } }.sorted().suffix(500)), forKey: DomainReminderSettings.shownKey)
    }

    /// Shows a reminder at once for the name that expires soonest, so the user can see what
    /// reminders look like and that macOS lets them through. `false` when there is no name or
    /// notifications are not allowed.
    func sendTest(_ names: [OwnedName], now: Date = Date()) async -> Bool {
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        authorization = status
        guard status == .authorized || status == .provisional,
              let soonest = names.filter({ $0.expires > now }).min(by: { $0.expires < $1.expires }),
              let reminder = DomainReminders.reminders(name: soonest.name, expires: soonest.expires).first(where: { $0.due > now }) ?? DomainReminders.reminders(name: soonest.name, expires: soonest.expires).last
        else { return false }
        let content = content(reminder, owner: soonest.owner)
        content.title = "Test: " + content.title
        try? await center.add(UNNotificationRequest(identifier: "domain-expiry-test|\(UUID().uuidString)", content: content, trigger: nil))
        return true
    }

    func removeScheduled() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("domain-expiry|") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func content(_ reminder: DomainReminders.Reminder, owner: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body(owner: owner)
        content.sound = .default
        content.threadIdentifier = "domain-expiry"
        content.userInfo = ["url": "https://app.tezos.domains/domain/\(reminder.name)"]
        return content
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown even while Signet is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Clicking a reminder opens the name on Tezos Domains, where it can be renewed.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: text),
              url.scheme == "https", url.host() == "app.tezos.domains" else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }
}
