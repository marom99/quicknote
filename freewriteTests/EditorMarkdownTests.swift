import AppKit
import SwiftUI
import Testing
@testable import freewrite

@MainActor
struct EditorMarkdownTests {
    @Test func sourceRangesCoverSupportedSyntaxWithoutChangingUnicode() {
        let source = "📝 intro\r\n## A **bold** _café_ ##\n> Quote\n- item\n2) ordered\n~~ignore~~ `x * y` [自分](https://example.com)"
        let spans = EditorMarkdown.spans(in: source)
        let text = source as NSString
        func matches(_ style: EditorMarkdown.Style) -> [String] {
            spans.filter { $0.style == style }.map { text.substring(with: $0.range) }
        }
        #expect(matches(.heading(2)) == [" A **bold** _café_"])
        #expect(matches(.bold) == ["bold"])
        #expect(matches(.italic) == ["café"])
        #expect(matches(.quote) == ["Quote"])
        #expect(matches(.listMarker) == ["-", "2)"])
        #expect(matches(.code) == ["x * y"])
        #expect(matches(.linkLabel) == ["自分"])
    }

    @Test func escapesFenceLengthsAndCodePrecedence() {
        let source = "\\*escaped* foo_bar_baz ***both***\n````swift\n**literal**\n```\n# still code\n````\n## Heading\n~~~\n[code](url)"
        let spans = EditorMarkdown.spans(in: source)
        let text = source as NSString
        #expect(spans.filter { $0.style == .code }.map { text.substring(with: $0.range) } == [
            "**literal**", "```", "# still code", "[code](url)"
        ])
        #expect(spans.filter { $0.style == .boldItalic }.map { text.substring(with: $0.range) } == ["both"])
        #expect(!spans.contains { [.italic, .bold, .heading(1), .linkLabel].contains($0.style) })
        #expect(spans.contains { $0.style == .heading(2) })
    }

    @Test func unmatchedAndEscapedDelimitersRemainLiteral() {
        let unmatched = String(repeating: "*a ", count: 3000)
        #expect(EditorMarkdown.spans(in: unmatched).isEmpty)
        let source = #"**strong and _italic_** **escaped closing\**"#
        let spans = EditorMarkdown.spans(in: source)
        let text = source as NSString
        #expect(spans.filter { $0.style == .bold }.map { text.substring(with: $0.range) } == ["strong and _italic_"])
        #expect(spans.filter { $0.style == .italic }.map { text.substring(with: $0.range) } == ["italic"])
    }

    @Test func typingAndUndoKeepSourceSelectionAndTypingFont() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor
        defer { window.contentView = nil }
        window.makeFirstResponder(editor)
        let id = UUID()
        configure(coordinator, editor, text: "**📝 memo*", id: id)
        let end = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
        editor.insertText("*", replacementRange: editor.selectedRange())
        #expect(Array(source.value.utf8) == Array("**📝 memo**".utf8))
        #expect(editor.selectedRange() == NSRange(location: end + 1, length: 0))
        #expect(isBold(try font(in: editor, at: 5)))

        let selection = NSRange(location: 2, length: 2)
        editor.setSelectedRange(selection)
        configure(coordinator, editor, text: editor.string, id: id, scheme: .dark)
        #expect(editor.selectedRange() == selection)
        #expect(isBold(try font(in: editor, at: 5)))
        #expect(editor.textStorage?.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
            == NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        #expect((editor.typingAttributes[.font] as? NSFont)?.pointSize == 16)

        editor.breakUndoCoalescing()
        let undo = try #require(editor.undoManager)
        #expect(undo.canUndo)
        undo.undo()
        #expect(source.value == "**📝 memo*")
        #expect(!isBold(try font(in: editor, at: 5)))
        undo.redo()
        #expect(source.value == "**📝 memo**")

        configure(coordinator, editor, text: "Plain note", id: UUID())
        #expect(!undo.canUndo)
        #expect(!isBold(try font(in: editor, at: 0)))
    }

    @Test func plainPasteAndSaveRetainMarkdownBytes() throws {
        let (editor, coordinator, source) = makeEditor()
        let initial = "## A heading"
        configure(coordinator, editor, text: initial, id: UUID())
        editor.setSelectedRange(NSRange(location: initial.utf16.count, length: 0))
        let pasted = "\n**e\u{301}** [label](https://example.com)\n>  \n`🍵`"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString(pasted, forType: .string)
        #expect(editor.readSelection(from: pasteboard, type: .string))
        let note = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("md")
        defer { try? FileManager.default.removeItem(at: note) }
        var saveState = NoteSaveState()
        _ = try saveState.save(source.value, to: note)
        let expected = Data((initial + pasted).utf8)
        #expect(try Data(contentsOf: note) == expected)
        #expect(Data(editor.string.utf8) == expected)
        #expect(editor.textStorage?.attribute(.link, at: initial.utf16.count + 12, effectiveRange: nil) == nil)
    }

    @Test func markedTextSurvivesSwiftUIUpdatesAndStylesOnCommit() async throws {
        let (editor, coordinator, source) = makeEditor()
        let id = UUID()
        source.value = "**"
        configure(coordinator, editor, text: source.value, id: id)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        configure(coordinator, editor, text: source.value, id: id)
        #expect(editor.markedRange() == NSRange(location: 2, length: 1))
        #expect(editor.string == "**に")
        #expect(source.value == "**")
        editor.insertText("日本**", replacementRange: editor.markedRange())
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(!editor.hasMarkedText())
        #expect(source.value == "**日本**")
        #expect(isBold(try font(in: editor, at: 2)))

        editor.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        source.value = "Another note"
        configure(coordinator, editor, text: source.value, id: UUID())
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(!editor.hasMarkedText())
        #expect(editor.string == "Another note")
        #expect(source.value == "Another note")
    }

    @Test func changingFenceUpdatesFollowingLinesAndSplittingAHeadingClearsOldStyle() throws {
        let (editor, coordinator, source) = makeEditor()
        let initial = "# Heading\n\n```\n**line**\n```\n# Tail"
        configure(coordinator, editor, text: initial, id: UUID())
        let start = (initial as NSString).range(of: "```").location
        let fencedBody = (initial as NSString).range(of: "line").location
        #expect(editor.textStorage?.attribute(.backgroundColor, at: fencedBody, effectiveRange: nil) != nil)
        editor.insertText("!", replacementRange: NSRange(location: start, length: 1))
        #expect(editor.textStorage?.attribute(.backgroundColor, at: fencedBody, effectiveRange: nil) == nil)
        #expect(isBold(try font(in: editor, at: fencedBody)))
        let tail = (source.value as NSString).range(of: "Tail").location
        #expect(editor.textStorage?.attribute(.backgroundColor, at: tail, effectiveRange: nil) != nil)

        let textStart = (source.value as NSString).range(of: "Heading").location
        editor.insertText("\n", replacementRange: NSRange(location: textStart, length: 0))
        #expect(!isBold(try font(in: editor, at: textStart + 1)))
        #expect(try font(in: editor, at: textStart + 1).pointSize == 16)
    }

    private final class Source {
        var value = ""
    }

    private func makeEditor() -> (FreewriteEditorTextView, FreewriteTextEditor.Coordinator, Source) {
        let source = Source()
        let editor = FreewriteEditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.isRichText = false
        editor.allowsUndo = true
        let coordinator = FreewriteTextEditor.Coordinator(
            text: Binding(get: { source.value }, set: { source.value = $0 }),
            onScrollMetricsChange: { _ in }
        )
        coordinator.textView = editor
        editor.delegate = coordinator
        return (editor, coordinator, source)
    }

    private func configure(_ coordinator: FreewriteTextEditor.Coordinator, _ editor: NSTextView, text: String, id: UUID, scheme: ColorScheme = .light) {
        coordinator.configureTextView(editor, text: text, editorID: id, selectedFont: "Lato-Regular", lineSpacing: 4, colorScheme: scheme)
    }

    private func font(in editor: NSTextView, at index: Int) throws -> NSFont {
        try #require(editor.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
    }

    private func isBold(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }
}
