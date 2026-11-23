import Carbon
import Foundation

struct HistoryTrash {
    struct Item {
        let originalURL: URL
        let trashedURL: URL
    }

    private(set) var items: [Item] = []
    private var emptyReplacement: (url: URL, attributes: NSDictionary)?
    private let recycleWithFinder: ((URL) throws -> URL?)?

    init(recycleWithFinder: ((URL) throws -> URL?)? = nil) {
        self.recycleWithFinder = recycleWithFinder
    }

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
        if let trashedURL = try recycleWithFinder?(url) {
            items.append(Item(originalURL: url, trashedURL: trashedURL))
            return
        }

        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let trashedURL = resultingURL as URL? else {
            throw CocoaError(.fileNoSuchFile)
        }
        items.append(Item(originalURL: url, trashedURL: trashedURL))
    }

    @discardableResult
    mutating func restore(finalizeCaptureDrafts: Bool = false, fileManager: FileManager = .default) throws -> [URL] {
        var restoredURLs: [URL] = []
        while let item = items.last {
            var destinationURL = item.originalURL
            if finalizeCaptureDrafts,
               DestinationWriteTarget.isCaptureDraftFilename(item.originalURL.lastPathComponent) {
                let content = try String(contentsOf: item.trashedURL, encoding: .utf8)
                let basename = DestinationWriteTarget.sanitizedTitleBasename(from: content)
                    ?? DestinationWriteTarget.dateCaptureBasename()
                let filename = DestinationWriteTarget.uniqueMarkdownFilename(
                    preferredBasename: basename,
                    documentsURL: item.originalURL.deletingLastPathComponent()
                )
                destinationURL = item.originalURL.deletingLastPathComponent().appendingPathComponent(filename)
            }
            if isUneditedReplacement(at: item.originalURL, fileManager: fileManager) {
                try fileManager.removeItem(at: item.originalURL)
                emptyReplacement = nil
            }
            try fileManager.moveItem(at: item.trashedURL, to: destinationURL)
            items.removeLast()
            restoredURLs.append(destinationURL)
        }
        return restoredURLs
    }
}

enum FinderTrash {
    static func recycle(_ url: URL) throws -> URL? {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
        // Recycle links with FileManager so resolving an alias can't follow the link's target.
        guard values.isSymbolicLink != true, values.isAliasFile != true else { return nil }

        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kAECoreSuite),
            eventID: AEEventID(kAEDelete),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder"),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(fileURL: url), forKeyword: AEKeyword(keyDirectObject))
        // The returned alias names the item even after a collision and grants sandbox access for Undo.
        event.setParam(NSAppleEventDescriptor(typeCode: DescType(typeAlias)), forKeyword: AEKeyword(keyAERequestedType))

        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 60)
            if let code = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, code != 0 {
                let message = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                throw NSError(
                    domain: NSOSStatusErrorDomain,
                    code: Int(code),
                    userInfo: message.map { [NSLocalizedDescriptionKey: $0] }
                )
            }
            guard let trashedURL = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.fileURLValue else {
                throw CocoaError(.fileNoSuchFile)
            }
            return trashedURL
        } catch let error as NSError where error.domain == NSOSStatusErrorDomain
            && error.code == Int(errAEEventNotPermitted) {
            // No move took place, so the existing Trash and in-app Undo path is still safe.
            return nil
        }
    }
}
