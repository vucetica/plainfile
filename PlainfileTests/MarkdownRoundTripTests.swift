import Testing
import AppKit
@testable import Plainfile

@MainActor
struct MarkdownRoundTripTests {

    private func roundTrip(_ markdown: String) -> String {
        let renderer = MarkdownRenderer(style: MarkdownStyle(), baseURL: nil)
        let attributed = renderer.render(markdown)
        return MarkdownSerializer.serialize(attributed)
    }

    @Test func headingsAndParagraphs() {
        let md = "# Title\n\nSome **bold** and *italic* text with `code`.\n\n## Second\n\nAnother paragraph.\n"
        #expect(roundTrip(md) == md)
    }

    @Test func lists() {
        let md = "- one\n- two\n    - nested\n- three\n\n1. first\n2. second\n"
        #expect(roundTrip(md) == md)
    }

    @Test func taskList() {
        let md = "- [ ] todo\n- [x] done\n"
        #expect(roundTrip(md) == md)
    }

    @Test func codeBlock() {
        let md = "```swift\nlet x = 1\nprint(x)\n```\n"
        #expect(roundTrip(md) == md)
    }

    @Test func blockQuote() {
        let md = "> quoted line\n>\n> second paragraph\n"
        #expect(roundTrip(md) == md)
    }

    @Test func table() {
        let md = "| Name | Qty |\n| --- | ---: |\n| Apple | 3 |\n| Pear | 12 |\n"
        #expect(roundTrip(md) == md)
    }

    @Test func linksImagesAndRule() {
        let md = "A [link](https://example.com) and ![alt](img.png) here.\n\n---\n\nEnd.\n"
        #expect(roundTrip(md) == md)
    }

    @Test func strikethroughAndEscapes() {
        let md = "Some ~~old~~ text and a literal \\*star\\*.\n"
        #expect(roundTrip(md) == md)
    }

    @Test func serializerStripsListMarkersTypedByAppKit() {
        // Simulate a list created by the editor: paragraph style with a text list and "\t•\t" marker.
        let style = MarkdownStyle()
        let list = NSTextList(markerFormat: .disc, options: 0)
        let p = style.listParagraphStyle(lists: [list], base: style.bodyParagraphStyle())
        var attrs = style.bodyAttributes()
        attrs[.paragraphStyle] = p
        let s = NSAttributedString(string: "\t\u{2022}\tHello\n", attributes: attrs)
        #expect(MarkdownSerializer.serialize(s) == "- Hello\n")
    }
}
