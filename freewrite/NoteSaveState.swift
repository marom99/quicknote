import Foundation

struct NoteSaveState {
    private var loadedTextByURL: [URL: String] = [:]

    mutating func load(from url: URL) throws -> String {
        let rawText = try String(contentsOf: url, encoding: .utf8)
        let text = String(rawText.drop(while: { $0 == "\n" }))
        didLoad(text, from: url)
        return text
    }

    mutating func didLoad(_ text: String, from url: URL) {
        loadedTextByURL[url.standardizedFileURL] = text
    }

    mutating func forget(_ url: URL) {
        loadedTextByURL.removeValue(forKey: url.standardizedFileURL)
    }

    func hasUnsavedChanges(_ text: String, at url: URL) -> Bool {
        loadedTextByURL[url.standardizedFileURL] != text
    }

    mutating func save(_ text: String, to url: URL) throws -> String {
        let unchanged = !hasUnsavedChanges(text, at: url)
        do {
            let diskText = try String(contentsOf: url, encoding: .utf8)
            if unchanged {
                didLoad(diskText, from: url)
                return diskText
            }
            if diskText == text {
                didLoad(text, from: url)
                return text
            }
        } catch CocoaError.fileReadNoSuchFile where !unchanged {
            // Changed text can create a missing file, but cannot replace an unreadable one.
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        didLoad(text, from: url)
        return text
    }
}
