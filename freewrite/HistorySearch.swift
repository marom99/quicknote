import Foundation

/// Pure History search: every whitespace-separated term must appear in a note's title or body,
/// ignoring case and diacritics. An empty query matches every note.
enum HistorySearch {
    private static let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func terms(from query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func matches(query: String, title: String, body: String) -> Bool {
        terms(from: query).allSatisfy { term in
            title.range(of: term, options: compareOptions) != nil
                || body.range(of: term, options: compareOptions) != nil
        }
    }

    static func filter<Item>(
        _ items: [Item],
        query: String,
        title: (Item) -> String,
        body: (Item) -> String
    ) -> [Item] {
        guard !terms(from: query).isEmpty else { return items }
        return items.filter { matches(query: query, title: title($0), body: body($0)) }
    }
}
