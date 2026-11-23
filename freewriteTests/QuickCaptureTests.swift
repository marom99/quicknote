import AppKit
import Carbon
import Testing
@testable import freewrite

struct QuickCaptureTests {
    @Test func hotKeyMappingAndPersistence() throws {
        #expect(CaptureHotKey.standard.keyCode == UInt32(kVK_ANSI_N))
        #expect(CaptureHotKey.standard.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
        #expect(CaptureHotKey.standard.displayString == "⌃⌥⌘N")

        let custom = CaptureHotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: [.shift, .command, .capsLock], keyLabel: "K")
        #expect(custom.carbonModifiers == UInt32(shiftKey | cmdKey))
        #expect(custom.displayString == "⇧⌘K")
        let decoded = try JSONDecoder().decode(CaptureHotKey.self, from: JSONEncoder().encode(custom))
        #expect(decoded == custom)
    }

    @Test func shortcutKeyCanBeEnteredWithoutItsModifiers() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_K)))
        #expect(CaptureHotKey(event: event) == nil)
        #expect(CaptureHotKey(event: event, modifiers: [.control, .option, .command])?.displayString == "⌃⌥⌘K")
    }

    @MainActor @Test func showWindowTargetsKeyEditorAndDoesNotUseFallback() {
        var events: [String] = []
        let center = QuickCaptureCenter(activate: { events.append("activate") }, fallback: { events.append("fallback") })
        center.openWindow = { events.append("open") }
        for key in [false, true] {
            center.register(id: UUID(), editor: .init(isAvailable: { true }, isKey: { key },
                show: { events.append(key ? "show-key" : "show-other") }, canAcceptCapture: { _ in true }))
        }

        center.showWindow()

        #expect(events == ["activate", "show-key"])
    }

    @MainActor @Test func showWindowReopensAfterTheLastEditorCloses() {
        var shown = 0
        var opened = 0
        let center = QuickCaptureCenter(activate: {}, fallback: {})
        center.openWindow = { opened += 1 }
        let id = UUID()
        center.register(id: id, editor: .init(isAvailable: { true }, isKey: { false }, show: { shown += 1 },
                                            canAcceptCapture: { _ in true }))
        center.showWindow()
        center.unregister(id: id)
        center.showWindow()

        #expect(shown == 1)
        #expect(opened == 1)
    }
}
