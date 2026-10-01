import Testing
import AppKit
@testable import Plainfile

@MainActor
struct SyntaxHighlighterTests {

    private func colors(_ storage: NSTextStorage) -> [String] {
        var out: [String] = []
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length), options: []) { v, r, _ in
            out.append("\(r.location)-\(r.length):\((v as? NSColor)?.description ?? "nil")")
        }
        return out
    }

    @Test func incrementalHighlightingMatchesFullRehighlight() {
        let tv = CodeTextView(usingTextLayoutManager: true)
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let hl = SyntaxHighlighter(textStorage: tv.textStorage!, language: LanguageRegistry.csharp, theme: EditorTheme(), font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        tv.string = "int a = 1; /* start\nstill comment\nend */ string s = \"x\";\n// tail\n"
        hl.rehighlightAll()
        #expect(hl.lineCount == 5)

        // Removing the comment opener must re-highlight the following lines.
        tv.insertText("", replacementRange: NSRange(location: 11, length: 2))
        let incremental = colors(tv.textStorage!)
        hl.rehighlightAll()
        #expect(incremental == colors(tv.textStorage!))

        // Putting it back must restore the comment colouring across lines.
        tv.insertText("/*", replacementRange: NSRange(location: 11, length: 0))
        let incremental2 = colors(tv.textStorage!)
        hl.rehighlightAll()
        #expect(incremental2 == colors(tv.textStorage!))

        // Inserting and deleting lines keeps the line index in sync.
        tv.insertText("\n\n", replacementRange: NSRange(location: 0, length: 0))
        #expect(hl.lineCount == 7)
        #expect(hl.lineIndex(for: 2) == 2)
        tv.insertText("", replacementRange: NSRange(location: 0, length: 2))
        #expect(hl.lineCount == 5)
    }

    @Test func languageSwitchRehighlights() {
        let tv = CodeTextView(usingTextLayoutManager: true)
        let hl = SyntaxHighlighter(textStorage: tv.textStorage!, language: LanguageRegistry.plainText, theme: EditorTheme(), font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        tv.string = "# comment\nx = 1\n"
        hl.rehighlightAll()
        let plain = colors(tv.textStorage!)
        hl.language = LanguageRegistry.python
        let python = colors(tv.textStorage!)
        #expect(plain != python)
        #expect(python.count > plain.count)
    }
}

@MainActor
struct CodeEditorCaretTests {
    private func makeEditor(_ language: Language, text: String) -> (CodeTextView, SyntaxHighlighter) {
        let tv = CodeTextView(usingTextLayoutManager: true)
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: tv.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = tv
        window.makeFirstResponder(tv)
        let hl = SyntaxHighlighter(textStorage: tv.textStorage!, language: language, theme: EditorTheme(), font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        tv.string = text
        hl.rehighlightAll()
        return (tv, hl)
    }

    @Test(arguments: [LanguageRegistry.markdown, LanguageRegistry.plainText, LanguageRegistry.csharp])
    func typingMidLineKeepsCaret(language: Language) {
        let (tv, _) = makeEditor(language, text: "first line here\nsecond line\nthird\n")
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        tv.insertText("X", replacementRange: tv.selectedRange())
        #expect(tv.selectedRange() == NSRange(location: 7, length: 0))
        tv.insertText("Y", replacementRange: tv.selectedRange())
        #expect(tv.selectedRange() == NSRange(location: 8, length: 0))
        #expect(tv.string.hasPrefix("first XYline"))
        tv.deleteBackward(nil)
        #expect(tv.selectedRange() == NSRange(location: 7, length: 0))
    }
}
