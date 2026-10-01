import Testing
import AppKit
@testable import Plainfile

/// Exercises the WYSIWYG editor's AppKit behaviour in-process.
@MainActor
struct RichTextViewTests {

    private func makeView(_ markdown: String) -> (RichTextView, NSWindow) {
        let tv = RichTextView.make()
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = tv
        window.makeFirstResponder(tv)
        let renderer = MarkdownRenderer(style: MarkdownStyle(), baseURL: nil)
        tv.textStorage!.setAttributedString(renderer.render(markdown))
        return (tv, window)
    }

    private func markdown(_ tv: RichTextView) -> String {
        MarkdownSerializer.serialize(tv.textStorage!)
    }

    @Test func returnContinuesList() {
        let (tv, _) = makeView("- one\n- two\n")
        let end = (tv.string as NSString).range(of: "two").upperBound
        tv.setSelectedRange(NSRange(location: end, length: 0))
        tv.insertNewline(nil)
        tv.insertText("three", replacementRange: tv.selectedRange())
        #expect(markdown(tv) == "- one\n- two\n- three\n")
    }

    @Test func returnAfterHeadingCreatesBodyParagraph() {
        let (tv, _) = makeView("# Title\n")
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        tv.insertNewline(nil)
        tv.insertText("body", replacementRange: tv.selectedRange())
        #expect(markdown(tv) == "# Title\n\nbody\n")
    }

    @Test func inlineAndParagraphToggles() {
        let (tv, _) = makeView("hello world\n")
        tv.setSelectedRange(NSRange(location: 0, length: 5))
        tv.toggleBold()
        #expect(markdown(tv) == "**hello** world\n")

        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.toggleParagraphKind(.bulletList)
        #expect(markdown(tv) == "- **hello** world\n")
        #expect(tv.selectedRange().location == 3, "caret stays in the converted paragraph")

        tv.toggleParagraphKind(.numberedList)
        #expect(markdown(tv) == "1. **hello** world\n")

        tv.toggleParagraphKind(.heading(2))
        #expect(markdown(tv) == "## hello world\n")

        tv.toggleParagraphKind(.codeBlock)
        #expect(markdown(tv) == "```\nhello world\n```\n")

        tv.toggleParagraphKind(.body)
        #expect(markdown(tv) == "hello world\n")

        tv.toggleParagraphKind(.blockQuote)
        #expect(markdown(tv) == "> hello world\n")
    }

    @Test func strikethroughAndInlineCode() {
        let (tv, _) = makeView("hello world\n")
        tv.setSelectedRange(NSRange(location: 6, length: 5))
        tv.toggleStrikethrough()
        #expect(markdown(tv) == "hello ~~world~~\n")
        tv.toggleStrikethrough()
        tv.toggleInlineCode()
        #expect(markdown(tv) == "hello `world`\n")
    }

    @Test func insertTableAndRule() {
        let (tv, _) = makeView("intro\n")
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        tv.insertTable(rows: 2, columns: 2)
        tv.insertHorizontalRule()
        let out = markdown(tv)
        #expect(out.hasPrefix("intro\n\n| Header | Header |\n| --- | --- |\n"))
        #expect(out.hasSuffix("---\n"))
    }
}

@MainActor
struct CenteredContainerTests {
    @Test func columnIsCenteredAndCapped() {
        let wide = CenteredTextContainerView.columnFrame(availableWidth: 1200, maxContentWidth: 760, margin: 24)
        #expect(wide.width == 760)
        #expect(wide.x == 220)
        let narrow = CenteredTextContainerView.columnFrame(availableWidth: 500, maxContentWidth: 760, margin: 24)
        #expect(narrow.width == 452)
        #expect(narrow.x == 24)
    }

    @Test func containerLaysOutTextViewAndTracksHeight() {
        let tv = RichTextView.make()
        let container = CenteredTextContainerView(textView: tv)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 400))
        scroll.documentView = container
        container.frame = NSRect(x: 0, y: 0, width: 1000, height: 400)
        container.layoutSubtreeIfNeeded()
        #expect(tv.frame.origin.x == 120)
        #expect(tv.frame.width == 760)
        #expect(tv.frame.origin.y == 28)
        #expect(tv.textContainerInset == .zero)
        tv.textStorage!.setAttributedString(MarkdownRenderer(style: MarkdownStyle(), baseURL: nil).render(String(repeating: "paragraph text\n\n", count: 60)))
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        tv.sizeToFit()
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        #expect(container.frame.height >= tv.frame.maxY + 28, "container=\(container.frame) tv=\(tv.frame) clip=\(scroll.contentSize)")
        #expect(container.frame.height > 400)
    }
}
