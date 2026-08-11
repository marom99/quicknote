import CryptoKit
import Foundation

/// Pure helpers for resolving per-destination write targets (rolling / existing modes).
enum DestinationWriteTarget {
    struct ResolvedTarget: Equatable {
        let fileURL: URL
        let filename: String
        let entryId: UUID
        let displayDate: String
        let didCreate: Bool
        let fileExists: Bool
    }

    // MARK: - Anchor dates

    /// Period-start date used when formatting a rolling basename.
    static func rollingAnchorDate(
        for period: RollingPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        switch period {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            let comps = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            return iso.date(from: comps).map { iso.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
        case .monthly:
            let comps = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: comps).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
        }
    }

    // MARK: - Basename formatting

    /// Formats an anchor date with a DateFormatter pattern. Returns nil if invalid.
    static func formattedBasename(
        format: String,
        period: RollingPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        let trimmed = format.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBasenamePattern(trimmed) else { return nil }

        let anchor = rollingAnchorDate(for: period, now: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if period == .weekly {
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            formatter.calendar = iso
        } else {
            formatter.calendar = calendar
        }
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = trimmed
        let raw = formatter.string(from: anchor)
        return validatedBasename(raw)
    }

    /// Rejects empty basenames and path separators (no subfolders in v1).
    static func isValidBasenamePattern(_ pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("/") || trimmed.contains("\\") { return false }
        if trimmed.contains("..") { return false }
        return true
    }

    /// Validates a concrete basename (no directories, not empty). Strips a trailing `.md` for reuse.
    static func validatedBasename(_ name: String) -> String? {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") || trimmed.contains("\\") { return nil }
        if trimmed == "." || trimmed == ".." || trimmed.contains("..") { return nil }
        if trimmed.hasSuffix(".md") {
            trimmed = String(trimmed.dropLast(3))
        }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") || trimmed.contains("\\") { return nil }
        return trimmed
    }

    static func markdownFilename(fromBasename basename: String) -> String {
        if basename.lowercased().hasSuffix(".md") {
            return basename
        }
        return "\(basename).md"
    }

    // MARK: - Identity & separator

    /// Deterministic UUID derived from a path string (stable across launches).
    static func stableUUID(fromPath path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        // RFC 4122 version 5-ish: set version nibble to 5 and variant to 10.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Session separator appended on New Entry in Rolling / Existing modes.
    static func sessionSeparator(at date: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\n---\n\(formatter.string(from: date))\n"
    }

    static func displayDateString(from date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    // MARK: - Resolve write target

    /// Resolves the file the editor should bind to for Rolling / Existing modes.
    /// Creates the file when missing (except Existing soft-fail when no filename is configured).
    static func resolve(
        for destination: SaveDestination,
        documentsURL: URL,
        now: Date = Date(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        createIfMissing: Bool = true
    ) -> ResolvedTarget? {
        switch destination.saveMode {
        case .newNote:
            return nil
        case .rolling:
            guard let basename = formattedBasename(
                format: destination.filenameFormat,
                period: destination.rollingPeriod,
                now: now,
                calendar: calendar
            ) else {
                return nil
            }
            return resolveFilename(
                markdownFilename(fromBasename: basename),
                documentsURL: documentsURL,
                now: now,
                calendar: calendar,
                fileManager: fileManager,
                createIfMissing: createIfMissing
            )
        case .existing:
            guard let configured = destination.existingNoteFilename,
                  let basename = validatedBasename(configured) else {
                return nil
            }
            return resolveFilename(
                markdownFilename(fromBasename: basename),
                documentsURL: documentsURL,
                now: now,
                calendar: calendar,
                fileManager: fileManager,
                createIfMissing: createIfMissing
            )
        }
    }

    private static func resolveFilename(
        _ filename: String,
        documentsURL: URL,
        now: Date,
        calendar: Calendar,
        fileManager: FileManager,
        createIfMissing: Bool
    ) -> ResolvedTarget? {
        let fileURL = documentsURL.appendingPathComponent(filename)
        let pathKey = fileURL.standardizedFileURL.path
        let entryId = stableUUID(fromPath: pathKey)
        let exists = fileManager.fileExists(atPath: fileURL.path)
        var didCreate = false

        if !exists && createIfMissing {
            do {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
                didCreate = true
            } catch {
                return ResolvedTarget(
                    fileURL: fileURL,
                    filename: filename,
                    entryId: entryId,
                    displayDate: displayDateString(from: now, calendar: calendar),
                    didCreate: false,
                    fileExists: false
                )
            }
        }

        let displayDate: String
        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let mod = attrs[.modificationDate] as? Date {
            displayDate = displayDateString(from: mod, calendar: calendar)
        } else {
            displayDate = displayDateString(from: now, calendar: calendar)
        }

        return ResolvedTarget(
            fileURL: fileURL,
            filename: filename,
            entryId: entryId,
            displayDate: displayDate,
            didCreate: didCreate,
            fileExists: exists || didCreate
        )
    }
}
