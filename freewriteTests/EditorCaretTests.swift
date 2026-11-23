import AppKit
import SwiftUI
import Testing
@testable import freewrite

@MainActor
struct EditorCaretTests {
    private final class TextBox {
        var value = ""
    }

    private func makeEditor() -> (FreewriteTextEditor.Coordinator, NSTextView, TextBox) {
        let box = TextBox()
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let coordinator = FreewriteTextEditor.Coordinator(text: binding, onScrollMetricsChange: { _ in })
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.delegate = coordinator
        coordinator.textView = textView
        return (coordinator, textView, box)
    }

    private func configure(_ coordinator: FreewriteTextEditor.Coordinator, _ textView: NSTextView, text: String, editorID: UUID) {
        coordinator.configureTextView(
            textView,
            text: text,
            editorID: editorID,
            selectedFont: "Lato-Regular",
            lineSpacing: 4,
            colorScheme: .light
        )
    }

    @Test func bodyUsesFixedSizeForLoadedTextAndTyping() {
        let (coordinator, textView, _) = makeEditor()
        configure(coordinator, textView, text: "Loaded note", editorID: UUID())

        let loadedFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let typingFont = textView.typingAttributes[.font] as? NSFont
        #expect(loadedFont?.pointSize == 16)
        #expect(typingFont?.pointSize == 16)
    }

    @Test func rollingSeparatorPutsNextSessionOnItsOwnLine() {
        let (coordinator, textView, box) = makeEditor()
        let entryId = UUID()
        configure(coordinator, textView, text: "", editorID: entryId)
        textView.insertText("SESSION ONE", replacementRange: textView.selectedRange())

        let separator = DestinationWriteTarget.sessionSeparator()
        configure(coordinator, textView, text: box.value + separator, editorID: entryId)
        coordinator.applyCaretEndRequest(UUID())
        textView.insertText("SESSION TWO", replacementRange: textView.selectedRange())

        #expect(box.value == "SESSION ONE" + separator + "SESSION TWO")
    }

    @Test func externalAppendKeepsCaretWithoutRequest() {
        let (coordinator, textView, _) = makeEditor()
        let entryId = UUID()
        configure(coordinator, textView, text: "SESSION ONE", editorID: entryId)
        textView.setSelectedRange(NSRange(location: 11, length: 0))

        configure(coordinator, textView, text: "SESSION ONE" + DestinationWriteTarget.sessionSeparator(), editorID: entryId)

        #expect(textView.selectedRange().location == 11)
    }
}
