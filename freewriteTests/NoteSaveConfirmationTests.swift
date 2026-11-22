import Testing
@testable import freewrite

struct NoteSaveConfirmationTests {
    @Test func successfulSaveUsesDestinationDisplayName() {
        #expect(NoteSaveConfirmation.message(didSave: true, destinationName: "Personal Journal") == "Saved to Personal Journal")
    }

    @Test func emptyCanvasDoesNotClaimSaved() {
        #expect(NoteSaveConfirmation.message(didSave: false, destinationName: "Freewrite") == nil)
    }

    @Test func failedWriteDoesNotClaimSaved() {
        #expect(NoteSaveConfirmation.message(didSave: false, destinationName: "Unavailable folder") == nil)
    }
}
