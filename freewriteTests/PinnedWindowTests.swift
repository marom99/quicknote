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

    @Test func editorWindowFloatsAboveOtherAppsOnEverySpace() {
        let window = makeEditorWindow()

        PinnedWindow.apply(to: window)

        #expect(window.level == .floating)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(!window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(!window.hidesOnDeactivate)
    }

    @Test func applyingTwiceKeepsTheSameFloatingState() {
        let window = makeEditorWindow()

        PinnedWindow.apply(to: window)
        let behavior = window.collectionBehavior
        PinnedWindow.apply(to: window)

        #expect(window.level == .floating)
        #expect(window.collectionBehavior == behavior)
    }

    @Test func appKitResettingTheLevelIsUndoneByTheNextWindowEvent() {
        let window = makeEditorWindow()
        PinnedWindow.apply(to: window)

        // Full screen exit / deminiaturize rebuild the window and drop our level.
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)

        #expect(window.level == .floating)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    @Test func floatingWindowReappliesAfterAnyScreenParameterChange() {
        let window = makeEditorWindow()
        PinnedWindow.apply(to: window)

        window.level = .normal
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(window.level == .floating)
    }

    @Test func applyingNeverOrdersTheWindowFrontOrUnminimizesIt() {
        let window = makeEditorWindow()

        PinnedWindow.apply(to: window)

        #expect(!window.isVisible)
        #expect(!window.isMiniaturized)
        #expect(window.level == .floating)
    }

    @Test func quickCapturePanelIsLeftAlone() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let originalBehavior = panel.collectionBehavior

        PinnedWindow.apply(to: panel)

        #expect(panel.collectionBehavior == originalBehavior)
    }

    @Test func legacyToggleSettingIsCleared() {
        UserDefaults.standard.set(false, forKey: PinnedWindow.legacyDefaultsKey)
        let window = makeEditorWindow()

        PinnedWindow.apply(to: window)

        #expect(UserDefaults.standard.object(forKey: PinnedWindow.legacyDefaultsKey) == nil)
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
