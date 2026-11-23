import Foundation

struct HistoryEntryReader {
    let directory: URL
    var fileManager = FileManager.default

    func entries() throws -> [HumanEntry] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap { Task.isCancelled ? nil : entry(at: $0) }
            .sorted {
                if $0.timestamp == $1.timestamp { return $0.filename > $1.filename }
                return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
            }
    }

    func entry(at url: URL, includeUnreadable: Bool = true) -> HumanEntry? {
        let filename = url.lastPathComponent
        guard url.pathExtension.lowercased() == "md",
              !DestinationWriteTarget.isCaptureDraftFilename(filename) else { return nil }
        let body: String?
        do {
            body = try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileReadCorruptFile where includeUnreadable {
            body = nil
        } catch {
            return nil
        }
        let date = Self.canonicalTimestamp(for: filename) ?? Self.modificationDate(for: url, fileManager: fileManager)
        let videoFilename = DestinationWriteTarget.videoAssetFilename(
            forNote: filename, in: directory, fileManager: fileManager
        )
        let videoDirectory = directory.appendingPathComponent("Videos", isDirectory: true)
        let videoEntryDirectory = videoDirectory.appendingPathComponent(
            url.deletingPathExtension().lastPathComponent, isDirectory: true
        )
        let hasVideo = videoFilename != nil
        let transcript = hasVideo ? try? String(
            contentsOf: videoEntryDirectory.appendingPathComponent("transcript.md"), encoding: .utf8
        ) : nil

        return HumanEntry(
            id: DestinationWriteTarget.stableUUID(fromPath: url.standardizedFileURL.path),
            date: DestinationWriteTarget.displayDateString(from: date),
            filename: filename,
            previewText: hasVideo ? Self.videoTitle(from: transcript) : body.map(HistoryRowFormatting.title(from:)) ?? filename,
            entryType: hasVideo ? .video : .text,
            videoFilename: videoFilename,
            timestamp: date,
            searchableBody: hasVideo ? (transcript ?? "") : (body ?? "")
        )
    }

    static func videoTitle(from transcript: String?) -> String {
        let normalized = (transcript ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var preview = String(normalized.prefix(10))
        while let last = preview.last, !last.isLetter && !last.isNumber {
            preview.removeLast()
        }
        return preview.isEmpty ? "Video Note" : preview + "..."
    }

    static func modificationDate(for url: URL, fileManager: FileManager = .default) -> Date {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
    }

    static func canonicalTimestamp(for filename: String) -> Date? {
        guard filename.hasPrefix("["),
              filename.lowercased().hasSuffix("].md"),
              let divider = filename.range(of: "]-[") else { return nil }

        let uuidStart = filename.index(after: filename.startIndex)
        guard UUID(uuidString: String(filename[uuidStart..<divider.lowerBound])) != nil else { return nil }

        let timestampEnd = filename.index(filename.endIndex, offsetBy: -4)
        guard divider.upperBound <= timestampEnd else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.date(from: String(filename[divider.upperBound..<timestampEnd]))
    }
}
