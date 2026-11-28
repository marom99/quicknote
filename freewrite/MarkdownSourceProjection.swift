import Foundation
import cmark_gfm
import cmark_gfm_extensions

enum MarkdownSourceProjection {
    private typealias Node = UnsafeMutablePointer<cmark_node>

    private static let extensions = ["table", "strikethrough", "autolink", "tasklist"]
    private static let registered: Void = cmark_gfm_core_extensions_ensure_registered()

    static func spans(in source: String) -> [EditorMarkdown.Span] {
        project(source).spans.compactMap { $0 }
    }

    static func isLiteral(at location: Int, in source: String) -> Bool {
        guard location >= 0, location <= source.utf16.count else { return false }
        return project(source).literalRanges.contains { $0.contains(location) }
    }

    private static func project(_ source: String) -> Projection {
        var result = Projection(source)
        guard !result.source.bytes.isEmpty else { return result }
        _ = registered
        guard let parser = cmark_parser_new(CMARK_OPT_SOURCEPOS) else { return result }
        defer { cmark_parser_free(parser) }
        for name in extensions {
            if let syntax = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntax)
            }
        }
        result.source.bytes.withUnsafeBytes { bytes in
            cmark_parser_feed(parser, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), bytes.count)
        }
        guard let root = cmark_parser_finish(parser) else { return result }
        defer { cmark_node_free(root) }
        _ = result.visit(root)
        result.hideStandaloneDefinitions(in: root)
        return result
    }

    private struct Source {
        let bytes: [UInt8]
        let utf16: [Int]
        let lines: [Range<Int>]
        let unmappableLines: Set<Int>

        init(_ text: String) {
            bytes = Array(text.utf8)
            var offsets = [Int](repeating: -1, count: bytes.count + 1)
            var lines: [Range<Int>] = []
            var lineStart = 0
            var index = 0
            var location = 0
            var unmappable: Set<Int> = []
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0 { unmappable.insert(lines.count + 1) }
                if byte == 13 || (byte == 10 && (index == 0 || bytes[index - 1] != 13)) {
                    lines.append(lineStart..<index)
                    lineStart = index + (byte == 13 && index + 1 < bytes.count && bytes[index + 1] == 10 ? 2 : 1)
                }
                offsets[index] = location
                location += byte >= 0xF0 ? 2 : 1
                index += byte < 0x80 ? 1 : byte < 0xE0 ? 2 : byte < 0xF0 ? 3 : 4
            }
            offsets[index] = location
            lines.append(lineStart..<index)
            self.lines = lines
            utf16 = offsets
            unmappableLines = unmappable
        }

        subscript(_ offset: Int) -> UInt8 {
            bytes.indices.contains(offset) ? bytes[offset] : 0
        }

        func line(_ number: Int) -> Range<Int>? {
            guard number > 0, number <= lines.count else { return nil }
            return lines[number - 1]
        }

        func offset(line number: Int, column: Int) -> Int? {
            guard !unmappableLines.contains(number), let line = line(number), column >= 0, column <= line.count else { return nil }
            let offset = line.lowerBound + column
            return utf16[offset] >= 0 ? offset : nil
        }

        func range(_ bytes: Range<Int>) -> NSRange? {
            guard bytes.lowerBound >= 0, bytes.upperBound < utf16.count,
                  utf16[bytes.lowerBound] >= 0, utf16[bytes.upperBound] >= 0 else { return nil }
            return NSRange(location: utf16[bytes.lowerBound], length: utf16[bytes.upperBound] - utf16[bytes.lowerBound])
        }
    }

    private struct Projection {
        let source: Source
        var spans: [EditorMarkdown.Span?] = []
        var literalRanges: [ClosedRange<Int>] = []
        var quotePrefixes: [Int: Int] = [:]
        var listPrefixes: [Int: Int] = [:]

        init(_ text: String) {
            source = Source(text)
        }

        mutating func add(_ range: Range<Int>, _ style: EditorMarkdown.Style) {
            guard !range.isEmpty, let range = source.range(range) else { return }
            spans.append(.init(range: range, style: style))
        }

        func start(_ node: Node) -> Int? {
            source.offset(line: Int(cmark_node_get_start_line(node)), column: Int(cmark_node_get_start_column(node)) - 1)
        }

        func end(_ node: Node, on line: Int? = nil) -> Int? {
            source.offset(line: line ?? Int(cmark_node_get_end_line(node)), column: Int(cmark_node_get_end_column(node)))
        }

        func bounds(_ node: Node) -> Range<Int>? {
            guard let start = start(node), let end = end(node), start <= end else { return nil }
            return start..<end
        }

        func space(_ byte: UInt8) -> Bool {
            byte == 32 || byte == 9
        }

        func trim(_ range: Range<Int>) -> Range<Int> {
            var first = range.lowerBound
            var last = range.upperBound
            while first < last && space(source[first]) { first += 1 }
            while last > first && space(source[last - 1]) { last -= 1 }
            return first..<last
        }

        func prefixEnd(_ line: Range<Int>) -> Int {
            max(quotePrefixes[line.lowerBound] ?? line.lowerBound, listPrefixes[line.lowerBound] ?? line.lowerBound)
        }

        mutating func hideStandaloneDefinitions(in root: Node) {
            var block = cmark_node_first_child(root)
            for (index, line) in source.lines.enumerated() {
                let lineNumber = index + 1
                while let current = block, cmark_node_get_end_line(current) < lineNumber {
                    block = cmark_node_next(current)
                }
                if let current = block, cmark_node_get_start_line(current) <= lineNumber { continue }
                let content = trim(line)
                guard !content.isEmpty, content.lowerBound - line.lowerBound <= 3, source[content.lowerBound] == 91,
                      content.contains(where: { source[$0] == 93 && source[$0 + 1] == 58 }) else { continue }
                let parsed = source.bytes.withUnsafeBytes { bytes in
                    cmark_parse_document(bytes.baseAddress?.assumingMemoryBound(to: CChar.self).advanced(by: line.lowerBound),
                                         line.count, CMARK_OPT_DEFAULT)
                }
                guard let parsed else { continue }
                if cmark_node_first_child(parsed) == nil { add(line, .marker) }
                cmark_node_free(parsed)
            }
        }

        mutating func visit(
            _ node: Node,
            bold: Bool = false,
            italic: Bool = false,
            listIndent: Int = 0,
            depth: Int = 0,
            precedingLiteralEnd: Int? = nil
        ) -> Range<Int>? {
            let type = String(cString: cmark_node_get_type_string(node))
            let range = bounds(node)
            guard depth < 128 else { return range }
            var indent = listIndent
            switch type {
            case "text":
                if let range { textEscapes(node, range: range) }
                return range
            case "heading": heading(node)
            case "block_quote": quote(node)
            case "item", "tasklist": indent = item(node, indent: indent)
            case "code_block": blockCode(node, indent: indent)
            case "code": return inlineCode(node)
            case "html_block":
                if let range, let mapped = source.range(range) {
                    literalRanges.append(mapped.location...NSMaxRange(mapped))
                }
                return range
            case "thematic_break": rule(node)
            case "table": table(node)
            case "table_header", "table_row": tableRow(node, header: type == "table_header")
            default: break
            }

            let isBold = type == "strong"
            let isItalic = type == "emph"
            let isStrike = type == "strikethrough"
            let isLink = type == "link" || type == "image"
            let slot = spans.count
            if isBold || isItalic || isStrike || isLink { spans.append(nil) }

            if type == "table_cell", let range,
               range.contains(where: { source[$0] == 124 && source[$0 - 1] == 92 }) { return range }

            if (type == "paragraph" || type == "heading"), let beginning = start(node),
               source[beginning] == 91,
               let line = source.line(Int(cmark_node_get_start_line(node))),
               line.contains(where: { $0 > beginning && source[$0 - 1] == 93 && source[$0] == 58 && !escaped($0 - 1) }),
               cmark_node_get_start_line(node) < cmark_node_get_end_line(node) { return range }

            var child = cmark_node_first_child(node)
            var first: Range<Int>?
            var last: Range<Int>?
            var literalEnd: Int?
            while let current = child {
                let childRange = visit(
                    current, bold: bold || isBold, italic: italic || isItalic, listIndent: indent,
                    depth: depth + 1, precedingLiteralEnd: literalEnd
                )
                if cmark_node_get_type(current) == CMARK_NODE_TEXT, let literal = cmark_node_get_literal(current),
                   let offset = start(current) ?? literalEnd {
                    let bytes = String(cString: literal).utf8
                    let end = offset + bytes.count
                    literalEnd = end <= source.bytes.count && source.bytes[offset..<end].elementsEqual(bytes) ? end : nil
                } else {
                    literalEnd = childRange?.upperBound
                }
                if let childRange, !childRange.isEmpty {
                    if first == nil { first = childRange }
                    last = childRange
                }
                child = cmark_node_next(current)
            }
            if isLink {
                return link(node, image: type == "image", labelEnd: last?.upperBound, slot: slot,
                            precedingLiteralEnd: precedingLiteralEnd) ?? range
            }
            if isBold || isItalic || isStrike {
                guard let first, let last, first.lowerBound <= last.upperBound,
                      let opening = start(node) else { return range }
                let width: Int
                let style: EditorMarkdown.Style
                if isStrike {
                    width = source[opening + 1] == 126 ? 2 : 1
                    style = .strike
                } else {
                    width = isBold ? 2 : 1
                    style = (bold || isBold) && (italic || isItalic) ? .boldItalic : isBold ? .bold : .italic
                }
                let line = isStrike ? Int(cmark_node_get_end_line(cmark_node_last_child(node))) : nil
                guard let closing = end(node, on: line) else { return range }
                let opener = first.lowerBound - width
                let closer = last.upperBound
                let delimiter = source[opening]
                guard (isStrike ? delimiter == 126 : delimiter == 42 || delimiter == 95),
                      opener >= opening, closer + width <= closing,
                      (opener..<first.lowerBound).allSatisfy({ source[$0] == delimiter }),
                      (closer..<(closer + width)).allSatisfy({ source[$0] == delimiter }),
                      !escaped(opener), !escaped(closer) else { return range }
                let content = first.lowerBound..<last.upperBound
                if let styleRange = source.range(content) { spans[slot] = .init(range: styleRange, style: style) }
                add(opener..<first.lowerBound, .marker)
                add(closer..<(closer + width), .marker)
                return opener..<(closer + width)
            }
            return range
        }

        func escaped(_ offset: Int) -> Bool {
            var start = offset
            while source[start - 1] == 92 { start -= 1 }
            return (offset - start) % 2 != 0
        }

        mutating func textEscapes(_ node: Node, range: Range<Int>) {
            guard source.bytes[range].contains(92), let literal = cmark_node_get_literal(node) else { return }
            var rendered: [UInt8] = []
            var markers: [Int] = []
            var offset = range.lowerBound
            while offset < range.upperBound {
                let next = source[offset + 1]
                let punctuation = (33...47).contains(next) || (58...64).contains(next)
                    || (91...96).contains(next) || (123...126).contains(next)
                if source[offset] == 92, offset + 1 < range.upperBound, punctuation {
                    markers.append(offset)
                    offset += 1
                }
                rendered.append(source[offset])
                offset += 1
            }
            guard !markers.isEmpty, rendered.elementsEqual(String(cString: literal).utf8) else { return }
            for marker in markers { add(marker..<(marker + 1), .marker) }
        }

        mutating func heading(_ node: Node) {
            let number = Int(cmark_node_get_start_line(node))
            let level = Int(cmark_node_get_heading_level(node))
            guard let start = start(node), let line = source.line(number) else { return }
            let openingEnd = start + level
            if openingEnd <= line.upperBound, (start..<openingEnd).allSatisfy({ source[$0] == 35 }),
               openingEnd == line.upperBound || space(source[openingEnd]) {
                let body = trim(openingEnd..<line.upperBound)
                var closing = body.upperBound
                while closing > body.lowerBound && source[closing - 1] == 35 { closing -= 1 }
                let hasClosing = closing < body.upperBound && space(source[closing - 1])
                let content = trim(body.lowerBound..<(hasClosing ? closing : body.upperBound))
                add(start..<body.lowerBound, .marker)
                if hasClosing { add(content.upperBound..<line.upperBound, .marker) }
                add(content, .heading(level))
                return
            }
            let last = Int(cmark_node_get_end_line(node))
            let afterContent = Int(cmark_node_get_end_line(cmark_node_last_child(node))) + 1
            for candidate in [afterContent, last, last - 1] where candidate > number && candidate <= last {
                guard let line = source.line(candidate) else { continue }
                let body = trim(prefixEnd(line)..<line.upperBound)
                let delimiter: UInt8 = level == 1 ? 61 : 45
                if !body.isEmpty && body.allSatisfy({ source[$0] == delimiter }) {
                    add(body, .marker)
                    if let previous = source.line(candidate - 1) { add(start..<previous.upperBound, .heading(level)) }
                    return
                }
            }
        }

        mutating func quote(_ node: Node) {
            let first = Int(cmark_node_get_start_line(node))
            let last = Int(cmark_node_get_end_line(node))
            guard let start = start(node), let lastLine = source.line(last), first <= last else { return }
            add(start..<lastLine.upperBound, .quote)
            for number in first...last {
                guard let line = source.line(number) else { continue }
                let marker = number == first ? start : trim(prefixEnd(line)..<line.upperBound).lowerBound
                guard marker < line.upperBound, source[marker] == 62 else { continue }
                let end = marker + (space(source[marker + 1]) ? 2 : 1)
                add(marker..<(marker + 1), .quoteBar)
                quotePrefixes[line.lowerBound] = end
            }
        }

        mutating func item(_ node: Node, indent: Int) -> Int {
            guard let start = start(node), let line = source.line(Int(cmark_node_get_start_line(node))) else { return indent }
            var markerEnd = start
            while (48...57).contains(source[markerEnd]) { markerEnd += 1 }
            let ordered = markerEnd > start
            guard ordered ? source[markerEnd] == 46 || source[markerEnd] == 41
                : source[markerEnd] == 45 || source[markerEnd] == 43 || source[markerEnd] == 42 else { return indent }
            markerEnd += 1
            guard markerEnd <= line.upperBound, markerEnd == line.upperBound || space(source[markerEnd]) else { return indent }
            add(start..<markerEnd, .listMarker)
            let body = trim(markerEnd..<line.upperBound).lowerBound
            let padding = max(1, min(4, body - markerEnd))
            listPrefixes[line.lowerBound] = markerEnd + min(body - markerEnd, padding)

            if body + 3 < line.upperBound, source[body] == 91, source[body + 2] == 93,
               space(source[body + 3]), body - markerEnd <= 4,
               source[body + 1] == 32 || source[body + 1] == 120 || source[body + 1] == 88 {
                if !ordered { add(start..<body, .marker) }
                add(body..<(body + 1), source[body + 1] == 32 ? .uncheckedTask : .checkedTask)
                add((body + 1)..<(body + 3), .marker)
            } else if !ordered {
                add(start..<markerEnd, .bullet)
            }
            let quoteEnd = quotePrefixes[line.lowerBound] ?? line.lowerBound
            return markerEnd - quoteEnd + padding
        }

        mutating func rule(_ node: Node) {
            guard let start = start(node), let line = source.line(Int(cmark_node_get_start_line(node))),
                  start < line.upperBound else { return }
            let delimiter = source[start]
            guard [45, 42, 95].contains(delimiter),
                  (start..<line.upperBound).allSatisfy({ source[$0] == delimiter || space(source[$0]) }) else { return }
            add(start..<(start + 1), .rule)
            add((start + 1)..<line.upperBound, .marker)
        }

        mutating func inlineCode(_ node: Node) -> Range<Int>? {
            guard let body = bounds(node), !body.isEmpty else { return nil }
            let length = Int(cmark_node_get_backtick_count(node))
            let opening = body.lowerBound - length
            let closing = body.upperBound + length
            guard length > 0, opening >= 0, closing <= source.bytes.count,
                  source[opening - 1] != 96, source[closing] != 96,
                  (opening..<body.lowerBound).allSatisfy({ source[$0] == 96 }),
                  (body.upperBound..<closing).allSatisfy({ source[$0] == 96 }),
                  !escaped(opening), let mapped = source.range(body) else { return body }
            add(opening..<body.lowerBound, .marker)
            add(body, .code)
            add(body.upperBound..<closing, .marker)
            literalRanges.append(mapped.location...NSMaxRange(mapped))
            return opening..<closing
        }

        mutating func blockCode(_ node: Node, indent: Int) {
            let first = Int(cmark_node_get_start_line(node))
            guard let start = start(node), let opening = source.line(first),
                  let literal = cmark_node_get_literal(node) else { return }
            let lineCount = String(cString: literal).utf8.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
            var fenceLength: Int32 = 0
            var fenceOffset: Int32 = 0
            var fence: CChar = 0
            let fenced = cmark_node_get_fenced(node, &fenceLength, &fenceOffset, &fence) != 0
            let firstBody = first + (fenced ? 1 : 0)
            let lastBody = firstBody + lineCount - 1
            var lastCaret = opening.upperBound
            if fenced {
                add(start..<opening.upperBound, .marker)
            }
            if firstBody <= lastBody {
                for number in firstBody...lastBody {
                    guard let line = source.line(number) else { break }
                    let prefix = prefixEnd(line)
                    let lower = number == first ? start : min(prefix + indent, trim(prefix..<line.upperBound).lowerBound)
                    add(lower..<line.upperBound, .code)
                    lastCaret = line.upperBound
                }
            }
            if fenced, let candidate = source.line(lastBody + 1) {
                let body = trim(prefixEnd(candidate)..<candidate.upperBound)
                let quoted = quotePrefixes[opening.lowerBound] != nil
                if lastBody + 1 == cmark_node_get_end_line(node),
                   !quoted || quotePrefixes[candidate.lowerBound] != nil,
                   body.lowerBound - prefixEnd(candidate) >= indent,
                   body.count >= fenceLength, body.allSatisfy({ source[$0] == UInt8(bitPattern: fence) }) {
                    add(body, .marker)
                    lastCaret = candidate.upperBound
                } else if candidate.isEmpty && candidate.upperBound == source.bytes.count {
                    lastCaret = candidate.upperBound
                }
            }
            if let mapped = source.range(start..<lastCaret) {
                literalRanges.append(mapped.location...NSMaxRange(mapped))
            }
        }

        mutating func link(_ node: Node, image: Bool, labelEnd: Int?, slot: Int, precedingLiteralEnd: Int?) -> Range<Int>? {
            let child = cmark_node_first_child(node)
            let last = cmark_node_last_child(node)
            let style: EditorMarkdown.Style = image ? .imageAlt : .linkLabel
            if let range = bounds(node), !range.isEmpty {
                let opening = range.lowerBound
                if source[opening] == 60, source[range.upperBound - 1] == 62, !image {
                    add(opening..<(opening + 1), .marker)
                    if let label = source.range((opening + 1)..<(range.upperBound - 1)) {
                        spans[slot] = .init(range: label, style: style)
                    }
                    add((range.upperBound - 1)..<range.upperBound, .marker)
                    return range
                }
                let labelStart = opening + (image ? 2 : 1)
                let closingStart = labelEnd ?? labelStart
                if labelStart <= range.upperBound, source[labelStart - 1] == 91,
                   !image || source[opening] == 33, !escaped(opening),
                   labelStart <= closingStart, closingStart < range.upperBound,
                   source[closingStart] == 93, !escaped(closingStart),
                   closingStart + 1 == range.upperBound || source[closingStart + 1] == 40 || source[closingStart + 1] == 91,
                   source[range.upperBound - 1] == 93 || source[range.upperBound - 1] == 41 {
                    if image, labelStart == closingStart {
                        add(opening..<(opening + 1), .imagePlaceholder)
                        add((opening + 1)..<labelStart, .marker)
                    } else {
                        add(opening..<labelStart, .marker)
                    }
                    if labelStart < closingStart, let label = source.range(labelStart..<closingStart) {
                        spans[slot] = .init(range: label, style: style)
                    }
                    let lastLine = last.map { cmark_node_get_end_line($0) } ?? cmark_node_get_start_line(node)
                    if lastLine == cmark_node_get_end_line(node) {
                        add(closingStart..<range.upperBound, .marker)
                    } else {
                        add(closingStart..<(closingStart + 1), .marker)
                    }
                    return range
                }
            }
            guard !image, let child, child == last, cmark_node_get_type(child) == CMARK_NODE_TEXT,
                  let literal = cmark_node_get_literal(child) else { return nil }
            let bytes = Array(String(cString: literal).utf8)
            guard !bytes.isEmpty else { return nil }
            var finish = end(node)
            if finish == nil, let precedingLiteralEnd, precedingLiteralEnd + bytes.count <= source.bytes.count,
               source.bytes[precedingLiteralEnd..<(precedingLiteralEnd + bytes.count)].elementsEqual(bytes) {
                finish = precedingLiteralEnd + bytes.count
            }
            if finish == nil {
                var next = cmark_node_next(node)
                while let sibling = next, start(sibling) == nil {
                    guard cmark_node_get_type(sibling) == CMARK_NODE_TEXT else { break }
                    next = cmark_node_next(sibling)
                }
                if let next {
                    finish = start(next)
                } else if let parent = cmark_node_parent(node) {
                    finish = end(parent)
                }
            }
            guard let finish, finish >= bytes.count,
                  source.bytes[(finish - bytes.count)..<finish].elementsEqual(bytes) else { return nil }
            let raw = (finish - bytes.count)..<finish
            if let label = source.range(raw) {
                spans[slot] = .init(range: label, style: style)
            }
            return raw
        }

        mutating func table(_ node: Node) {
            guard let line = source.line(Int(cmark_node_get_start_line(node)) + 1) else { return }
            let body = trim(prefixEnd(line)..<line.upperBound)
            guard !body.isEmpty, body.allSatisfy({ [45, 58, 124].contains(source[$0]) || space(source[$0]) }) else { return }
            add(body, .marker)
        }

        mutating func tableRow(_ node: Node, header: Bool) {
            guard let start = start(node), let line = source.line(Int(cmark_node_get_start_line(node))) else { return }
            let body = trim(start..<line.upperBound)
            if header { add(body, .tableHeader) }
            for pipe in body where source[pipe] == 124 && source[pipe - 1] != 92 {
                add(pipe..<(pipe + 1), pipe == body.lowerBound || pipe == body.upperBound - 1 ? .marker : .tableDivider)
            }
        }
    }
}
