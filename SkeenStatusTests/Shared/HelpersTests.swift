import Foundation
import Testing

@testable import SkeenStatus

struct HelpersTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let locale = Locale(identifier: "en_GB")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func chartTimeShowsTheDayForOlderPoints() {
        let today = chartTimeString(now.addingTimeInterval(-600), bucketWidth: 600, now: now, calendar: calendar, locale: locale)
        let older = chartTimeString(now.addingTimeInterval(-3 * 86_400), bucketWidth: 600, now: now, calendar: calendar, locale: locale)
        #expect(!today.contains("Jan"))
        #expect(older.contains("Jan"))
        #expect(older.contains(":"))
    }

    @Test func chartTimeShowsSecondsOnlyForShortBuckets() {
        let date = now.addingTimeInterval(-60)
        let short = chartTimeString(date, bucketWidth: 2, now: now, calendar: calendar, locale: locale)
        let long = chartTimeString(date, bucketWidth: 60, now: now, calendar: calendar, locale: locale)
        #expect(short.split(separator: ":").count == 3)
        #expect(long.split(separator: ":").count == 2)
    }
}
