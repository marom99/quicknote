import Foundation
import AppKit
import SwiftUI
import Testing
@testable import freewrite

struct DestinationWriteTargetTests {
    @Test func existingNoteChoicesListOnlyVisibleRootMarkdownNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Videos/folder.md"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let videoBase = "[6910BBDE-75FC-415C-ABB9-C76644B037B2]-[2026-02-20-08-01-04]"
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Videos/\(videoBase)"),
            withIntermediateDirectories: true
        )
        try "x".write(
            to: directory.appendingPathComponent("Videos/\(videoBase)/\(videoBase).mov"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: directory.appendingPathComponent("Videos/Uppercase.mov"))
        for name in ["journal.md", "Ideas 10.md", "Ideas 2.MD", "notes.txt", ".hidden.md",
                     "twice.md.md", " leading.md", "\(videoBase).md", "Uppercase.MD",
                     DestinationWriteTarget.captureDraftFilename(captureId: UUID())] {
            try "x".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try "x".write(to: directory.appendingPathComponent("Videos/nested.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("dir.md"), withIntermediateDirectories: true)

        #expect(DestinationWriteTarget.existingNoteChoices(in: directory) == ["Ideas 2.MD", "Ideas 10.md", "journal.md"])
        #expect(DestinationWriteTarget.existingNoteChoices(in: directory.appendingPathComponent("missing")).isEmpty)
    }

    @Test func existingNoteFilenameFromInputRequiresRootBasename() {
        #expect(DestinationWriteTarget.existingNoteFilename(fromInput: " journal ") == "journal.md")
        #expect(DestinationWriteTarget.existingNoteFilename(fromInput: "journal.md") == "journal.md")
        #expect(DestinationWriteTarget.existingNoteFilename(fromInput: "") == nil)
        #expect(DestinationWriteTarget.existingNoteFilename(fromInput: "a/b.md") == nil)
        #expect(DestinationWriteTarget.existingNoteFilename(fromInput: "..") == nil)
    }

    @Test func recoveryProtectsAllWindowsLiveDraftsUntilRegistrationEnds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let otherDirectory = directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filename = DestinationWriteTarget.captureDraftFilename(captureId: UUID())
        let live = directory.appendingPathComponent(filename)
        let emptyLive = directory.appendingPathComponent(DestinationWriteTarget.captureDraftFilename(captureId: UUID()))
        let other = otherDirectory.appendingPathComponent(filename)
        try "Window A title".write(to: live, atomically: true, encoding: .utf8)
        try " \n".write(to: emptyLive, atomically: true, encoding: .utf8)
        try "Other destination title".write(to: other, atomically: true, encoding: .utf8)
        var registrations = [
            LiveCaptureDraftRegistration(fileURL: live),
            LiveCaptureDraftRegistration(fileURL: emptyLive)
        ]
        #expect(registrations.count == 2)
        #expect(try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory).isEmpty)
        #expect(try String(contentsOf: live, encoding: .utf8) == "Window A title")
        #expect(try String(contentsOf: emptyLive, encoding: .utf8) == " \n")
        #expect(try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: otherDirectory).isEmpty)
        #expect(try String(contentsOf: otherDirectory.appendingPathComponent("Other destination title.md"), encoding: .utf8) == "Other destination title")
        registrations.removeAll()
        #expect(!LiveCaptureDraftRegistration.contains(live))
        #expect(!LiveCaptureDraftRegistration.contains(emptyLive))
        #expect(try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory).isEmpty)
        #expect(try String(contentsOf: directory.appendingPathComponent("Window A title.md"), encoding: .utf8) == "Window A title")
        #expect(!FileManager.default.fileExists(atPath: emptyLive.path))
    }

    @Test(arguments: ["Live title", " \n\t"])
    func recoversOrphanDraftsWithoutTouchingLiveDraftOrOtherFiles(liveContent: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = DestinationWriteTarget.captureDraftFilename(captureId: UUID())
        let orphan = DestinationWriteTarget.captureDraftFilename(captureId: UUID())
        let empty = DestinationWriteTarget.captureDraftFilename(captureId: UUID())
        let fixtures = [live: liveContent, orphan: "Recovered: title / test\n\nBody", empty: " \n\t", "ordinary.md": "Unchanged"]
        for (filename, content) in fixtures {
            try content.write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }
        let failures = try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory, excluding: live)
        #expect(failures.isEmpty)
        #expect(try String(contentsOf: directory.appendingPathComponent("Recovered title  test.md"), encoding: .utf8) == fixtures[orphan])
        #expect(try String(contentsOf: directory.appendingPathComponent(live), encoding: .utf8) == fixtures[live])
        #expect(try String(contentsOf: directory.appendingPathComponent("ordinary.md"), encoding: .utf8) == "Unchanged")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(empty).path))
        #expect(try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory, excluding: live).isEmpty)
    }

    @Test func recoveryUsesCollisionSuffixesAndTimestampFallbackAndPreservesUnreadableDrafts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for filename in ["Title.md", "Title-2.md"] {
            try "Existing".write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }
        for content in ["Title", "///:?"] {
            try content.write(to: directory.appendingPathComponent(DestinationWriteTarget.captureDraftFilename(captureId: UUID())), atomically: true, encoding: .utf8)
        }
        let invalid = directory.appendingPathComponent(DestinationWriteTarget.captureDraftFilename(captureId: UUID()))
        try Data([0xff]).write(to: invalid)
        let failures = try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory)
        #expect(failures.map { $0.resolvingSymlinksInPath() } == [invalid.resolvingSymlinksInPath()])
        #expect(try Data(contentsOf: invalid) == Data([0xff]))
        #expect(try String(contentsOf: directory.appendingPathComponent("Title-3.md"), encoding: .utf8) == "Title")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let fallback = try #require(files.first { $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}\.md$"#, options: .regularExpression) != nil })
        #expect(try String(contentsOf: fallback, encoding: .utf8) == "///:?")
        #expect(try String(contentsOf: directory.appendingPathComponent("Title.md"), encoding: .utf8) == "Existing")
    }

    @Test func recoveryHandlesEmptyAndMissingDirectories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory).isEmpty)
        #expect(throws: (any Error).self) {
            try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory.appendingPathComponent("missing"))
        }
    }

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
    func settingsValidationRejectsNonUTF8TargetWithoutChangingIt(mode: DestinationSaveMode) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = SaveDestination(
            id: UUID(), displayName: "Test", isDefault: false,
            saveMode: mode, existingNoteFilename: "journal.md"
        )
        let now = Date()
        let missing = try #require(DestinationWriteTarget.resolve(
            for: destination, documentsURL: directory, now: now, createIfMissing: false
        ))
        try DestinationWriteTarget.validateSettingsTarget(missing)
        #expect(!FileManager.default.fileExists(atPath: missing.fileURL.path))

        let invalid = Data([0xFF])
        try invalid.write(to: missing.fileURL)
        let existing = try #require(DestinationWriteTarget.resolve(
            for: destination, documentsURL: directory, now: now, createIfMissing: false
        ))
        #expect(throws: (any Error).self) { try DestinationWriteTarget.validateSettingsTarget(existing) }
        #expect(try Data(contentsOf: existing.fileURL) == invalid)

        try "Readable note".write(to: existing.fileURL, atomically: true, encoding: .utf8)
        try DestinationWriteTarget.validateSettingsTarget(existing)
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

    @Test func oversizedTitleFilenameFitsWithExtensionAndCollisionSuffix() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let letter = "a\u{301}\u{301}\u{301}"
        let title = String(repeating: letter, count: 80)
        let content = "\(title)\n\nKeep this text."
        let basename = try #require(DestinationWriteTarget.sanitizedTitleBasename(from: content))
        let first = DestinationWriteTarget.uniqueMarkdownFilename(preferredBasename: basename, documentsURL: directory)
        #expect(first == String(repeating: letter, count: 36) + ".md")
        #expect(first.utf8.count == 255)
        let existing = directory.appendingPathComponent(first)
        try "Existing".write(to: existing, atomically: true, encoding: .utf8)

        let collision = DestinationWriteTarget.uniqueMarkdownFilename(preferredBasename: basename, documentsURL: directory)
        #expect(collision == String(repeating: letter, count: 35) + "-2.md")
        #expect(collision.utf8.count <= 255)
        let draft = directory.appendingPathComponent(DestinationWriteTarget.captureDraftFilename(captureId: UUID()))
        try content.write(to: draft, atomically: true, encoding: .utf8)
        #expect(try DestinationWriteTarget.recoverOrphanedCaptureDrafts(in: directory).isEmpty)
        #expect(try String(contentsOf: directory.appendingPathComponent(collision), encoding: .utf8) == content)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Existing")
    }

    @Test func truncatedTitleWithTrailingPeriodAppearsInExistingNoteChoices() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let prefix = String(repeating: "📝", count: 62)
        let title = prefix + "ab. more notes"
        let basename = try #require(DestinationWriteTarget.sanitizedTitleBasename(from: title))
        let filename = DestinationWriteTarget.uniqueMarkdownFilename(preferredBasename: basename, documentsURL: directory)
        #expect(filename == prefix + "ab.md")
        try title.write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        #expect(DestinationWriteTarget.existingNoteChoices(in: directory) == [filename])
    }
}
