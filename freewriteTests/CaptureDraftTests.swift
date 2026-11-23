import CryptoKit
import Foundation
import Testing
@testable import freewrite

struct CaptureDraftTests {
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var destination: URL { root.appendingPathComponent("Destination") }
        var store: CaptureDraftStore { .init(url: root.appendingPathComponent("Recovery/Draft.json")) }

        init() throws {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        func draft(_ mode: DestinationSaveMode, format: NewNoteFilenameFormat = .date,
                   calendar: Calendar = .current) -> CaptureDraft {
            CaptureDraft(destination: .init(id: UUID(), displayName: "Original", isDefault: true, saveMode: mode,
                                             newNoteFilenameFormat: format, existingNoteFilename: "Keep.md"),
                         startedAt: Date(timeIntervalSince1970: 1_700_000_000), calendar: calendar)
        }

        func target(for draft: CaptureDraft) throws -> URL {
            if draft.destination.saveMode == .existing { return destination.appendingPathComponent("Keep.md") }
            return try #require(DestinationWriteTarget.resolve(for: draft.destination, documentsURL: destination,
                                now: draft.startedAt, createIfMissing: false)?.fileURL)
        }
    }

    @Test(arguments: DestinationSaveMode.allCases)
    func blankCaptureDoesNotWriteOrAppend(mode: DestinationSaveMode) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(mode)
        let existing = f.destination.appendingPathComponent("Keep.md")
        try "Previous".write(to: existing, atomically: true, encoding: .utf8)
        draft.text = " \n\t"
        try f.store.preserve(draft)

        #expect(try f.store.save(&draft, in: f.destination) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.destination.path) == ["Keep.md"])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Previous")
        #expect(try f.store.load() == nil)
    }

    @Test func titleCaptureCreatesAUniqueMarkdownFile() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let existing = f.destination.appendingPathComponent("Launch ideas.md")
        try "Other note".write(to: existing, atomically: true, encoding: .utf8)
        var draft = f.draft(.newNote, format: .title)
        draft.text = "Launch ideas\n\nSecond paragraph"

        let url = try #require(f.store.save(&draft, in: f.destination))

        #expect(url.lastPathComponent == "Launch ideas-2.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == draft.text)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Other note")
        #expect(try f.store.load() == nil)
    }

    @Test func dateCaptureUsesTheSessionDate() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.newNote)
        draft.text = "A dated thought"

        let url = try #require(f.store.save(&draft, in: f.destination))

        #expect(url.lastPathComponent == DestinationWriteTarget.dateCaptureBasename(now: draft.startedAt) + ".md")
        #expect(try String(contentsOf: url, encoding: .utf8) == draft.text)
    }

    @Test func caseAliasesOnlyMatchWhenTheyReferToTheSameFile() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let original = f.destination.appendingPathComponent("Daily.md")
        let caseAlias = f.destination.appendingPathComponent("daily.md")
        try Data().write(to: original)
        if FileManager.default.fileExists(atPath: caseAlias.path) {
            #expect(CaptureDraftStore.sameFile(original, caseAlias))
        } else {
            try Data().write(to: caseAlias)
            #expect(!CaptureDraftStore.sameFile(original, caseAlias))
        }
    }

    @Test(arguments: [DestinationSaveMode.rolling, .existing])
    func appendPreservesTheLatestDestinationText(mode: DestinationSaveMode) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(mode)
        draft.text = "Captured"
        try f.store.preserve(draft)
        let file = try f.target(for: draft)
        let before = "Original\nEdited in another app\n"
        try before.write(to: file, atomically: true, encoding: .utf8)

        #expect(try f.store.save(&draft, in: f.destination) == file)
        #expect(try String(contentsOf: file, encoding: .utf8) == before + draft.separator + draft.text)
    }

    @Test func appendPreservesTheExistingFileIdentity() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.existing)
        draft.text = "Captured"
        let file = try f.target(for: draft)
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        let alias = f.destination.appendingPathComponent("Hard link.md")
        try FileManager.default.linkItem(at: file, to: alias)

        #expect(try f.store.save(&draft, in: f.destination) == file)
        #expect(CaptureDraftStore.sameFile(file, alias))
        #expect(try String(contentsOf: alias, encoding: .utf8) == "Original" + draft.separator + draft.text)
    }

    @Test func rollingCreatesMissingFileOnlyOnNonemptySave() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.rolling)
        draft.text = "Captured"
        let file = try f.target(for: draft)

        #expect(try f.store.save(&draft, in: f.destination) == file)
        #expect(try String(contentsOf: file, encoding: .utf8) == draft.separator + draft.text)
    }

    @Test(arguments: [0, 9])
    func recoveredRollingCaptureKeepsItsOriginalDay(hourOffset: Int) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: hourOffset * 3600))
        var draft = f.draft(.rolling, calendar: calendar)
        draft.text = "Captured while traveling"
        try f.store.preserve(draft)
        let restored = try f.store.load()
        var recovered = try #require(restored)

        let saved = try #require(f.store.save(&recovered, in: f.destination))

        #expect(saved.lastPathComponent == (hourOffset == 0 ? "2023-11-14.md" : "2023-11-15.md"))
        #expect(try String(contentsOf: saved, encoding: .utf8) == draft.separator + draft.text)
    }

    @Test func missingDestinationLeavesDraftForRetryInTheOriginalDestination() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.newNote)
        draft.text = "Do not lose this"
        try f.store.preserve(draft)
        try FileManager.default.removeItem(at: f.destination)

        #expect(throws: CaptureDraftStore.SaveError.unavailable) {
            try f.store.save(&draft, in: f.destination)
        }

        let restored = try CaptureDraftStore(url: f.store.url).load()
        var recovered = try #require(restored)
        #expect(recovered == draft)
        try FileManager.default.createDirectory(at: f.destination, withIntermediateDirectories: false)
        let url = try #require(f.store.save(&recovered, in: f.destination))
        #expect(try String(contentsOf: url, encoding: .utf8) == draft.text)
    }

    @Test func leavesUnreadableNoteAndUnsavedEditorIntact() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.existing)
        draft.text = "Not in the original file"
        let file = try f.target(for: draft)
        let bytes = Data([0xFF, 0xFE, 0xFF])
        try bytes.write(to: file)

        #expect(throws: CaptureDraftStore.SaveError.invalidText) {
            try f.store.save(&draft, in: f.destination)
        }
        #expect(try Data(contentsOf: file) == bytes)

        try "Previous".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: CaptureDraftStore.SaveError.unsavedEditor) {
            try f.store.save(&draft, in: f.destination, canWrite: { _ in false })
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "Previous")
    }

    @Test(arguments: ["", "\nAppended by another app"])
    func completedAppendIsNotRepeatedWhenRecoveringAfterAnInterruption(suffix: String) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.existing)
        draft.text = "Captured"
        let file = try f.target(for: draft)
        let previous = Data("Original".utf8)
        let output = previous + Data((draft.separator + draft.text).utf8)
        draft.pendingWrite = .init(filename: file.lastPathComponent, previousDigest: Data(SHA256.hash(data: previous)),
                                   savedDigest: Data(SHA256.hash(data: output)), previousByteCount: previous.count)
        try f.store.preserve(draft)
        let onDisk = output + Data(suffix.utf8)
        try onDisk.write(to: file)

        let restored = try f.store.load()
        var recovered = try #require(restored)
        #expect(try f.store.save(&recovered, in: f.destination) == file)
        #expect(try Data(contentsOf: file) == onDisk)
        #expect(try f.store.load() == nil)
    }

    @Test(arguments: [false, true])
    func retriesPartialAppendOnlyIfNoOtherBytesWereAdded(anotherAppAppended: Bool) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.existing)
        draft.text = "Éclair"
        let file = try f.target(for: draft)
        let previous = Data("Original".utf8)
        let addition = Data((draft.separator + draft.text).utf8)
        let complete = previous + addition
        var partial = previous + addition.prefix(draft.separator.utf8.count + 1)
        if anotherAppAppended { partial += Data("Other app's edits".utf8) }
        draft.pendingWrite = .init(filename: file.lastPathComponent, previousDigest: Data(SHA256.hash(data: previous)),
                                   savedDigest: Data(SHA256.hash(data: complete)), previousByteCount: previous.count)
        try f.store.preserve(draft)
        try partial.write(to: file)

        let restored = try f.store.load()
        var recovered = try #require(restored)
        if anotherAppAppended {
            #expect(throws: CaptureDraftStore.SaveError.changedTarget) {
                try f.store.save(&recovered, in: f.destination)
            }
            #expect(try Data(contentsOf: file) == partial)
            #expect(try f.store.load() == draft)
        } else {
            #expect(try f.store.save(&recovered, in: f.destination) == file)
            #expect(try Data(contentsOf: file) == complete)
            #expect(try f.store.load() == nil)
        }
    }

    @Test func recoveryWillNotOverwriteAFileChangedDuringAnInterruptedWrite() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var draft = f.draft(.existing)
        draft.text = "Captured"
        let file = try f.target(for: draft)
        draft.pendingWrite = .init(filename: file.lastPathComponent,
                                   previousDigest: Data(SHA256.hash(data: Data("Before".utf8))),
                                   savedDigest: Data(SHA256.hash(data: Data("After".utf8))))
        try f.store.preserve(draft)
        try "Other app’s edits".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: CaptureDraftStore.SaveError.changedTarget) {
            try f.store.save(&draft, in: f.destination)
        }
        #expect(try f.store.load() == draft)
        #expect(try String(contentsOf: file, encoding: .utf8) == "Other app’s edits")
    }
}
