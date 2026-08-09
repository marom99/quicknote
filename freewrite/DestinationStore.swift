import Foundation

struct SaveDestination: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var bookmarkData: Data?
    var isDefault: Bool

    static func makeDefault(displayName: String = "Freewrite") -> SaveDestination {
        SaveDestination(id: UUID(), displayName: displayName, bookmarkData: nil, isDefault: true)
    }
}

enum DestinationAccessResult {
    case accessible(URL)
    case softFailure
}

final class DestinationStore: ObservableObject {
    static let destinationsKey = "saveDestinations"
    static let activeDestinationIdKey = "activeDestinationId"

    @Published private(set) var destinations: [SaveDestination]
    @Published private(set) var activeDestinationId: UUID
    @Published private(set) var activeAccessFailed: Bool = false

    private let userDefaults: UserDefaults
    private var scopedURL: URL?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let seeded = Self.seedIfNeeded(userDefaults: userDefaults)
        self.destinations = seeded.destinations
        self.activeDestinationId = seeded.activeId
    }

    var activeDestination: SaveDestination? {
        destinations.first(where: { $0.id == activeDestinationId })
    }

    static func defaultFreewriteURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freewrite", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func resolvedDocumentsURL(fileManager: FileManager = .default) -> URL? {
        switch resolveActiveAccess(fileManager: fileManager) {
        case .accessible(let url):
            ensureDirectoryExists(at: url, fileManager: fileManager)
            return url
        case .softFailure:
            return nil
        }
    }

    func resolvedVideosURL(fileManager: FileManager = .default) -> URL? {
        guard let documentsURL = resolvedDocumentsURL(fileManager: fileManager) else {
            return nil
        }
        let videosURL = documentsURL.appendingPathComponent("Videos", isDirectory: true)
        ensureDirectoryExists(at: videosURL, fileManager: fileManager)
        return videosURL
    }

    func resolveDocumentsURL(for destination: SaveDestination, fileManager: FileManager = .default) -> URL? {
        switch resolveAccess(for: destination, fileManager: fileManager) {
        case .accessible(let url):
            ensureDirectoryExists(at: url, fileManager: fileManager)
            return url
        case .softFailure:
            return nil
        }
    }

    func resolveVideosURL(for destination: SaveDestination, fileManager: FileManager = .default) -> URL? {
        guard let documentsURL = resolveDocumentsURL(for: destination, fileManager: fileManager) else {
            return nil
        }
        let videosURL = documentsURL.appendingPathComponent("Videos", isDirectory: true)
        ensureDirectoryExists(at: videosURL, fileManager: fileManager)
        return videosURL
    }

    @discardableResult
    func activateDestination(id: UUID, fileManager: FileManager = .default) -> DestinationAccessResult {
        guard destinations.contains(where: { $0.id == id }) else {
            return .softFailure
        }

        stopAccessingCurrentScope()
        activeDestinationId = id
        userDefaults.set(id.uuidString, forKey: Self.activeDestinationIdKey)
        let access = resolveActiveAccess(fileManager: fileManager)
        activeAccessFailed = access == .softFailure
        return access
    }

    func addDestination(from pickedURL: URL, activate: Bool = true, fileManager: FileManager = .default) throws -> SaveDestination {
        let bookmarkData = try pickedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let displayName = pickedURL.lastPathComponent
        let destination = SaveDestination(
            id: UUID(),
            displayName: displayName,
            bookmarkData: bookmarkData,
            isDefault: false
        )
        destinations.append(destination)
        persistDestinations()

        if activate {
            activateDestination(id: destination.id, fileManager: fileManager)
        }

        return destination
    }

    func renameDestination(id: UUID, displayName: String) {
        guard let index = destinations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        destinations[index].displayName = trimmed
        persistDestinations()
    }

    func stopAccessingCurrentScope() {
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }

    private func resolveActiveAccess(fileManager: FileManager = .default) -> DestinationAccessResult {
        guard let destination = activeDestination else {
            return .softFailure
        }
        return resolveAccess(for: destination, fileManager: fileManager)
    }

    private func resolveAccess(for destination: SaveDestination, fileManager: FileManager = .default) -> DestinationAccessResult {
        if destination.isDefault {
            let url = Self.defaultFreewriteURL(fileManager: fileManager)
            scopedURL = nil
            activeAccessFailed = false
            return .accessible(url)
        }

        guard let bookmarkData = destination.bookmarkData else {
            activeAccessFailed = true
            return .softFailure
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                let refreshed = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                if let index = destinations.firstIndex(where: { $0.id == destination.id }) {
                    destinations[index].bookmarkData = refreshed
                    persistDestinations()
                }
            }

            if scopedURL != url {
                stopAccessingCurrentScope()
                guard url.startAccessingSecurityScopedResource() else {
                    activeAccessFailed = true
                    return .softFailure
                }
                scopedURL = url
            }

            activeAccessFailed = false
            return .accessible(url)
        } catch {
            activeAccessFailed = true
            return .softFailure
        }
    }

    private func ensureDirectoryExists(at url: URL, fileManager: FileManager) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func persistDestinations() {
        if let data = try? JSONEncoder().encode(destinations) {
            userDefaults.set(data, forKey: Self.destinationsKey)
        }
    }

    private static func seedIfNeeded(userDefaults: UserDefaults) -> (destinations: [SaveDestination], activeId: UUID) {
        if let data = userDefaults.data(forKey: destinationsKey),
           let decoded = try? JSONDecoder().decode([SaveDestination].self, from: data),
           !decoded.isEmpty {
            let activeIdString = userDefaults.string(forKey: activeDestinationIdKey)
            let activeId = decoded.first(where: { $0.id.uuidString == activeIdString })?.id ?? decoded[0].id
            return (decoded, activeId)
        }

        let defaultDestination = SaveDestination.makeDefault()
        let destinations = [defaultDestination]
        if let data = try? JSONEncoder().encode(destinations) {
            userDefaults.set(data, forKey: destinationsKey)
        }
        userDefaults.set(defaultDestination.id.uuidString, forKey: activeDestinationIdKey)
        return (destinations, defaultDestination.id)
    }
}
