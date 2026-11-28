import AppKit
import SwiftUI
import Testing
@testable import freewrite

@MainActor
@Suite(.serialized)
struct TaskCheckboxTests {
    private let note = "- [ ] Buy milk\n- [x] Ship it\n\nPlain line\n"

    @Test func togglingATaskRewritesOnlyTheStateCharacter() {
        #expect(EditorMarkdown.toggledTask(in: "- [ ] Buy milk", at: 2) == "- [x] Buy milk")
        #expect(EditorMarkdown.toggledTask(in: "- [x] Buy milk", at: 2) == "- [ ] Buy milk")
        #expect(EditorMarkdown.toggledTask(in: "- [X] Buy milk", at: 2) == "- [ ] Buy milk")
        #expect(EditorMarkdown.toggledTask(in: "  - [ ] Nested", at: 4) == "  - [x] Nested")
        #expect(EditorMarkdown.toggledTask(in: "* [ ] Star", at: 2) == "* [x] Star")

        for (source, location) in [("- [ ] A", 2), ("- [x] A", 2)] {
            let toggled = EditorMarkdown.toggledTask(in: source, at: location)
            #expect(toggled.flatMap { EditorMarkdown.toggledTask(in: $0, at: location) } == source)
        }
    }

    @Test func onlyRenderedTaskBoxesToggle() {
        #expect(EditorMarkdown.toggledTask(in: "- Buy milk", at: 2) == nil)
        #expect(EditorMarkdown.toggledTask(in: "- [y] Keep", at: 2) == nil)
        #expect(EditorMarkdown.toggledTask(in: "[ ] Loose", at: 0) == nil)
        #expect(EditorMarkdown.toggledTask(in: "A [ ] Mid-line", at: 2) == nil)
        #expect(EditorMarkdown.toggledTask(in: "> - [ ] Quoted", at: 4) == "> - [x] Quoted")
        #expect(EditorMarkdown.toggledTask(in: "- [ ] A", at: 0) == nil)
        #expect(EditorMarkdown.toggledTask(in: "- [ ] A", at: 40) == nil)
    }

    @Test func boxesSitOnTheirOwnLinesAndKeepLineHeight() throws {
        let (editor, coordinator, _) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: note, id: UUID())
        editor.setSelectedRange(NSRange(location: 30, length: 0))
        let layout = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        layout.ensureLayout(for: container)

        let first = try #require(editor.taskBoxRect(at: 2))
        let second = try #require(editor.taskBoxRect(at: 17))
        #expect(editor.taskBoxRect(at: 0) == nil)
        #expect(editor.taskBoxRect(at: 40) == nil)
        #expect(first.width == EditorMarkdown.taskBoxSize(forFontSize: FreewriteTextEditor.bodyFontSize))
        for character in [2, 17] {
            let line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: character),
                                               effectiveRange: nil)
            let box = try #require(editor.taskBoxRect(at: character))
            let point = NSPoint(x: box.midX - editor.textContainerOrigin.x,
                                y: box.midY - editor.textContainerOrigin.y)
            #expect(line.insetBy(dx: 0, dy: -2).contains(point))
        }
        #expect(second.minY > first.maxY)

        let before = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 2), effectiveRange: nil)
        editor.toggleTask(at: 2)
        let after = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 2), effectiveRange: nil)
        #expect(before == after)
        #expect(editor.taskBoxRect(at: 2) == first)
    }

    @Test func clickingTheBoxTogglesItWithoutMovingTheCaret() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: note, id: UUID())
        let caret = NSRange(location: 30, length: 0)
        editor.setSelectedRange(caret)

        let box = try #require(editor.taskBoxRect(at: 2))
        let down = try #require(mouse(.leftMouseDown, at: box.center, in: editor, window: window))
        let up = try #require(mouse(.leftMouseUp, at: box.center, in: editor, window: window))
        editor.mouseDown(with: down)
        editor.mouseUp(with: up)

        #expect(source.value == "- [x] Buy milk\n- [x] Ship it\n\nPlain line\n")
        #expect(editor.string == source.value)
        #expect(editor.selectedRange() == caret)
        #expect(window.firstResponder === editor)

        let checkedBox = try #require(editor.taskBoxRect(at: 17))
        editor.mouseDown(with: try #require(mouse(.leftMouseDown, at: checkedBox.center, in: editor, window: window)))
        editor.mouseUp(with: try #require(mouse(.leftMouseUp, at: checkedBox.center, in: editor, window: window)))
        #expect(source.value == "- [x] Buy milk\n- [ ] Ship it\n\nPlain line\n")
        #expect(editor.selectedRange() == caret)
    }

    @Test func clickingTheTextIsNotACheckboxTarget() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: note, id: UUID())
        editor.setSelectedRange(NSRange(location: 30, length: 0))
        let box = try #require(editor.taskBoxRect(at: 2))

        #expect(!editor.beginTaskPress(at: NSPoint(x: box.maxX + 6, y: box.midY)))
        #expect(editor.string == note)
        #expect(!editor.beginTaskPress(at: NSPoint(x: box.maxX + 20, y: box.midY)))
        #expect(!editor.beginTaskPress(at: NSPoint(x: box.midX, y: box.maxY + 5)))
        editor.endTaskPress(at: NSPoint(x: box.maxX + 20, y: box.midY))
        #expect(editor.string == note)

        let textX = box.maxX + 40
        #expect(editor.hitTest(NSPoint(x: textX, y: box.midY)) === editor)
        #expect(editor.taskBoxes(in: box.insetBy(dx: -2, dy: -2)).count == 1)
    }

    @Test func releasingOutsideTheBoxLeavesItUnchanged() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: note, id: UUID())
        editor.setSelectedRange(NSRange(location: 30, length: 0))
        let box = try #require(editor.taskBoxRect(at: 2))

        editor.mouseDown(with: try #require(mouse(.leftMouseDown, at: box.center, in: editor, window: window)))
        editor.mouseUp(with: try #require(mouse(.leftMouseUp, at: NSPoint(x: box.maxX + 30, y: box.midY),
                                                in: editor, window: window)))
        #expect(editor.string == note)
    }

    @Test func togglingIsOneUndoStep() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor, deterministicUndo: true)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: note, id: UUID())
        editor.setSelectedRange(NSRange(location: 30, length: 0))
        let box = try #require(editor.taskBoxRect(at: 2))
        let undo = try #require(editor.undoManager)
        undo.beginUndoGrouping()
        editor.mouseDown(with: try #require(mouse(.leftMouseDown, at: box.center, in: editor, window: window)))
        editor.mouseUp(with: try #require(mouse(.leftMouseUp, at: box.center, in: editor, window: window)))
        undo.endUndoGrouping()
        #expect(source.value.hasPrefix("- [x] Buy milk"))

        undo.undo()
        #expect(source.value == note)
        undo.redo()
        #expect(source.value.hasPrefix("- [x] Buy milk"))
    }

    @Test func sourceModeHidesTheCheckboxLayer() throws {
        let (editor, coordinator, source) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: note, id: UUID())
        editor.setSelectedRange(NSRange(location: 30, length: 0))
        #expect(editor.taskBoxRect(at: 2) != nil)
        configure(coordinator, editor, text: source.value, id: UUID(), showsMarkdownSource: true)
        #expect(editor.taskBoxRect(at: 2) == nil)
        #expect(!editor.beginTaskPress(at: NSPoint(x: 20, y: 20)))
    }

    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func renderedBoxesReadAtRestHoverAndChecked(scheme: ColorScheme) throws {
        let (editor, coordinator, _) = makeEditor()
        let window = attach(editor)
        defer { window.contentView = nil }
        configure(coordinator, editor, text: "- [ ] One\n- [x] Two\n", id: UUID(), scheme: scheme)
        editor.setSelectedRange(NSRange(location: 16, length: 0))
        let unchecked = try #require(editor.taskBoxRect(at: 2))
        let checked = try #require(editor.taskBoxRect(at: 12))

        let rest = try render(editor)
        let uncheckedInk = pixels(in: rest, inside: unchecked, matching: { isInk($0, scheme: scheme) })
        let checkedInk = pixels(in: rest, inside: checked, matching: { isInk($0, scheme: scheme) })
        #expect(!uncheckedInk.isEmpty)
        #expect(checkedInk.count > uncheckedInk.count, "checked item adds a filled centre")
        #expect(!hasAccentTint(in: rest, inside: unchecked))
        #expect(middleLine(of: checked, in: rest, scheme: scheme).contains { $0 >= 2 },
                "checked box keeps a visible gap between ring and fill")

        editor.mouseMoved(with: try #require(mouse(.mouseMoved, at: unchecked.center, in: editor, window: window)))
        let hovered = try render(editor)
        #expect(hasAccentTint(in: hovered, inside: unchecked))

        editor.mouseDown(with: try #require(mouse(.leftMouseDown, at: unchecked.center, in: editor, window: window)))
        let pressed = try render(editor)
        #expect(!pixels(in: pressed, inside: unchecked, matching: { isInk($0, scheme: scheme) }).isEmpty)
        editor.mouseUp(with: try #require(mouse(.leftMouseUp, at: NSPoint(x: unchecked.midX, y: unchecked.maxY + 5),
                                                in: editor, window: window)))
        #expect(editor.string == "- [ ] One\n- [x] Two\n")
    }

    private func render(_ editor: NSView) throws -> NSBitmapImageRep {
        let scale: CGFloat = 2
        let size = editor.bounds.size
        let pdf = try #require(editor.dataWithPDF(inside: editor.bounds) as Data?)
        let page = try #require(NSImage(data: pdf))
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        page.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func pixels(in rep: NSBitmapImageRep, inside rect: NSRect,
                        matching predicate: (NSColor) -> Bool) -> [(x: Int, y: Int)] {
        let scale = CGFloat(rep.pixelsWide) / max(rep.size.width, 1)
        let box = rect.insetBy(dx: 1, dy: 1)
        let columns = Int(box.minX * scale)...max(Int(box.maxX * scale), Int(box.minX * scale))
        let rows = Int(box.minY * scale)...max(Int(box.maxY * scale), Int(box.minY * scale))
        var found: [(Int, Int)] = []
        for y in rows {
            for x in columns {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let color = rep.colorAt(x: x, y: y) else { continue }
                if predicate(color) { found.append((x, y)) }
            }
        }
        return found
    }

    /// Runs of drawn and blank pixels along the horizontal centre of `rect`.
    private func middleLine(of rect: NSRect, in rep: NSBitmapImageRep, scheme: ColorScheme) -> [Int] {
        let scale = CGFloat(rep.pixelsWide) / max(rep.size.width, 1)
        let y = Int(rect.midY * scale)
        var gaps: [Int] = []
        var run = 0
        for x in Int(rect.minX * scale)...max(Int(rect.maxX * scale), Int(rect.minX * scale)) {
            let drawn = rep.colorAt(x: x, y: y).map { isInk($0, scheme: scheme) } ?? false
            if drawn {
                gaps.append(run)
                run = 0
            } else {
                run += 1
            }
        }
        return gaps
    }

    private func isInk(_ color: NSColor, scheme: ColorScheme) -> Bool {
        guard color.alphaComponent > 0.5 else { return false }
        return scheme == .light ? color.brightnessComponent < 0.85 : color.brightnessComponent > 0.15
    }

    private func hasAccentTint(in rep: NSBitmapImageRep, inside rect: NSRect) -> Bool {
        pixels(in: rep, inside: rect, matching: { color in
            let rgb = color.usingColorSpace(.deviceRGB) ?? .black
            return abs(rgb.redComponent - rgb.blueComponent) > 0.03
        }).count > 6
    }

    private final class Source {
        var value = ""
    }

    private func makeEditor() -> (FreewriteEditorTextView, FreewriteTextEditor.Coordinator, Source) {
        let source = Source()
        let editor = FreewriteEditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.drawsBackground = false
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

    private func configure(_ coordinator: FreewriteTextEditor.Coordinator, _ editor: NSTextView, text: String,
                           id: UUID?, scheme: ColorScheme = .light, showsMarkdownSource: Bool = false) {
        coordinator.configureTextView(editor, text: text, editorID: id, selectedFont: "Lato-Regular",
                                      lineSpacing: 4, colorScheme: scheme, showsMarkdownSource: showsMarkdownSource)
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

    /// A real `NSEvent` carrying `point` (text view coordinates) in window coordinates.
    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in editor: NSTextView,
                       window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: editor.convert(point, to: nil), modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
