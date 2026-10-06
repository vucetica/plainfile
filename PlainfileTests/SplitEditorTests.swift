import Testing
import AppKit
import SwiftUI
@testable import Plainfile

/// Hosts a whole document window in-process and checks the split editor and the
/// selection that follows between Rich Text, Table and Source panes.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SplitEditorTests {

    private struct Host {
        let window: NSWindow
        let document: PlainDocument
        var layout: EditorLayout { document.layout }
    }

    private func host(_ text: String, language: Language, mode: ViewMode) async throws -> Host {
        let document = PlainDocument()
        document.text = text
        document.language = language
        document.viewMode = mode
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let hosting = NSHostingView(rootView: DocumentView(document: document, fileURL: nil))
        // As the content view, the hosting view would resize the window to its own size.
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        try await settle()
        return Host(window: window, document: document)
    }

    private func settle(_ milliseconds: Int = 80) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// Views of a type, top pane first.
    private func views<T: NSView>(_ type: T.Type, in host: Host) -> [T] {
        var found: [T] = []
        func walk(_ view: NSView) {
            if let match = view as? T { found.append(match) }
            view.subviews.forEach(walk)
        }
        if let root = host.window.contentView { walk(root) }
        return found.sorted {
            $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY
        }
    }

    private func selectedText(_ textView: NSTextView) -> String {
        (textView.string as NSString).substring(with: textView.selectedRange())
    }

    private func select(_ word: String, in textView: NSTextView, of host: Host) {
        host.window.makeFirstResponder(textView)
        let range = (textView.string as NSString).range(of: word)
        #expect(range.location != NSNotFound, "\(word) is not in the text")
        textView.setSelectedRange(range)
    }

    private let markdown = "# Notes\n\nThe quick **brown** fox.\n\nSecond paragraph here.\n"
    private let csv = "name,qty,price\nApple,3,1.20\nPear,12,0.80\nPlum,7,2.10\n"

    // MARK: Splitting

    @Test func splittingAddsAPaneAndKeepsTheOriginalEditor() async throws {
        let host = try await host("hello world\n", language: LanguageRegistry.plainText, mode: .source)
        let original = try #require(views(CodeTextView.self, in: host).first)
        host.layout.split(document: host.document)
        try await settle()
        let editors = views(CodeTextView.self, in: host)
        #expect(editors.count == 2)
        #expect(editors.contains { $0 === original })
        #expect(editors.last === original, "the original editor should be the bottom pane")
    }

    @Test func removingTheSplitLeavesTheOtherPaneWorking() async throws {
        let host = try await host("hello world\n", language: LanguageRegistry.plainText, mode: .source)
        host.layout.split(document: host.document)
        try await settle()
        host.layout.removePane(host.layout.panes[1])
        try await settle()
        let editors = views(CodeTextView.self, in: host)
        #expect(editors.count == 1)
        let editor = try #require(editors.first)
        host.window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("Say ", replacementRange: editor.selectedRange())
        #expect(host.document.text == "Say hello world\n")
    }

    @Test func panesCanShowDifferentModes() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
        try await settle()
        #expect(views(CodeTextView.self, in: host).count == 1)
        #expect(views(RichTextView.self, in: host).count == 1)
    }

    // MARK: Text sync

    @Test func typingInSourceUpdatesTheRichPane() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        let rich = try #require(views(RichTextView.self, in: host).first)
        select("fox", in: source, of: host)
        source.insertText("cat", replacementRange: source.selectedRange())
        try await settle(400)
        #expect(rich.string.contains("brown cat."))
    }

    @Test func twoSourcePanesStayInSyncAndKeepTheirOwnSelection() async throws {
        let host = try await host("alpha beta gamma\n", language: LanguageRegistry.plainText, mode: .source)
        host.layout.split(document: host.document)
        try await settle()
        let editors = views(CodeTextView.self, in: host)
        try #require(editors.count == 2)
        let (top, bottom) = (editors[0], editors[1])
        select("gamma", in: bottom, of: host)
        select("alpha", in: top, of: host)
        top.insertText("ALPHA", replacementRange: top.selectedRange())
        try await settle()
        #expect(bottom.string == "ALPHA beta gamma\n")
        #expect(selectedText(bottom) == "gamma")
    }

    @Test func undoAfterAnEditInTheOtherPaneKeepsTheTextConsistent() async throws {
        let host = try await host("one two\n", language: LanguageRegistry.plainText, mode: .source)
        host.layout.split(document: host.document)
        try await settle()
        let editors = views(CodeTextView.self, in: host)
        try #require(editors.count == 2)
        let (top, bottom) = (editors[0], editors[1])
        select("one", in: top, of: host)
        top.insertText("1", replacementRange: top.selectedRange())
        try await settle()
        select("two", in: bottom, of: host)
        bottom.insertText("2", replacementRange: bottom.selectedRange())
        try await settle()
        #expect(host.document.text == "1 2\n")
        let undoManager = try #require(bottom.undoManager)
        undoManager.undo()
        try await settle()
        #expect(host.document.text == "1 two\n")
        #expect(top.string == host.document.text)
        #expect(bottom.string == host.document.text)
    }

    @Test func undoInSourceUpdatesTheDocument() async throws {
        let host = try await host("one two\n", language: LanguageRegistry.plainText, mode: .source)
        let editor = try #require(views(CodeTextView.self, in: host).first)
        select("two", in: editor, of: host)
        editor.insertText("2", replacementRange: editor.selectedRange())
        try await settle()
        #expect(host.document.text == "one 2\n")
        try #require(editor.undoManager).undo()
        try await settle()
        #expect(host.document.text == "one two\n")
    }

    @Test func undoInRichTextUpdatesTheDocument() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        let editor = try #require(views(RichTextView.self, in: host).first)
        select("fox", in: editor, of: host)
        editor.insertText("dog", replacementRange: editor.selectedRange())
        host.document.flushPendingEdits()
        #expect(host.document.text.contains("dog"))
        try await settle()
        try #require(editor.undoManager).undo()
        host.document.flushPendingEdits()
        #expect(host.document.text == markdown)
    }

    // MARK: Linked selection

    @Test func selectingInRichSelectsTheSameTextInSource() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        let rich = try #require(views(RichTextView.self, in: host).first)
        select("brown", in: rich, of: host)
        try await settle()
        #expect(selectedText(source) == "brown")
    }

    @Test func selectingInSourceSelectsTheSameTextInRich() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        let rich = try #require(views(RichTextView.self, in: host).first)
        select("**brown** fox", in: source, of: host)
        try await settle()
        #expect(selectedText(rich) == "brown fox")
    }

    @Test func selectingRowsInTheTableSelectsTheirLinesInSource() async throws {
        let host = try await host(csv, language: LanguageRegistry.csv, mode: .table)
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        let grid = try #require(views(GridTableView.self, in: host).first)
        host.window.makeFirstResponder(grid)
        grid.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try await settle()
        #expect(selectedText(source) == "Pear,12,0.80")
        grid.selectRowIndexes(IndexSet([1, 2]), byExtendingSelection: false)
        try await settle()
        #expect(selectedText(source) == "Pear,12,0.80\nPlum,7,2.10")
    }

    @Test func selectingLinesInSourceSelectsTheirRowsInTheTable() async throws {
        let host = try await host(csv, language: LanguageRegistry.csv, mode: .table)
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        let grid = try #require(views(GridTableView.self, in: host).first)
        select("Apple,3", in: source, of: host)
        try await settle()
        #expect(grid.selectedRowIndexes == IndexSet(integer: 0))
        select("12,0.80\nPlum", in: source, of: host)
        try await settle()
        #expect(grid.selectedRowIndexes == IndexSet([1, 2]))
    }

    @Test func switchingModeKeepsTheSelection() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        let rich = try #require(views(RichTextView.self, in: host).first)
        select("Second", in: rich, of: host)
        host.document.viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        #expect(selectedText(source) == "Second")
        select("quick", in: source, of: host)
        host.document.viewMode = .rich
        try await settle()
        let richAgain = try #require(views(RichTextView.self, in: host).first)
        #expect(selectedText(richAgain) == "quick")
    }

    @Test func switchingFromTableToSourceKeepsTheSelectedRows() async throws {
        let host = try await host(csv, language: LanguageRegistry.csv, mode: .table)
        let grid = try #require(views(GridTableView.self, in: host).first)
        host.window.makeFirstResponder(grid)
        grid.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        host.document.viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        #expect(selectedText(source) == "Plum,7,2.10")
    }

    @Test func richEditsAreSavedBeforeTheOtherPaneTakesFocus() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
        try await settle()
        let source = try #require(views(CodeTextView.self, in: host).first)
        let rich = try #require(views(RichTextView.self, in: host).first)
        select("fox", in: rich, of: host)
        rich.insertText("dog", replacementRange: rich.selectedRange())
        // Focus moves to the source pane before the rich pane's own sync runs.
        host.window.makeFirstResponder(source)
        #expect(host.document.text.contains("brown** dog."))
        try await settle()
        #expect(source.string.contains("brown** dog."))
    }
}
