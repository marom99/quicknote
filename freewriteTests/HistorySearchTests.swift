import Foundation
import Testing
@testable import freewrite

struct HistorySearchTests {
    @Test func emptyOrBlankQueryMatchesEverything() {
        #expect(HistorySearch.matches(query: "", title: "Anything", body: "at all"))
        #expect(HistorySearch.matches(query: "   \n", title: "", body: ""))
    }

    @Test func matchesTitle() {
        #expect(HistorySearch.matches(query: "launch", title: "Ideas for the launch", body: ""))
    }

    @Test func matchesBodyBeyondTitle() {
        let body = "Ideas for the launch\nCall the printer about the poster"
        #expect(HistorySearch.matches(query: "printer", title: "Ideas for the launch", body: body))
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(HistorySearch.matches(query: "CAFE", title: "", body: "Met at the café"))
        #expect(HistorySearch.matches(query: "Résumé", title: "update resume", body: ""))
    }

    @Test func everyTermMustMatchTitleOrBody() {
        #expect(HistorySearch.matches(query: "launch poster", title: "Launch", body: "the poster"))
        #expect(!HistorySearch.matches(query: "launch budget", title: "Launch", body: "the poster"))
    }

    @Test func noMatchReturnsFalse() {
        #expect(!HistorySearch.matches(query: "zebra", title: "Morning pages", body: "coffee"))
    }

    @Test func filterKeepsOrderOfMatches() {
        let notes = [("A", "apple pie"), ("B", "banana"), ("C", "apple tart")]
        let result = HistorySearch.filter(notes, query: "apple", title: { $0.0 }, body: { $0.1 })
        #expect(result.map(\.0) == ["A", "C"])
    }

    @Test func filterWithEmptyQueryReturnsAll() {
        let notes = ["one", "two"]
        #expect(HistorySearch.filter(notes, query: " ", title: { $0 }, body: { $0 }) == notes)
    }
}
