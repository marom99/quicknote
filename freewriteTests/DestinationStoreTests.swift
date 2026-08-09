import Foundation
import Testing
@testable import freewrite

struct DestinationStoreTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "DestinationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

  @Test func firstLaunchSeedsDefaultFreewriteDestination() {
        let defaults = makeIsolatedDefaults()
        let store = DestinationStore(userDefaults: defaults)

        #expect(store.destinations.count == 1)
        #expect(store.destinations[0].isDefault)
        #expect(store.destinations[0].displayName == "Freewrite")
        #expect(store.activeDestinationId == store.destinations[0].id)

        let documentsURL = store.resolvedDocumentsURL()
        #expect(documentsURL != nil)
        #expect(documentsURL?.lastPathComponent == "Freewrite")
        #expect(store.activeAccessFailed == false)
    }

    @Test func encodingRoundTripPreservesBookmarkAndDisplayName() throws {
        let defaults = makeIsolatedDefaults()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freewrite-dest-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bookmarkData = try tempDir.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let destination = SaveDestination(
            id: UUID(),
            displayName: "Projects-2026",
            bookmarkData: bookmarkData,
            isDefault: false
        )

        let encoded = try JSONEncoder().encode([destination])
        let decoded = try JSONDecoder().decode([SaveDestination].self, from: encoded)

        #expect(decoded.count == 1)
        #expect(decoded[0].displayName == "Projects-2026")
        #expect(decoded[0].bookmarkData == bookmarkData)
        #expect(decoded[0].isDefault == false)

        defaults.set(encoded, forKey: DestinationStore.destinationsKey)
        defaults.set(destination.id.uuidString, forKey: DestinationStore.activeDestinationIdKey)

        let store = DestinationStore(userDefaults: defaults)
        #expect(store.destinations.count == 1)
        #expect(store.destinations[0].displayName == "Projects-2026")
    }

    @Test func renameUpdatesDisplayNameOnly() {
        let defaults = makeIsolatedDefaults()
        let store = DestinationStore(userDefaults: defaults)
        let id = store.destinations[0].id
        let originalBookmark = store.destinations[0].bookmarkData

        store.renameDestination(id: id, displayName: "July")

        #expect(store.destinations[0].displayName == "July")
        #expect(store.destinations[0].bookmarkData == originalBookmark)
        #expect(store.destinations[0].isDefault == true)
    }

    @Test func defaultDestinationVideosURLIsUnderDocumentsRoot() {
        let defaults = makeIsolatedDefaults()
        let store = DestinationStore(userDefaults: defaults)

        let documentsURL = store.resolvedDocumentsURL()
        let videosURL = store.resolvedVideosURL()

        #expect(documentsURL != nil)
        #expect(videosURL != nil)
        #expect(videosURL?.deletingLastPathComponent() == documentsURL)
        #expect(videosURL?.lastPathComponent == "Videos")
    }

    @Test func activatingUnknownDestinationSoftFails() {
        let defaults = makeIsolatedDefaults()
        let store = DestinationStore(userDefaults: defaults)

        let result = store.activateDestination(id: UUID())
        #expect(result == .softFailure)
        #expect(store.activeAccessFailed == true)
    }
}
