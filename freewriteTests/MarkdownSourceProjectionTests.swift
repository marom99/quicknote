import Foundation
import Testing
@testable import freewrite

struct MarkdownSourceProjectionTests {
    @Test func unicodeAndNestedEmphasisUseOriginalUTF16Coordinates() {
        let source = "👩🏽‍💻\r\n## **bold _café_** ***both*** ~~日記~~ ##"
        let spans = MarkdownSourceProjection.spans(in: source)
        #expect(spans.contains(.init(range: (source as NSString).range(of: "café"), style: .boldItalic)))
        #expect(matches(.boldItalic, in: source) == ["café", "both"])
        #expect(matches(.strike, in: source) == ["日記"])
        #expect(matches(.heading(2), in: source).count == 1)
        #expect(visibleSource(source) == "👩🏽‍💻\r\nbold café both 日記")
    }

    @Test func setextNestedListsQuotesAndRulesKeepReplacementGlyphsOneUnitWide() {
        let source = "#Literal\n---\n\n> - [x] first\n>   - [ ] second\n>     1. third\n\n- bullet\n\n- - -"
        #expect(matches(.heading(2), in: source) == ["#Literal"])
        #expect(matches(.listMarker, in: source) == ["-", "-", "1.", "-"])
        #expect(matches(.checkedTask, in: source) == ["["])
        #expect(matches(.uncheckedTask, in: source) == ["["])
        #expect(matches(.bullet, in: source) == ["-"])
        #expect(matches(.rule, in: source) == ["-"])
        #expect(matches(.quote, in: source).count == 1)
        #expect(visibleSource(source).contains("1. third"))
    }

    @Test func linksProjectLabelsWithoutTouchingTheDestinationOrSource() {
        let source = """
        [自分](https://example.com "title") [`code`][ref] ![alt *text*](image.png)

        <https://example.com> https://example.com www.example.com me@example.com

        [ref]: /target
        """
        #expect(matches(.linkLabel, in: source) == ["自分", "`code`", "https://example.com", "https://example.com", "www.example.com", "me@example.com"])
        #expect(matches(.imageAlt, in: source) == ["alt *text*"])
        #expect(matches(.code, in: source) == ["code"])
        #expect(visibleSource(source).hasPrefix("自分 code alt text"))
        #expect(!visibleSource(source).contains("[ref]: /target"))
    }

    @Test func referenceDefinitionsAndImagesStayInert() {
        let source = """
        [Label][ref] ![](https://example.com/image.png)

        [ref]: https://example.com

        ```
        [literal]: /code
        ```

        <script>
        [literal]: /html
        </script>

        [incomplete]:
        """
        let visible = visibleSource(source)
        #expect(matches(.linkLabel, in: source) == ["Label"])
        #expect(matches(.imagePlaceholder, in: source) == ["!"])
        #expect(!visible.contains("[ref]: https://example.com"))
        #expect(!visible.contains("image.png"))
        #expect(visible.contains("[literal]: /code"))
        #expect(visible.contains("<script>\n[literal]: /html\n</script>"))
        #expect(visible.contains("[incomplete]:"))
    }

    @Test func bareEmailLinksCanAppearInsideTextWithNoParserCoordinates() {
        let source = "Mail me@example.com or you@example.net today.\nThen write."
        #expect(matches(.linkLabel, in: source) == ["me@example.com", "you@example.net"])
    }

    @Test func fencesAndIndentedBlocksDoNotProjectLiteralMarkdown() {
        let source = """
        > ````swift
        > **literal**
        > ```
        > ````
        > Ordinary **bold**

            indented *literal*

        ~~~
        - unfinished
        """
        #expect(matches(.code, in: source) == ["**literal**", "```", "indented *literal*", "- unfinished"])
        #expect(matches(.bold, in: source) == ["bold"])
        #expect(matches(.bullet, in: source).isEmpty)
        #expect(MarkdownSourceProjection.isLiteral(at: source.utf16.count, in: source))
        #expect(MarkdownSourceProjection.isLiteral(at: 4, in: "```\n"))
        #expect(!MarkdownSourceProjection.isLiteral(at: 8, in: "```\n```\n"))
        #expect(MarkdownSourceProjection.isLiteral(at: 3, in: "a `x`"))
        #expect(!MarkdownSourceProjection.isLiteral(at: 5, in: "a `x`"))
    }

    @Test func tablesKeepCellTextAndLiteralEscapedPipes() {
        let source = "| head \\| pipe | **title** |\n| :--- | ---: |\n| 1 | `2` |\n| a\\\\|b | c |"
        #expect(matches(.tableHeader, in: source) == ["| head \\| pipe | **title** |"])
        #expect(matches(.tableDivider, in: source) == ["|", "|", "|"])
        #expect(matches(.bold, in: source) == ["title"])
        #expect(matches(.code, in: source) == ["2"])
        #expect(visibleSource(source) == " head \\| pipe | title \n\n 1 | 2 \n a\\\\|b | c ")
    }

    @Test func unmatchedAndEscapedCharactersRemainVisible() {
        let source = #"\*escaped* ***strong** *unfinished [not a link](broken"#
        #expect(visibleSource(source) == #"\*escaped* *strong *unfinished [not a link](broken"#)
        #expect(matches(.bold, in: source) == ["strong"])
    }

    @Test func escapeBackslashHidesOnlyForValidatedTextPunctuation() {
        let source = """
        \\- literal dash and \\! punctuation

        `\\- code` and \\q literal backslash

        <span title="\\-">inline</span>
        """
        #expect(matches(.bullet, in: source).isEmpty)
        #expect(visibleSource("\\- ") == "- ")
        #expect(visibleSource(source) == """
        - literal dash and ! punctuation

        \\- code and \\q literal backslash

        <span title="\\-">inline</span>
        """)
    }

    @Test func adjacentSetextUnderlineAndRuleAreDistinct() {
        let source = "Heading\n---\n---"
        #expect(matches(.heading(2), in: source) == ["Heading"])
        #expect(matches(.rule, in: source) == ["-"])
        #expect(visibleSource(source) == "Heading\n\n-")
    }

    private func matches(_ style: EditorMarkdown.Style, in source: String) -> [String] {
        MarkdownSourceProjection.spans(in: source).filter { $0.style == style }
            .map { (source as NSString).substring(with: $0.range) }
    }

    private func visibleSource(_ source: String) -> String {
        var hidden = IndexSet()
        for span in MarkdownSourceProjection.spans(in: source) where span.style == .marker {
            hidden.insert(integersIn: span.range.location..<NSMaxRange(span.range))
        }
        return String(decoding: source.utf16.enumerated().compactMap { hidden.contains($0.offset) ? nil : $0.element }, as: UTF16.self)
    }
}
