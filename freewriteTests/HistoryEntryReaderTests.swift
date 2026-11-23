import Foundation
import Testing
@testable import freewrite

struct HistoryEntryReaderTests {
    @Test func scansAuthorizedRootWithoutCreatingOrRecoveringAnything() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = directory.appendingPathComponent("Note.md")
        let draft = directory.appendingPathComponent(".quicknote-capture-\(UUID().uuidString).md")
        try "Title\nBody".write(to: note, atomically: true, encoding: .utf8)
        try "Draft".write(to: draft, atomically: true, encoding: .utf8)
        let nonUTF8 = directory.appendingPathComponent("Broken.md")
        try Data([0xFF]).write(to: nonUTF8)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()

        let entries = try HistoryEntryReader(directory: directory).entries()

        #expect(entries.map(\.filename).sorted() == ["Broken.md", "Note.md"])
        #expect(entries.first(where: { $0.filename == "Note.md" })?.searchableBody == "Title\nBody")
        #expect(HistoryEntryReader(directory: directory).entry(at: nonUTF8, includeUnreadable: false) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == before)
    }

    @Test func readsExistingVideoTranscriptsForSearch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let video = directory.appendingPathComponent("Videos/Video")
        try FileManager.default.createDirectory(at: video, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "Video Entry".write(to: directory.appendingPathComponent("Video.md"), atomically: true, encoding: .utf8)
        try Data().write(to: video.appendingPathComponent("Video.mov"))
        try "Transcript includes prism".write(to: video.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)

        let entry = try #require(HistoryEntryReader(directory: directory).entries().first)
        #expect(entry.entryType == .video)
        #expect(entry.videoFilename == "Video.mov")
        #expect(HistorySearch.matches(query: "prism", title: entry.previewText, body: entry.searchableBody))
    }
}
