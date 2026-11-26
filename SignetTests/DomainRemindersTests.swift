import Foundation
import Testing
@testable import Signet

/// Domain expiry reminders: 2 months, 1 month, 2 weeks, 1 week, then daily for the last six
/// days and on the day, at 9:00; what is still to come is scheduled, the latest one already due
/// is shown once, expired names give nothing.
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

    @Test func atMostTheLimitIsScheduledEarliestFirst() {
        let names = (0..<10).map { (name: "n\($0).tez", expires: Self.date("2027-11-26T22:33:52Z").addingTimeInterval(Double($0) * 86_400)) }
        let plan = DomainReminders.plan(names, shown: [], now: Self.date("2027-01-01T00:00:00Z"), calendar: Self.calendar, limit: 60)
        #expect(plan.upcoming.count == 60)
        #expect(zip(plan.upcoming, plan.upcoming.dropFirst()).allSatisfy { $0.due <= $1.due })
    }
}
