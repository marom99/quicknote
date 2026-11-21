import Foundation

struct HistoryTrash {
    struct Item {
        let originalURL: URL
        let trashedURL: URL
    }

    private(set) var items: [Item] = []

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
            try fileManager.moveItem(at: item.trashedURL, to: item.originalURL)
            items.removeLast()
        }
    }
}
