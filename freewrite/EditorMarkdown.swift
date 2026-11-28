import AppKit

enum EditorMarkdown {
    enum Style: Hashable {
        case heading(Int), quote, listMarker, marker
        case bold, italic, boldItalic, code, linkLabel
    }

    struct Span: Equatable {
        let range: NSRange
        let style: Style
    }

    private static let fence = try! NSRegularExpression(pattern: #"^ {0,3}(\x60{3,}(?!\x60)[^\x60\r\n\u2028\u2029]*|~{3,}[^\r\n\u2028\u2029]*)$"#, options: .anchorsMatchLines)
    private static let heading = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})(?=[ \t]|$)"#)
    private static let headingEnd = try! NSRegularExpression(pattern: #"[ \t]+(#+)[ \t]*$"#)
    private static let quote = try! NSRegularExpression(pattern: #"^ {0,3}(>(?:[ \t]?>)*)[ \t]?"#)
    private static let list = try! NSRegularExpression(pattern: #"^[ \t]*([-+*]|[0-9]{1,9}[.)])(?=[ \t]|$)"#)
    private static let inline = try! NSRegularExpression(pattern: [
        #"\\[[:punct:]]"#,
        #"(?<!\x60)(\x60+)(?!\x60)(.+?)(?<!\x60)\1(?!\x60)"#,
        #"\[([^\[\]]+)\]\((?:[^()\s]|\([^()\s]*\))+\)"#,
        #"(?<!\*)(\*{1,3})(?![\s*])((?:[^*\\]|\\.)+?)(?<!\s)\4(?!\*)"#,
        #"(?<![\p{L}\p{N}_])(_{1,3})(?![\s_])((?:[^_\\]|\\.)+?)(?<!\s)\6(?![\p{L}\p{N}_])"#,
    ].joined(separator: "|"))

    private struct Fence {
        let marker: UInt16
        let length: Int

        static func toggle(_ open: inout Fence?, for match: NSTextCheckingResult, in text: NSString) -> Bool {
            let token = match.range(at: 1)
            let marker = text.character(at: token.location)
            var end = token.location + 1
            while end < NSMaxRange(token), text.character(at: end) == marker { end += 1 }
            let length = end - token.location
            if let active = open {
                guard marker == active.marker, length >= active.length else { return false }
                while end < NSMaxRange(token) {
                    let character = text.character(at: end)
                    guard character == 32 || character == 9 else { return false }
                    end += 1
                }
                open = nil
            } else {
                open = Fence(marker: marker, length: length)
            }
            return true
        }
    }

    struct Edit {
        let range: NSRange
        let changeInLength: Int
    }

    static func invalidatedRange(in source: String, replacing previous: String, edit: Edit) -> NSRange {
        let full = NSRange(location: 0, length: source.utf16.count)
        let oldLength = previous.utf16.count
        let oldEditLength = edit.range.length - edit.changeInLength
        guard full.length - oldLength == edit.changeInLength, NSMaxRange(edit.range) <= full.length,
              oldEditLength >= 0, edit.range.location + oldEditLength <= oldLength else {
            return full
        }
        let oldLines = (previous as NSString).lineRange(for: NSRange(
            location: edit.range.location, length: oldEditLength + min(1, oldLength - edit.range.location - oldEditLength)
        ))
        let newLines = (source as NSString).lineRange(for: NSRange(
            location: edit.range.location, length: edit.range.length + min(1, full.length - NSMaxRange(edit.range))
        ))
        if fence.firstMatch(in: previous, range: oldLines) != nil || fence.firstMatch(in: source, range: newLines) != nil {
            return NSRange(location: newLines.location, length: full.length - newLines.location)
        }
        return newLines
    }

    static func spans(in source: String, range: NSRange? = nil) -> [Span] {
        let text = source as NSString
        let range = range ?? NSRange(location: 0, length: text.length)
        var spans: [Span] = []
        var openFence: Fence?
        if range.location > 0 {
            for match in fence.matches(in: source, range: NSRange(location: 0, length: range.location)) {
                _ = Fence.toggle(&openFence, for: match, in: text)
            }
        }
        var location = range.location
        while location < NSMaxRange(range) {
            var end = 0
            var contentEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: location, length: contentEnd - location)
            location = end
            guard line.length > 0 else { continue }

            if let match = fence.firstMatch(in: source, range: line),
               Fence.toggle(&openFence, for: match, in: text) {
                spans.append(Span(range: line, style: .marker))
                continue
            }
            if openFence != nil {
                spans.append(Span(range: line, style: .code))
                continue
            }

            var body = line
            if let match = quote.firstMatch(in: source, range: body) {
                spans.append(Span(range: match.range(at: 1), style: .marker))
                body = NSRange(location: NSMaxRange(match.range), length: NSMaxRange(body) - NSMaxRange(match.range))
                spans.append(Span(range: body, style: .quote))
            }
            if let match = list.firstMatch(in: source, range: body) {
                spans.append(Span(range: match.range(at: 1), style: .listMarker))
                let start = NSMaxRange(match.range)
                body = NSRange(location: start, length: NSMaxRange(body) - start)
            }
            if let match = heading.firstMatch(in: source, range: body) {
                let hashes = match.range(at: 1)
                spans.append(Span(range: hashes, style: .marker))
                let start = NSMaxRange(match.range)
                let closing = headingEnd.firstMatch(in: source, range: NSRange(location: start, length: NSMaxRange(body) - start))
                if let closing { spans.append(Span(range: closing.range(at: 1), style: .marker)) }
                body = NSRange(location: start, length: (closing?.range.location ?? NSMaxRange(body)) - start)
                spans.append(Span(range: body, style: .heading(hashes.length)))
            }
            appendInline(in: source, range: body, to: &spans)
        }
        return spans
    }

    private static func appendInline(in source: String, range: NSRange, to spans: inout [Span], depth: Int = 0) {
        guard range.length > 0, depth < 3 else { return }
        for match in inline.matches(in: source, range: range) {
            let content: NSRange
            let style: Style
            if match.range(at: 1).location != NSNotFound {
                content = match.range(at: 2)
                style = .code
            } else if match.range(at: 3).location != NSNotFound {
                content = match.range(at: 3)
                style = .linkLabel
            } else if match.range(at: 4).location != NSNotFound || match.range(at: 6).location != NSNotFound {
                let group = match.range(at: 4).location != NSNotFound ? 4 : 6
                content = match.range(at: group + 1)
                let length = match.range(at: group).length
                style = length == 3 ? .boldItalic : length == 2 ? .bold : .italic
            } else {
                continue
            }
            spans.append(Span(range: NSRange(location: match.range.location, length: content.location - match.range.location), style: .marker))
            spans.append(Span(range: content, style: style))
            spans.append(Span(range: NSRange(location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)), style: .marker))
            if style != .code {
                appendInline(in: source, range: content, to: &spans, depth: depth + 1)
            }
        }
    }

    static func apply(to storage: NSTextStorage, attributes: [NSAttributedString.Key: Any], range: NSRange) {
        let source = storage.string
        guard range.length > 0 else { return }
        let bodyFont = attributes[.font] as? NSFont ?? .systemFont(ofSize: 16)
        let ink = attributes[.foregroundColor] as? NSColor ?? .textColor
        let fonts = NSFontManager.shared
        var faces: [FontFace: NSFont] = [:]
        storage.beginEditing()
        storage.setAttributes(attributes, range: range)
        for span in spans(in: source, range: range) where span.range.length > 0 {
            switch span.style {
            case .marker:
                storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.68), range: span.range)
            case .listMarker:
                storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.72), range: span.range)
                storage.addAttribute(.font, value: fonts.convert(bodyFont, toHaveTrait: .boldFontMask), range: span.range)
            case .linkLabel:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
            case .code:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular), range: span.range)
                storage.addAttribute(.backgroundColor, value: ink.withAlphaComponent(0.08), range: span.range)
            case .heading, .quote, .italic, .bold, .boldItalic:
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
                        case .bold:
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
        storage.endEditing()
    }

    private struct FontFace: Hashable {
        let font: NSFont
        let style: Style
    }
}
