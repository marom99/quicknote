import Foundation

/// Pure helpers for the History sidebar row: a first-line title and a date-plus-time label.
enum HistoryRowFormatting {
    static let maxTitleLength = 120

    /// First non-blank line of a note, trimmed, with a leading Markdown heading marker removed.
    static func title(from content: String) -> String {
        guard let firstLine = content
            .split(whereSeparator: \.isNewline)
            .lazy
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else {
            return ""
        }

        var title = firstLine
        if let headingRange = title.range(of: "^#{1,6}\\s+", options: .regularExpression) {
            title.removeSubrange(headingRange)
        }
        title = title.trimmingCharacters(in: .whitespaces)

        if title.count > maxTitleLength {
            return String(title.prefix(maxTitleLength)) + "…"
        }
        return title
    }

    /// Day plus time of day, e.g. "Feb 20, 3:30 PM" (localized ordering and clock style).
    static func timestamp(
        from date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        return formatter.string(from: date)
    }
}
