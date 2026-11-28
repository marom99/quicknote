import AppKit
import SwiftUI
import Testing
@testable import freewrite

@MainActor
@Suite(.serialized)
struct EditorMarkdownTests {
    @Test func keyboardRevealsInlineSourceAndKeepsNativeNavigationAndUndo() async throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor, deterministicUndo: true)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: "", id: nil)
        for character in "**Test*" { key(String(character), in: window) }
        #expect(characterIsHidden(at: 0, in: editor) == false)
        key("*", in: window)
        #expect(source.value == "**Test**")
        #expect(editor.selectedRange() == NSRange(location: 8, length: 0))
        for index in [0, 1, 6, 7] { #expect(!characterIsHidden(at: index, in: editor)) }
        #expect(!isBold(try font(in: editor, at: 2)))

        key("\r", code: 36, in: window)
        #expect(characterIsHidden(at: 0, in: editor))
        #expect(isBold(try font(in: editor, at: 2)))
        key("\u{f702}", code: 123, in: window)
        await settleSelection()
        #expect(!characterIsHidden(at: 0, in: editor))

        key("\u{f702}", code: 123, in: window)
        #expect(editor.selectedRange().location < 8)
        key("\u{f703}", code: 124, in: window)
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        key("\u{7f}", code: 51, in: window)
        #expect(source.value == "**Test*\n")
        let undo = try #require(editor.undoManager)
        undo.undo()
        #expect(source.value == "**Test**\n")
        undo.redo()
        #expect(source.value == "**Test*\n")

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        key("\u{f728}", code: 117, in: window)
        #expect(source.value == "*Test*\n")
        undo.undo()
        #expect(source.value == "**Test*\n")
    }

    @Test(arguments: [false, true])
    func typedHeadingStaysSourceUntilReturnAndReappearsOnArrowUp(afterBullet: Bool) async throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: "", id: UUID())
        if afterBullet {
            key("-", code: 27, in: window)
            #expect(source.value == "- ")
            #expect(editor.textStorage?.attribute(.markdownGlyph, at: 0, effectiveRange: nil) as? UInt16 == 0x2022)
            key("\r", code: 36, in: window)
            #expect(source.value == "")
        }
        for character in "# Heading" {
            key(String(character), in: window)
            #expect(!characterIsHidden(at: 0, in: editor))
        }
        #expect(source.value == "# Heading")
        #expect(try font(in: editor, at: 2).pointSize == 16)
        key("\r", code: 36, in: window)
        #expect(source.value == "# Heading\n")
        #expect(characterIsHidden(at: 0, in: editor))
        #expect(try font(in: editor, at: 2).pointSize > 16)
        key("\u{f700}", code: 126, in: window)
        await settleSelection()
        #expect(!characterIsHidden(at: 0, in: editor))
        #expect(try font(in: editor, at: 2).pointSize == 16)
        #expect(source.value == "# Heading\n")
    }

    @Test func lineTransitionsRevealLinkQuoteAndFenceSyntaxWithoutChangingSelection() async throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        let markdown = "Plain\n> [link](url)\n\n```swift\nlet x = 1\n```\n"
        source.value = markdown
        configure(coordinator, editor, text: markdown, id: UUID())
        let original = markdown as NSString
        let url = original.range(of: "url")
        let fence = original.range(of: "```swift")
        #expect(characterIsHidden(at: url.location, in: editor))
        #expect(characterIsHidden(at: fence.location, in: editor))
        editor.setSelectedRange(url)
        await settleSelection()
        #expect(editor.selectedRange() == url)
        #expect(!characterIsHidden(at: url.location, in: editor))
        #expect(characterIsHidden(at: fence.location, in: editor))
        editor.setSelectedRange(NSRange(location: fence.location, length: 0))
        await settleSelection()
        #expect(characterIsHidden(at: url.location, in: editor))
        #expect(!characterIsHidden(at: fence.location, in: editor))
        #expect(Data(source.value.utf8) == Data(markdown.utf8))
    }

    @Test func keyboardAutoBulletSurvivesAutosaveBindingAndContinuesThenExits() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor, deterministicUndo: true)
        defer { window.contentView = nil }
        let session = UUID()
        configure(coordinator, editor, text: "", id: session)
        key("-", code: 27, in: window)
        #expect(source.value == "- ")
        let layout = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        layout.ensureLayout(for: container)
        let glyph = layout.glyph(at: 0)
        let font = try font(in: editor, at: 0)
        var bullet: UInt16 = 0x2022
        var expected: CGGlyph = 0
        #expect(CTFontGetGlyphsForCharacters(font, &bullet, &expected, 1))
        #expect(glyph == UInt32(expected))

        configure(coordinator, editor, text: source.value, id: session)
        let undo = try #require(editor.undoManager)
        #expect(undo.canUndo)
        key(" ", code: 49, in: window, groupUndo: false)
        #expect(source.value == "- ")
        editor.breakUndoCoalescing()
        undo.undo()
        #expect(source.value == "")
        configure(coordinator, editor, text: source.value, id: session)
        #expect(undo.canRedo)
        undo.redo()
        #expect(source.value == "- ")

        key("A", in: window)
        key("\r", code: 36, in: window)
        #expect(source.value == "- A\n- ")
        key("\r", code: 36, in: window)
        #expect(source.value == "- A\n")
        undo.undo()
        #expect(source.value == "- A\n- ")
    }

    @Test func emptyTypedDashAfterParagraphAppearsAsBulletInsteadOfSetextHeading() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: "Paragraph\n", id: UUID())
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        key("-", code: 27, in: window)
        #expect(source.value == "Paragraph\n- ")
        #expect((try font(in: editor, at: 0)).pointSize == 16)
        #expect(editor.textStorage?.attribute(.markdownGlyph, at: 10, effectiveRange: nil) as? UInt16 == 0x2022)
        key("\r", code: 36, in: window)
        #expect(source.value == "Paragraph\n")
    }

    @Test func keyboardContinuesOrderedNestedAndTaskItemsAndLeavesCodeLiteral() {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        let examples = [
            ("3. One", "\r", "3. One\n4. "),
            ("- Parent\n  - Child", "\r", "- Parent\n  - Child\n  - "),
            ("- [x] Done", "\r", "- [x] Done\n- [ ] "),
            ("```\n", "-", "```\n-"),
            ("", "---", "---"),
        ]
        for (initial, typed, expected) in examples {
            configure(coordinator, editor, text: initial, id: UUID())
            editor.setSelectedRange(NSRange(location: initial.utf16.count, length: 0))
            for character in typed {
                key(String(character), code: character == "\r" ? 36 : 27, in: window)
            }
            #expect(source.value == expected)
        }
    }

    @Test func pastedDashInlineDashAndLiteralEscapeAreNotAutoExpanded() {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: "", id: UUID())
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("-", forType: .string)
        #expect(editor.readSelection(from: pasteboard, type: .string))
        #expect(source.value == "-")

        configure(coordinator, editor, text: "A", id: UUID())
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        key("-", code: 27, in: window)
        #expect(source.value == "A-")

        configure(coordinator, editor, text: "", id: UUID())
        key("\\", in: window)
        key("-", code: 27, in: window)
        key(" ", code: 49, in: window)
        #expect(source.value == "\\- ")
        #expect(!characterIsHidden(at: 0, in: editor))
        #expect(!characterIsHidden(at: 1, in: editor))
        key("\r", code: 36, in: window)
        #expect(characterIsHidden(at: 0, in: editor))
    }

    @Test func switchingToSourceRevealsSyntaxWithoutChangingSelectionOrBytes() {
        let (editor, coordinator, source) = makeEditor()
        let id = UUID()
        source.value = "**📝** [link](https://example.com)\nPlain"
        configure(coordinator, editor, text: source.value, id: id)
        let selection = (source.value as NSString).range(of: "Plain")
        editor.setSelectedRange(selection)
        configure(coordinator, editor, text: source.value, id: id, scheme: .dark)
        #expect(characterIsHidden(at: 0, in: editor))
        coordinator.configureTextView(editor, text: source.value, editorID: id, selectedFont: "Lato-Regular",
                                      lineSpacing: 4, colorScheme: .light, showsMarkdownSource: true)
        #expect(!characterIsHidden(at: 0, in: editor))
        #expect(editor.selectedRange() == selection)
        #expect(Data(source.value.utf8) == Data(editor.string.utf8))
        configure(coordinator, editor, text: source.value, id: id)
        #expect(characterIsHidden(at: 0, in: editor))
    }

    @Test func renderedWindowTitleOmitsInlineFormattingSyntax() {
        #expect(EditorMarkdown.renderedTitle("**Test** and [a guide](https://example.com)") == "Test and a guide")
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
        #expect(!isBold(try font(in: editor, at: 5)))

        let selection = NSRange(location: 2, length: 2)
        editor.setSelectedRange(selection)
        configure(coordinator, editor, text: editor.string, id: id, scheme: .dark)
        #expect(editor.selectedRange() == selection)
        #expect(!isBold(try font(in: editor, at: 5)))
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
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        #expect(editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string).map { Data($0.utf8) } == expected)
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
        #expect(!isBold(try font(in: editor, at: 2)))
        #expect(!characterIsHidden(at: 0, in: editor))

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

    @Test func changingFenceUpdatesFollowingLinesAndSplittingAHeadingClearsOldStyle() async throws {
        let (editor, coordinator, source) = makeEditor()
        let initial = "# Heading\n\n```\n**line**\n```\n# Tail"
        configure(coordinator, editor, text: initial, id: UUID())
        let start = (initial as NSString).range(of: "```").location
        let fencedBody = (initial as NSString).range(of: "line").location
        #expect(editor.textStorage?.attribute(.backgroundColor, at: fencedBody, effectiveRange: nil) != nil)
        editor.insertText("!", replacementRange: NSRange(location: start, length: 1))
        #expect(editor.textStorage?.attribute(.backgroundColor, at: fencedBody, effectiveRange: nil) == nil)
        #expect(isBold(try font(in: editor, at: fencedBody)))
        editor.setSelectedRange(NSRange(location: fencedBody, length: 0))
        await settleSelection()
        #expect(!isBold(try font(in: editor, at: fencedBody)))
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

    private func configure(_ coordinator: FreewriteTextEditor.Coordinator, _ editor: NSTextView, text: String, id: UUID?, scheme: ColorScheme = .light) {
        coordinator.configureTextView(editor, text: text, editorID: id, selectedFont: "Lato-Regular", lineSpacing: 4, colorScheme: scheme)
    }

    private final class KeyboardTestWindow: NSWindow {
        let keyboardUndoManager = UndoManager()
        override var undoManager: UndoManager? { keyboardUndoManager }
    }

    private func attach(_ editor: NSTextView, deterministicUndo: Bool = false) -> NSWindow {
        let window: NSWindow
        if deterministicUndo {
            let test = KeyboardTestWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: true)
            test.keyboardUndoManager.groupsByEvent = false
            window = test
        } else {
            window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: true)
        }
        window.contentView = editor
        window.makeFirstResponder(editor)
        return window
    }

    private func key(_ characters: String, code: UInt16 = 0, in window: NSWindow, groupUndo: Bool = true) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
        guard let event else { return }
        if groupUndo, let undo = (window as? KeyboardTestWindow)?.keyboardUndoManager {
            undo.beginUndoGrouping()
            defer { undo.endUndoGrouping() }
            window.sendEvent(event)
        } else {
            window.sendEvent(event)
        }
    }

    private func characterIsHidden(at index: Int, in editor: NSTextView) -> Bool {
        guard let layout = editor.layoutManager, let container = editor.textContainer else { return false }
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndexForCharacter(at: index)
        return layout.propertyForGlyph(at: glyph).contains(.null)
    }

    private func settleSelection() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func font(in editor: NSTextView, at index: Int) throws -> NSFont {
        try #require(editor.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
    }

    private func isBold(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }
}
