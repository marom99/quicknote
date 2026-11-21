import AppKit
import Carbon
import Testing
@testable import freewrite

struct QuickCaptureTests {
    @Test func hotKeyMapping() {
        #expect(CaptureHotKey.standard.keyCode == UInt32(kVK_ANSI_N))
        #expect(CaptureHotKey.standard.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
        #expect(CaptureHotKey.standard.displayString == "⌃⌥⌘N")
        let empty = CaptureHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [])
        #expect(empty.carbonModifiers == 0)
        #expect(empty.displayString == "N")
        let shifted = CaptureHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.shift, .command, .capsLock])
        #expect(shifted.carbonModifiers == UInt32(shiftKey | cmdKey))
        #expect(shifted.displayString == "⇧⌘N")
    }

    @MainActor @Test func targetsOnlyKeyEditorAndActivatesFirst() {
        var events: [String] = []
        let center = QuickCaptureCenter(activate: { events.append("activate") }, fallback: { events.append("fallback") })
        center.openWindow = { events.append("open") }
        for key in [false, true] {
            center.register(id: UUID(), editor: .init(isAvailable: { true }, isKey: { key },
                show: { events.append(key ? "show-key" : "show-other") },
                capture: { events.append(key ? "capture-key" : "capture-other") }))
        }
        center.trigger()
        #expect(events == ["activate", "show-key", "capture-key"])
        #expect(!center.hasPendingCapture)
    }

    @MainActor @Test func opensAndConsumesPendingRequestOnce() {
        var opened = 0
        var captures = 0
        let center = QuickCaptureCenter(activate: {}, fallback: {})
        center.openWindow = { opened += 1 }
        center.trigger()
        #expect(opened == 1)
        #expect(center.hasPendingCapture)
        let editor = QuickCaptureCenter.Editor(isAvailable: { true }, isKey: { false }, show: {}, capture: { captures += 1 })
        let id = UUID()
        center.register(id: id, editor: editor)
        center.register(id: id, editor: editor)
        #expect(captures == 1)
        #expect(!center.hasPendingCapture)
    }

    @MainActor @Test func closedEditorsUseFallbackAndKeepPendingRequest() {
        var fallbacks = 0
        var captures = 0
        let center = QuickCaptureCenter(activate: {}, fallback: { fallbacks += 1 })
        center.register(id: UUID(), editor: .init(isAvailable: { false }, isKey: { true }, show: {}, capture: { captures += 1 }))
        center.trigger()
        #expect(fallbacks == 1)
        #expect(captures == 0)
        #expect(center.hasPendingCapture)
    }

    @MainActor @Test func showWindowDoesNotStartCaptureAndUnregisterRemovesTarget() {
        var shown = 0
        var captures = 0
        var opened = 0
        let center = QuickCaptureCenter(activate: {}, fallback: {})
        center.openWindow = { opened += 1 }
        let id = UUID()
        center.register(id: id, editor: .init(isAvailable: { true }, isKey: { false }, show: { shown += 1 }, capture: { captures += 1 }))
        center.showWindow()
        #expect(shown == 1)
        #expect(captures == 0)
        center.unregister(id: id)
        center.showWindow()
        #expect(opened == 1)
        #expect(!center.hasPendingCapture)
    }
}
