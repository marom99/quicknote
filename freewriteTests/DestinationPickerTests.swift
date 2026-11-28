import Foundation
import Testing
@testable import freewrite

struct DestinationPickerTests {
    private let quickNote = DestinationPickerItem(id: UUID(), name: "Quick Note")
    private let fieldNotes = DestinationPickerItem(id: UUID(), name: "Field Notes")
    private let cafe = DestinationPickerItem(id: UUID(), name: "Café Journal")

    private var all: [DestinationPickerItem] { [quickNote, fieldNotes, cafe] }

    @Test func emptyQueryKeepsEveryDestination() {
        #expect(DestinationPickerFilter.filter(all, query: "") == all)
        #expect(DestinationPickerFilter.filter(all, query: "   ") == all)
    }

    @Test func queryMatchesPartOfTheName() {
        #expect(DestinationPickerFilter.filter(all, query: "note") == [quickNote, fieldNotes])
    }

    @Test func queryIgnoresCaseAndDiacritics() {
        #expect(DestinationPickerFilter.filter(all, query: "CAFE").map(\.name) == ["Café Journal"])
        #expect(DestinationPickerFilter.filter(all, query: "JOURNAL").map(\.name) == ["Café Journal"])
    }

    @Test func everyTermMustAppearInTheName() {
        #expect(DestinationPickerFilter.filter(all, query: "field notes").map(\.name) == ["Field Notes"])
        #expect(DestinationPickerFilter.filter(all, query: "field journal").isEmpty)
    }

    @Test func noMatchReturnsAnEmptyList() {
        #expect(DestinationPickerFilter.filter(all, query: "zebra").isEmpty)
    }

    @Test func highlightStartsOnTheFirstVisibleDestination() {
        var selection = DestinationPickerSelection()
        selection.highlightFirst(in: all)
        #expect(selection.highlighted(in: all) == quickNote)
    }

    @Test func highlightStartsOnTheFirstMatchOfAFilteredList() {
        var selection = DestinationPickerSelection()
        selection.highlightFirst(in: DestinationPickerFilter.filter(all, query: "journal"))
        #expect(selection.highlightedID == cafe.id)
    }

    @Test func moveDownAndUpWalkTheList() {
        var selection = DestinationPickerSelection()
        selection.highlightFirst(in: all)

        selection.move(by: 1, in: all)
        #expect(selection.highlightedID == fieldNotes.id)

        selection.move(by: 1, in: all)
        selection.move(by: 1, in: all)
        #expect(selection.highlightedID == cafe.id, "moving past the last row clamps instead of wrapping")

        selection.move(by: -1, in: all)
        #expect(selection.highlightedID == fieldNotes.id)
    }

    @Test func moveUpFromTheFirstRowClamps() {
        var selection = DestinationPickerSelection()
        selection.highlightFirst(in: all)
        selection.move(by: -1, in: all)
        #expect(selection.highlightedID == quickNote.id)
    }

    @Test func moveWithoutAHighlightPicksTheNearerEnd() {
        var selection = DestinationPickerSelection()
        selection.highlight(nil)

        selection.move(by: 1, in: all)
        #expect(selection.highlightedID == quickNote.id)

        selection.highlight(nil)
        selection.move(by: -1, in: all)
        #expect(selection.highlightedID == cafe.id)
    }

    @Test func moveInAnEmptyListClearsTheHighlight() {
        var selection = DestinationPickerSelection()
        selection.highlightFirst(in: all)
        selection.move(by: 1, in: [])
        #expect(selection.highlightedID == nil)
        #expect(selection.highlighted(in: []) == nil)
    }

    @Test func highlightFallsBackWhenTheHighlightedDestinationIsFilteredOut() {
        var selection = DestinationPickerSelection()
        selection.highlightFirst(in: all)
        selection.move(by: 1, in: all)

        let filtered = DestinationPickerFilter.filter(all, query: "quick")
        #expect(selection.highlighted(in: filtered) == nil)

        selection.highlightFirst(in: filtered)
        #expect(selection.highlighted(in: filtered) == quickNote)
    }
}
