import Foundation

struct NoteSaveState {
    private var loadedTextByURL: [URL: String] = [:]

    mutating func didLoad(_ text: String, from url: URL) {
        loadedTextByURL[url.standardizedFileURL] = text
    }

    mutating func save(_ text: String, to url: URL) throws -> String {
        if loadedTextByURL[url.standardizedFileURL] == text {
            let diskText = try String(contentsOf: url, encoding: .utf8)
            didLoad(diskText, from: url)
            return diskText
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        didLoad(text, from: url)
        return text
    }
}
