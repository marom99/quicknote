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

    private func configure(_ coordinator: FreewriteTextEditor.Coordinator, _ textView: NSTextView, text: String,
                           editorID: UUID, colorScheme: ColorScheme = .light, increasedContrast: Bool = false) {
        coordinator.configureTextView(
            textView,
            text: text,
            editorID: editorID,
            selectedFont: "Lato-Regular",
            lineSpacing: 4,
            colorScheme: colorScheme,
            increasedContrast: increasedContrast
        )
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func caretRetainsContrastWithoutMatchingBodyInk(scheme: ColorScheme) throws {
        let (coordinator, editor, _) = makeEditor()
        let id = UUID()
        let isLight = scheme == .light
        for content in ["", "Hills and quiet mornings\n\n## Heading\n\n- [ ] A task"] {
            configure(coordinator, editor, text: content, editorID: id, colorScheme: scheme)
            let body = try #require(editor.typingAttributes[.foregroundColor] as? NSColor)
            let caret = try #require(editor.insertionPointColor?.usingColorSpace(.sRGB))
            #expect(caret.alphaComponent == 1)
            let gray = caret.redComponent
            let bodyGray = try #require(body.usingColorSpace(.sRGB)).redComponent
            #expect(isLight ? gray > bodyGray : gray < bodyGray)
            let luminance = pow((gray + 0.055) / 1.055, 2.4)
            #expect((isLight ? 1.05 / (luminance + 0.05) : (luminance + 0.05) / 0.05) >= 5)

            let selection = NSRange(location: (content as NSString).length, length: 0)
            editor.setSelectedRange(selection)
            configure(coordinator, editor, text: content, editorID: id, colorScheme: scheme, increasedContrast: true)
            #expect(editor.insertionPointColor == body)
            #expect(editor.selectedRange() == selection)
        }
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
