import Foundation

/// When to remind the user that a Tezos Domains name they own is about to expire: 2 months,
/// 1 month, 2 weeks and 1 week before, then every day for the last 6 days and on the day
/// itself, each at 9:00 local time. Pure, so the schedule can be tested.
enum DomainReminders {
    /// How far before the expiry a reminder comes, and how it is said.
    struct Lead: Hashable, Sendable {
        let id: String
        let component: Calendar.Component
        let value: Int
        let phrase: String
    }

    static let leads: [Lead] = [
        Lead(id: "2mo", component: .month, value: 2, phrase: "in 2 months"),
        Lead(id: "1mo", component: .month, value: 1, phrase: "in 1 month"),
        Lead(id: "2w", component: .day, value: 14, phrase: "in 2 weeks"),
        Lead(id: "1w", component: .day, value: 7, phrase: "in 1 week"),
    ] + (2...6).reversed().map { Lead(id: "\($0)d", component: .day, value: $0, phrase: "in \($0) days") }
      + [Lead(id: "1d", component: .day, value: 1, phrase: "tomorrow"), Lead(id: "0d", component: .day, value: 0, phrase: "today")]

    /// One notification: which name, which lead, when it is due and what it says.
    struct Reminder: Hashable, Sendable {
        let name: String
        let expires: Date
        let lead: Lead
        let due: Date
        /// Stable across scans while the expiry stays the same; a renewal gives new ones.
        var id: String { "domain-expiry|\(name)|\(Int(expires.timeIntervalSince1970))|\(lead.id)" }
        var title: String { "\(name) expires \(lead.phrase)" }
        func body(owner: String) -> String {
            "Your Tezos Domains name \(name), held by \(owner), expires on \(expires.formatted(date: .long, time: .omitted)). Renew it on Tezos Domains to keep it."
        }
    }

    /// Every reminder for a name expiring at `expires`, in date order.
    static func reminders(name: String, expires: Date, calendar: Calendar = .current, hour: Int = 9) -> [Reminder] {
        let day = calendar.startOfDay(for: expires)
        return leads.compactMap { lead in
            guard let date = calendar.date(byAdding: lead.component, value: -lead.value, to: day),
                  var due = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) else { return nil }
            // A name that expires before 9:00 on its last day is reminded at midnight that day.
            if lead.value == 0, due > expires { due = day }
            return Reminder(name: name, expires: expires, lead: lead, due: due)
        }
        .sorted { $0.due < $1.due }
    }

    /// What to do now for the names: the reminders still to come (to schedule, earliest
    /// first, at most `limit`), and the latest one already due but not yet shown (to show at
    /// once, so a name first seen a few days before it expires is still mentioned). Expired
    /// names give nothing.
    static func plan(_ names: [(name: String, expires: Date)], shown: Set<String>, now: Date, calendar: Calendar = .current, limit: Int = 60)
        -> (upcoming: [Reminder], overdue: [Reminder]) {
        var upcoming: [Reminder] = []
        var overdue: [Reminder] = []
        for entry in names where entry.expires > now {
            let all = reminders(name: entry.name, expires: entry.expires, calendar: calendar)
            upcoming += all.filter { $0.due > now }
            if let latest = all.last(where: { $0.due <= now }), !shown.contains(latest.id) { overdue.append(latest) }
        }
        return (Array(upcoming.sorted { $0.due < $1.due }.prefix(limit)), overdue)
    }
}
