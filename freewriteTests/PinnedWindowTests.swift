import AppKit
import Testing
@testable import freewrite

@MainActor
struct PinnedWindowTests {
    private func makeEditorWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
        return window
    }

    @Test func pinningFloatsTheWindowAboveOtherAppsOnEverySpace() {
        let window = makeEditorWindow()
        let before = window.collectionBehavior

        PinnedWindow.apply(to: window, pinned: true)

        #expect(window.level == .floating)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(!window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(!window.hidesOnDeactivate)
        #expect(PinnedWindow.isPinned(window))
        #expect(window.collectionBehavior != before)
    }

    @Test func unpinningRestoresTheOriginalWindowState() {
        let window = makeEditorWindow()
        let originalLevel = window.level
        let originalBehavior = window.collectionBehavior

        PinnedWindow.apply(to: window, pinned: true)
        PinnedWindow.apply(to: window, pinned: false)

        #expect(window.level == originalLevel)
        #expect(window.collectionBehavior == originalBehavior)
        #expect(!PinnedWindow.isPinned(window))
    }

    @Test func pinningTwiceStillRestoresTheStateFromBeforeTheFirstPin() {
        let window = makeEditorWindow()
        let originalLevel = window.level
        let originalBehavior = window.collectionBehavior

        PinnedWindow.apply(to: window, pinned: true)
        PinnedWindow.apply(to: window, pinned: true)
        PinnedWindow.apply(to: window, pinned: false)

        #expect(window.level == originalLevel)
        #expect(window.collectionBehavior == originalBehavior)
    }

    @Test func unpinningAWindowThatWasNeverPinnedLeavesItAlone() {
        let window = makeEditorWindow()
        let originalBehavior = window.collectionBehavior

        PinnedWindow.apply(to: window, pinned: false)

        #expect(window.level == .normal)
        #expect(window.collectionBehavior == originalBehavior)
        #expect(!PinnedWindow.isPinned(window))
    }

    @Test func appKitResettingTheLevelIsUndoneByTheNextWindowEvent() {
        let window = makeEditorWindow()
        PinnedWindow.apply(to: window, pinned: true)

        // Full screen exit / deminiaturize rebuild the window and drop our level.
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)

        #expect(window.level == .floating)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))

        PinnedWindow.apply(to: window, pinned: false)
    }

    @Test func floatingWindowReappliesAfterAnyScreenParameterChange() {
        let window = makeEditorWindow()
        PinnedWindow.apply(to: window, pinned: true)

        window.level = .normal
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(window.level == .floating)

        PinnedWindow.apply(to: window, pinned: false)
    }

    @Test func quickCapturePanelIsNotPinned() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        let originalBehavior = panel.collectionBehavior

        PinnedWindow.apply(to: panel, pinned: true)

        #expect(!PinnedWindow.isPinned(panel))
        #expect(panel.collectionBehavior == originalBehavior)
    }

    @Test func firstClickIntoAnInactiveEditorPlacesTheCaret() throws {
        let editor = FreewriteEditorTextView()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        #expect(editor.acceptsFirstMouse(for: event))
    }
}
