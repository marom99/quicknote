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
        // Synthetic bookmark payload — avoid security-scoped bookmark creation
        // (requires a signed host with app-scope keys in some CI/test environments).
        let bookmarkData = Data("synthetic-bookmark-payload".utf8)

        let destination = SaveDestination(
            id: UUID(),
            displayName: "Projects-2026",
            bookmarkData: bookmarkData,
            isDefault: false,
            saveMode: .rolling,
            rollingPeriod: .weekly,
            filenameFormat: "yyyy-'W'ww",
            existingNoteFilename: nil
        )

        let encoded = try JSONEncoder().encode([destination])
        let decoded = try JSONDecoder().decode([SaveDestination].self, from: encoded)

        #expect(decoded.count == 1)
        #expect(decoded[0].displayName == "Projects-2026")
        #expect(decoded[0].bookmarkData == bookmarkData)
        #expect(decoded[0].isDefault == false)
        #expect(decoded[0].saveMode == .rolling)
        #expect(decoded[0].rollingPeriod == .weekly)
        #expect(decoded[0].filenameFormat == "yyyy-'W'ww")

        defaults.set(encoded, forKey: DestinationStore.destinationsKey)
        defaults.set(destination.id.uuidString, forKey: DestinationStore.activeDestinationIdKey)

        let store = DestinationStore(userDefaults: defaults)
        #expect(store.destinations.count == 1)
        #expect(store.destinations[0].displayName == "Projects-2026")
        #expect(store.destinations[0].saveMode == .rolling)
    }

    @Test func legacyDecodeDefaultsToNewNoteSaveMode() throws {
        let id = UUID()
        // Simulate pre-save-mode persisted JSON (no saveMode / rolling fields).
        let legacyJSON = """
        [{
            "id": "\(id.uuidString)",
            "displayName": "Freewrite",
            "isDefault": true
        }]
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode([SaveDestination].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0].saveMode == .newNote)
        #expect(decoded[0].rollingPeriod == .daily)
        #expect(decoded[0].filenameFormat == RollingPeriod.daily.defaultFilenameFormat)
        #expect(decoded[0].existingNoteFilename == nil)

        let defaults = makeIsolatedDefaults()
        defaults.set(data, forKey: DestinationStore.destinationsKey)
        defaults.set(id.uuidString, forKey: DestinationStore.activeDestinationIdKey)
        let store = DestinationStore(userDefaults: defaults)
        #expect(store.destinations[0].saveMode == .newNote)
    }

    @Test func updateDestinationPersistsSaveModeFields() throws {
        let defaults = makeIsolatedDefaults()
        let store = DestinationStore(userDefaults: defaults)
        let id = store.destinations[0].id

        store.updateDestination(
            id: id,
            saveMode: .rolling,
            rollingPeriod: .weekly,
            filenameFormat: "yyyy-'W'ww"
        )

        #expect(store.destinations[0].saveMode == .rolling)
        #expect(store.destinations[0].rollingPeriod == .weekly)
        #expect(store.destinations[0].filenameFormat == "yyyy-'W'ww")

        let reloaded = DestinationStore(userDefaults: defaults)
        #expect(reloaded.destinations[0].saveMode == .rolling)
        #expect(reloaded.destinations[0].rollingPeriod == .weekly)
    }

    @Test func updateDestinationPeriodAppliesDefaultFormat() {
        let defaults = makeIsolatedDefaults()
        let store = DestinationStore(userDefaults: defaults)
        let id = store.destinations[0].id

        store.updateDestination(id: id, rollingPeriod: .monthly)
        #expect(store.destinations[0].filenameFormat == RollingPeriod.monthly.defaultFilenameFormat)
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
