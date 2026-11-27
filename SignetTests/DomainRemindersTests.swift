import Foundation
import Testing
@testable import Signet

/// Domain expiry reminders: 2 months, 1 month, 2 weeks, 1 week, then daily for the last six
/// days and on the day, at 9:00; the latest one already due is shown once (as an alert in the
/// app), expired names give nothing.
struct DomainRemindersTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }
    static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")!
        return formatter.date(from: text)!
    }
    static let expires = date("2027-11-26T22:33:52Z")

    @Test func theScheduleIsTheAgreedOne() {
        let all = DomainReminders.reminders(name: "mytestdomain.tez", expires: Self.expires, calendar: Self.calendar)
        let days = all.map { Self.calendar.dateComponents([.year, .month, .day, .hour], from: $0.due) }
        #expect(all.map(\.lead.id) == ["2mo", "1mo", "2w", "1w", "6d", "5d", "4d", "3d", "2d", "1d", "0d"])
        #expect(days.map(\.day) == [26, 26, 12, 19, 20, 21, 22, 23, 24, 25, 26])
        #expect(days.map(\.month) == [9, 10, 11, 11, 11, 11, 11, 11, 11, 11, 11])
        #expect(days.allSatisfy { $0.hour == 9 })
        #expect(all[2].title == "mytestdomain.tez expires in 2 weeks" && all[9].title == "mytestdomain.tez expires tomorrow")
        #expect(all.last?.title == "mytestdomain.tez expires today")
        // A name that runs out before 9:00 on its last day is reminded at midnight that day.
        let early = DomainReminders.reminders(name: "x.tez", expires: Self.date("2027-11-26T06:00:00Z"), calendar: Self.calendar)
        #expect(Self.calendar.dateComponents([.hour], from: early.last!.due).hour == 0)
    }

    @Test func thePlanSchedulesWhatIsComingAndShowsWhatIsDueOnce() {
        let names = [(name: "mytestdomain.tez", expires: Self.expires)]
        // Five days before: the 6-day reminder is due, 5d and the rest are still to come.
        let now = Self.date("2027-11-21T12:00:00Z")
        let plan = DomainReminders.plan(names, shown: [], now: now, calendar: Self.calendar)
        #expect(plan.overdue.map(\.lead.id) == ["5d"])
        #expect(plan.upcoming.map(\.lead.id) == ["4d", "3d", "2d", "1d", "0d"])
        // Once shown, it is not shown again.
        #expect(DomainReminders.plan(names, shown: [plan.overdue[0].id], now: now, calendar: Self.calendar).overdue.isEmpty)
        // A renewal gives new reminders (the id carries the expiry).
        let renewed = DomainReminders.reminders(name: "mytestdomain.tez", expires: Self.date("2028-11-26T22:33:52Z"), calendar: Self.calendar)
        #expect(!renewed.map(\.id).contains(plan.overdue[0].id))
        // Expired: nothing. Far off: nothing due yet, everything to come.
        #expect(DomainReminders.plan(names, shown: [], now: Self.date("2027-12-01T00:00:00Z"), calendar: Self.calendar) == ([], []))
        let early = DomainReminders.plan(names, shown: [], now: Self.date("2027-01-01T00:00:00Z"), calendar: Self.calendar)
        #expect(early.overdue.isEmpty && early.upcoming.count == 11)
    }

    @Test func theDashboardListsNamesWithinTwoMonths() {
        #expect(!DomainReminders.isDueSoon(Self.expires, now: Self.date("2027-09-25T12:00:00Z"), calendar: Self.calendar))
        #expect(DomainReminders.isDueSoon(Self.expires, now: Self.date("2027-09-26T10:00:00Z"), calendar: Self.calendar))
        #expect(!DomainReminders.isDueSoon(Self.expires, now: Self.date("2027-11-27T00:00:00Z"), calendar: Self.calendar))
        #expect(DomainReminders.phrase(until: Self.expires, now: Self.date("2027-11-14T08:00:00Z"), calendar: Self.calendar) == "in 12 days")
        #expect(DomainReminders.phrase(until: Self.expires, now: Self.date("2027-11-25T23:00:00Z"), calendar: Self.calendar) == "tomorrow")
        #expect(DomainReminders.phrase(until: Self.expires, now: Self.date("2027-11-26T08:00:00Z"), calendar: Self.calendar) == "today")
    }

    @Test func atMostTheLimitIsScheduledEarliestFirst() {
        let names = (0..<10).map { (name: "n\($0).tez", expires: Self.date("2027-11-26T22:33:52Z").addingTimeInterval(Double($0) * 86_400)) }
        let plan = DomainReminders.plan(names, shown: [], now: Self.date("2027-01-01T00:00:00Z"), calendar: Self.calendar, limit: 60)
        #expect(plan.upcoming.count == 60)
        #expect(zip(plan.upcoming, plan.upcoming.dropFirst()).allSatisfy { $0.due <= $1.due })
    }

    /// The service hands back what is due once; after it is marked shown, nothing until the next
    /// reminder, and names no longer owned drop out of the record. Off means nothing at all.
    @MainActor @Test func dueRemindersAreShownOnce() throws {
        let suite = "DomainRemindersTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = DomainReminderService(defaults: defaults)
        let names = [DomainReminderService.OwnedName(name: "a.tez", expires: Self.expires, owner: "Main"),
                     DomainReminderService.OwnedName(name: "b.tez", expires: Self.expires.addingTimeInterval(400 * 86_400), owner: "Main")]
        let now = Self.date("2027-11-21T12:00:00Z")
        let due = service.due(names, now: now)
        #expect(due.map(\.name) == ["a.tez"])
        service.markShown(due, owned: names)
        #expect(service.due(names, now: now).isEmpty)
        #expect(service.due(names, now: now.addingTimeInterval(86_400)).count == 1)
        service.markShown(due, owned: [names[1]])
        #expect(defaults.stringArray(forKey: DomainReminderSettings.shownKey) == [])
        defaults.set(false, forKey: DomainReminderSettings.key)
        #expect(service.due(names, now: now.addingTimeInterval(86_400)).isEmpty)
    }
}

/// Tezos Domains refuses tz5 and tz6 addresses outright; Signet does not ask about them, so one
/// such account never breaks the reminders, the Domains tab or the dashboard's name.
struct TezosDomainsAddressTests {
    @Test func onlyAddressesTezosDomainsKnowsAreAsked() async throws {
        #expect(TezosDomainsService.supports(Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")))
        #expect(TezosDomainsService.supports(Address("tz4E128TU3t1TdLCJEY4oHg8gZzZNoNBknwh")))
        #expect(TezosDomainsService.supports(Address("KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton")))
        let tz5 = Address("tz5gPthTHipBCx3PBp1asAzdCEJfDFLRPeBS")
        #expect(!TezosDomainsService.supports(tz5))
        // Answered without a request (the endpoint does not exist).
        let service = TezosDomainsService(endpoint: URL(string: "https://offline.invalid/graphql")!)
        #expect(try await service.domains(of: tz5).isEmpty)
        #expect(try await service.reverseName(for: tz5) == nil)
    }
}
