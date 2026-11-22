import Foundation
import AppKit
import SwiftUI
import Testing
@testable import freewrite

struct DestinationWriteTargetTests {
    @Test @MainActor func mergedEditCaretRequestMovesToEndOnlyOnce() {
        let coordinator = FreewriteTextEditor.Coordinator(text: .constant(""), onScrollMetricsChange: { _ in })
        let textView = NSTextView()
        coordinator.textView = textView
        textView.string = "Restored note\nTyped text 📝"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(!coordinator.applyCaretEndRequest(nil))
        #expect(textView.selectedRange().location == 1)
        let request = UUID()
        #expect(coordinator.applyCaretEndRequest(request))
        #expect(textView.selectedRange() == NSRange(location: (textView.string as NSString).length, length: 0))
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(!coordinator.applyCaretEndRequest(request))
        #expect(textView.selectedRange().location == 2)
        textView.string = ""
        coordinator.applyCaretEndRequest(UUID())
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test(arguments: [DestinationSaveMode.existing, .rolling])
    func directoryAtTargetPathIsRejected(mode: DestinationSaveMode) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = SaveDestination(
            id: UUID(), displayName: "Test", isDefault: false,
            saveMode: mode, existingNoteFilename: "journal.md"
        )
        let now = Date()
        let target = try #require(DestinationWriteTarget.resolve(
            for: destination, documentsURL: directory, now: now, createIfMissing: false
        ))
        try FileManager.default.createDirectory(at: target.fileURL, withIntermediateDirectories: false)
        let child = target.fileURL.appendingPathComponent("keep.txt")
        try "keep".write(to: child, atomically: true, encoding: .utf8)
        for createIfMissing in [true, false] {
            #expect(DestinationWriteTarget.resolve(
                for: destination, documentsURL: directory, now: now, createIfMissing: createIfMissing
            ) == nil)
        }
        #expect(DestinationWriteTarget.resolveForUnboundEdit(
            content: "text", destination: destination, documentsURL: directory, now: now
        ) == nil)
        #expect(try String(contentsOf: child, encoding: .utf8) == "keep")
    }

    @Test func unboundEditPreservesRestoredContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = SaveDestination(
            id: UUID(), displayName: "Test", isDefault: false,
            saveMode: .existing, existingNoteFilename: "journal.md"
        )
        let target = try #require(DestinationWriteTarget.resolveForUnboundEdit(
            content: "new text", destination: destination, documentsURL: directory
        ))
        #expect(try DestinationWriteTarget.contentForUnboundEdit("new text", target: target) == "new text")
        for restored in ["restored text", "restored text\n", " \n"] {
            try restored.write(to: target.fileURL, atomically: true, encoding: .utf8)
            let merged = try DestinationWriteTarget.contentForUnboundEdit("new text", target: target)
            #expect(merged == restored + (restored.hasSuffix("\n") ? "" : "\n") + "new text")
            #expect(try String(contentsOf: target.fileURL, encoding: .utf8) == restored)
        }
        try FileManager.default.removeItem(at: target.fileURL)
        #expect(throws: (any Error).self) {
            try DestinationWriteTarget.contentForUnboundEdit("new text", target: target)
        }
    }

    @Test(arguments: [DestinationSaveMode.existing, .rolling])
    func unboundEditRecreatesDeletedTarget(mode: DestinationSaveMode) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = SaveDestination(
            id: UUID(), displayName: "Test", isDefault: false,
            saveMode: mode, existingNoteFilename: "journal.md"
        )
        let now = Date()
        let original = try #require(DestinationWriteTarget.resolve(
            for: destination, documentsURL: directory, now: now
        ))
        try "old note".write(to: original.fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: original.fileURL)

        for content in ["", " \n\t"] {
            #expect(DestinationWriteTarget.resolveForUnboundEdit(
                content: content, destination: destination, documentsURL: directory, now: now
            ) == nil)
            #expect(!FileManager.default.fileExists(atPath: original.fileURL.path))
        }
        let recreated = try #require(DestinationWriteTarget.resolveForUnboundEdit(
            content: "new note", destination: destination, documentsURL: directory, now: now
        ))
        #expect(recreated.filename == original.filename)
        #expect(recreated.entryId == original.entryId)
        #expect(recreated.didCreate)
        try "new note".write(to: recreated.fileURL, atomically: true, encoding: .utf8)
        let again = try #require(DestinationWriteTarget.resolveForUnboundEdit(
            content: "more text", destination: destination, documentsURL: directory, now: now
        ))
        #expect(!again.didCreate)
        #expect(try String(contentsOf: again.fileURL, encoding: .utf8) == "new note")
    }

    @Test func unboundEditRejectsInvalidAndUnavailableTargets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = SaveDestination(
            id: UUID(), displayName: "Test", isDefault: false,
            saveMode: .existing, existingNoteFilename: "journal.md"
        )
        #expect(DestinationWriteTarget.resolveForUnboundEdit(
            content: "text", destination: destination, documentsURL: directory
        ) == nil)
        var invalid = destination
        for filename in [nil, "../journal.md"] as [String?] {
            invalid.existingNoteFilename = filename
            #expect(DestinationWriteTarget.resolveForUnboundEdit(
                content: "text", destination: invalid, documentsURL: directory
            ) == nil)
        }
        #expect(DestinationWriteTarget.resolveForUnboundEdit(
            content: "text", destination: .makeDefault(), documentsURL: directory
        ) == nil)
    }

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
