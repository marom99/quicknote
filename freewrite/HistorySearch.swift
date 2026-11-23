import Foundation

struct HistoryResult: Identifiable {
    struct ID: Hashable {
        let destination: UUID
        let filename: String
    }

    let destinationID: UUID
    let destinationLabel: String
    let entry: HumanEntry

    var id: ID { ID(destination: destinationID, filename: entry.filename) }
}

/// Pure History search: every whitespace-separated term must appear in a note's title or body,
/// ignoring case and diacritics. An empty query matches every note.
enum HistorySearch {
    private static let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func terms(from query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func matches(query: String, title: String, body: String) -> Bool {
        matches(terms: terms(from: query), title: title, body: body)
    }

    private static func matches(terms: [String], title: String, body: String) -> Bool {
        terms.allSatisfy { term in
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
        let searchTerms = terms(from: query)
        guard !searchTerms.isEmpty else { return items }
        return items.filter { matches(terms: searchTerms, title: title($0), body: body($0)) }
    }

    static func snippet(query: String, body: String, droppingTitleLine: Bool) -> String? {
        let searchTerms = terms(from: query)
        guard !searchTerms.isEmpty else { return nil }
        let lines = body.split(whereSeparator: \.isNewline)
            .drop(while: { $0.allSatisfy(\.isWhitespace) })
        let content = (droppingTitleLine ? lines.dropFirst() : lines).joined(separator: " ")
        let normalized = content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let match = searchTerms.compactMap({ normalized.range(of: $0, options: compareOptions) })
            .min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let start = normalized.index(match.lowerBound, offsetBy: -18, limitedBy: normalized.startIndex)
            ?? normalized.startIndex
        let end = normalized.index(match.upperBound, offsetBy: 42, limitedBy: normalized.endIndex)
            ?? normalized.endIndex
        return (start == normalized.startIndex ? "" : "…") + normalized[start..<end]
            + (end == normalized.endIndex ? "" : "…")
    }
}
