import Foundation
import Testing
@testable import freewrite

struct NoteSaveStateTests {
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
