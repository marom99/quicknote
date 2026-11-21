import Foundation

struct HistoryTrash {
    struct Item {
        let originalURL: URL
        let trashedURL: URL
    }

    private(set) var items: [Item] = []
    private var emptyReplacement: (url: URL, attributes: NSDictionary)?

    mutating func trackEmptyReplacement(at url: URL, fileManager: FileManager = .default) throws {
        guard try Data(contentsOf: url).isEmpty else { return }
        emptyReplacement = (url, try fileManager.attributesOfItem(atPath: url.path) as NSDictionary)
    }

    func isUneditedReplacement(at url: URL, fileManager: FileManager = .default) -> Bool {
        guard let replacement = emptyReplacement, replacement.url == url,
              let data = try? Data(contentsOf: url), data.isEmpty,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return replacement.attributes.isEqual(to: attributes)
    }

    mutating func invalidateReplacement() {
        emptyReplacement = nil
    }

    mutating func moveToTrash(_ url: URL, fileManager: FileManager = .default) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let trashedURL = resultingURL as URL? else {
            throw CocoaError(.fileNoSuchFile)
        }
        items.append(Item(originalURL: url, trashedURL: trashedURL))
    }

    mutating func restore(fileManager: FileManager = .default) throws {
        while let item = items.last {
            if isUneditedReplacement(at: item.originalURL, fileManager: fileManager) {
                try fileManager.removeItem(at: item.originalURL)
                emptyReplacement = nil
            }
            try fileManager.moveItem(at: item.trashedURL, to: item.originalURL)
            items.removeLast()
        }
    }
}
