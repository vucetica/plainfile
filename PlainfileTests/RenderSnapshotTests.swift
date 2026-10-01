import Testing
import AppKit
@testable import Plainfile

/// Renders the sample document off-screen and writes a PNG into the app container's
/// temporary folder so the rendering can be inspected without screen access.
@MainActor
struct RenderSnapshotTests {
    @Test func renderSampleToImage() throws {
        let markdown = """
        # Plainfile Sample

        This document shows **bold**, *italic*, ~~strike~~ and `inline code` text with a [link](https://example.com).

        ## Lists

        - First item
        - Second item
            - Nested item
        - Third item

        1. Step one
        2. Step two

        - [ ] Open task
        - [x] Done task

        ## Table

        | Name | Qty | Price |
        | --- | ---: | ---: |
        | Apple | 3 | 1.20 |
        | Pear | 12 | 0.80 |

        > A block quote with some wise words.

        ```swift
        let greeting = "Hello, world"
        print(greeting)
        ```

        ---

        Final paragraph.
        """
        let tv = RichTextView.make()
        let container = CenteredTextContainerView(textView: tv)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 1100))
        scroll.documentView = container
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = scroll
        container.frame = scroll.bounds
        tv.textStorage!.setAttributedString(MarkdownRenderer(style: MarkdownStyle(), baseURL: nil).render(markdown))
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        let rep = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("render-snapshot.png")
        try data.write(to: url)
        #expect(data.count > 1000)
    }
}
