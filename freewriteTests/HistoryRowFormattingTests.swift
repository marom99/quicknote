import Foundation
import Testing
@testable import freewrite

struct HistoryRowFormattingTests {
    @Test func titleIsFirstLineOnly() {
        let content = "Ideas for the launch\nSecond line with more detail\nThird"
        #expect(HistoryRowFormatting.title(from: content) == "Ideas for the launch")
    }

    @Test func titleSkipsLeadingBlankLinesAndTrims() {
        #expect(HistoryRowFormatting.title(from: "\n\n   \n  Morning pages  \nrest") == "Morning pages")
    }

    @Test func titleIsNotCutAtThirtyCharacters() {
        let line = "This first line is clearly longer than thirty characters"
        #expect(HistoryRowFormatting.title(from: line + "\nmore") == line)
    }

    @Test func titleStripsMarkdownHeadingMarker() {
        #expect(HistoryRowFormatting.title(from: "## Weekly review\nbody") == "Weekly review")
        #expect(HistoryRowFormatting.title(from: "#hashtag stays") == "#hashtag stays")
    }

    @Test func titleHandlesCRLF() {
        #expect(HistoryRowFormatting.title(from: "First\r\nSecond") == "First")
    }

    @Test func titleIsEmptyForBlankContent() {
        #expect(HistoryRowFormatting.title(from: "") == "")
        #expect(HistoryRowFormatting.title(from: " \n\t\n ") == "")
    }

    @Test func titleIsCappedForVeryLongLines() {
        let title = HistoryRowFormatting.title(from: String(repeating: "a", count: 500))
        #expect(title.count == HistoryRowFormatting.maxTitleLength + 1)
        #expect(title.hasSuffix("…"))
    }

    @Test func timestampIncludesDayAndTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 15, minute: 7))!
        let label = HistoryRowFormatting.timestamp(
            from: date,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        #expect(label.contains("Feb 20"))
        #expect(label.contains("3:07"))
        #expect(label.contains("PM"))
    }

    @Test func timestampUses24HourClockWhenLocaleDoes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 15, minute: 7))!
        let label = HistoryRowFormatting.timestamp(
            from: date,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        #expect(label.contains("15:07"))
    }
}
