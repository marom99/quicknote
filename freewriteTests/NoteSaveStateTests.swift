import Foundation
import Testing
@testable import freewrite

struct NoteSaveStateTests {
    @Test func deletedDateCaptureCanRestoreIdenticalTextAtSameTimestamp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let basename = DestinationWriteTarget.dateCaptureBasename(now: Date(timeIntervalSince1970: 1_800_000_000))
        let filename = DestinationWriteTarget.uniqueMarkdownFilename(preferredBasename: basename, documentsURL: directory)
        let url = directory.appendingPathComponent(filename)
        var state = NoteSaveState()
        _ = try state.save("Restored capture", to: url)
        try FileManager.default.removeItem(at: url)
        state.forget(url)
        let restoredFilename = DestinationWriteTarget.uniqueMarkdownFilename(preferredBasename: basename, documentsURL: directory)
        #expect(restoredFilename == filename)
        _ = try state.save("Restored capture", to: directory.appendingPathComponent(restoredFilename))
        _ = try state.save("Restored capture", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Restored capture")
    }

    @Test func renamedCaptureDoesNotLeaveBaselineAtReusedURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("draft.md")
        let destination = directory.appendingPathComponent("title.md")
        var state = NoteSaveState()
        _ = try state.save("Capture text", to: source)
        try FileManager.default.moveItem(at: source, to: destination)
        state.forget(source)
        state.forget(destination)
        _ = try state.save("Capture text", to: source)
        #expect(try String(contentsOf: source, encoding: .utf8) == "Capture text")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "Capture text")
    }

    @Test func unchangedEditorPreservesExternalEditsOnRepeatedSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("existing.md")
        var state = NoteSaveState()
        var editor = try state.save("Quicknote text", to: url)
        try "External text".write(to: url, atomically: true, encoding: .utf8)
        editor = try state.save(editor, to: url)
        #expect(editor == "External text")
        _ = try state.save(editor, to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "External text")
    }

    @Test func loadedNormalizedTextDoesNotRewriteDiskAndLocalClearingSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("existing.md")
        try "\nLegacy text".write(to: url, atomically: true, encoding: .utf8)
        var state = NoteSaveState()
        state.didLoad("Legacy text", from: url)
        #expect(try state.save("Legacy text", to: url) == "\nLegacy text")
        #expect(try String(contentsOf: url, encoding: .utf8) == "\nLegacy text")
        #expect(try state.save("", to: url) == "")
        #expect(try String(contentsOf: url, encoding: .utf8) == "")
    }

    @Test func failedSaveDoesNotMarkLocalChangesAsSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("note.md")
        var state = NoteSaveState()
        #expect(throws: (any Error).self) { try state.save("Local text", to: url) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try state.save("Local text", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Local text")
    }

    @Test func unreadableUnchangedNoteIsNotRecreated() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var state = NoteSaveState()
        state.didLoad("Loaded text", from: url)
        #expect(throws: (any Error).self) { try state.save("Loaded text", to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
