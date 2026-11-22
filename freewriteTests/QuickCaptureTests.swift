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
        #expect(events == ["activate", "capture-key", "show-key"])
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

    @MainActor @Test func inputIsBlockedUntilClearedTextIsApplied() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let editor = NSTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(editor)
        editor.string = "previous capture"
        window.makeFirstResponder(editor)
        QuickCaptureInputGate.suspend(in: window)
        #expect(!editor.isEditable)
        #expect(window.firstResponder !== editor)
        #expect(editor.string == "previous capture")
        editor.string = ""
        QuickCaptureInputGate.resume(editor)
        #expect(editor.isEditable)
        #expect(window.firstResponder === editor)
        #expect(editor.string.isEmpty)
    }

    @MainActor @Test func resumeMovesSelectionToEndOfRollingNote() {
        let editor = NSTextView()
        editor.string = "Earlier writing 📝\n---\n2026-11-21 12:15\n"
        editor.setSelectedRange(NSRange(location: 0, length: 7))
        editor.isEditable = false
        QuickCaptureInputGate.resume(editor)
        #expect(editor.selectedRange() == NSRange(location: (editor.string as NSString).length, length: 0))
        #expect(editor.isEditable)
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
