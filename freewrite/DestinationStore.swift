import Foundation

enum DestinationSaveMode: String, Codable, Equatable, CaseIterable {
    case newNote
    case rolling
    case existing

    var displayName: String {
        switch self {
        case .newNote: return "New note"
        case .rolling: return "Rolling"
        case .existing: return "Existing note"
        }
    }

    var explanation: String {
        switch self {
        case .newNote: return "Creates one file per session."
        case .rolling: return "One file per day, week, or month."
        case .existing: return "Writes to a note you choose."
        }
    }
}

enum NewNoteFilenameFormat: String, Codable, Equatable, CaseIterable {
    case date
    case title

    var displayName: String {
        switch self {
        case .date: return "Date"
        case .title: return "Title"
        }
    }
}

enum RollingPeriod: String, Codable, Equatable, CaseIterable {
    case daily
    case weekly
    case monthly

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var defaultFilenameFormat: String {
        switch self {
        case .daily: return "yyyy-MM-dd"
        case .weekly: return "yyyy-'W'ww"
        case .monthly: return "yyyy-MM"
        }
    }
}

struct SaveDestination: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var bookmarkData: Data?
    var isDefault: Bool
    var saveMode: DestinationSaveMode
    var rollingPeriod: RollingPeriod
    var filenameFormat: String
    var newNoteFilenameFormat: NewNoteFilenameFormat
    var existingNoteFilename: String?

    init(
        id: UUID,
        displayName: String,
        bookmarkData: Data? = nil,
        isDefault: Bool,
        saveMode: DestinationSaveMode = .newNote,
        rollingPeriod: RollingPeriod = .daily,
        filenameFormat: String = RollingPeriod.daily.defaultFilenameFormat,
        newNoteFilenameFormat: NewNoteFilenameFormat = .date,
        existingNoteFilename: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.isDefault = isDefault
        self.saveMode = saveMode
        self.rollingPeriod = rollingPeriod
        self.filenameFormat = filenameFormat
        self.newNoteFilenameFormat = newNoteFilenameFormat
        self.existingNoteFilename = existingNoteFilename
    }

    static let defaultDisplayName = "Quick Note"
    static let legacyDefaultDisplayName = "Freewrite"

    static func makeDefault(displayName: String = defaultDisplayName) -> SaveDestination {
        SaveDestination(id: UUID(), displayName: displayName, bookmarkData: nil, isDefault: true)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case bookmarkData
        case isDefault
        case saveMode
        case rollingPeriod
        case filenameFormat
        case newNoteFilenameFormat
        case existingNoteFilename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        // Backward-compatible defaults: pre-save-mode destinations stay New note.
        saveMode = try container.decodeIfPresent(DestinationSaveMode.self, forKey: .saveMode) ?? .newNote
        rollingPeriod = try container.decodeIfPresent(RollingPeriod.self, forKey: .rollingPeriod) ?? .daily
        filenameFormat = try container.decodeIfPresent(String.self, forKey: .filenameFormat)
            ?? rollingPeriod.defaultFilenameFormat
        newNoteFilenameFormat = try container.decodeIfPresent(NewNoteFilenameFormat.self, forKey: .newNoteFilenameFormat) ?? .date
        existingNoteFilename = try container.decodeIfPresent(String.self, forKey: .existingNoteFilename)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(saveMode, forKey: .saveMode)
        try container.encode(rollingPeriod, forKey: .rollingPeriod)
        try container.encode(filenameFormat, forKey: .filenameFormat)
        try container.encode(newNoteFilenameFormat, forKey: .newNoteFilenameFormat)
        try container.encodeIfPresent(existingNoteFilename, forKey: .existingNoteFilename)
    }
}

enum DestinationAccessResult: Equatable {
    case accessible(URL)
    case softFailure
}

final class DestinationStore: ObservableObject {
    static let destinationsKey = "saveDestinations"
    static let activeDestinationIdKey = "activeDestinationId"

    @Published private(set) var destinations: [SaveDestination]
    @Published private(set) var activeDestinationId: UUID
    @Published private(set) var activeAccessFailed: Bool = false
    /// Path string for UI labels — avoids resolving bookmarks during view updates.
    @Published private(set) var activeDocumentsPath: String?

    private let userDefaults: UserDefaults
    private var scopedURL: URL?
    private var cachedDocumentsURL: URL?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let seeded = Self.seedIfNeeded(userDefaults: userDefaults)
        self.destinations = seeded.destinations
        self.activeDestinationId = seeded.activeId
    }

    var activeDestination: SaveDestination? {
        destinations.first(where: { $0.id == activeDestinationId })
    }

    static let defaultFolderName = "Quick Note"
    static let legacyDefaultFolderName = "Freewrite"

    static func defaultDocumentsURL(fileManager: FileManager = .default) -> URL {
        let parent = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return defaultDocumentsURL(in: parent, fileManager: fileManager)
    }

    /// Resolves the default journal folder under `parent`, moving a legacy
    /// `Freewrite` folder to `Quick Note` the first time. If the move fails the
    /// legacy folder keeps being used so existing notes never disappear.
    static func defaultDocumentsURL(in parent: URL, fileManager: FileManager = .default) -> URL {
        let directory = parent.appendingPathComponent(defaultFolderName, isDirectory: true)
        let legacyDirectory = parent.appendingPathComponent(legacyDefaultFolderName, isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path),
           fileManager.fileExists(atPath: legacyDirectory.path) {
            do {
                try fileManager.moveItem(at: legacyDirectory, to: directory)
            } catch {
                print("Could not move \(legacyDirectory.path) to \(directory.path): \(error)")
                return legacyDirectory
            }
        }

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func resolvedDocumentsURL(fileManager: FileManager = .default) -> URL? {
        if let cachedDocumentsURL {
            ensureDirectoryExists(at: cachedDocumentsURL, fileManager: fileManager)
            return cachedDocumentsURL
        }

        switch resolveActiveAccess(fileManager: fileManager) {
        case .accessible(let url):
            cacheAccessibleURL(url, fileManager: fileManager)
            return url
        case .softFailure:
            clearCachedAccess(failed: true)
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

    @discardableResult
    func activateDestination(id: UUID, fileManager: FileManager = .default) -> DestinationAccessResult {
        guard destinations.contains(where: { $0.id == id }) else {
            clearCachedAccess(failed: true)
            return .softFailure
        }

        stopAccessingCurrentScope()
        cachedDocumentsURL = nil
        activeDocumentsPath = nil
        activeDestinationId = id
        userDefaults.set(id.uuidString, forKey: Self.activeDestinationIdKey)

        let access = resolveActiveAccess(fileManager: fileManager)
        switch access {
        case .accessible(let url):
            cacheAccessibleURL(url, fileManager: fileManager)
        case .softFailure:
            clearCachedAccess(failed: true)
        }
        return access
    }

    func addDestination(from pickedURL: URL, activate: Bool = true, fileManager: FileManager = .default) throws -> SaveDestination {
        let accessStarted = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if accessStarted {
                pickedURL.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData: Data
        do {
            bookmarkData = try pickedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw error
        }

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
            _ = activateDestination(id: destination.id, fileManager: fileManager)
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

    /// Updates save-mode related fields and persists immediately.
    func updateDestination(
        id: UUID,
        displayName: String? = nil,
        saveMode: DestinationSaveMode? = nil,
        rollingPeriod: RollingPeriod? = nil,
        filenameFormat: String? = nil,
        newNoteFilenameFormat: NewNoteFilenameFormat? = nil,
        existingNoteFilename: String?? = nil
    ) {
        guard let index = destinations.firstIndex(where: { $0.id == id }) else { return }
        var destination = destinations[index]
        var didChange = false

        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, destination.displayName != trimmed {
                destination.displayName = trimmed
                didChange = true
            }
        }

        if let saveMode, destination.saveMode != saveMode {
            destination.saveMode = saveMode
            didChange = true
        }

        if let rollingPeriod, destination.rollingPeriod != rollingPeriod {
            destination.rollingPeriod = rollingPeriod
            // When period changes, apply that period's default format unless caller also sets format.
            if filenameFormat == nil {
                destination.filenameFormat = rollingPeriod.defaultFilenameFormat
            }
            didChange = true
        }

        if let filenameFormat {
            let trimmed = filenameFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, destination.filenameFormat != trimmed {
                destination.filenameFormat = trimmed
                didChange = true
            }
        }

        if let newNoteFilenameFormat, destination.newNoteFilenameFormat != newNoteFilenameFormat {
            destination.newNoteFilenameFormat = newNoteFilenameFormat
            didChange = true
        }

        if let existingNoteFilename {
            if destination.existingNoteFilename != existingNoteFilename {
                destination.existingNoteFilename = existingNoteFilename
                didChange = true
            }
        }

        guard didChange else { return }
        destinations[index] = destination
        persistDestinations()
    }

    func stopAccessingCurrentScope() {
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }

    private func cacheAccessibleURL(_ url: URL, fileManager: FileManager) {
        ensureDirectoryExists(at: url, fileManager: fileManager)
        cachedDocumentsURL = url
        if activeDocumentsPath != url.path {
            activeDocumentsPath = url.path
        }
        if activeAccessFailed {
            activeAccessFailed = false
        }
    }

    private func clearCachedAccess(failed: Bool) {
        cachedDocumentsURL = nil
        if activeDocumentsPath != nil {
            activeDocumentsPath = nil
        }
        if activeAccessFailed != failed {
            activeAccessFailed = failed
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
            let url = Self.defaultDocumentsURL(fileManager: fileManager)
            scopedURL = nil
            return .accessible(url)
        }

        guard let bookmarkData = destination.bookmarkData else {
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

            if scopedURL?.standardizedFileURL.path != url.standardizedFileURL.path {
                stopAccessingCurrentScope()
                let started = url.startAccessingSecurityScopedResource()
                guard started else {
                    return .softFailure
                }
                scopedURL = url
            }

            return .accessible(url)
        } catch {
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
           var decoded = try? JSONDecoder().decode([SaveDestination].self, from: data),
           !decoded.isEmpty {
            var renamedLegacyDefault = false
            for index in decoded.indices
            where decoded[index].isDefault && decoded[index].displayName == SaveDestination.legacyDefaultDisplayName {
                decoded[index].displayName = SaveDestination.defaultDisplayName
                renamedLegacyDefault = true
            }
            if renamedLegacyDefault, let migrated = try? JSONEncoder().encode(decoded) {
                userDefaults.set(migrated, forKey: destinationsKey)
            }
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
