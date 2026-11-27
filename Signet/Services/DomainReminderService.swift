#if canImport(AppKit)
import AppKit
import Foundation
@preconcurrency import UserNotifications
#else
import Foundation
#endif

/// Settings > Notifications: whether Signet reminds the user before a Tezos Domains name one
/// of their accounts owns expires. On by default; in UserDefaults.
enum DomainReminderSettings {
    static let key = "domainExpiryReminders"
    static let shownKey = "domainExpiryRemindersShown"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}

/// Shows `DomainReminders` inside Signet. Signet checks at launch and once a day while it runs
/// (`SignetApp`); a reminder that is due for a name and has not been shown yet goes up as an
/// alert on the main window, once, with Renew (opens the name on Tezos Domains) and OK. Nothing
/// is scheduled and no system notification is used, so every platform behaves the same and no
/// permission is asked for. The alert waits while another sheet or alert is up on the window,
/// so it never lands on top of a half-finished operation. The dashboard lists the names due
/// soon besides. Never used under the test host.
@MainActor
final class DomainReminderService {
    /// One name to remind about: what it is called, when it expires, and whose it is.
    struct OwnedName: Sendable, Hashable, Identifiable {
        let name: String
        let expires: Date
        let owner: String
        var id: String { name }
    }

    /// The one the app uses (never under the test host).
    static let shared = DomainReminderService()

    private let defaults: UserDefaults
    private var presenting = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The reminders now due for `names` and not shown before (the latest one per name).
    func due(_ names: [OwnedName], now: Date = Date()) -> [DomainReminders.Reminder] {
        guard DomainReminderSettings.isOn(defaults), !names.isEmpty else { return [] }
        let shown = Set(defaults.stringArray(forKey: DomainReminderSettings.shownKey) ?? [])
        return DomainReminders.plan(names.map { ($0.name, $0.expires) }, shown: shown, now: now).overdue
    }

    /// Records `reminders` as shown, keeping the record to names still owned.
    func markShown(_ reminders: [DomainReminders.Reminder], owned names: [OwnedName]) {
        var shown = Set(defaults.stringArray(forKey: DomainReminderSettings.shownKey) ?? [])
        shown.formUnion(reminders.map(\.id))
        let live = Set(names.map(\.name))
        defaults.set(Array(shown.filter { id in live.contains { id.hasPrefix("domain-expiry|\($0)|") } }.sorted().suffix(500)),
                     forKey: DomainReminderSettings.shownKey)
    }

    #if canImport(AppKit)
    /// Shows the reminders now due for `names` and not shown before, in one alert, once.
    func deliverDue(_ names: [OwnedName], now: Date = Date()) async {
        await Self.removeOldNotifications()
        let reminders = due(names, now: now)
        guard !reminders.isEmpty, !presenting else { return }
        presenting = true
        defer { presenting = false }
        // Marked shown once the alert is actually up, so a quit before then shows it next time.
        guard let window = await Self.freeMainWindow() else { return }
        markShown(reminders, owned: names)
        let (alert, url) = Self.alert(reminders, names: names)
        await Self.present(alert, opening: url, on: window)
    }

    /// Shows the alert for the soonest-expiring name now, as a test. `false` with no name.
    func showTest(_ names: [OwnedName], now: Date = Date()) async -> Bool {
        guard let soonest = names.filter({ $0.expires > now }).min(by: { $0.expires < $1.expires }) else { return false }
        let all = DomainReminders.reminders(name: soonest.name, expires: soonest.expires)
        guard let reminder = all.first(where: { $0.due > now }) ?? all.last else { return false }
        let (alert, url) = Self.alert([reminder], names: [soonest])
        alert.messageText = "Test: " + alert.messageText
        guard var window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        while let sheet = window.attachedSheet { window = sheet }
        await Self.present(alert, opening: url, on: window)
        return true
    }

    private static func alert(_ reminders: [DomainReminders.Reminder], names: [OwnedName]) -> (NSAlert, URL?) {
        let owners = Dictionary(names.map { ($0.name, $0.owner) }, uniquingKeysWith: { first, _ in first })
        let alert = NSAlert()
        alert.alertStyle = .warning
        if reminders.count == 1, let reminder = reminders.first {
            alert.messageText = reminder.title
            alert.informativeText = reminder.body(owner: owners[reminder.name] ?? "")
            alert.addButton(withTitle: "Renew…")
        } else {
            let sorted = reminders.sorted { $0.expires < $1.expires }
            alert.messageText = "\(sorted.count) of your Tezos Domains names expire soon"
            alert.informativeText = sorted.map { "\($0.name) expires \($0.lead.phrase) (\($0.expires.formatted(date: .abbreviated, time: .omitted)), \(owners[$0.name] ?? ""))" }
                .joined(separator: "\n") + "\n\nRenew them on Tezos Domains to keep them."
            alert.addButton(withTitle: "Open Tezos Domains")
        }
        alert.addButton(withTitle: "OK")
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""
        let url = URL(string: reminders.count == 1 ? "https://app.tezos.domains/domain/\(reminders[0].name)" : "https://app.tezos.domains/")
        return (alert, url)
    }

    private static func present(_ alert: NSAlert, opening url: URL?, on window: NSWindow) async {
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        if response == .alertFirstButtonReturn, let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Signet's main window once nothing is attached to it (no sheet, no alert), checked every
    /// few seconds; `nil` if the task is cancelled first.
    private static func freeMainWindow() async -> NSWindow? {
        while !Task.isCancelled {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }) ?? NSApp.mainWindow,
               window.attachedSheet == nil, window.isVisible {
                return window
            }
            try? await Task.sleep(for: .seconds(3))
        }
        return nil
    }

    /// An earlier development build scheduled macOS notifications ahead; remove any left over.
    private static func removeOldNotifications() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("domain-expiry") }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }
    #else
    /// What the alert says: its title and text, the first button's title and what it opens.
    struct Alert: Sendable {
        var title: String
        var message: String
        let firstButton: String
        let url: URL?
    }

    /// Shows the reminders now due for `names` and not shown before, in one alert, once. Off
    /// the Mac the port waits for its main window (`freeMainWindow`) and shows the alert
    /// (`present`).
    func deliverDue(_ names: [OwnedName], now: Date = Date()) async {
        let reminders = due(names, now: now)
        guard !reminders.isEmpty, !presenting else { return }
        presenting = true
        defer { presenting = false }
        // Marked shown once the alert is actually up, so a quit before then shows it next time.
        guard await Self.freeMainWindow() else { return }
        markShown(reminders, owned: names)
        await Self.present(Self.alert(reminders, names: names), onTop: false)
    }

    /// Shows the alert for the soonest-expiring name now, as a test. `false` with no name.
    func showTest(_ names: [OwnedName], now: Date = Date()) async -> Bool {
        guard let soonest = names.filter({ $0.expires > now }).min(by: { $0.expires < $1.expires }) else { return false }
        let all = DomainReminders.reminders(name: soonest.name, expires: soonest.expires)
        guard let reminder = all.first(where: { $0.due > now }) ?? all.last else { return false }
        var alert = Self.alert([reminder], names: [soonest])
        alert.title = "Test: " + alert.title
        await Self.present(alert, onTop: true)
        return true
    }

    static func alert(_ reminders: [DomainReminders.Reminder], names: [OwnedName]) -> Alert {
        let owners = Dictionary(names.map { ($0.name, $0.owner) }, uniquingKeysWith: { first, _ in first })
        let url = URL(string: reminders.count == 1 ? "https://app.tezos.domains/domain/\(reminders[0].name)" : "https://app.tezos.domains/")
        if reminders.count == 1, let reminder = reminders.first {
            return Alert(title: reminder.title, message: reminder.body(owner: owners[reminder.name] ?? ""),
                         firstButton: "Renew…", url: url)
        }
        let sorted = reminders.sorted { $0.expires < $1.expires }
        return Alert(title: "\(sorted.count) of your Tezos Domains names expire soon",
                     message: sorted.map { "\($0.name) expires \($0.lead.phrase) (\($0.expires.formatted(date: .abbreviated, time: .omitted)), \(owners[$0.name] ?? ""))" }
                         .joined(separator: "\n") + "\n\nRenew them on Tezos Domains to keep them.",
                     firstButton: "Open Tezos Domains", url: url)
    }
    #endif
}
