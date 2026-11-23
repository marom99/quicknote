import CryptoKit
import Darwin
import Foundation

struct CaptureDraft: Codable, Equatable {
    struct PendingWrite: Codable, Equatable {
        let filename: String
        let previousDigest: Data?
        let savedDigest: Data
    }

    let destination: SaveDestination
    let startedAt: Date
    let calendar: Calendar
    var text = ""
    var pendingWrite: PendingWrite?

    init(destination: SaveDestination, startedAt: Date = Date(), calendar: Calendar = .current) {
        self.destination = destination
        self.startedAt = startedAt
        self.calendar = calendar
    }

    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var separator: String { DestinationWriteTarget.sessionSeparator(at: startedAt, calendar: calendar) }
}

struct CaptureDraftStore {
    let url: URL
    var fileManager: FileManager = .default

    static var local: Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(url: support.appendingPathComponent("Quick Note/Capture Draft.json"))
    }

    static func sameFile(_ first: URL, _ second: URL) -> Bool {
        if first.standardizedFileURL.path == second.standardizedFileURL.path { return true }
        var lhs = stat()
        var rhs = stat()
        return stat(first.path, &lhs) == 0 && stat(second.path, &rhs) == 0
            && lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    func load() throws -> CaptureDraft? {
        do {
            return try JSONDecoder().decode(CaptureDraft.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func preserve(_ draft: CaptureDraft) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url, options: .atomic)
    }

    func discard() throws {
        do {
            try fileManager.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }

    enum SaveError: LocalizedError {
        case unavailable, missingTarget, changedTarget, unsavedEditor, invalidText

        var errorDescription: String? {
            switch self {
            case .unavailable: "The destination folder isn’t available."
            case .missingTarget: "The original note isn’t available."
            case .changedTarget: "The note changed during the save. Copy your draft to keep both versions."
            case .unsavedEditor: "The same note has unsaved edits in the main window."
            case .invalidText: "The original note isn’t UTF-8 text."
            }
        }
    }

    /// Resolve the snapshot, not the active settings, and keep its scope open through the write.
    func save(_ draft: inout CaptureDraft, canWrite: (URL) -> Bool) throws -> URL? {
        guard !draft.isBlank else {
            try discard()
            return nil
        }

        if draft.destination.isDefault {
            return try save(&draft, in: DestinationStore.defaultDocumentsURL(), canWrite: canWrite)
        }

        guard let bookmark = draft.destination.bookmarkData else { throw SaveError.unavailable }
        var stale = false
        guard let directory = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                       relativeTo: nil, bookmarkDataIsStale: &stale),
              directory.startAccessingSecurityScopedResource() else { throw SaveError.unavailable }
        defer { directory.stopAccessingSecurityScopedResource() }
        return try save(&draft, in: directory, canWrite: canWrite)
    }

    func save(_ draft: inout CaptureDraft, in directory: URL, canWrite: (URL) -> Bool = { _ in true }) throws -> URL? {
        guard !draft.isBlank else {
            try discard()
            return nil
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SaveError.unavailable
        }

        let mode = draft.destination.saveMode
        let filename: String
        if let pendingWrite = draft.pendingWrite {
            filename = pendingWrite.filename
        } else if mode == .newNote {
            let date = DestinationWriteTarget.dateCaptureBasename(now: draft.startedAt, calendar: draft.calendar)
            let title = draft.destination.newNoteFilenameFormat == .title
                ? DestinationWriteTarget.sanitizedTitleBasename(from: draft.text) : nil
            filename = DestinationWriteTarget.uniqueMarkdownFilename(
                preferredBasename: title ?? date, documentsURL: directory, fileManager: fileManager
            )
        } else {
            guard let target = DestinationWriteTarget.resolve(for: draft.destination, documentsURL: directory,
                    now: draft.startedAt, calendar: draft.calendar, fileManager: fileManager, createIfMissing: false),
                  mode != .existing || target.fileExists else { throw SaveError.missingTarget }
            filename = target.filename
        }

        let target = directory.appendingPathComponent(filename)
        let original = try read(target)
        let originalDigest = original.map(digest)
        if let pending = draft.pendingWrite, originalDigest == pending.savedDigest {
            // The app stopped after writing the note but before clearing the local draft.
            try discard()
            return target
        }
        if let pending = draft.pendingWrite, originalDigest != pending.previousDigest {
            throw SaveError.changedTarget
        }
        if mode == .existing && original == nil { throw SaveError.missingTarget }
        if mode == .newNote && original != nil { throw SaveError.changedTarget }
        guard canWrite(target) else { throw SaveError.unsavedEditor }

        if let original, String(data: original, encoding: .utf8) == nil { throw SaveError.invalidText }
        let addition = Data(((mode == .newNote ? "" : draft.separator) + draft.text).utf8)
        let outputDigest = digest((original ?? Data()) + addition)

        if draft.pendingWrite == nil {
            var prepared = draft
            prepared.pendingWrite = .init(filename: filename, previousDigest: originalDigest, savedDigest: outputDigest)
            try preserve(prepared)
            draft = prepared
        }

        do {
            if let originalDigest {
                try append(addition, to: target, after: originalDigest)
            } else {
                // Move a complete file into place without replacing a newly created note.
                let staged = directory.appendingPathComponent(".quicknote-write-\(UUID()).tmp")
                defer { try? fileManager.removeItem(at: staged) }
                try addition.write(to: staged, options: .atomic)
                try fileManager.moveItem(at: staged, to: target)
            }
            if try read(target).map(digest) != outputDigest {
                throw SaveError.changedTarget
            }
        } catch {
            if (try? read(target).map(digest) == originalDigest) == true {
                var retryable = draft
                retryable.pendingWrite = nil
                if (try? preserve(retryable)) != nil { draft = retryable }
            }
            throw error
        }
        try discard()
        return target
    }

    private func append(_ data: Data, to target: URL, after previousDigest: Data) throws {
        // Never publish a replacement built from a stale read of another app's note.
        let fd = open(target.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        if try read(target).map(digest) != previousDigest { throw SaveError.changedTarget }
        try file.write(contentsOf: data)
        try file.synchronize()
    }

    private func read(_ target: URL) throws -> Data? {
        do {
            let values = try target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true || values.isRegularFile != true {
                throw SaveError.changedTarget
            }
            return try Data(contentsOf: target)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
}
