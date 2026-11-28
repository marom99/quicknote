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

    static func apply(to storage: NSTextStorage, attributes: [NSAttributedString.Key: Any], range: NSRange,
                      spans: [Span], editingLines: NSRange?) {
        guard range.length > 0 else { return }
        let bodyFont = attributes[.font] as? NSFont ?? .systemFont(ofSize: 16)
        let ink = attributes[.foregroundColor] as? NSColor ?? .textColor
        let fonts = NSFontManager.shared
        var faces: [FontFace: NSFont] = [:]

        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(attributes, range: range)
        for span in spans where span.range.length > 0 && NSMaxRange(span.range) <= storage.length {
            let target = NSIntersectionRange(span.range, range)
            guard target.length > 0 else { continue }
            let source = editingLines.map { NSIntersectionRange($0, target) }
            let keepsBullet = span.style == .bullet && (storage.string as NSString).character(at: span.range.location) == 45
            if let source, source.length > 0, span.style != .listMarker, !keepsBullet {
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
                            let size = bodyFont.pointSize + CGFloat(max(0, 4 - level)) * 2
                            styled = fonts.convert(fonts.convert(font, toHaveTrait: .boldFontMask), toSize: size)
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
    static let markdownGlyph = Self("QuickNoteMarkdownGlyph")
    static let markdownList = Self("QuickNoteMarkdownList")
}
