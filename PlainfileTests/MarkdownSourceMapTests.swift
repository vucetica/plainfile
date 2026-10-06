import Testing
import AppKit
@testable import Plainfile

/// Checks that a selection moves between the rendered rich text and the Markdown source.
@MainActor
struct MarkdownSourceMapTests {

    private func render(_ markdown: String) -> (rendered: NSString, map: MarkdownSourceMap) {
        let result = MarkdownRenderer(style: MarkdownStyle(), baseURL: nil).renderMapped(markdown)
        return (result.text.string as NSString, result.map)
    }

    /// Selects `word` in the rendered text and returns the source text it maps to.
    private func sourceText(selecting word: String, in markdown: String) -> String {
        let (rendered, map) = render(markdown)
        let range = rendered.range(of: word)
        #expect(range.location != NSNotFound, "\(word) is not in the rendered text")
        return (markdown as NSString).substring(with: map.sourceRange(forRendered: range))
    }

    /// Selects `snippet` in the source and returns the rendered text it maps to.
    private func renderedText(selecting snippet: String, in markdown: String) -> String {
        let (rendered, map) = render(markdown)
        let range = (markdown as NSString).range(of: snippet)
        #expect(range.location != NSNotFound)
        return rendered.substring(with: map.renderedRange(forSource: range))
    }

    @Test func renderingWithAMapLeavesNoAttributeBehind() {
        let result = MarkdownRenderer(style: MarkdownStyle(), baseURL: nil).renderMapped("# Title\n\nSome *text*.\n")
        var found = false
        result.text.enumerateAttribute(.pfSourceRange, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in
            if value != nil { found = true }
        }
        #expect(!found)
        #expect(!result.map.entries.isEmpty)
    }

    @Test func plainWordsMapExactly() {
        let md = "# Title\n\nThe quick brown fox.\n"
        #expect(sourceText(selecting: "quick brown", in: md) == "quick brown")
        #expect(sourceText(selecting: "Title", in: md) == "Title")
        #expect(renderedText(selecting: "brown fox", in: md) == "brown fox")
    }

    @Test func emphasisAndLinksMapToTheirText() {
        let md = "Some **bold** and *italic* and [a link](https://example.com) here.\n"
        #expect(sourceText(selecting: "bold", in: md) == "bold")
        #expect(sourceText(selecting: "italic", in: md) == "italic")
        #expect(sourceText(selecting: "a link", in: md) == "a link")
        #expect(renderedText(selecting: "**bold**", in: md) == "bold")
        #expect(renderedText(selecting: "[a link](https://example.com)", in: md) == "a link")
    }

    @Test func headingMarkupMapsToTheHeadingText() {
        let md = "## Second level\n\nBody\n"
        #expect(renderedText(selecting: "## Second level", in: md) == "Second level")
    }

    @Test func inlineCodeMapsWithoutBackticks() {
        let md = "Run `make all` now.\n"
        #expect(sourceText(selecting: "make all", in: md) == "make all")
    }

    @Test func listItemsMapToTheirText() {
        let md = "- one\n- two\n- three\n"
        #expect(sourceText(selecting: "two", in: md) == "two")
        #expect(renderedText(selecting: "three", in: md) == "three")
    }

    @Test func codeBlockBodyMapsLineForLine() {
        let md = "Intro\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nAfter\n"
        #expect(sourceText(selecting: "let b = 2", in: md) == "let b = 2")
        #expect(renderedText(selecting: "let a = 1", in: md) == "let a = 1")
    }

    @Test func tableCellsMapToTheirText() {
        let md = "| Name | Age |\n| --- | --- |\n| Ann | 31 |\n"
        #expect(sourceText(selecting: "Ann", in: md) == "Ann")
        #expect(renderedText(selecting: "31", in: md) == "31")
    }

    @Test func multiByteTextMapsInUTF16() {
        let md = "Café 👋 naïve **émoji** end\n"
        #expect(sourceText(selecting: "émoji", in: md) == "émoji")
        #expect(sourceText(selecting: "naïve", in: md) == "naïve")
        #expect(renderedText(selecting: "end", in: md) == "end")
    }

    @Test func selectionAcrossParagraphsCoversTheSource() {
        let md = "First paragraph.\n\nSecond paragraph.\n"
        let source = sourceText(selecting: "paragraph.\nSecond", in: md)
        #expect(source == "paragraph.\n\nSecond")
    }

    @Test func caretMapsBothWays() {
        let md = "Hello world\n"
        let (rendered, map) = render(md)
        let caret = rendered.range(of: "world").location
        #expect(map.sourceRange(forRendered: NSRange(location: caret, length: 0)) == NSRange(location: 6, length: 0))
        #expect(map.renderedRange(forSource: NSRange(location: 6, length: 0)) == NSRange(location: caret, length: 0))
    }

    @Test func alignmentMapsAroundAnEdit() {
        let a = "Hello brave world" as NSString
        let b = "Hello new world" as NSString
        let alignment = TextAlignment(from: a, to: b)
        #expect(alignment.map(2) == 2)
        #expect(alignment.map(a.range(of: "world").location) == b.range(of: "world").location)
        #expect(alignment.inverted.map(b.range(of: "world").location) == a.range(of: "world").location)
    }
}
