import AppKit

enum EditorMarkdown {
    enum Style: Hashable {
        case heading(Int), quote, quoteBar, listMarker, bullet, checkedTask, uncheckedTask, marker
        case bold, italic, boldItalic, strike, code, linkLabel, imageAlt, imagePlaceholder, rule, tableHeader, tableDivider
    }

    struct Span: Equatable {
        let range: NSRange
        let style: Style
    }

    private static let atxOpener = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}$"#)
    private static let atxPrefix = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6}[ \t]+)"#)
    private static let taskPrefixPattern = try! NSRegularExpression(pattern: #"^[ \t]*([-+*][ \t]+\[[ xX]\][ \t]+)"#)

    static func isATXOpener(in source: String, range: NSRange) -> Bool {
        atxOpener.firstMatch(in: source, range: range)?.range == range
    }

    static func atxPrefix(in source: String, at location: Int) -> NSRange? {
        let text = source as NSString
        guard location < text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        guard line.location == location else { return nil }
        return atxPrefix.firstMatch(in: source, range: line)?.range(at: 1)
    }

    /// The Markdown that replaces a line-start `[` or `[x` once its closing bracket arrives.
    static func taskOpening(typed: String) -> String? {
        switch typed {
        case "[": "- [ ] "
        case "[x", "[X": "- [x] "
        default: nil
        }
    }

    /// The task item prefix (`- [ ] ` or `- [x] `) at the start of the line holding `location`.
    static func taskPrefix(in source: String, at location: Int) -> NSRange? {
        let text = source as NSString
        guard location < text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        guard line.location == location else { return nil }
        return taskPrefixPattern.firstMatch(in: source, range: line)?.range(at: 1)
    }

    static func apply(to storage: NSTextStorage, attributes: [NSAttributedString.Key: Any], range: NSRange,
                      spans: [Span], editingLines: NSRange?, liveHeadingPrefix: NSRange?,
                      liveTaskPrefix: NSRange? = nil) {
        guard range.length > 0 else { return }
        let bodyFont = attributes[.font] as? NSFont ?? .systemFont(ofSize: 16)
        let ink = attributes[.foregroundColor] as? NSColor ?? .textColor
        let fonts = NSFontManager.shared
        var faces: [FontFace: NSFont] = [:]
        let liveHeading = liveHeadingPrefix.map { spans.contains(Span(range: $0, style: .marker)) } == true
            ? liveHeadingPrefix : nil
        let liveTask = liveTaskPrefix.flatMap { prefix -> NSRange? in
            let boxed = spans.contains {
                ($0.style == .uncheckedTask || $0.style == .checkedTask)
                    && $0.range.location >= prefix.location && NSMaxRange($0.range) <= NSMaxRange(prefix)
            }
            return boxed ? prefix : nil
        }

        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(attributes, range: range)
        for span in spans where span.range.length > 0 && NSMaxRange(span.range) <= storage.length {
            let target = NSIntersectionRange(span.range, range)
            guard target.length > 0 else { continue }
            let source = editingLines.map { NSIntersectionRange($0, target) }
            let keepsBullet = span.style == .bullet && (storage.string as NSString).character(at: span.range.location) == 45
            let keepsHeading: Bool
            if let liveHeading, let source, source.length > 0 {
                if case .heading = span.style {
                    keepsHeading = span.range.location == NSMaxRange(liveHeading)
                } else {
                    keepsHeading = span.style == .marker && span.range == liveHeading
                }
            } else {
                keepsHeading = false
            }
            let keepsTask = liveTask.map { span.range.location >= $0.location && NSMaxRange(span.range) <= NSMaxRange($0) } ?? false
            if let source, source.length > 0, span.style != .listMarker, !keepsBullet, !keepsHeading, !keepsTask {
                if target.location < source.location {
                    apply(Span(range: NSRange(location: target.location, length: source.location - target.location), style: span.style))
                }
                if NSMaxRange(source) < NSMaxRange(target) {
                    apply(Span(range: NSRange(location: NSMaxRange(source), length: NSMaxRange(target) - NSMaxRange(source)), style: span.style))
                }
            } else {
                apply(Span(range: target, style: span.style))
            }
        }

        if let liveHeading, NSLocationInRange(liveHeading.location, range) {
            let level = (storage.string as NSString).substring(with: liveHeading).prefix { $0 == "#" }.count
            let anchor = NSRange(location: liveHeading.location, length: 1)
            storage.addAttributes([.markdownCaretAnchor: true, .font: headingFont(bodyFont, level: level)], range: anchor)
        }
        if let liveTask, NSLocationInRange(liveTask.location, range) {
            storage.addAttribute(.markdownCaretAnchor, value: true, range: NSRange(location: liveTask.location, length: 1))
        }

        func apply(_ span: Span) {
            switch span.style {
            case .marker:
                storage.addAttribute(.markdownHidden, value: true, range: span.range)
            case .listMarker:
                storage.addAttribute(.markdownList, value: true, range: span.range)
            case .bullet, .checkedTask, .uncheckedTask, .rule, .tableDivider, .quoteBar, .imagePlaceholder:
                guard let glyph = glyph(for: span.style) else { return }
                storage.addAttribute(.markdownGlyph, value: glyph, range: span.range)
                let symbolFont = NSFont(name: "Menlo", size: bodyFont.pointSize)
                let fallback = NSFont.systemFont(ofSize: bodyFont.pointSize)
                let font = span.style == .bullet ? fallback : (symbolFont ?? fallback)
                storage.addAttribute(.font, value: font, range: span.range)
            case .linkLabel:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
            case .imageAlt:
                storage.addAttribute(.backgroundColor, value: ink.withAlphaComponent(0.08), range: span.range)
            case .code:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular), range: span.range)
                storage.addAttribute(.backgroundColor, value: ink.withAlphaComponent(0.08), range: span.range)
            case .heading, .quote, .italic, .bold, .boldItalic, .tableHeader:
                var runs: [(NSFont, NSRange)] = []
                storage.enumerateAttribute(.font, in: span.range) { value, range, _ in
                    runs.append((value as? NSFont ?? bodyFont, range))
                }
                for (font, range) in runs {
                    let key = FontFace(font: font, style: span.style)
                    let styled: NSFont
                    if let cached = faces[key] {
                        styled = cached
                    } else {
                        switch span.style {
                        case .heading(let level):
                            styled = headingFont(font, level: level)
                        case .bold, .tableHeader:
                            styled = fonts.convert(font, toHaveTrait: .boldFontMask)
                        case .boldItalic:
                            styled = fonts.convert(fonts.convert(font, toHaveTrait: .boldFontMask), toHaveTrait: .italicFontMask)
                        default:
                            styled = fonts.convert(font, toHaveTrait: .italicFontMask)
                        }
                        faces[key] = styled
                    }
                    storage.addAttribute(.font, value: styled, range: range)
                }
            }
        }

        func headingFont(_ font: NSFont, level: Int) -> NSFont {
            let size = bodyFont.pointSize + CGFloat([8, 6, 4, 3, 2, 1][level - 1])
            return fonts.convert(fonts.convert(font, toHaveTrait: .boldFontMask), toSize: size)
        }
    }

    static func renderedTitle(_ line: String) -> String {
        var hidden = IndexSet()
        var replacements: [Int: UInt16] = [:]
        for span in MarkdownSourceProjection.spans(in: line) {
            if span.style == .marker {
                hidden.insert(integersIn: span.range.location..<NSMaxRange(span.range))
            } else if let glyph = glyph(for: span.style) {
                replacements[span.range.location] = glyph
            }
        }
        let units = line.utf16.enumerated().compactMap { index, character in
            hidden.contains(index) ? nil : (replacements[index] ?? character)
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func glyph(for style: Style) -> UInt16? {
        switch style {
        case .bullet: 0x2022
        case .checkedTask: 0x2611
        case .uncheckedTask: 0x2610
        case .rule: 0x2015
        case .tableDivider, .quoteBar: 0x2502
        case .imagePlaceholder: 0x25C7
        default: nil
        }
    }

    static func displaySpans(in source: String, provisionalBullet: Int?) -> [Span] {
        let spans = MarkdownSourceProjection.spans(in: source)
        guard let index = provisionalBullet else { return spans }
        let text = source as NSString
        guard index + 2 <= text.length else { return spans }
        var start = 0
        var end = 0
        text.getLineStart(&start, end: nil, contentsEnd: &end, for: NSRange(location: index, length: 0))
        guard index == start, end - start == 2,
              text.substring(with: NSRange(location: start, length: 2)) == "- " else { return spans }
        let marker = NSRange(location: index, length: 1)
        guard !spans.contains(Span(range: marker, style: .listMarker)) else { return spans }
        let neutralSource = text.replacingCharacters(in: marker, with: "a")
        return MarkdownSourceProjection.spans(in: neutralSource) + [
            Span(range: marker, style: .listMarker), Span(range: marker, style: .bullet),
        ]
    }

    private struct FontFace: Hashable {
        let font: NSFont
        let style: Style
    }
}

extension NSAttributedString.Key {
    static let markdownHidden = Self("QuickNoteMarkdownHidden")
    static let markdownCaretAnchor = Self("QuickNoteMarkdownCaretAnchor")
    static let markdownGlyph = Self("QuickNoteMarkdownGlyph")
    static let markdownList = Self("QuickNoteMarkdownList")
}
