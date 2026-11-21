import Foundation
import Testing
@testable import freewrite

struct HistoryTrashTests {
    @Test func undoReplacesOnlyTrackedUneditedEmptyFile() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("rolling.md")
            try "Original".write(to: url, atomically: true, encoding: .utf8)
            var trash = HistoryTrash()
            try trash.moveToTrash(url)
            defer { try? trash.restore() }
            try "".write(to: url, atomically: true, encoding: .utf8)
            try trash.trackEmptyReplacement(at: url)
            #expect(trash.isUneditedReplacement(at: url))
            try trash.restore()
            #expect(try String(contentsOf: url, encoding: .utf8) == "Original")
        }
    }

    @Test func undoPreservesEditedReplacement() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("rolling.md")
            try "Original".write(to: url, atomically: true, encoding: .utf8)
            var trash = HistoryTrash()
            try trash.moveToTrash(url)
            defer { try? trash.restore() }
            try "".write(to: url, atomically: true, encoding: .utf8)
            try trash.trackEmptyReplacement(at: url)
            try "User content".write(to: url, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) { try trash.restore() }
            #expect(try String(contentsOf: url, encoding: .utf8) == "User content")
            try FileManager.default.removeItem(at: url)
        }
    }

    @Test func undoPreservesUntrackedEmptyOccupant() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("rolling.md")
            try "Original".write(to: url, atomically: true, encoding: .utf8)
            var trash = HistoryTrash()
            try trash.moveToTrash(url)
            defer { try? trash.restore() }
            try "".write(to: url, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) { try trash.restore() }
            #expect(try Data(contentsOf: url).isEmpty)
            try FileManager.default.removeItem(at: url)
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test func trashAndRestorePreserveContentsAndPath() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("note.md")
            try "A note".write(to: url, atomically: true, encoding: .utf8)
            var trash = HistoryTrash()
            try trash.moveToTrash(url)
            defer { try? trash.restore() }
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(trash.items.count == 1)
            #expect(try String(contentsOf: trash.items[0].trashedURL, encoding: .utf8) == "A note")
            try trash.restore()
            #expect(try String(contentsOf: url, encoding: .utf8) == "A note")
            #expect(trash.items.isEmpty)
        }
    }

    @Test func emptyRestoreIsHarmless() throws {
        var trash = HistoryTrash()
        try trash.restore()
        #expect(trash.items.isEmpty)
    }

    @Test func missingFileDoesNotAddUndoItem() throws {
        try withDirectory { directory in
            var trash = HistoryTrash()
            #expect(throws: (any Error).self) {
                try trash.moveToTrash(directory.appendingPathComponent("missing.md"))
            }
            #expect(trash.items.isEmpty)
        }
    }

    @Test func restoreConflictDoesNotOverwriteAndCanBeRetried() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("note.md")
            try "Original".write(to: url, atomically: true, encoding: .utf8)
            var trash = HistoryTrash()
            try trash.moveToTrash(url)
            defer { try? trash.restore() }
            try "Replacement".write(to: url, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) { try trash.restore() }
            #expect(try String(contentsOf: url, encoding: .utf8) == "Replacement")
            #expect(trash.items.count == 1)
            try FileManager.default.removeItem(at: url)
            try trash.restore()
            #expect(try String(contentsOf: url, encoding: .utf8) == "Original")
        }
    }

    @Test func restoresNoteAndVideoDirectory() throws {
        try withDirectory { directory in
            let note = directory.appendingPathComponent("video.md")
            let assets = directory.appendingPathComponent("video")
            try "Video Entry".write(to: note, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: assets.appendingPathComponent("video.mov"))
            var trash = HistoryTrash()
            try trash.moveToTrash(note)
            try trash.moveToTrash(assets)
            defer { try? trash.restore() }
            try trash.restore()
            #expect(FileManager.default.fileExists(atPath: note.path))
            #expect(try Data(contentsOf: assets.appendingPathComponent("video.mov")) == Data([1, 2, 3]))
        }
    }
}
