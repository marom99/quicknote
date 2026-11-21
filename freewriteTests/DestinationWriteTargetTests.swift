import Foundation
import Testing
@testable import freewrite

struct DestinationWriteTargetTests {
    @Test func dailyAnchorIsStartOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 15, minute: 30))!
        let anchor = DestinationWriteTarget.rollingAnchorDate(for: .daily, now: now, calendar: calendar)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: anchor)
        #expect(comps.year == 2026)
        #expect(comps.month == 8)
        #expect(comps.day == 10)
        #expect(comps.hour == 0)
        #expect(comps.minute == 0)
    }

    @Test func weeklyAnchorIsISOWeekStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-08-10 is a Monday → ISO week start is that day.
        let monday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        let monAnchor = DestinationWriteTarget.rollingAnchorDate(for: .weekly, now: monday, calendar: calendar)
        #expect(calendar.component(.day, from: monAnchor) == 10)

        // Wednesday should still anchor to Monday of that ISO week.
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))!
        let wedAnchor = DestinationWriteTarget.rollingAnchorDate(for: .weekly, now: wednesday, calendar: calendar)
        #expect(calendar.component(.day, from: wedAnchor) == 10)
    }

    @Test func monthlyAnchorIsFirstOfMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!
        let anchor = DestinationWriteTarget.rollingAnchorDate(for: .monthly, now: now, calendar: calendar)
        let comps = calendar.dateComponents([.year, .month, .day], from: anchor)
        #expect(comps.year == 2026)
        #expect(comps.month == 8)
        #expect(comps.day == 1)
    }

    @Test func defaultFormatsProduceExpectedBasenames() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!

        let daily = DestinationWriteTarget.formattedBasename(
            format: RollingPeriod.daily.defaultFilenameFormat,
            period: .daily,
            now: now,
            calendar: calendar
        )
        #expect(daily == "2026-08-10")

        let monthly = DestinationWriteTarget.formattedBasename(
            format: RollingPeriod.monthly.defaultFilenameFormat,
            period: .monthly,
            now: now,
            calendar: calendar
        )
        #expect(monthly == "2026-08")

        let weekly = DestinationWriteTarget.formattedBasename(
            format: RollingPeriod.weekly.defaultFilenameFormat,
            period: .weekly,
            now: now,
            calendar: calendar
        )
        #expect(weekly == "2026-W33")
    }

    @Test func rejectsPathSeparatorsAndEmptyPatterns() {
        #expect(DestinationWriteTarget.isValidBasenamePattern("") == false)
        #expect(DestinationWriteTarget.isValidBasenamePattern("  ") == false)
        #expect(DestinationWriteTarget.isValidBasenamePattern("notes/daily") == false)
        #expect(DestinationWriteTarget.isValidBasenamePattern("notes\\daily") == false)
        #expect(DestinationWriteTarget.isValidBasenamePattern("yyyy-MM-dd") == true)

        #expect(DestinationWriteTarget.validatedBasename("") == nil)
        #expect(DestinationWriteTarget.validatedBasename("../evil") == nil)
        #expect(DestinationWriteTarget.validatedBasename("journal.md") == "journal")
        #expect(DestinationWriteTarget.validatedBasename("journal") == "journal")
    }

    @Test func stableUUIDIsDeterministicAndDiffersByPath() {
        let a1 = DestinationWriteTarget.stableUUID(fromPath: "/tmp/journal/2026-08-10.md")
        let a2 = DestinationWriteTarget.stableUUID(fromPath: "/tmp/journal/2026-08-10.md")
        let b = DestinationWriteTarget.stableUUID(fromPath: "/tmp/journal/2026-08-11.md")
        #expect(a1 == a2)
        #expect(a1 != b)
    }

    @Test func sessionSeparatorMatchesContract() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 14, minute: 5))!
        let separator = DestinationWriteTarget.sessionSeparator(at: date, calendar: calendar)
        #expect(separator == "\n---\n2026-08-10 14:05\n")
    }

    @Test func resolveRollingCreatesMissingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freewrite-write-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!

        let destination = SaveDestination(
            id: UUID(),
            displayName: "Test",
            isDefault: false,
            saveMode: .rolling,
            rollingPeriod: .daily,
            filenameFormat: "yyyy-MM-dd"
        )

        let resolved = DestinationWriteTarget.resolve(
            for: destination,
            documentsURL: tempDir,
            now: now,
            calendar: calendar,
            createIfMissing: true
        )

        #expect(resolved != nil)
        #expect(resolved?.filename == "2026-08-10.md")
        #expect(resolved?.didCreate == true)
        #expect(resolved?.fileExists == true)
        #expect(FileManager.default.fileExists(atPath: resolved!.fileURL.path))

        // Second resolve should not recreate.
        let again = DestinationWriteTarget.resolve(
            for: destination,
            documentsURL: tempDir,
            now: now,
            calendar: calendar,
            createIfMissing: true
        )
        #expect(again?.didCreate == false)
        #expect(again?.entryId == resolved?.entryId)
    }

    @Test func resolveExistingSoftFailsWithoutFilename() {
        let destination = SaveDestination(
            id: UUID(),
            displayName: "Test",
            isDefault: false,
            saveMode: .existing
        )
        let url = FileManager.default.temporaryDirectory
        let resolved = DestinationWriteTarget.resolve(
            for: destination,
            documentsURL: url,
            createIfMissing: false
        )
        #expect(resolved == nil)
    }

    @Test func resolveExistingMissingFileDoesNotCreate() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freewrite-existing-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let destination = SaveDestination(
            id: UUID(),
            displayName: "Test",
            isDefault: false,
            saveMode: .existing,
            existingNoteFilename: "gone.md"
        )
        let resolved = DestinationWriteTarget.resolve(
            for: destination,
            documentsURL: tempDir,
            createIfMissing: false
        )
        #expect(resolved != nil)
        #expect(resolved?.filename == "gone.md")
        #expect(resolved?.fileExists == false)
        #expect(resolved?.didCreate == false)
        #expect(!FileManager.default.fileExists(atPath: resolved!.fileURL.path))
    }

    @Test func newNoteResolveReturnsNil() {
        let destination = SaveDestination.makeDefault()
        let resolved = DestinationWriteTarget.resolve(
            for: destination,
            documentsURL: FileManager.default.temporaryDirectory
        )
        #expect(resolved == nil)
    }

    @Test func dateCaptureBasenameUsesContractFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10, minute: 30, second: 45))!
        let basename = DestinationWriteTarget.dateCaptureBasename(now: now, calendar: calendar)
        #expect(basename == "2026-08-12-10-30-45")
    }

    @Test func sanitizedTitleBasenameFromFirstParagraph() {
        let content = "Meeting notes about launch\n\nSecond paragraph ignored."
        let basename = DestinationWriteTarget.sanitizedTitleBasename(from: content)
        #expect(basename == "Meeting notes about launch")
    }

    @Test func sanitizedTitleBasenameStripsInvalidCharacters() {
        let content = "Notes: launch / planning?"
        let basename = DestinationWriteTarget.sanitizedTitleBasename(from: content)
        #expect(basename == "Notes launch  planning")
    }

    @Test func captureDraftFilenameIsHiddenDraft() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let filename = DestinationWriteTarget.captureDraftFilename(captureId: id)
        #expect(filename == ".quicknote-capture-00000000-0000-0000-0000-000000000001.md")
        #expect(DestinationWriteTarget.isCaptureDraftFilename(filename))
    }

    @Test func uniqueMarkdownFilenameAvoidsCollisions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freewrite-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "first".write(
            to: tempDir.appendingPathComponent("note.md"),
            atomically: true,
            encoding: .utf8
        )

        let unique = DestinationWriteTarget.uniqueMarkdownFilename(
            preferredBasename: "note",
            documentsURL: tempDir
        )
        #expect(unique == "note-2.md")
    }
}
