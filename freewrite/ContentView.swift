// Swift 5.0
//
//  ContentView.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum EntryType {
    case text
    case video
}

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    var previewText: String
    var entryType: EntryType
    var videoFilename: String?
    var timestamp: Date? = nil
    var searchableBody: String = ""
}

struct EditorScrollMetrics: Equatable {
    var contentHeight: CGFloat = 1
    var viewportHeight: CGFloat = 1
    var offsetY: CGFloat = 0

    var maxOffset: CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    var canScroll: Bool {
        maxOffset > 1
    }

    var offsetFraction: CGFloat {
        guard canScroll else { return 0 }
        return min(max(offsetY / maxOffset, 0), 1)
    }
}

struct EditorScrollRequest: Equatable {
    let id = UUID()
    let fraction: CGFloat
}

final class FreewriteEditorTextView: NSTextView, NSLayoutManagerDelegate {
    var onMarkedTextChange: (() -> Void)?
    var onEditingFocusChange: (() -> Void)?
    private(set) var isSettingMarkedText = false
    var showsMarkdownSource = false {
        didSet {
            if showsMarkdownSource != oldValue {
                automaticBulletEnd = nil
                liveHeadingLineStart = nil
                liveTaskLineStart = nil
            }
        }
    }
    private var keyboardCharacters: String?
    private var automaticBulletEnd: Int?
    private(set) var provisionalBulletLocation: Int?
    var liveHeadingLineStart: Int?
    var liveTaskLineStart: Int?

    func resetMarkdownKeyboardState() {
        automaticBulletEnd = nil
        provisionalBulletLocation = nil
        liveHeadingLineStart = nil
        liveTaskLineStart = nil
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onEditingFocusChange?() }
        return accepted
    }

    /// The activating click into an inactive (pinned) window lands in the text,
    /// so the caret is where it was clicked and typing can start at once.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onEditingFocusChange?() }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        let before = automaticBulletEnd
        automaticBulletEnd = nil
        let keyboardEdit = !showsMarkdownSource && !hasMarkedText()
            && event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if keyboardEdit {
            keyboardCharacters = event.characters
            if let before, before >= 2, before <= string.utf16.count,
               selectedRange() == NSRange(location: before, length: 0) {
                let prefix = NSRange(location: before - 2, length: 2)
                if (string as NSString).substring(with: prefix) == "- " {
                    if event.characters == " " {
                        keyboardCharacters = nil
                        return
                    }
                    if event.characters == "-" {
                        keyboardCharacters = nil
                        super.insertText("--", replacementRange: prefix)
                        return
                    }
                }
            }
        }
        defer { keyboardCharacters = nil }
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if keyboardCharacters == " ", string as? String == " ", !hasMarkedText(), selectedRanges.count == 1 {
            let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
            let source = self.string as NSString
            let line = source.lineRange(for: NSRange(location: target.location, length: 0))
            let opener = NSRange(location: line.location, length: target.location - line.location)
            if target.length == 0, EditorMarkdown.isATXOpener(in: self.string, range: opener) {
                liveHeadingLineStart = line.location
                breakUndoCoalescing()
                super.insertText(string, replacementRange: replacementRange)
                breakUndoCoalescing()
                return
            }
        }
        if keyboardCharacters == "-", string as? String == "-", !hasMarkedText(),
           selectedRanges.count == 1 {
            let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
            let source = self.string as NSString
            let line = source.lineRange(for: NSRange(location: target.location, length: 0))
            if target.length == 0, target.location == line.location,
               (line.length == 0 || [UInt16(10), 13, 0x2028, 0x2029].contains(source.character(at: line.location))),
               !MarkdownSourceProjection.isLiteral(at: target.location, in: self.string) {
                breakUndoCoalescing()
                provisionalBulletLocation = target.location
                super.insertText("- ", replacementRange: target)
                automaticBulletEnd = NSMaxRange(target) + 2
                return
            }
        }
        if keyboardCharacters == "]", string as? String == "]", !hasMarkedText(),
           selectedRanges.count == 1 {
            let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
            let source = self.string as NSString
            var contentEnd = 0
            source.getLineStart(nil, end: nil, contentsEnd: &contentEnd, for: NSRange(location: target.location, length: 0))
            let line = source.lineRange(for: NSRange(location: target.location, length: 0))
            let typed = NSRange(location: line.location, length: target.location - line.location)
            if target.length == 0, NSMaxRange(typed) == contentEnd,
               let task = EditorMarkdown.taskOpening(typed: source.substring(with: typed)),
               !MarkdownSourceProjection.isLiteral(at: target.location, in: self.string) {
                liveTaskLineStart = line.location
                super.insertText(task, replacementRange: typed)
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    private static let listPrefix = try! NSRegularExpression(pattern: #"^[ \t]*([-+*]|([0-9]{1,9})([.)]))[ \t]+(?:\[([ xX])\][ \t]+)?"#)

    private func listMatch(at caret: Int) -> (NSTextCheckingResult, NSRange)? {
        guard !showsMarkdownSource, !hasMarkedText(), selectedRanges.count == 1, selectedRange().length == 0,
              let storage = textStorage else { return nil }
        var start = 0
        var end = 0
        let source = string as NSString
        source.getLineStart(&start, end: nil, contentsEnd: &end, for: NSRange(location: caret, length: 0))
        let line = NSRange(location: start, length: end - start)
        guard let match = Self.listPrefix.firstMatch(in: string, range: line),
              caret >= NSMaxRange(match.range),
              storage.attribute(.markdownList, at: match.range(at: 1).location, effectiveRange: nil) != nil else { return nil }
        return (match, line)
    }

    override func insertNewline(_ sender: Any?) {
        let caret = selectedRange().location
        if let (match, line) = listMatch(at: caret) {
            let source = string as NSString
            let start = NSMaxRange(match.range)
            let body = source.substring(with: NSRange(location: start, length: NSMaxRange(line) - start))
            breakUndoCoalescing()
            if body.trimmingCharacters(in: .whitespaces).isEmpty {
                provisionalBulletLocation = nil
                liveTaskLineStart = nil
                super.insertText("", replacementRange: line)
            } else {
                let marker = match.range(at: 1)
                let indentation = source.substring(with: NSRange(location: line.location, length: marker.location - line.location))
                let digits = match.range(at: 2)
                let next = digits.location == NSNotFound
                    ? source.substring(with: marker)
                    : "\((Int(source.substring(with: digits)) ?? 0) + 1)\(source.substring(with: match.range(at: 3)))"
                let task = match.range(at: 4).location == NSNotFound ? "" : "[ ] "
                let caret = selectedRange()
                liveTaskLineStart = task.isEmpty ? nil : caret.location + 1
                super.insertText("\n" + indentation + next + " " + task, replacementRange: caret)
            }
            return
        }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        let caret = selectedRange().location
        if !hasMarkedText(), selectedRanges.count == 1, selectedRange().length == 0,
           let start = liveHeadingLineStart, caret > start,
           let prefix = EditorMarkdown.atxPrefix(in: string, at: start), caret <= NSMaxRange(prefix),
           textStorage?.attribute(.markdownHidden, at: caret - 1, effectiveRange: nil) != nil {
            super.insertText("", replacementRange: NSRange(location: caret - 1, length: 1))
            return
        }
        if let (match, line) = listMatch(at: caret), caret == NSMaxRange(match.range), caret == NSMaxRange(line) {
            provisionalBulletLocation = nil
            liveTaskLineStart = nil
            super.insertText("", replacementRange: line)
            return
        }
        if deleteAcrossHidden(backward: true) { return }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if deleteAcrossHidden(backward: false) { return }
        super.deleteForward(sender)
    }

    private func deleteAcrossHidden(backward: Bool) -> Bool {
        guard isEditable, !showsMarkdownSource, !hasMarkedText(), selectedRanges.count == 1, let storage = textStorage else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let caret = selection.location
        var index = backward ? caret - 1 : caret
        let first = index
        while index >= 0, index < storage.length,
              storage.attribute(.markdownHidden, at: index, effectiveRange: nil) != nil {
            index += backward ? -1 : 1
        }
        guard index != first, index >= 0, index < storage.length else { return false }
        let deletion = (string as NSString).rangeOfComposedCharacterSequence(at: index)
        breakUndoCoalescing()
        super.insertText("", replacementRange: deletion)
        setSelectedRange(NSRange(location: backward ? caret - deletion.length : caret, length: 0))
        return true
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        guard !showsMarkdownSource else { return 0 }
        var modified: (glyphs: [CGGlyph], flags: [NSLayoutManager.GlyphProperty])?
        let marked = markedRange()
        for offset in 0..<glyphRange.length {
            let index = characterIndexes[offset]
            if NSLocationInRange(index, marked) { continue }
            let attributes = storage.attributes(at: index, effectiveRange: nil)
            let hidden = attributes[.markdownHidden] != nil
            var glyph = glyphs[offset]
            if attributes[.markdownTask] != nil {
                var space: UInt16 = 0x20
                guard CTFontGetGlyphsForCharacters(font, &space, &glyph, 1) else { continue }
            } else if !hidden {
                guard var character = attributes[.markdownGlyph] as? UInt16,
                      CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { continue }
            }
            if modified == nil {
                modified = (Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length)),
                            Array(UnsafeBufferPointer(start: properties, count: glyphRange.length)))
            }
            modified?.glyphs[offset] = glyph
            modified?.flags[offset] = hidden
                ? (attributes[.markdownCaretAnchor] != nil ? .controlCharacter : .null)
                : []
        }
        guard let modified else { return 0 }
        layoutManager.setGlyphs(modified.glyphs, properties: modified.flags, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard layoutManager.textStorage?.attribute(.markdownCaretAnchor, at: charIndex, effectiveRange: nil) != nil else {
            return action
        }
        return .zeroAdvancement
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        isSettingMarkedText = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        isSettingMarkedText = false
        let marked = markedRange()
        if marked.location != NSNotFound, marked.length > 0 {
            layoutManager?.invalidateGlyphs(forCharacterRange: marked, changeInLength: 0, actualCharacterRange: nil)
        }
        onMarkedTextChange?()
    }

    override func unmarkText() {
        let wasMarked = hasMarkedText()
        super.unmarkText()
        if wasMarked { onMarkedTextChange?() }
    }

    struct TaskBox {
        let characterIndex: Int
        let rect: NSRect
    }

    private static let taskPressScale: CGFloat = 0.9

    private var taskTrackingArea: NSTrackingArea?
    private var scrollObserver: NSObjectProtocol?
    private var hoveredTaskCharacter: Int?
    private var pressedTaskCharacter: Int?

    /// Every checkbox laid out inside `rect`, in text view coordinates.
    func taskBoxes(in rect: NSRect) -> [TaskBox] {
        guard !showsMarkdownSource, let layout = layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0, rect.width > 0, rect.height > 0 else { return [] }
        layout.ensureLayout(for: container)
        let glyphRange = layout.glyphRange(
            forBoundingRect: rect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y),
            in: container
        )
        let characterRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var boxes: [TaskBox] = []
        storage.enumerateAttribute(.markdownTask, in: characterRange) { value, range, _ in
            guard value != nil, let box = taskBoxRect(at: range.location) else { return }
            boxes.append(TaskBox(characterIndex: range.location, rect: box))
        }
        return boxes
    }

    /// Each task item's line, from the item's left edge to the end of its text, in text view coordinates.
    func taskRowRects(in rect: NSRect) -> [(characterIndex: Int, rect: NSRect)] {
        guard !showsMarkdownSource, let layout = layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0, rect.width > 0, rect.height > 0 else { return [] }
        layout.ensureLayout(for: container)
        let glyphRange = layout.glyphRange(
            forBoundingRect: rect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y),
            in: container
        )
        let source = string as NSString
        let characters = source.lineRange(
            for: layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        )
        var rows: [(characterIndex: Int, rect: NSRect)] = []
        storage.enumerateAttribute(.markdownTask, in: characters) { value, range, _ in
            guard value != nil else { return }
            let paragraph = source.lineRange(for: NSRange(location: range.location, length: 0))
            let glyphs = layout.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
            layout.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, usedRect, _, _, _ in
                let origin = self.textContainerOrigin
                rows.append((range.location, NSRect(
                    x: origin.x + lineRect.minX,
                    y: origin.y + lineRect.minY,
                    width: max(usedRect.maxX - lineRect.minX, 0),
                    height: lineRect.height
                )))
            }
        }
        return rows
    }

    /// The task item whose line holds `point`, in text view coordinates.
    func taskRow(at point: NSPoint) -> Int? {
        let probe = NSRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
        return taskRowRects(in: probe).first { $0.rect.contains(point) }?.characterIndex
    }

    /// The cursor `point` deserves: a hand across a task item's line, otherwise the text I-beam.
    func cursor(at point: NSPoint) -> NSCursor {
        taskRow(at: point) == nil ? .iBeam : .pointingHand
    }

    /// The checkbox whose `[` sits at `characterIndex`, in text view coordinates.
    func taskBoxRect(at characterIndex: Int) -> NSRect? {
        guard !showsMarkdownSource, let layout = layoutManager, let container = textContainer,
              let storage = textStorage, characterIndex >= 0, characterIndex < storage.length,
              storage.attribute(.markdownTask, at: characterIndex, effectiveRange: nil) != nil else { return nil }
        layout.ensureLayout(for: container)
        let glyphIndex = layout.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex < layout.numberOfGlyphs else { return nil }
        let font = storage.attribute(.font, at: characterIndex, effectiveRange: nil) as? NSFont
            ?? .systemFont(ofSize: FreewriteTextEditor.bodyFontSize)
        let size = EditorMarkdown.taskBoxSize(forFontSize: font.pointSize)
        let slot = EditorMarkdown.taskSlotWidth(forFontSize: font.pointSize)
        let lineRect = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let location = layout.location(forGlyphAt: glyphIndex)
        let centreY = textContainerOrigin.y + lineRect.minY + location.y - font.capHeight / 2
        return NSRect(x: textContainerOrigin.x + lineRect.minX + location.x + (slot - size) / 2, y: centreY - size / 2,
                      width: size, height: size)
    }

    /// Starts a press on a checkbox and returns whether the point landed on one.
    @discardableResult
    func beginTaskPress(at point: NSPoint) -> Bool {
        guard let character = taskRow(at: point) else { return false }
        pressedTaskCharacter = character
        if let box = taskBoxRect(at: character) { setNeedsDisplay(box.insetBy(dx: -3, dy: -3)) }
        return true
    }

    /// Finishes a press started on a checkbox, toggling it when the release stayed inside.
    func endTaskPress(at point: NSPoint) {
        guard let pressed = pressedTaskCharacter else { return }
        pressedTaskCharacter = nil
        if let box = taskBoxRect(at: pressed) { setNeedsDisplay(box.insetBy(dx: -3, dy: -3)) }
        guard taskRow(at: point) == pressed else { return }
        toggleTask(at: pressed)
    }

    /// Flips the task item owning the checkbox at `characterIndex` between `[ ]` and `[x]`.
    @discardableResult
    func toggleTask(at characterIndex: Int) -> Bool {
        guard let storage = textStorage, let state = EditorMarkdown.taskStateRange(in: string, at: characterIndex),
              let toggled = EditorMarkdown.toggledTask(in: string, at: characterIndex) else { return false }
        let replacement = (toggled as NSString).substring(with: state)
        let selection = selectedRange()
        breakUndoCoalescing()
        guard shouldChangeText(in: state, replacementString: replacement) else { return false }
        storage.replaceCharacters(in: state, with: replacement)
        didChangeText()
        if selectedRange() != selection { setSelectedRange(selection) }
        breakUndoCoalescing()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if beginTaskPress(at: convert(event.locationInWindow, from: nil)) { return }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedTaskCharacter != nil else { return super.mouseUp(with: event) }
        endTaskPress(at: convert(event.locationInWindow, from: nil))
        if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedTaskCharacter == nil else { return }
        super.mouseDragged(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateTaskHover(at: convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateTaskHover(at: nil)
        super.mouseExited(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let taskTrackingArea { removeTrackingArea(taskTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        taskTrackingArea = area
        window?.acceptsMouseMovedEvents = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for row in taskRowRects(in: visibleRect) {
            addCursorRect(row.rect, cursor: .pointingHand)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        pressedTaskCharacter = nil
        updateTaskHover(at: nil)
        window?.invalidateCursorRects(for: self)
    }

    private func updateTaskHover(at point: NSPoint?) {
        let inside = point.map { bounds.contains($0) } ?? false
        let hovered = inside ? point.flatMap { taskRow(at: $0) } : nil
        if hovered != hoveredTaskCharacter {
            let previous = hoveredTaskCharacter
            hoveredTaskCharacter = hovered
            for character in [previous, hovered].compactMap({ $0 }) {
                if let box = taskBoxRect(at: character) { setNeedsDisplay(box.insetBy(dx: -3, dy: -3)) }
            }
        }
        guard inside else { return }
        if hovered == nil { NSCursor.iBeam.set() } else { NSCursor.pointingHand.set() }
    }

    private func pointerLocation() -> NSPoint? {
        guard let window, window.isKeyWindow else { return nil }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(location) ? location : nil
    }

    private func observeScrolling() {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateTaskHover(at: self.pointerLocation())
            self.window?.invalidateCursorRects(for: self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !showsMarkdownSource, let storage = textStorage else { return }
        for box in taskBoxes(in: dirtyRect) {
            let checked = storage.attribute(.markdownTask, at: box.characterIndex, effectiveRange: nil) as? Bool ?? false
            let ink = storage.attribute(.foregroundColor, at: box.characterIndex, effectiveRange: nil) as? NSColor ?? .textColor
            drawTaskBox(box.rect,
                        checked: checked,
                        hovered: hoveredTaskCharacter == box.characterIndex,
                        pressed: pressedTaskCharacter == box.characterIndex,
                        ink: ink)
        }
    }

    private func drawTaskBox(_ rect: NSRect, checked: Bool, hovered: Bool, pressed: Bool, ink: NSColor) {
        let scale = pressed ? Self.taskPressScale : 1
        let width = rect.width * scale
        let box = NSRect(x: rect.midX - width / 2, y: rect.midY - width / 2, width: width, height: width)
        let radius = width * 0.29
        let lineWidth = max(1.5, width * 0.13)
        let lit = hovered || pressed
        if lit {
            NSColor.controlAccentColor.withAlphaComponent(pressed ? 0.22 : 0.14).setFill()
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
        }
        if checked {
            let inner = box.insetBy(dx: width * 0.26, dy: width * 0.26)
            ink.withAlphaComponent(lit ? 0.78 : 0.68).setFill()
            NSBezierPath(roundedRect: inner, xRadius: radius * 0.45, yRadius: radius * 0.45).fill()
        }
        ink.withAlphaComponent(checked ? 0.72 : (lit ? 0.8 : 0.5)).setStroke()
        let ring = NSBezierPath(roundedRect: box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                                xRadius: max(radius - lineWidth / 2, 0.5), yRadius: max(radius - lineWidth / 2, 0.5))
        ring.lineWidth = lineWidth
        ring.stroke()
    }

    var allowsAutomaticFocus = true {
        didSet {
            if allowsAutomaticFocus && !oldValue {
                requestAutomaticFocus()
            }
        }
    }
    private var keyWindowObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrolling()
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
        keyWindowObserver = nil
        guard let window else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.focusIfAvailable()
        }
        requestAutomaticFocus()
    }

    func requestAutomaticFocus() {
        DispatchQueue.main.async { [weak self] in
            self?.focusIfAvailable()
        }
    }

    func focusIfAvailable() {
        guard allowsAutomaticFocus, let window, window.isKeyWindow,
              !isHiddenOrHasHiddenAncestor, window.attachedSheet == nil else { return }
        let responder = window.firstResponder
        if let textView = responder as? NSTextView, textView.window === window,
           !textView.isHiddenOrHasHiddenAncestor {
            if !textView.isFieldEditor { return }
            if let owner = textView.delegate as? NSView,
               owner.window === window, !owner.isHiddenOrHasHiddenAncestor { return }
            if hasLiveFieldEditorOwner(textView, in: window.contentView) { return }
        }
        if let textField = responder as? NSTextField, textField.window === window,
           !textField.isHiddenOrHasHiddenAncestor { return }
        window.makeFirstResponder(self)
    }

    private func hasLiveFieldEditorOwner(_ editor: NSTextView, in view: NSView?) -> Bool {
        guard let view, !view.isHiddenOrHasHiddenAncestor else { return false }
        if let field = view as? NSTextField, field.currentEditor() === editor { return true }
        return view.subviews.contains { hasLiveFieldEditorOwner(editor, in: $0) }
    }

    deinit {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }
}

struct RailRemovalObserver: NSViewRepresentable {
    let onRemoval: () -> Void

    func makeNSView(context: Context) -> RemovalView {
        let view = RemovalView()
        view.onRemoval = onRemoval
        return view
    }

    func updateNSView(_ nsView: RemovalView, context: Context) {
        nsView.onRemoval = onRemoval
    }

    final class RemovalView: NSView {
        var onRemoval: (() -> Void)?
        private var wasInWindow = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                wasInWindow = true
            } else if wasInWindow {
                wasInWindow = false
                let onRemoval = onRemoval
                DispatchQueue.main.async { onRemoval?() }
            }
        }
    }
}

private struct NativeTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipView {
        TooltipView()
    }

    func updateNSView(_ nsView: TooltipView, context: Context) {
        if nsView.toolTip != text {
            nsView.toolTip = text
        }
    }

    final class TooltipView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private extension View {
    func nativeTooltip(_ text: String) -> some View {
        background(NativeTooltip(text: text).accessibilityHidden(true))
            .accessibilityHint(Text(text))
    }
}

struct FreewriteTextEditor: NSViewRepresentable {
    static let bodyFontSize: CGFloat = 16

    @Binding var text: String
    @Binding var isComposingText: Bool
    @Binding var scrollRequest: EditorScrollRequest?
    var selectionFocusRequest: UUID?

    let editorID: UUID?
    let allowsAutomaticFocus: Bool
    let focusRequest: UUID
    @Binding var caretEndRequest: UUID?
    let selectedFont: String
    let showsMarkdownSource: Bool
    let lineSpacing: CGFloat
    let colorScheme: ColorScheme
    let editorInset: CGFloat
    let editorNativeTextPadding: CGFloat
    let bottomContentMargin: CGFloat
    let onScrollMetricsChange: (EditorScrollMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isComposingText: $isComposingText, onScrollMetricsChange: onScrollMetricsChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: max(bottomContentMargin - editorInset, 0),
            right: 0
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = FreewriteEditorTextView(frame: .zero)
        textView.allowsAutomaticFocus = allowsAutomaticFocus
        textView.setAccessibilityIdentifier("mainEditor")
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = editorNativeTextPadding
        textView.textContainerInset = NSSize(
            width: max(editorInset - editorNativeTextPadding, 0),
            height: editorInset
        )
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.configureTextView(
            textView,
            text: text,
            editorID: editorID,
            selectedFont: selectedFont,
            lineSpacing: lineSpacing,
            colorScheme: colorScheme,
            showsMarkdownSource: showsMarkdownSource
        )
        context.coordinator.startObservingBoundsChanges()
        context.coordinator.publishScrollMetrics()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: max(bottomContentMargin - editorInset, 0),
            right: 0
        )

        if let textView = context.coordinator.textView {
            (textView as? FreewriteEditorTextView)?.allowsAutomaticFocus = allowsAutomaticFocus
            if context.coordinator.lastFocusRequest != focusRequest {
                context.coordinator.lastFocusRequest = focusRequest
                (textView as? FreewriteEditorTextView)?.requestAutomaticFocus()
            }
            textView.textContainer?.lineFragmentPadding = editorNativeTextPadding
            textView.textContainerInset = NSSize(
                width: max(editorInset - editorNativeTextPadding, 0),
                height: editorInset
            )
            context.coordinator.configureTextView(
                textView,
                text: text,
                editorID: editorID,
                selectedFont: selectedFont,
                lineSpacing: lineSpacing,
                colorScheme: colorScheme,
                showsMarkdownSource: showsMarkdownSource
            )
        }

        if context.coordinator.applyCaretEndRequest(caretEndRequest) {
            let appliedRequest = caretEndRequest
            DispatchQueue.main.async {
                if caretEndRequest == appliedRequest {
                    caretEndRequest = nil
                }
            }
        }

        if let request = scrollRequest, request != context.coordinator.lastAppliedScrollRequest {
            context.coordinator.scrollTo(fraction: request.fraction)
            context.coordinator.lastAppliedScrollRequest = request
        }

        if let selectionFocusRequest,
           selectionFocusRequest != context.coordinator.lastSelectionFocusRequest {
            context.coordinator.lastSelectionFocusRequest = selectionFocusRequest
            // A History row click must pull focus back from the History search field.
            DispatchQueue.main.async { [weak scrollView] in
                guard let textView = scrollView?.documentView as? NSTextView,
                      let window = textView.window, window.isKeyWindow else { return }
                window.makeFirstResponder(textView)
            }
        }

        context.coordinator.publishScrollMetrics()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingBoundsChanges()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var isComposingText: Bool
        private let onScrollMetricsChange: (EditorScrollMetrics) -> Void
        private var boundsObserver: NSObjectProtocol?
        private var isUpdatingText = false
        private var appearance: EditorAppearance?
        private var attributes: [NSAttributedString.Key: Any] = [:]
        private var isWaitingForComposition = false
        private var isUpdatingEditingLines = false
        private var projectedSpans: [EditorMarkdown.Span] = []
        private var editingLines: NSRange?

        private struct EditorAppearance: Equatable {
            let fontName: String
            let lineSpacing: CGFloat
            let colorScheme: ColorScheme
            let showsMarkdownSource: Bool
        }

        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        var lastAppliedScrollRequest: EditorScrollRequest?
        var lastSelectionFocusRequest: UUID?
        var lastConfiguredEditorID: UUID?
        var lastFocusRequest: UUID?
        var lastAppliedCaretEndRequest: UUID?

        init(text: Binding<String>, isComposingText: Binding<Bool> = .constant(false), onScrollMetricsChange: @escaping (EditorScrollMetrics) -> Void) {
            _text = text
            _isComposingText = isComposingText
            self.onScrollMetricsChange = onScrollMetricsChange
        }

        func configureTextView(
            _ textView: NSTextView,
            text: String,
            editorID: UUID?,
            selectedFont: String,
            lineSpacing: CGFloat,
            colorScheme: ColorScheme,
            showsMarkdownSource: Bool = false
        ) {
            let editorChanged = lastConfiguredEditorID != editorID
            if let editor = textView as? FreewriteEditorTextView, editor.onMarkedTextChange == nil {
                editor.onMarkedTextChange = { [weak self] in self?.finishCompositionSoon() }
                editor.onEditingFocusChange = { [weak self] in self?.updateEditingLinesSoon() }
                editor.layoutManager?.delegate = editor
            }
            if !editorChanged, isComposing(in: textView) || isWaitingForComposition { return }
            (textView as? FreewriteEditorTextView)?.showsMarkdownSource = showsMarkdownSource

            let nextAppearance = EditorAppearance(fontName: selectedFont, lineSpacing: lineSpacing, colorScheme: colorScheme, showsMarkdownSource: showsMarkdownSource)
            let appearanceChanged = appearance != nextAppearance
            if appearanceChanged {
                appearance = nextAppearance
                let fontSize = FreewriteTextEditor.bodyFontSize
                let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
                let shade: CGFloat = colorScheme == .light ? 0.20 : 0.90
                let textColor = NSColor(red: shade, green: shade, blue: shade, alpha: 1)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = max(lineSpacing, 0)
                attributes = [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
                textView.defaultParagraphStyle = paragraphStyle
                textView.insertionPointColor = textColor
            }

            if editorChanged || textView.string != text {
                isWaitingForComposition = false
                isUpdatingText = true
                (textView as? FreewriteEditorTextView)?.resetMarkdownKeyboardState()
                if textView.hasMarkedText() {
                    textView.inputContext?.discardMarkedText()
                    if textView.hasMarkedText() { textView.unmarkText() }
                }
                let selectedRanges = clampedSelectedRanges(textView.selectedRanges, maxLength: (text as NSString).length)
                textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
                textView.undoManager?.removeAllActions()
                textView.selectedRanges = selectedRanges
                restyle(textView)
                isUpdatingText = false
                if isComposingText { finishCompositionSoon() }
            } else if appearanceChanged {
                restyle(textView)
            }
            lastConfiguredEditorID = editorID
        }

        @discardableResult
        func applyCaretEndRequest(_ request: UUID?) -> Bool {
            guard let request, request != lastAppliedCaretEndRequest, let textView else { return false }
            let range = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            if let window = textView.window, window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
            lastAppliedCaretEndRequest = request
            return true
        }

        func startObservingBoundsChanges() {
            guard boundsObserver == nil, let contentView = scrollView?.contentView else { return }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publishScrollMetrics()
            }
        }

        func stopObservingBoundsChanges() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingText, let textView else { return }
            if isComposing(in: textView) || isWaitingForComposition {
                finishCompositionSoon()
                return
            }
            restyle(textView)
            text = textView.string
            publishScrollMetrics()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateEditingLinesSoon()
        }

        private func updateEditingLinesSoon() {
            guard !isUpdatingText, !isUpdatingEditingLines else { return }
            isUpdatingEditingLines = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { isUpdatingEditingLines = false }
                guard let textView, !isWaitingForComposition, !isComposing(in: textView) else { return }
                let next = activeEditingLines(in: textView)
                let endedLivePrefix = clearLivePrefixIfInactive(in: textView, editingLines: next)
                guard next != editingLines || endedLivePrefix else { return }
                let previous = editingLines
                editingLines = next
                if let previous, let next, NSIntersectionRange(previous, next).length > 0 {
                    style(textView, range: NSUnionRange(previous, next))
                } else {
                    if let previous { style(textView, range: previous) }
                    if let next { style(textView, range: next) }
                }
                publishScrollMetrics()
            }
        }

        private func activeEditingLines(in textView: NSTextView) -> NSRange? {
            guard appearance?.showsMarkdownSource == false,
                  textView.window == nil || textView.window?.firstResponder === textView else { return nil }
            let selection = textView.selectedRange()
            let source = textView.string as NSString
            guard selection.location <= source.length, selection.length <= source.length - selection.location else { return nil }
            let lines = source.lineRange(for: selection)
            return lines.length > 0 ? lines : nil
        }

        private func isComposing(in textView: NSTextView) -> Bool {
            textView.hasMarkedText() || (textView as? FreewriteEditorTextView)?.isSettingMarkedText == true
        }

        private func finishCompositionSoon() {
            guard !isUpdatingText, !isWaitingForComposition else { return }
            isWaitingForComposition = true
            DispatchQueue.main.async { [weak self] in
                guard let self, isWaitingForComposition else { return }
                isWaitingForComposition = false
                guard let textView else { return }
                let composing = isComposing(in: textView)
                if isComposingText != composing { isComposingText = composing }
                guard !composing else { return }
                restyle(textView)
                if text != textView.string { text = textView.string }
                publishScrollMetrics()
            }
        }

        private func restyle(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            editingLines = activeEditingLines(in: textView)
            clearLivePrefixIfInactive(in: textView, editingLines: editingLines)
            projectedSpans = appearance?.showsMarkdownSource == true ? [] : EditorMarkdown.displaySpans(
                in: storage.string, provisionalBullet: (textView as? FreewriteEditorTextView)?.provisionalBulletLocation
            )
            style(textView, range: NSRange(location: 0, length: storage.length))
            textView.typingAttributes = attributes
        }

        private func style(_ textView: NSTextView, range: NSRange) {
            guard let storage = textView.textStorage, range.length > 0, NSMaxRange(range) <= storage.length else { return }
            let view = textView as? FreewriteEditorTextView
            let headingPrefix = view?.liveHeadingLineStart.flatMap { EditorMarkdown.atxPrefix(in: storage.string, at: $0) }
            let taskLine = view?.liveTaskLineStart ?? editingLines?.location
            let taskPrefix = taskLine.flatMap { EditorMarkdown.taskPrefix(in: storage.string, at: $0) }
            EditorMarkdown.apply(to: storage, attributes: attributes, range: range, spans: projectedSpans,
                                 editingLines: editingLines, liveHeadingPrefix: headingPrefix, liveTaskPrefix: taskPrefix)
            textView.layoutManager?.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            textView.window?.invalidateCursorRects(for: textView)
            textView.typingAttributes = attributes
        }

        @discardableResult
        private func clearLivePrefixIfInactive(in textView: NSTextView, editingLines: NSRange?) -> Bool {
            guard let view = textView as? FreewriteEditorTextView else { return false }
            let activeLine = textView.selectedRange().length == 0 ? editingLines?.location : nil
            var cleared = false
            if let start = view.liveHeadingLineStart, start != activeLine {
                view.liveHeadingLineStart = nil
                cleared = true
            }
            if let start = view.liveTaskLineStart, start != activeLine {
                view.liveTaskLineStart = nil
                cleared = true
            }
            return cleared
        }

        func scrollTo(fraction: CGFloat) {
            guard let scrollView else { return }
            let metrics = currentMetrics()
            guard metrics.canScroll else { return }
            let y = min(max(fraction, 0), 1) * metrics.maxOffset
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            publishScrollMetrics()
        }

        func publishScrollMetrics() {
            guard let textView, let textContainer = textView.textContainer else { return }
            textView.layoutManager?.ensureLayout(for: textContainer)
            let metrics = currentMetrics()
            DispatchQueue.main.async { [onScrollMetricsChange] in
                onScrollMetricsChange(metrics)
            }
        }

        private func clampedSelectedRanges(_ ranges: [NSValue], maxLength: Int) -> [NSValue] {
            ranges.map { value in
                let range = value.rangeValue
                let location = min(range.location, maxLength)
                let length = min(range.length, max(maxLength - location, 0))
                return NSValue(range: NSRange(location: location, length: length))
            }
        }

        private func currentMetrics() -> EditorScrollMetrics {
            guard let scrollView, let textView else {
                return EditorScrollMetrics()
            }

            let viewportHeight = max(scrollView.contentView.bounds.height, 1)
            let textContainer = textView.textContainer
            let usedRect = textContainer.flatMap { textView.layoutManager?.usedRect(for: $0) } ?? .zero
            let contentHeight = max(
                usedRect.height + (textView.textContainerInset.height * 2) + scrollView.contentInsets.bottom,
                viewportHeight
            )
            let offsetY = min(max(scrollView.contentView.bounds.origin.y, 0), max(contentHeight - viewportHeight, 0))

            return EditorScrollMetrics(
                contentHeight: contentHeight,
                viewportHeight: viewportHeight,
                offsetY: offsetY
            )
        }
    }
}

struct NativeEditorEdgeScroller: NSViewRepresentable {
    let metrics: EditorScrollMetrics
    let colorScheme: ColorScheme
    let onScrollFractionChange: (CGFloat) -> Void

    final class Coordinator: NSObject {
        let onScrollFractionChange: (CGFloat) -> Void

        init(onScrollFractionChange: @escaping (CGFloat) -> Void) {
            self.onScrollFractionChange = onScrollFractionChange
        }

        @objc func scrollerChanged(_ sender: NSScroller) {
            onScrollFractionChange(CGFloat(sender.doubleValue))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollFractionChange: onScrollFractionChange)
    }

    func makeNSView(context: Context) -> NSScroller {
        let scroller = NSScroller()
        scroller.scrollerStyle = .legacy
        scroller.controlSize = .regular
        scroller.target = context.coordinator
        scroller.action = #selector(Coordinator.scrollerChanged(_:))
        scroller.isEnabled = metrics.canScroll
        scroller.isHidden = !metrics.canScroll
        updateScroller(scroller)
        return scroller
    }

    func updateNSView(_ scroller: NSScroller, context: Context) {
        scroller.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        scroller.isEnabled = metrics.canScroll
        scroller.isHidden = !metrics.canScroll
        updateScroller(scroller)
    }

    private func updateScroller(_ scroller: NSScroller) {
        let knobProportion = metrics.canScroll
            ? min(max(metrics.viewportHeight / metrics.contentHeight, 0), 1)
            : 1
        scroller.knobProportion = knobProportion
        scroller.doubleValue = Double(metrics.offsetFraction)
    }
}

struct ContentView: View {
    @StateObject private var destinationStore = DestinationStore()
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    @State private var isComposingEditorText = false
    @State private var showsMarkdownSource = false
    @State private var captureEditorSessionID = UUID()
    
    private let selectedFont: String = "Lato-Regular"
    @State private var bottomNavOpacity: Double = 1.0
    @State private var savedConfirmation: String?
    @State private var savedConfirmationID = UUID()
    @State private var isHoveringBottomNav = false
    @State private var selectedEntryIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var editorScrollMetrics = EditorScrollMetrics()
    @State private var editorScrollRequest: EditorScrollRequest?
    @State private var editorFocusRequest = UUID()
    @State private var historySelectionFocusRequest: UUID?
    @State private var historySelectionFocusEntryId: UUID?
    @State private var editorCaretEndRequest: UUID?
    @State private var selectedEntryId: UUID? = nil
    @State private var isLoadingEntry = false
    @State private var noteSaveState = NoteSaveState()
    @State private var unreadableConfiguredNoteURL: URL?
    @State private var hoveredEntryId: UUID? = nil
    @State private var showingSidebar = false  // Add this state variable
    @State private var historySearchQuery = ""
    @State private var historySearchFocusRequest: UUID?
    @State private var isSearchingNotes = false
    @State private var historyKeyboardEntryID: HistoryResult.ID?
    @State private var searchAllDestinations = false
    @State private var otherDestinationResults: [HistoryResult]?
    @State private var showingDestinationSettings = false
    @State private var hoveredTrashId: UUID? = nil
    @State private var placeholderText: String = ""  // Add this line
    @State private var isHoveringNewEntry = false
    @State private var isHoveringClock = false
    @State private var isHoveringHistory = false
    @State private var isHoveringHistoryText = false
    @State private var isHoveringHistoryPath = false
    @State private var isHoveringHistoryArrow = false
    @State private var isHoveringCopyTranscript = false
    @State private var isHoveringDestinationChip = false
    @State private var settingsDisplayName: String = ""
    @State private var settingsSaveMode: DestinationSaveMode = .newNote
    @State private var settingsRollingPeriod: RollingPeriod = .daily
    @State private var settingsFilenameFormat: String = RollingPeriod.daily.defaultFilenameFormat
    @State private var settingsNewNoteFilenameFormat: NewNoteFilenameFormat = .date
    @State private var settingsExistingNoteFilename: String? = nil
    @State private var pendingDestinationSettingsCloseAction: DestinationSettingsCloseAction? = nil
    @State private var showingDiscardDestinationSettingsConfirmation = false
    @State private var inProgressCaptureFilename: String? = nil
    @State private var liveCaptureDraftRegistration: LiveCaptureDraftRegistration?
    @State private var captureStartedAt: Date? = nil
    @State private var historyTrash: HistoryTrash? = nil
    @State private var trashedEntry: HumanEntry? = nil
    @State private var trashedEntryIndex = 0
    @State private var trashedEntryWasSelected = false
    @State private var trashDestinationID: UUID? = nil
    @State private var trashNoticeID = UUID()
    @State private var trashError: String? = nil
    @State private var noteOpenError: String? = nil
    @State private var noteSaveFailure: NoteSaveFailure?
    @State private var colorScheme: ColorScheme = .light // Add state for color scheme
    @State private var isHoveringThemeToggle = false // Add state for theme toggle hover
    @State private var didCopyTranscript: Bool = false
    @State private var selectedVideoHasTranscript = false
    @State private var currentVideoURL: URL? = nil // Add state for current video being viewed
    private let editorInset: CGFloat = 18
    // NSTextView line-fragment padding (horizontal only; top inset is 0).
    private let editorNativeTextPadding: CGFloat = 5
    // Bottom nav: 12pt above/below ~16pt controls ≈ 40pt tall.
    private let bottomNavVerticalPadding: CGFloat = 12
    private let bottomNavHeight: CGFloat = 40
    // Gap between the last editor line and the nav's top border.
    private let bottomNavContentGap: CGFloat = 8
    
    let placeholderOptions = [
        "Begin writing",
        "Pick a thought and go",
        "Start typing",
        "What's on your mind",
        "Just start",
        "Type your first thought",
        "Start with one sentence",
        "Just say it"
    ]
    
    private let fileManager = FileManager.default

    private let thumbnailMemoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    private enum DestinationSettingsCloseAction {
        case closeRail
        case openHistory
        case searchNotes
    }
    
    // Initialize with saved theme preference if available
    init() {
        // Load saved color scheme preference
        let savedScheme = UserDefaults.standard.string(forKey: "colorScheme") ?? "light"
        _colorScheme = State(initialValue: savedScheme == "dark" ? .dark : .light)
    }
    
    // Active journal root; nil when the destination cannot be accessed (soft-fail).
    private func getDocumentsDirectory() -> URL? {
        destinationStore.resolvedDocumentsURL()
    }

    private func getVideosDirectory() -> URL? {
        destinationStore.resolvedVideosURL()
    }

    private var activeDestinationHistoryLabel: String {
        destinationStore.activeAccessFailed
            ? "\(activeDestinationDisplayName) (unavailable)"
            : activeDestinationDisplayName
    }

    private func getVideoEntryDirectory(for videoFilename: String) -> URL? {
        guard let videosDirectory = getVideosDirectory() else { return nil }
        let baseName = (videoFilename as NSString).deletingPathExtension
        return videosDirectory.appendingPathComponent(baseName, isDirectory: true)
    }

    private func getManagedVideoURL(for filename: String) -> URL? {
        guard let directory = getVideoEntryDirectory(for: filename) else { return nil }
        return directory.appendingPathComponent(filename)
    }

    private func getVideoThumbnailURL(for filename: String) -> URL? {
        guard let directory = getVideoEntryDirectory(for: filename) else { return nil }
        return directory.appendingPathComponent("thumbnail.jpg")
    }

    private func getVideoTranscriptURL(for filename: String) -> URL? {
        guard let directory = getVideoEntryDirectory(for: filename) else { return nil }
        return directory.appendingPathComponent("transcript.md")
    }

    @discardableResult
    private func ensureVideoEntryDirectoryExists(for videoFilename: String) throws -> URL {
        guard let directory = getVideoEntryDirectory(for: videoFilename) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func getVideoURL(for filename: String) -> URL? {
        // Current production layout: Videos/[entry-base]/[entry-filename].mov
        if let managedVideoURL = getManagedVideoURL(for: filename),
           fileManager.fileExists(atPath: managedVideoURL.path) {
            return managedVideoURL
        }

        // Backward compatibility: older builds stored videos flat under Videos/
        if let videosDirectory = getVideosDirectory() {
            let flatVideosURL = videosDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: flatVideosURL.path) {
                return flatVideosURL
            }
        }

        // Backward compatibility: oldest builds stored videos in the destination root
        if let documentsDirectory = getDocumentsDirectory() {
            let rootVideosURL = documentsDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: rootVideosURL.path) {
                return rootVideosURL
            }
        }

        // Default to managed path for newly created entries.
        return getManagedVideoURL(for: filename)
    }

    private func resolvedVideoFilename(for entry: HumanEntry) -> String? {
        guard entry.entryType == .video else {
            return nil
        }
        if let videoFilename = entry.videoFilename, !videoFilename.isEmpty {
            return videoFilename
        }
        return entry.filename.replacingOccurrences(of: ".md", with: ".mov")
    }

    private func persistThumbnail(_ image: NSImage, for videoFilename: String) {
        do {
            let directory = try ensureVideoEntryDirectoryExists(for: videoFilename)
            let thumbnailURL = directory.appendingPathComponent("thumbnail.jpg")
            guard let tiff = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiff),
                  let imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
                print("Could not convert thumbnail image to JPEG data")
                return
            }
            try imageData.write(to: thumbnailURL, options: .atomic)
        } catch {
            print("Error saving thumbnail: \(error)")
        }
    }

    private func loadThumbnailImage(for videoFilename: String) -> NSImage? {
        let cacheKey = videoFilename as NSString
        if let cachedImage = thumbnailMemoryCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let thumbnailURL = getVideoThumbnailURL(for: videoFilename) else {
            return nil
        }
        if fileManager.fileExists(atPath: thumbnailURL.path),
           let image = NSImage(contentsOf: thumbnailURL) {
            thumbnailMemoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        // Backward compatibility: generate once for old video entries, then persist.
        guard let videoURL = getVideoURL(for: videoFilename),
              fileManager.fileExists(atPath: videoURL.path),
              let generated = generateVideoThumbnail(from: videoURL) else {
            return nil
        }
        persistThumbnail(generated, for: videoFilename)
        thumbnailMemoryCache.setObject(generated, forKey: cacheKey)
        return generated
    }

    private func loadTranscriptText(for videoFilename: String) -> String? {
        guard let transcriptURL = getVideoTranscriptURL(for: videoFilename),
              fileManager.fileExists(atPath: transcriptURL.path),
              let content = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
            return nil
        }
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func copyTranscriptForSelectedVideoEntry() {
        guard let selectedEntryId,
              let selectedEntry = entries.first(where: { $0.id == selectedEntryId }),
              let videoFilename = resolvedVideoFilename(for: selectedEntry),
              let transcript = loadTranscriptText(for: videoFilename) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        didCopyTranscript = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyTranscript = false
        }
    }
    
    private var activeSaveMode: DestinationSaveMode {
        destinationStore.activeDestination?.saveMode ?? .newNote
    }

    private var isCapturePerSessionMode: Bool {
        activeSaveMode == .newNote
    }

    private func normalizedCaptureContent(_ content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginFreshCaptureSession(clearText: Bool) {
        captureEditorSessionID = UUID()
        liveCaptureDraftRegistration = nil
        inProgressCaptureFilename = nil
        captureStartedAt = nil
        selectedEntryId = nil
        currentVideoURL = nil
        selectedVideoHasTranscript = false
        didCopyTranscript = false
        if clearText {
            isLoadingEntry = true
            text = ""
            isLoadingEntry = false
        }
        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
    }

    private func deleteCaptureFileIfExists(_ filename: String) {
        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                return
            }
        }
        noteSaveState.forget(fileURL)
    }

    private func removeEntry(withFilename filename: String) {
        if let index = entries.firstIndex(where: { $0.filename == filename }) {
            entries.remove(at: index)
        }
        if selectedEntryId != nil,
           entries.first(where: { $0.id == selectedEntryId }) == nil {
            selectedEntryId = nil
        }
    }

    @discardableResult
    private func moveCaptureFile(from sourceFilename: String, to destinationFilename: String, in documentsDirectory: URL) -> Bool {
        let sourceURL = documentsDirectory.appendingPathComponent(sourceFilename)
        let destinationURL = documentsDirectory.appendingPathComponent(destinationFilename)
        guard sourceFilename != destinationFilename else { return true }
        guard fileManager.fileExists(atPath: sourceURL.path) else { return false }

        if fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.removeItem(at: destinationURL)
                noteSaveState.forget(destinationURL)
            } catch {
                return false
            }
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            noteSaveState.forget(sourceURL)
            noteSaveState.forget(destinationURL)
            return true
        } catch {
            print("Error renaming capture file: \(error)")
            return false
        }
    }

    private func updateEntryFilename(from sourceFilename: String, to destinationFilename: String) {
        guard let index = entries.firstIndex(where: { $0.filename == sourceFilename }) else { return }
        let existing = entries[index]
        let newPath = getDocumentsDirectory()?
            .appendingPathComponent(destinationFilename)
            .standardizedFileURL.path ?? destinationFilename
        let newId = DestinationWriteTarget.stableUUID(fromPath: newPath)
        entries[index] = HumanEntry(
            id: newId,
            date: existing.date,
            filename: destinationFilename,
            previewText: existing.previewText,
            entryType: existing.entryType,
            videoFilename: existing.videoFilename,
            timestamp: existing.timestamp,
            searchableBody: existing.searchableBody
        )
        if selectedEntryId == existing.id {
            selectedEntryId = newId
        }
        if inProgressCaptureFilename == sourceFilename {
            inProgressCaptureFilename = destinationFilename
        }
    }

    private func startCaptureSession() {
        guard isCapturePerSessionMode,
              inProgressCaptureFilename == nil,
              let documentsDirectory = getDocumentsDirectory() else {
            return
        }

        let format = destinationStore.activeDestination?.newNoteFilenameFormat ?? .date
        let now = Date()
        captureStartedAt = now
        let captureId = UUID()

        let filename: String
        switch format {
        case .date:
            filename = DestinationWriteTarget.uniqueMarkdownFilename(
                preferredBasename: DestinationWriteTarget.dateCaptureBasename(now: now),
                documentsURL: documentsDirectory
            )
        case .title:
            filename = DestinationWriteTarget.captureDraftFilename(captureId: captureId)
            liveCaptureDraftRegistration = LiveCaptureDraftRegistration(
                fileURL: documentsDirectory.appendingPathComponent(filename)
            )
        }

        inProgressCaptureFilename = filename
        let pathKey = documentsDirectory.appendingPathComponent(filename).standardizedFileURL.path
        let entry = HumanEntry(
            id: DestinationWriteTarget.stableUUID(fromPath: pathKey),
            date: DestinationWriteTarget.displayDateString(from: now),
            filename: filename,
            previewText: "",
            entryType: .text,
            videoFilename: nil,
            timestamp: now
        )
        entries.insert(entry, at: 0)
        selectedEntryId = entry.id
        saveEntry(entry: entry)
    }

    private func handleCaptureTextChange() {
        guard isCapturePerSessionMode, !isLoadingEntry else { return }

        let trimmed = normalizedCaptureContent(text)

        if trimmed.isEmpty {
            if let filename = inProgressCaptureFilename {
                deleteCaptureFileIfExists(filename)
                removeEntry(withFilename: filename)
                liveCaptureDraftRegistration = nil
                inProgressCaptureFilename = nil
                captureStartedAt = nil
            }
            return
        }

        if inProgressCaptureFilename == nil {
            startCaptureSession()
        }

        guard let filename = inProgressCaptureFilename,
              let entry = entries.first(where: { $0.filename == filename }) else {
            return
        }
        saveEntry(entry: entry)
    }

    private enum EntryDeparture {
        case ready, captureSaved, failed(filename: String)
    }

    private struct NoteSaveFailure {
        let filename: String
        let text: String
        let discard: () -> Void
    }

    private func finalizeCaptureSession(draftFilename: String) -> EntryDeparture {
        guard let documentsDirectory = getDocumentsDirectory() else {
            return .failed(filename: draftFilename)
        }

        let trimmed = normalizedCaptureContent(text)
        if trimmed.isEmpty {
            deleteCaptureFileIfExists(draftFilename)
            removeEntry(withFilename: draftFilename)
            beginFreshCaptureSession(clearText: true)
            return .ready
        }

        guard let entry = entries.first(where: { $0.filename == draftFilename }),
              saveEntry(entry: entry, updatePreview: true) else {
            return .failed(filename: draftFilename)
        }

        let format = destinationStore.activeDestination?.newNoteFilenameFormat ?? .date
        if format == .title {
            let fallbackBasename: String
            if let started = captureStartedAt {
                fallbackBasename = DestinationWriteTarget.dateCaptureBasename(now: started)
            } else {
                fallbackBasename = DestinationWriteTarget.dateCaptureBasename()
            }

            let preferredBasename = DestinationWriteTarget.sanitizedTitleBasename(from: text) ?? fallbackBasename
            let finalFilename = DestinationWriteTarget.uniqueMarkdownFilename(
                preferredBasename: preferredBasename,
                documentsURL: documentsDirectory,
                excluding: draftFilename
            )

            if finalFilename != draftFilename {
                guard moveCaptureFile(from: draftFilename, to: finalFilename, in: documentsDirectory) else {
                    return .failed(filename: draftFilename)
                }
                updateEntryFilename(from: draftFilename, to: finalFilename)
            }
        }

        liveCaptureDraftRegistration = nil
        inProgressCaptureFilename = nil
        captureStartedAt = nil
        selectedEntryId = nil
        isLoadingEntry = true
        text = ""
        isLoadingEntry = false
        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
        return .captureSaved
    }

    /// Builds a HumanEntry for a resolved write target, creating a shell if not yet listed.
    private func entryForResolvedTarget(_ target: DestinationWriteTarget.ResolvedTarget) -> HumanEntry {
        if let existing = entries.first(where: { $0.filename == target.filename }) {
            return existing
        }
        return HumanEntry(
            id: target.entryId,
            date: target.displayDate,
            filename: target.filename,
            previewText: "",
            entryType: .text,
            videoFilename: nil,
            timestamp: target.fileExists ? HistoryEntryReader.modificationDate(for: target.fileURL) : Date()
        )
    }

    private func bindToResolvedWriteTarget(appendSeparator: Bool = false) -> Bool {
        unreadableConfiguredNoteURL = nil
        guard let destination = destinationStore.activeDestination,
              destination.saveMode == .rolling || destination.saveMode == .existing,
              let documentsDirectory = destinationStore.resolvedDocumentsURL() else {
            return false
        }

        // Soft-fail existing when no note is configured: empty editor, no crash.
        if destination.saveMode == .existing,
           destination.existingNoteFilename == nil ||
            DestinationWriteTarget.validatedBasename(destination.existingNoteFilename ?? "") == nil {
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            placeholderText = "Choose a note in Destination settings"
            return !appendSeparator
        }

        let createIfMissing = destination.saveMode == .rolling

        guard let target = DestinationWriteTarget.resolve(
            for: destination,
            documentsURL: documentsDirectory,
            createIfMissing: createIfMissing
        ) else {
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            return !appendSeparator
        }

        // Missing paths stay unbound until a nonempty edit resolves the target.
        guard target.fileExists else {
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            isLoadingEntry = false
            if destination.saveMode == .existing {
                placeholderText = "Configured note is missing"
            } else {
                placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
            }
            return !appendSeparator
        }

        let entry = entryForResolvedTarget(target)
        if !entries.contains(where: { $0.id == entry.id }) {
            entries.insert(entry, at: 0)
        }

        guard loadEntry(entry: entry) else {
            unreadableConfiguredNoteURL = target.fileURL.standardizedFileURL
            return false
        }

        if appendSeparator {
            text += DestinationWriteTarget.sessionSeparator()
            let didSave = saveEntry(entry: entry)
            editorCaretEndRequest = UUID()
            placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
            return didSave
        } else if entry.entryType == .text {
            updatePreviewText(for: entry)
        }

        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
        return true
    }

    private func openHistorySidebar() {
        if showingSidebar {
            closeHistorySidebar()
        } else {
            showHistory(searching: false)
        }
    }

    private func searchNotes() {
        showHistory(searching: true)
    }

    private func showHistory(searching: Bool) {
        if showingDestinationSettings && hasUnsavedDestinationSettingsChanges {
            pendingDestinationSettingsCloseAction = searching ? .searchNotes : .openHistory
            showingDiscardDestinationSettingsConfirmation = true
            return
        }

        if !showingSidebar {
            historySearchQuery = ""
            syncSettingsDraftFromActiveDestination()
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            showingDestinationSettings = false
            showingSidebar = true
        }
        if searching {
            isSearchingNotes = true
            historySearchFocusRequest = UUID()
        }
    }

    private func closeHistorySidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingSidebar = false
        }
    }

    private func openDestinationSettings() {
        guard !showingDestinationSettings else { return }
        syncSettingsDraftFromActiveDestination()
        withAnimation(.easeInOut(duration: 0.2)) {
            showingSidebar = false
            showingDestinationSettings = true
        }
    }

    private func syncSettingsDraftFromActiveDestination() {
        guard let destination = destinationStore.activeDestination else { return }
        settingsDisplayName = destination.displayName
        settingsSaveMode = destination.saveMode
        settingsRollingPeriod = destination.rollingPeriod
        settingsFilenameFormat = destination.filenameFormat
        settingsNewNoteFilenameFormat = destination.newNoteFilenameFormat
        settingsExistingNoteFilename = destination.existingNoteFilename
    }

    private var hasUnsavedDestinationSettingsChanges: Bool {
        guard let destination = destinationStore.activeDestination else { return false }
        let draftDisplayName = settingsDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedDisplayName = destination.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let filenameFormatChanged: Bool
        if settingsRollingFilenamePreview == nil {
            filenameFormatChanged = settingsSaveMode == .rolling && settingsFilenameFormat != destination.filenameFormat
        } else {
            let draftFilenameFormat = settingsFilenameFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedFilenameFormat = destination.filenameFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            filenameFormatChanged = draftFilenameFormat != savedFilenameFormat
        }

        return (!draftDisplayName.isEmpty && draftDisplayName != savedDisplayName)
            || settingsSaveMode != destination.saveMode
            || settingsRollingPeriod != destination.rollingPeriod
            || filenameFormatChanged
            || settingsNewNoteFilenameFormat != destination.newNoteFilenameFormat
            || settingsExistingNoteFilename != destination.existingNoteFilename
    }

    private var settingsRollingFilenamePreview: String? {
        DestinationWriteTarget.formattedBasename(
            format: settingsFilenameFormat,
            period: settingsRollingPeriod
        )
    }

    private var canSaveDestinationSettings: Bool {
        hasUnsavedDestinationSettingsChanges && (settingsSaveMode != .rolling || settingsRollingFilenamePreview != nil)
    }

    private func closeDestinationSettingsRail() {
        if hasUnsavedDestinationSettingsChanges {
            pendingDestinationSettingsCloseAction = .closeRail
            showingDiscardDestinationSettingsConfirmation = true
            return
        }

        syncSettingsDraftFromActiveDestination()
        withAnimation(.easeInOut(duration: 0.2)) {
            showingDestinationSettings = false
        }
    }

    private func discardDestinationSettingsChangesAndContinue() {
        showingDiscardDestinationSettingsConfirmation = false
        syncSettingsDraftFromActiveDestination()

        let action = pendingDestinationSettingsCloseAction
        pendingDestinationSettingsCloseAction = nil

        switch action {
        case .openHistory:
            showHistory(searching: false)
        case .searchNotes:
            showHistory(searching: true)
        case .closeRail:
            withAnimation(.easeInOut(duration: 0.2)) {
                showingDestinationSettings = false
            }
        case .none:
            break
        }
    }

    private func cancelDestinationSettingsChangesAndClose() {
        syncSettingsDraftFromActiveDestination()
        pendingDestinationSettingsCloseAction = nil
        showingDiscardDestinationSettingsConfirmation = false
        withAnimation(.easeInOut(duration: 0.2)) {
            showingDestinationSettings = false
        }
    }

    private func saveDestinationSettingsDraft() {
        guard canSaveDestinationSettings, let destination = destinationStore.activeDestination else { return }

        var draftDestination = destination
        draftDestination.saveMode = settingsSaveMode
        draftDestination.rollingPeriod = settingsRollingPeriod
        draftDestination.filenameFormat = settingsFilenameFormat
        draftDestination.existingNoteFilename = settingsExistingNoteFilename
        if let documentsURL = getDocumentsDirectory(),
           let target = DestinationWriteTarget.resolve(
               for: draftDestination,
               documentsURL: documentsURL,
               createIfMissing: false
           ) {
            do {
                try DestinationWriteTarget.validateSettingsTarget(target)
            } catch {
                noteOpenError = "\(target.filename)\n\(error.localizedDescription)\nDestination settings were not saved."
                return
            }
        }

        guard prepareToLeaveEntry(onDiscard: {
            discardEditorChanges(then: saveDestinationSettingsDraft)
        }) else { return }

        if settingsSaveMode == .existing,
           let filename = settingsExistingNoteFilename,
           let documentsURL = destinationStore.resolvedDocumentsURL() {
            let finalURL = documentsURL.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: finalURL.path) {
                try? "".write(to: finalURL, atomically: true, encoding: .utf8)
            }
        }

        destinationStore.updateDestination(
            id: destination.id,
            displayName: settingsDisplayName,
            saveMode: settingsSaveMode,
            rollingPeriod: settingsRollingPeriod,
            filenameFormat: settingsRollingFilenamePreview == nil ? nil : settingsFilenameFormat,
            newNoteFilenameFormat: settingsNewNoteFilenameFormat,
            existingNoteFilename: .some(settingsExistingNoteFilename)
        )

        syncSettingsDraftFromActiveDestination()
        pendingDestinationSettingsCloseAction = nil
        showingDiscardDestinationSettingsConfirmation = false

        DispatchQueue.main.async {
            self.reloadJournalForActiveDestination()
        }
    }
    
    private func selectEntry(_ entry: HumanEntry, onDiscard: @escaping () -> Void) -> Bool {
        guard selectedEntryId != entry.id else { return true }
        guard let targetEntry = entries.first(where: { $0.id == entry.id }),
              loadEntry(entry: targetEntry, beforeDisplaying: {
                  prepareToLeaveEntry(onDiscard: onDiscard)
              }) else { return false }

        if targetEntry.entryType == .text {
            DispatchQueue.main.async {
                self.updatePreviewText(for: targetEntry)
            }
        }
        return true
    }

    private func prepareToLeaveEntry(onDiscard: @escaping () -> Void) -> Bool {
        allowDeparture(finishEditingEntry(), onDiscard: onDiscard)
    }

    private func allowDeparture(_ departure: EntryDeparture, onDiscard: @escaping () -> Void) -> Bool {
        guard case let .failed(filename) = departure else { return true }
        if noteSaveFailure == nil {
            noteSaveFailure = NoteSaveFailure(filename: filename, text: text, discard: onDiscard)
        }
        return false
    }

    private func discardEditorChanges(then action: () -> Void) {
        beginFreshCaptureSession(clearText: true)
        action()
    }

    private func finishEditingEntry() -> EntryDeparture {
        if isCapturePerSessionMode, let draftFilename = inProgressCaptureFilename {
            return finalizeCaptureSession(draftFilename: draftFilename)
        } else if let currentId = selectedEntryId,
                  let currentEntry = entries.first(where: { $0.id == currentId }),
                  currentEntry.entryType == .text,
                  !saveEntry(entry: currentEntry, updatePreview: false) {
            let hasUnsavedChanges = getDocumentsDirectory().map { directory in
                noteSaveState.hasUnsavedChanges(text, at: directory.appendingPathComponent(currentEntry.filename))
            } ?? true
            if hasUnsavedChanges {
                return .failed(filename: currentEntry.filename)
            }
        }
        return .ready
    }

    private func reloadJournalForActiveDestination() {
        selectedEntryId = nil
        currentVideoURL = nil
        selectedVideoHasTranscript = false
        didCopyTranscript = false
        thumbnailMemoryCache.removeAllObjects()
        liveCaptureDraftRegistration = nil
        inProgressCaptureFilename = nil
        captureStartedAt = nil
        text = ""
        loadExistingEntries()
    }

    private func switchToDestination(id: UUID) {
        guard id != destinationStore.activeDestinationId,
              prepareToLeaveEntry(onDiscard: {
                  discardEditorChanges { switchToDestination(id: id) }
              }) else { return }

        destinationStore.activateDestination(id: id)
        if showingDestinationSettings {
            syncSettingsDraftFromActiveDestination()
        }
        historyTrash = nil
        trashedEntry = nil
        historySearchQuery = ""
        searchAllDestinations = false
        historyKeyboardEntryID = nil
        // Defer journal reload so ForEach(entries) isn't mid-update when History is open.
        DispatchQueue.main.async {
            self.reloadJournalForActiveDestination()
        }
    }

    private func revealActiveDestinationInFinder() {
        guard let url = destinationStore.resolvedDocumentsURL() else { return }
        // Use the security-scoped URL directly. Path-based selectFile can crash/fail
        // for user-picked destinations outside the app container.
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func addDestinationFromFolderPicker() {
        // AppKit restores NSOSPLastRootDirectory when the panel opens. That
        // bookmark often isn't a valid security-scoped bookmark and surfaces as
        // NSCocoaErrorDomain 256 — "The file couldn’t be opened."
        UserDefaults.standard.removeObject(forKey: "NSOSPLastRootDirectory")

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder for this journal destination."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            let destination = try destinationStore.addDestination(from: url, activate: false)
            switchToDestination(id: destination.id)
        } catch {
            print("Error adding destination: \(error)")
        }
    }

    private var activeDestinationDisplayName: String {
        destinationStore.activeDestination?.displayName ?? SaveDestination.defaultDisplayName
    }

    private var unreadableConfiguredNoteBlocksEditor: Bool {
        guard selectedEntryId == nil, let unreadableConfiguredNoteURL else { return false }
        return fileManager.fileExists(atPath: unreadableConfiguredNoteURL.path)
    }

    // Add function to load existing entries
    private func loadExistingEntries(preservingSelection: Bool = false) {
        unreadableConfiguredNoteURL = nil
        guard let documentsDirectory = destinationStore.resolvedDocumentsURL() else {
            print("Active destination is unavailable; showing empty History")
            entries = []
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            return
        }
        print("Looking for entries in: \(documentsDirectory.path)")
        if let videosDirectory = getVideosDirectory() {
            print("Looking for videos in: \(videosDirectory.path)")
        }
        
        do {
            let failedDrafts = try DestinationWriteTarget.recoverOrphanedCaptureDrafts(
                in: documentsDirectory,
                excluding: inProgressCaptureFilename,
                fileManager: fileManager
            )
            for draft in failedDrafts {
                print("Could not recover capture draft: \(draft.lastPathComponent)")
            }
            let loadedEntries = try HistoryEntryReader(directory: documentsDirectory).entries()
            print("Successfully loaded and sorted \(loadedEntries.count) entries")

            // Now assign to the state variable
            let liveEntry = entries.first { $0.filename == inProgressCaptureFilename }
            entries = loadedEntries
            if let liveEntry, !entries.contains(where: { $0.filename == liveEntry.filename }) {
                entries.insert(liveEntry, at: 0)
            }

            if preservingSelection { return }

            // Rolling / Existing: bind to resolved write target (skip new-note launch rules).
            if activeSaveMode == .rolling || activeSaveMode == .existing {
                _ = bindToResolvedWriteTarget(appendSeparator: false)
                return
            }

            // New note: load history, start with a fresh empty capture session.
            if inProgressCaptureFilename == nil {
                beginFreshCaptureSession(clearText: true)
            }
            
        } catch {
            print("Error loading directory contents: \(error)")
            if preservingSelection {
                entries = []
                return
            }
            print("Creating default entry after error")
            if activeSaveMode == .rolling || activeSaveMode == .existing {
                _ = bindToResolvedWriteTarget(appendSeparator: false)
            } else if inProgressCaptureFilename == nil {
                beginFreshCaptureSession(clearText: true)
            }
        }
    }
    
    var lineHeight: CGFloat {
        let fontSize = FreewriteTextEditor.bodyFontSize
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (fontSize * 1.5) - defaultLineHeight
    }

    private func captureTitleBarDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    private func titleBarDateFromCaptureFilename(_ filename: String) -> String? {
        var basename = filename
        if basename.lowercased().hasSuffix(".md") {
            basename = String(basename.dropLast(3))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

        if let date = formatter.date(from: basename) {
            return captureTitleBarDate(from: date)
        }

        if let suffixRange = basename.range(of: #"-\d+$"#, options: .regularExpression) {
            let withoutSuffix = String(basename[..<suffixRange.lowerBound])
            if let date = formatter.date(from: withoutSuffix) {
                return captureTitleBarDate(from: date)
            }
        }

        return nil
    }

    private var currentEntryTitle: String {
        if isCapturePerSessionMode,
           destinationStore.activeDestination?.newNoteFilenameFormat == .date {
            if let started = captureStartedAt, inProgressCaptureFilename != nil {
                return captureTitleBarDate(from: started)
            }

            if let selectedEntryId,
               let entry = entries.first(where: { $0.id == selectedEntryId }) {
                if entry.entryType == .video {
                    return entry.previewText.isEmpty ? "Video Note" : entry.previewText
                }
                if let fromFilename = titleBarDateFromCaptureFilename(entry.filename) {
                    return fromFilename
                }
                return entry.date
            }

            return "Untitled"
        }

        guard let selectedEntryId,
              let entry = entries.first(where: { $0.id == selectedEntryId }) else {
            return "Untitled"
        }

        if entry.entryType == .video {
            return entry.previewText.isEmpty ? "Video Note" : entry.previewText
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return "Untitled"
        }

        let firstLine = trimmedText.components(separatedBy: .newlines).first ?? trimmedText
        let titleLine = showsMarkdownSource ? firstLine : EditorMarkdown.renderedTitle(firstLine)
        let words = titleLine
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if words.isEmpty {
            return "Untitled"
        }
        let title = words.prefix(4).joined(separator: " ")
        return words.count > 4 ? "\(title)..." : title
    }

    
    var body: some View {
        let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = colorScheme == .light ? Color.black : Color.white
        let isViewingVideoEntry = currentVideoURL != nil
        
        HStack(spacing: 0) {
            // Main content
            ZStack {
                Color(colorScheme == .light ? .white : .black)
                    .ignoresSafeArea()

                // Show video player if a video entry is selected
                if let videoURL = currentVideoURL {
                    VideoPlayerView(
                        videoURL: videoURL,
                        isPlaybackSuspended: false
                    )
                        .id(videoURL.path)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(edges: .top)
                        // Avoid animating AVKit/AppKit representables when History opens.
                        .transaction { $0.animation = nil }
                } else if unreadableConfiguredNoteBlocksEditor {
                    Text("The configured note couldn't be opened. Choose another note in History or Destination settings.")
                        .foregroundStyle(.secondary)
                        .padding(editorInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    // Show text editor for text entries
                    FreewriteTextEditor(
                        text: $text,
                        isComposingText: $isComposingEditorText,
                        scrollRequest: $editorScrollRequest,
                        selectionFocusRequest: historySelectionFocusRequest,
                        editorID: isCapturePerSessionMode && (inProgressCaptureFilename != nil || selectedEntryId == nil)
                            ? captureEditorSessionID : selectedEntryId,
                        allowsAutomaticFocus: !showingDestinationSettings && !showingSidebar,
                        focusRequest: editorFocusRequest,
                        caretEndRequest: $editorCaretEndRequest,
                        selectedFont: selectedFont,
                        showsMarkdownSource: showsMarkdownSource,
                        lineSpacing: lineHeight,
                        colorScheme: colorScheme,
                        editorInset: editorInset,
                        editorNativeTextPadding: editorNativeTextPadding,
                        bottomContentMargin: bottomNavHeight + bottomNavContentGap,
                        onScrollMetricsChange: { metrics in
                            if editorScrollMetrics != metrics {
                                editorScrollMetrics = metrics
                            }
                        }
                    )
                    .background(Color(colorScheme == .light ? .white : .black))
                        // Placeholder shares the editor's coordinate space so it sits on the first line.
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty && !isComposingEditorText {
                                Text(placeholderText)
                                    .font(.custom(selectedFont, fixedSize: FreewriteTextEditor.bodyFontSize))
                                    .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
                                    // Align with NSTextView's native horizontal line-fragment padding.
                                    .padding(.top, editorInset)
                                    .padding(.leading, editorInset)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(selectedFont)
                        .colorScheme(colorScheme)
                        .transaction { $0.animation = nil }
                        .onAppear {
                            placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
                        }
                        .onDisappear { isComposingEditorText = false }

                    NativeEditorEdgeScroller(
                        metrics: editorScrollMetrics,
                        colorScheme: colorScheme,
                        onScrollFractionChange: { fraction in
                            editorScrollRequest = EditorScrollRequest(fraction: fraction)
                        }
                    )
                    .padding(.bottom, bottomNavHeight)
                    .frame(width: 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transaction { $0.animation = nil }
                }

                // Bottom nav
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 8) {
                            destinationChip()

                            if isViewingVideoEntry {
                                if selectedVideoHasTranscript {
                                    Button(action: {
                                        copyTranscriptForSelectedVideoEntry()
                                    }) {
                                        Text(didCopyTranscript ? "Copied Transcript" : "Copy Transcript")
                                            .font(.system(size: 13))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy the video transcript")
                                    .foregroundColor(isHoveringCopyTranscript ? textHoverColor : textColor)
                                    .onHover { hovering in
                                        isHoveringCopyTranscript = hovering
                                        isHoveringBottomNav = hovering
                                        if hovering {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                }
                            }
                        }
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                        }

                        Spacer()
                        
                        // Utility buttons (moved to right)
                        HStack(spacing: 8) {
                            Button(action: {
                                createNewEntry()
                            }) {
                                Text("New Note")
                                    .font(.system(size: 13))
                                    .fixedSize()
                            }
                            .buttonStyle(.plain)
                            .nativeTooltip("Start a new note")
                            .foregroundColor(isHoveringNewEntry ? textHoverColor : textColor)
                            .onHover { hovering in
                                isHoveringNewEntry = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Theme toggle button
                            Button(action: {
                                colorScheme = colorScheme == .light ? .dark : .light
                                // Save preference
                                UserDefaults.standard.set(colorScheme == .light ? "light" : "dark", forKey: "colorScheme")
                            }) {
                                Image(systemName: colorScheme == .light ? "moon.fill" : "sun.max.fill")
                                    .foregroundColor(isHoveringThemeToggle ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .nativeTooltip(colorScheme == .light ? "Switch to dark mode" : "Switch to light mode")
                            .accessibilityIdentifier("themeToggleButton")
                            .onHover { hovering in
                                isHoveringThemeToggle = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }

                            Text("•")
                                .foregroundColor(.gray)

                            // Version history button
                            Button(action: {
                                openHistorySidebar()
                            }) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(isHoveringClock ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .nativeTooltip(showingSidebar ? "Hide History" : "Show History")
                            .accessibilityIdentifier("historyButton")
                            .onHover { hovering in
                                isHoveringClock = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, bottomNavVerticalPadding - 1)
                    .padding(.bottom, bottomNavVerticalPadding)
                    .background(Color(colorScheme == .light ? .white : .black))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.gray.opacity(colorScheme == .light ? 0.2 : 0.35))
                            .frame(height: 1)
                    }
                    .opacity(bottomNavOpacity)
                    .overlay(alignment: .bottomTrailing) {
                        if let savedConfirmation {
                            Text(savedConfirmation)
                                .font(.system(size: 13))
                                .foregroundColor(textColor)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(colorScheme == .light ? .white : .black))
                                .offset(y: -bottomNavHeight)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .task(id: savedConfirmationID) {
                        guard savedConfirmation != nil else { return }
                        do {
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                        } catch {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.25)) {
                            savedConfirmation = nil
                        }
                    }
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                            if hovering {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    bottomNavOpacity = 1.0
                                }
                            }
                        }
                }
            }

            // Right side rails: History and Destination settings (mutually exclusive)
            if showingSidebar {
                Divider()
                
                VStack(spacing: 0) {
                    // Header
                    Button(action: {
                        revealActiveDestinationInFinder()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("History")
                                        .font(.system(size: 13))
                                        .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                                }
                                Text(activeDestinationHistoryLabel)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("historyHeader")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .nativeTooltip("Reveal destination in Finder")
                    .onHover { hovering in
                        isHoveringHistory = hovering
                    }
                    
                    Divider()

                    historySearchField

                    if destinationStore.destinations.count > 1 {
                        historyScopeButton
                    }

                    Divider()

                    historyResultsList
                }
                .frame(width: 200)
                .background(RailRemovalObserver { editorFocusRequest = UUID() })
                .background(Color(colorScheme == .light ? .white : NSColor.black))
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
                .task(id: searchAllDestinations) {
                    await loadOtherDestinationResults()
                }
            }

            if showingDestinationSettings {
                Divider()
                destinationSettingsRail(textColor: textColor)
                    .frame(width: 260)
                    .background(RailRemovalObserver { editorFocusRequest = UUID() })
                    .background(Color(colorScheme == .light ? .white : NSColor.black))
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
            }
        }
        // Keep the editor usable at compact sizes: sidebar is fixed 200pt wide,
        // and top inset + bottom nav need leftover vertical room to write.
        .frame(
            minWidth: (showingSidebar || showingDestinationSettings) ? 480 : 280,
            minHeight: 200
        )
        // Animate only sidebar insertion; AppKit editor is excluded via .transaction above.
        .animation(.easeInOut(duration: 0.2), value: showingSidebar)
        .animation(.easeInOut(duration: 0.2), value: showingDestinationSettings)
        .preferredColorScheme(colorScheme)
        .overlay(alignment: .top) {
            if historyTrash != nil {
                HStack(spacing: 12) {
                    Text("Moved to Trash")
                    Button("Undo", action: undoHistoryTrash)
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 13))
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 12)
            }
        }
        .alert("Couldn't update Trash", isPresented: Binding(
            get: { trashError != nil },
            set: { if !$0 { trashError = nil } }
        )) {
            Button("OK") { trashError = nil }
        } message: {
            Text(trashError ?? "")
        }
        .alert("Couldn't open note", isPresented: Binding(
            get: { noteOpenError != nil },
            set: { if !$0 { noteOpenError = nil } }
        )) {
            Button("OK") { if showingSidebar { historySearchFocusRequest = UUID() } }
        } message: {
            Text(noteOpenError ?? "")
        }
        .alert("Couldn't save note", isPresented: Binding(
            get: { noteSaveFailure != nil },
            set: { if !$0 { noteSaveFailure = nil } }
        ), presenting: noteSaveFailure) { failure in
            Button("Keep Editing", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Copy Text") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(failure.text, forType: .string)
            }
            Button("Discard Changes", role: .destructive) {
                DispatchQueue.main.async { failure.discard() }
            }
        } message: { failure in
            Text("\(failure.filename)\nYour text is still in the editor. Discarding changes continues without saving your edits.")
        }
        .focusedSceneValue(\.editorCommandActions, EditorCommandActions(
            newEntry: createNewEntry,
            openHistory: {
                if !showingSidebar {
                    openHistorySidebar()
                }
            },
            searchNotes: searchNotes,
            openDestinationSettings: openDestinationSettings,
            markdownSourceShown: showsMarkdownSource,
            toggleMarkdownSource: currentVideoURL == nil ? { showsMarkdownSource.toggle() } : nil
        ))
        .background(WindowTitleAccessor(
            title: currentEntryTitle,
            isDark: colorScheme == .dark,
            prepareToClose: { continuation in
                prepareToLeaveEntry(onDiscard: { discardEditorChanges(then: continuation) })
            }
        ))
        .background(QuickCaptureWindowAccessor(canAcceptCapture: canAcceptQuickCapture))
        .background(PinnedWindowAccessor())
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureDidSave)) { notification in
            if let url = notification.object as? URL { receiveQuickCapture(at: url) }
        }
        .onChange(of: selectedEntryId) { _, newId in
            // Drop a History focus request once its note is no longer open, so a later editor can't replay it.
            if newId != historySelectionFocusEntryId {
                historySelectionFocusRequest = nil
                historySelectionFocusEntryId = nil
            }
        }
        .onChange(of: showingSidebar) { _, isShowing in
            if !isShowing {
                isSearchingNotes = false
                historySearchFocusRequest = nil
                historyKeyboardEntryID = nil
                searchAllDestinations = false
                otherDestinationResults = nil
            }
        }
        .onAppear {
            showingSidebar = false  // Hide sidebar by default
            showingDestinationSettings = false
            destinationStore.activateDestination(id: destinationStore.activeDestinationId)
            loadExistingEntries()
        }
        .onChange(of: text) { _ in
            guard !isLoadingEntry else { return }
            if isCapturePerSessionMode {
                if inProgressCaptureFilename != nil {
                    handleCaptureTextChange()
                } else if let currentId = selectedEntryId,
                          let currentEntry = entries.first(where: { $0.id == currentId }),
                          currentEntry.entryType == .text {
                    saveEntry(entry: currentEntry)
                } else if normalizedCaptureContent(text).isEmpty == false {
                    handleCaptureTextChange()
                }
            } else if let currentId = selectedEntryId,
               let currentEntry = entries.first(where: { $0.id == currentId }),
               currentEntry.entryType == .text {
                saveEntry(entry: currentEntry)
            } else if selectedEntryId == nil,
                      let destination = destinationStore.activeDestination,
                      let documentsDirectory = getDocumentsDirectory(),
                      let target = DestinationWriteTarget.resolveForUnboundEdit(
                        content: text,
                        destination: destination,
                        documentsURL: documentsDirectory
                      ) {
                let mergedText: String
                do {
                    mergedText = try DestinationWriteTarget.contentForUnboundEdit(text, target: target)
                } catch {
                    print("Error reading unbound write target: \(error)")
                    return
                }
                if unreadableConfiguredNoteURL == target.fileURL.standardizedFileURL {
                    unreadableConfiguredNoteURL = nil
                }
                if mergedText != text {
                    text = mergedText
                    editorCaretEndRequest = UUID()
                }
                let entry = entryForResolvedTarget(target)
                if !entries.contains(where: { $0.id == entry.id }) {
                    entries.insert(entry, at: 0)
                }
                noteSaveState.forget(target.fileURL)
                selectedEntryId = entry.id
                saveEntry(entry: entry)
            }
        }
        .confirmationDialog(
            "Discard unsaved destination settings?",
            isPresented: $showingDiscardDestinationSettingsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                discardDestinationSettingsChangesAndContinue()
            }
            Button("Keep Editing", role: .cancel) {
                pendingDestinationSettingsCloseAction = nil
            }
        } message: {
            Text("Your destination settings changes have not been saved.")
        }
    }
    
    private var filteredHistoryResults: [HistoryResult] {
        let current = entries.map {
            HistoryResult(
                destinationID: destinationStore.activeDestinationId,
                destinationLabel: activeDestinationDisplayName,
                entry: $0
            )
        }
        let others = searchAllDestinations ? otherDestinationResults ?? [] : []
        return HistorySearch.filter(current + others, query: historySearchQuery, title: {
            historyRowTitle(for: $0.entry)
        }, body: historyBody(for:))
    }

    private func historyBody(for result: HistoryResult) -> String {
        if result.destinationID == destinationStore.activeDestinationId,
           result.entry.id == selectedEntryId, result.entry.entryType == .text {
            return text
        }
        return result.entry.searchableBody
    }

    @MainActor
    private func loadOtherDestinationResults() async {
        guard searchAllDestinations else { return }
        let others = destinationStore.destinations.filter { $0.id != destinationStore.activeDestinationId }
        let load = Task.detached(priority: .userInitiated) {
            others.flatMap { destination -> [HistoryResult] in
                guard !Task.isCancelled else { return [] }
                return DestinationStore.withHistoryReadAccess(to: destination) { directory in
                    (try? HistoryEntryReader(directory: directory).entries())?.map {
                        HistoryResult(destinationID: destination.id, destinationLabel: destination.displayName, entry: $0)
                    }
                } ?? []
            }
        }
        let results = await withTaskCancellationHandler(operation: { await load.value }, onCancel: { load.cancel() })
        guard !Task.isCancelled else { return }
        otherDestinationResults = results
    }

    private var historyScopeButton: some View {
        Button {
            searchAllDestinations.toggle()
            otherDestinationResults = nil
            historyKeyboardEntryID = nil
            historySearchFocusRequest = UUID()
        } label: {
            Label("All Destinations", systemImage: searchAllDestinations ? "checkmark.square" : "square")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .help("Search all destinations (⇧⌘A)")
        .accessibilityValue(searchAllDestinations ? "On" : "Off")
        .accessibilityIdentifier("historySearchScope")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var historyResultsList: some View {
        let results = filteredHistoryResults
        let hasQuery = !HistorySearch.terms(from: historySearchQuery).isEmpty
        let keyboardSelection = historyKeyboardEntryID != nil || isSearchingNotes || hasQuery
        let highlightedID = keyboardSelection ? keyboardHistoryResult(in: results)?.id : nil
        let isLoading = searchAllDestinations && otherDestinationResults == nil

        return VStack(spacing: 0) {
            if isLoading || (results.isEmpty && hasQuery) {
                Text(isLoading ? "Searching destinations…" : "No notes match")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier(isLoading ? "historySearchLoading" : "historySearchEmpty")
            }

            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            let selected = keyboardSelection ? result.id == highlightedID : isOpenHistoryResult(result)
                            historyResultRow(result, isSelected: selected, hasQuery: hasQuery)
                                .id(result.id)
                            if result.id != results.last?.id { Divider() }
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: highlightedID) { _, id in
                    if let id { scroll.scrollTo(id) }
                }
            }
        }
    }

    private func historyResultRow(_ result: HistoryResult, isSelected: Bool, hasQuery: Bool) -> some View {
        let entry = result.entry
        let isActive = result.destinationID == destinationStore.activeDestinationId
        return HStack(alignment: .top) {
            if let videoFilename = resolvedVideoFilename(for: entry) {
                historyVideoThumbnail(isActive ? loadThumbnailImage(for: videoFilename) : nil)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(historyRowTitle(for: entry))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(entry.previewText.isEmpty ? .secondary : .primary)
                if hasQuery, let snippet = HistorySearch.snippet(
                    query: historySearchQuery,
                    body: historyBody(for: result),
                    droppingTitleLine: entry.entryType == .text
                ) {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if isSearchingNotes || searchAllDestinations || hasQuery {
                    Text(result.destinationLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(historyRowTimestamp(for: entry))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(backgroundColor(for: result, isSelected: isSelected)))
        .contentShape(Rectangle())
        .onTapGesture { openHistoryResult(result) }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .trailing) {
            if isActive && hoveredEntryId == entry.id {
                Button(action: { deleteEntry(entry: entry) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(hoveredTrashId == entry.id ? .red : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredTrashId = hovering ? entry.id : nil
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .onHover { hovering in
            if isActive { hoveredEntryId = hovering ? entry.id : nil }
        }
    }

    @ViewBuilder
    private func historyVideoThumbnail(_ thumbnail: NSImage?) -> some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .cornerRadius(4)
                .overlay(Image(systemName: "play.circle.fill").foregroundStyle(.white).font(.system(size: 16)))
        } else {
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.3))
                Image(systemName: "video.fill").foregroundStyle(.gray).font(.system(size: 16))
            }
            .frame(width: 40, height: 40)
        }
    }

    private var historySearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HistoryQueryField(
                query: Binding(get: { historySearchQuery }, set: {
                    historySearchQuery = $0
                    historyKeyboardEntryID = nil
                }),
                focusRequest: historySearchFocusRequest,
                moveSelection: moveHistorySelection,
                submit: {
                    if let result = keyboardHistoryResult(in: filteredHistoryResults) { openHistoryResult(result) }
                },
                cancel: closeHistorySidebar
            )
            .frame(height: 17)
            if !historySearchQuery.isEmpty {
                Button(action: {
                    historySearchQuery = ""
                    historyKeyboardEntryID = nil
                    historySearchFocusRequest = UUID()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityIdentifier("historySearchClear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func keyboardHistoryResult(in results: [HistoryResult]) -> HistoryResult? {
        if let highlighted = results.first(where: { $0.id == historyKeyboardEntryID }) { return highlighted }
        if !isSearchingNotes, let open = results.first(where: isOpenHistoryResult) { return open }
        return results.first
    }

    private func isOpenHistoryResult(_ result: HistoryResult) -> Bool {
        result.destinationID == destinationStore.activeDestinationId && result.entry.id == selectedEntryId
    }

    private func moveHistorySelection(by offset: Int) {
        let results = filteredHistoryResults
        guard !results.isEmpty else { return }
        let currentID = keyboardHistoryResult(in: results)?.id
        let currentIndex = results.firstIndex { $0.id == currentID } ?? 0
        let nextIndex = max(0, min(results.count - 1, currentIndex + offset))
        historyKeyboardEntryID = results[nextIndex].id
    }

    private func openHistoryResult(_ result: HistoryResult) {
        let entry = result.entry
        let otherDestination = result.destinationID != destinationStore.activeDestinationId
        let onDiscard = {
            discardEditorChanges { openHistoryResult(result) }
        }
        if otherDestination {
            guard openHistoryResultInOtherDestination(result, onDiscard: onDiscard) else { return }
        } else {
            guard selectEntry(entry, onDiscard: onDiscard) else { return }
        }
        if currentVideoURL == nil {
            historySelectionFocusEntryId = selectedEntryId
            historySelectionFocusRequest = UUID()
        }
        historyKeyboardEntryID = nil
        if isSearchingNotes || otherDestination { closeHistorySidebar() }
    }

    private func openHistoryResultInOtherDestination(_ result: HistoryResult, onDiscard: @escaping () -> Void) -> Bool {
        func readEntry(in directory: URL) -> HumanEntry? {
            HistoryEntryReader(directory: directory).entry(
                at: directory.appendingPathComponent(result.entry.filename), includeUnreadable: false
            )
        }

        let previousDestination = destinationStore.activeDestinationId
        guard let destination = destinationStore.destinations.first(where: { $0.id == result.destinationID }),
              DestinationStore.withHistoryReadAccess(to: destination, read: readEntry(in:)) != nil else {
            noteOpenError = "This note is no longer available."
            return false
        }
        guard prepareToLeaveEntry(onDiscard: onDiscard) else { return false }

        guard case .accessible = destinationStore.activateDestination(id: destination.id) else {
            destinationStore.activateDestination(id: previousDestination)
            noteOpenError = "This destination is no longer available."
            return false
        }
        // Activation can migrate the legacy default folder; bind using the final path.
        guard let directory = getDocumentsDirectory(), let entry = readEntry(in: directory) else {
            destinationStore.activateDestination(id: previousDestination)
            noteOpenError = "This note is no longer available."
            return false
        }
        guard loadEntry(entry: entry) else {
            destinationStore.activateDestination(id: previousDestination)
            return false
        }
        historyTrash = nil
        trashedEntry = nil
        thumbnailMemoryCache.removeAllObjects()
        loadExistingEntries(preservingSelection: true)
        return true
    }

    private func historyRowTitle(for entry: HumanEntry) -> String {
        entry.previewText.isEmpty ? "Untitled" : entry.previewText
    }

    private func historyRowTimestamp(for entry: HumanEntry) -> String {
        guard let timestamp = entry.timestamp else { return entry.date }
        return HistoryRowFormatting.timestamp(from: timestamp)
    }

    private func backgroundColor(for entry: HistoryResult, isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.2) : Color.gray.opacity(0.1)
        } else if entry.destinationID == destinationStore.activeDestinationId && entry.entry.id == hoveredEntryId {
            return Color.gray.opacity(0.05)  // Even more subtle hover state
        } else {
            return Color.clear
        }
    }
    
    private func updatePreviewText(for entry: HumanEntry) {
        if entry.entryType == .video {
            if let index = entries.firstIndex(where: { $0.id == entry.id }),
               let videoFilename = resolvedVideoFilename(for: entry) {
                entries[index].previewText = HistoryEntryReader.videoTitle(from: loadTranscriptText(for: videoFilename))
                entries[index].searchableBody = loadTranscriptText(for: videoFilename) ?? ""
            }
            return
        }

        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            
            // Find and update the entry in the entries array
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index].previewText = HistoryRowFormatting.title(from: content)
                entries[index].searchableBody = content
                if HistoryEntryReader.canonicalTimestamp(for: entry.filename) == nil {
                    entries[index].timestamp = HistoryEntryReader.modificationDate(for: fileURL)
                }
            }
        } catch {
            print("Error updating preview text: \(error)")
        }
    }
    
    @discardableResult
    private func saveEntry(entry: HumanEntry, updatePreview: Bool = true) -> Bool {
        guard entry.entryType == .text else {
            return false
        }

        guard let documentsDirectory = destinationStore.resolvedDocumentsURL() else {
            print("Skipping save — active destination unavailable")
            return false
        }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        
        do {
            if historyTrash?.isUneditedReplacement(at: fileURL) == true {
                if text.isEmpty { return true }
                historyTrash?.invalidateReplacement()
            }
            text = try noteSaveState.save(text, to: fileURL)
            print("Successfully saved entry: \(entry.filename)")
            if updatePreview {
                updatePreviewText(for: entry)
            }
            return true
        } catch {
            print("Error saving entry: \(error)")
            return false
        }
    }
    
    @discardableResult
    private func loadEntry(entry: HumanEntry, beforeDisplaying: () -> Bool = { true }) -> Bool {
        let videoFilename = resolvedVideoFilename(for: entry)
        var loadedText = ""
        var loadedURL: URL?
        if videoFilename == nil {
            guard let documentsDirectory = getDocumentsDirectory() else { return false }
            let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

            do {
                loadedText = try noteSaveState.load(from: fileURL)
                loadedURL = fileURL.standardizedFileURL
                print("Successfully loaded entry: \(entry.filename)")
            } catch {
                print("Error loading entry: \(error)")
                noteOpenError = "\(entry.filename)\n\(error.localizedDescription)"
                return false
            }
        }

        guard beforeDisplaying() else { return false }
        if let loadedURL, unreadableConfiguredNoteURL == loadedURL {
            unreadableConfiguredNoteURL = nil
        }
        isLoadingEntry = true
        defer { isLoadingEntry = false }

        text = loadedText
        if let videoFilename {
            // Load video entry
            let videoURL = getVideoURL(for: videoFilename)
            let transcriptURL = getVideoTranscriptURL(for: videoFilename)
            didCopyTranscript = false
            selectedVideoHasTranscript = transcriptURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
            if let videoURL, fileManager.fileExists(atPath: videoURL.path) {
                currentVideoURL = videoURL
                print("Successfully loaded video entry: \(videoFilename)")
            } else {
                print("Video file missing for entry: \(videoFilename)")
            }
        } else {
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
        }
        selectedEntryId = entry.id
        return true
    }
    
    private func createNewEntry() {
        editorFocusRequest = UUID()
        savedConfirmation = nil
        let departure = finishEditingEntry()
        guard allowDeparture(departure, onDiscard: {
            discardEditorChanges(then: createNewEntry)
        }) else { return }

        let didSave: Bool
        // Rolling / Existing: re-bind to current period/target and append a session separator.
        if activeSaveMode == .rolling || activeSaveMode == .existing {
            didSave = bindToResolvedWriteTarget(appendSeparator: true)
        } else {
            if case .captureSaved = departure {
                didSave = true
            } else {
                didSave = false
            }
            beginFreshCaptureSession(clearText: true)
        }

        savedConfirmation = NoteSaveConfirmation.message(didSave: didSave, destinationName: activeDestinationDisplayName)
        savedConfirmationID = UUID()
    }

    private func quickCaptureDirectory(for url: URL) -> URL? {
        guard let directory = getDocumentsDirectory(),
              CaptureDraftStore.sameFile(directory, url.deletingLastPathComponent()) else { return nil }
        return directory
    }

    private func canAcceptQuickCapture(at url: URL) -> Bool {
        guard let directory = quickCaptureDirectory(for: url),
              let selected = entries.first(where: { $0.id == selectedEntryId }),
              selected.entryType == .text else { return true }
        let selectedURL = directory.appendingPathComponent(selected.filename)
        return !CaptureDraftStore.sameFile(selectedURL, url) || !noteSaveState.hasUnsavedChanges(text, at: selectedURL)
    }

    private func receiveQuickCapture(at url: URL) {
        guard let directory = quickCaptureDirectory(for: url) else { return }
        let index = entries.firstIndex {
            $0.filename.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame
                && CaptureDraftStore.sameFile(directory.appendingPathComponent($0.filename), url)
        }
        let actualURL = directory.appendingPathComponent(index.map { entries[$0].filename } ?? url.lastPathComponent)
        guard let updated = HistoryEntryReader(directory: directory).entry(
            at: actualURL, includeUnreadable: false
        ) else { return }
        if updated.entryType == .text,
           let selected = entries.first(where: { $0.id == selectedEntryId }), selected.entryType == .text {
            let selectedURL = directory.appendingPathComponent(selected.filename)
            if CaptureDraftStore.sameFile(selectedURL, url), !noteSaveState.hasUnsavedChanges(text, at: selectedURL) {
                text = updated.searchableBody
                noteSaveState.didLoad(text, from: selectedURL)
            }
        }
        if let index {
            entries[index] = updated
        } else {
            entries.insert(updated, at: 0)
        }
    }

    @ViewBuilder
    private func destinationChip() -> some View {
        Menu {
            ForEach(destinationStore.destinations) { destination in
                Button {
                    switchToDestination(id: destination.id)
                } label: {
                    HStack {
                        Text(destination.displayName)
                        Spacer()
                        if destination.id == destinationStore.activeDestinationId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Destination settings…") {
                openDestinationSettings()
            }
            Button("Add destination…") {
                // Dismiss the SwiftUI Menu before presenting NSOpenPanel.
                // Presenting the panel synchronously from a Menu action can race
                // AppKit's open-panel restore and show "The file couldn’t be opened."
                DispatchQueue.main.async {
                    addDestinationFromFolderPicker()
                }
            }
        } label: {
            DestinationMenuLabel(name: activeDestinationDisplayName)
        }
        .menuStyle(.borderlessButton)
        .opacity(isHoveringDestinationChip ? 1 : (colorScheme == .light ? 0.5 : 0.45))
        .nativeTooltip("Switch or manage save destinations")
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(-1)
        .onHover { hovering in
            isHoveringDestinationChip = hovering
            isHoveringBottomNav = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private func destinationSettingsRail(textColor: Color) -> some View {
        let pathLabel = destinationStore.activeDocumentsPath
            ?? (destinationStore.activeAccessFailed ? "Unavailable" : "—")
        let currentMode = settingsSaveMode
        let currentPeriod = settingsRollingPeriod
        let existingName = settingsExistingNoteFilename
        let existingNoteChoices = currentMode == .existing
            ? destinationStore.resolvedDocumentsURL().map { DestinationWriteTarget.existingNoteChoices(in: $0) } ?? []
            : []

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Destination settings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)
                Spacer()
                Button {
                    closeDestinationSettingsRail()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Display name", text: $settingsDisplayName)
                            .textFieldStyle(.roundedBorder)

                        Text("Folder")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        Text(pathLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)

                        Button("Reveal in Finder", action: revealActiveDestinationInFinder)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(destinationStore.activeDocumentsPath == nil)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save mode")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        ForEach(DestinationSaveMode.allCases, id: \.self) { mode in
                            Button {
                                settingsSaveMode = mode
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: currentMode == mode ? "circle.inset.filled" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundColor(textColor)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .font(.system(size: 13))
                                            .foregroundColor(textColor)
                                        Text(mode.explanation)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(mode.displayName)
                            .accessibilityHint(mode.explanation)
                            .accessibilityAddTraits(currentMode == mode ? .isSelected : [])
                        }
                    }

                    if currentMode == .newNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Filename format")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            ForEach(NewNoteFilenameFormat.allCases, id: \.self) { format in
                                Button {
                                    settingsNewNoteFilenameFormat = format
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: settingsNewNoteFilenameFormat == format ? "circle.inset.filled" : "circle")
                                            .font(.system(size: 12))
                                            .foregroundColor(textColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(format.displayName)
                                                .font(.system(size: 13))
                                                .foregroundColor(textColor)
                                            Text(format == .date
                                                 ? "Date and time when the note starts"
                                                 : "First paragraph when the note closes")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if currentMode == .rolling {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Period")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                ForEach(RollingPeriod.allCases, id: \.self) { period in
                                    Button {
                                        settingsRollingPeriod = period
                                        settingsFilenameFormat = period.defaultFilenameFormat
                                    } label: {
                                        Text(period.displayName)
                                            .font(.system(size: 12))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                currentPeriod == period
                                                    ? Color.gray.opacity(0.15)
                                                    : Color.clear
                                            )
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(textColor)
                                }
                            }

                            Text("Filename format")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            TextField("yyyy-MM-dd", text: $settingsFilenameFormat)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            Text("Tokens: yyyy MM dd ww — quote literals, e.g. yyyy-'W'ww")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let preview = settingsRollingFilenamePreview {
                                Text("Today → \(preview).md")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Invalid format (no path separators; basename only)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if currentMode == .existing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(existingName ?? "None selected")
                                .font(.system(size: 12))
                                .foregroundColor(existingName == nil ? .secondary : textColor)
                                .lineLimit(2)

                            Menu("Choose note…") {
                                ForEach(existingNoteChoices, id: \.self) { filename in
                                    Button {
                                        settingsExistingNoteFilename = filename
                                    } label: {
                                        if filename == existingName {
                                            Label(filename, systemImage: "checkmark")
                                        } else {
                                            Text(filename)
                                        }
                                    }
                                }
                                if !existingNoteChoices.isEmpty {
                                    Divider()
                                }
                                Button("New note…") {
                                    // Dismiss the SwiftUI Menu before presenting the alert.
                                    DispatchQueue.main.async {
                                        promptForNewExistingNote()
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .font(.system(size: 13))
                            .foregroundColor(textColor)
                            .disabled(destinationStore.activeAccessFailed)
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)

            Divider()

            HStack(spacing: 10) {
                Button("Cancel", action: cancelDestinationSettingsChangesAndClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)

                Spacer()

                Button("Save", action: saveDestinationSettingsDraft)
                    .buttonStyle(.bordered)
                    .disabled(!canSaveDestinationSettings)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func promptForNewExistingNote(initialName: String = "", rejected: Bool = false) {
        let field = NSTextField(string: initialName)
        field.placeholderString = "journal.md"
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)

        let alert = NSAlert()
        alert.messageText = "New note"
        alert.informativeText = rejected
            ? "Use a file name without folders, like journal.md."
            : "Name a markdown file in \(activeDestinationDisplayName). It is created when you save."
        alert.accessoryView = field
        alert.addButton(withTitle: "Use Note")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            if let filename = DestinationWriteTarget.existingNoteFilename(fromInput: field.stringValue) {
                settingsExistingNoteFilename = filename
            } else {
                DispatchQueue.main.async {
                    promptForNewExistingNote(initialName: field.stringValue, rejected: true)
                }
            }
        }

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            handleResponse(alert.runModal())
            return
        }
        alert.beginSheetModal(for: window, completionHandler: handleResponse)
        alert.window.makeFirstResponder(field)
    }

    private func deleteEntry(entry: HumanEntry) {
        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        var trash = HistoryTrash()
        do {
            try trash.moveToTrash(fileURL)
            if let videoFilename = resolvedVideoFilename(for: entry) {
                var assets: [URL] = []
                if let directory = getVideoEntryDirectory(for: videoFilename) {
                    assets.append(directory)
                }
                if let directory = getVideosDirectory() {
                    assets.append(directory.appendingPathComponent(videoFilename))
                }
                assets.append(documentsDirectory.appendingPathComponent(videoFilename))
                for url in assets where fileManager.fileExists(atPath: url.path) {
                    try trash.moveToTrash(url)
                }
                thumbnailMemoryCache.removeObject(forKey: videoFilename as NSString)
            }

            noteSaveState.forget(fileURL)
            historyTrash = trash
            trashedEntry = entry
            trashedEntryIndex = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
            trashedEntryWasSelected = selectedEntryId == entry.id
            trashDestinationID = destinationStore.activeDestinationId
            let noticeID = UUID()
            trashNoticeID = noticeID
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                guard trashNoticeID == noticeID else { return }
                historyTrash = nil
                trashedEntry = nil
            }

            // Remove the entry from the entries array
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)
                if inProgressCaptureFilename == entry.filename {
                    liveCaptureDraftRegistration = nil
                    inProgressCaptureFilename = nil
                    captureStartedAt = nil
                }

                // If the deleted entry was selected, select the first entry or create a new one
                if selectedEntryId == entry.id {
                    if let firstEntry = entries.first, loadEntry(entry: firstEntry) { return }
                    beginFreshCaptureSession(clearText: true)
                }
            }
        } catch {
            let deletionError = error
            do {
                try trash.restore()
            } catch {
                historyTrash = trash
                trashedEntry = entry
                trashDestinationID = destinationStore.activeDestinationId
            }
            trashError = deletionError.localizedDescription
        }
    }

    private func undoHistoryTrash() {
        guard var trash = historyTrash,
              trashDestinationID == destinationStore.activeDestinationId else { return }
        do {
            if trashedEntryWasSelected {
                let noticeID = trashNoticeID
                guard prepareToLeaveEntry(onDiscard: {
                    guard historyTrash != nil, trashNoticeID == noticeID else { return }
                    discardEditorChanges(then: undoHistoryTrash)
                }) else { return }
            }
            let restoredURLs = try trash.restore(finalizeCaptureDrafts: true)
            historyTrash = nil
            var restoredEntry = trashedEntry
            if let draft = trashedEntry,
               DestinationWriteTarget.isCaptureDraftFilename(draft.filename),
               let url = restoredURLs.first(where: { $0.pathExtension == "md" }) {
                restoredEntry = HistoryEntryReader(directory: url.deletingLastPathComponent()).entry(at: url)
            }
            if let entry = restoredEntry {
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index] = entry
                } else {
                    entries.insert(entry, at: min(trashedEntryIndex, entries.count))
                }
                if trashedEntryWasSelected {
                    loadEntry(entry: entry)
                }
            }
            trashedEntry = nil
        } catch {
            historyTrash = trash
            trashError = error.localizedDescription
        }
    }
}

// Helper function to calculate line height
func getLineHeight(font: NSFont) -> CGFloat {
    return font.ascender - font.descender + font.leading
}

// Add helper extension to find NSTextView
extension NSView {
    func findTextView() -> NSView? {
        if self is NSTextView {
            return self
        }
        for subview in subviews {
            if let textView = subview.findTextView() {
                return textView
            }
        }
        return nil
    }
}

struct DestinationMenuLabel: View {
    let name: String

    /// The destination menu hugs its name, so a long name has to be shortened by hand;
    /// letting the label take its full width would squeeze the nav's right-hand controls.
    static let maxNameWidth: CGFloat = 150
    static let fontSize: CGFloat = 13

    var body: some View {
        Text(Self.shortened(name, toFit: Self.maxNameWidth))
            .font(.system(size: Self.fontSize))
            .lineLimit(1)
    }

    static func shortened(_ name: String, toFit maxWidth: CGFloat) -> String {
        guard width(of: name) > maxWidth else { return name }
        var shortened = name
        while !shortened.isEmpty, width(of: shortened + "…") > maxWidth {
            shortened.removeLast()
        }
        return shortened.trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func width(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)]).width
    }
}

// Add helper extension for finding subviews of a specific type
extension NSView {
    func findSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let typedSelf = self as? T {
            return typedSelf
        }
        for subview in subviews {
            if let found = subview.findSubview(ofType: type) {
                return found
            }
        }
        return nil
    }
}

#Preview {
    ContentView()
}
