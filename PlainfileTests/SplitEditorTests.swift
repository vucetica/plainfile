import Testing
import AppKit
import SwiftUI
@testable import Plainfile

/// Hosts a whole document window in-process and checks the split editor and the
/// selection that follows between Rich Text, Table and Source panes.
///
/// SwiftUI builds and updates the editors on later run loop turns, and how long that
/// takes depends on the machine (CI runners are slower), so the tests wait for each
/// expected state instead of sleeping for a fixed time.
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
        return Host(window: window, document: document)
    }

    /// Waits until `condition` holds, for at most `timeout`.
    @discardableResult
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Waits for exactly `count` views of a type and returns them, top pane first.
    private func editors<T: NSView>(_ type: T.Type, count: Int = 1, in host: Host) async throws -> [T] {
        try await waitUntil { views(type, in: host).count == count }
        let found = views(type, in: host)
        let modes = host.layout.panes.map(\.viewMode.rawValue)
        try #require(found.count == count, "expected \(count) \(T.self), found \(found.count) with pane modes \(modes)")
        return found
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

    /// Splits the window and shows Source in the top pane, over `bottom` in the other.
    private func splitWithSourceOnTop(_ host: Host) {
        host.layout.split(document: host.document)
        host.layout.panes[0].viewMode = .source
    }

    private let markdown = "# Notes\n\nThe quick **brown** fox.\n\nSecond paragraph here.\n"
    private let csv = "name,qty,price\nApple,3,1.20\nPear,12,0.80\nPlum,7,2.10\n"

    // MARK: Splitting

    @Test func splittingAddsAPaneAndKeepsTheOriginalEditor() async throws {
        let host = try await host("hello world\n", language: LanguageRegistry.plainText, mode: .source)
        let original = try await editors(CodeTextView.self, in: host)[0]
        host.layout.split(document: host.document)
        let both = try await editors(CodeTextView.self, count: 2, in: host)
        #expect(both.contains { $0 === original })
        #expect(both.last === original, "the original editor should be the bottom pane")
    }

    @Test func removingTheSplitLeavesTheOtherPaneWorking() async throws {
        let host = try await host("hello world\n", language: LanguageRegistry.plainText, mode: .source)
        _ = try await editors(CodeTextView.self, in: host)
        host.layout.split(document: host.document)
        _ = try await editors(CodeTextView.self, count: 2, in: host)
        host.layout.removePane(host.layout.panes[1])
        let editor = try await editors(CodeTextView.self, in: host)[0]
        host.window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("Say ", replacementRange: editor.selectedRange())
        #expect(host.document.text == "Say hello world\n")
    }

    @Test func panesCanShowDifferentModes() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        splitWithSourceOnTop(host)
        _ = try await editors(CodeTextView.self, in: host)
        _ = try await editors(RichTextView.self, in: host)
    }

    // MARK: Text sync

    @Test func typingInSourceUpdatesTheRichPane() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        splitWithSourceOnTop(host)
        let source = try await editors(CodeTextView.self, in: host)[0]
        let rich = try await editors(RichTextView.self, in: host)[0]
        select("fox", in: source, of: host)
        source.insertText("cat", replacementRange: source.selectedRange())
        #expect(try await waitUntil { rich.string.contains("brown cat.") })
    }

    @Test func twoSourcePanesStayInSyncAndKeepTheirOwnSelection() async throws {
        let host = try await host("alpha beta gamma\n", language: LanguageRegistry.plainText, mode: .source)
        _ = try await editors(CodeTextView.self, in: host)
        host.layout.split(document: host.document)
        let both = try await editors(CodeTextView.self, count: 2, in: host)
        let (top, bottom) = (both[0], both[1])
        select("gamma", in: bottom, of: host)
        select("alpha", in: top, of: host)
        top.insertText("ALPHA", replacementRange: top.selectedRange())
        #expect(try await waitUntil { bottom.string == "ALPHA beta gamma\n" })
        #expect(selectedText(bottom) == "gamma")
    }

    @Test func undoAfterAnEditInTheOtherPaneKeepsTheTextConsistent() async throws {
        let host = try await host("one two\n", language: LanguageRegistry.plainText, mode: .source)
        _ = try await editors(CodeTextView.self, in: host)
        host.layout.split(document: host.document)
        let both = try await editors(CodeTextView.self, count: 2, in: host)
        let (top, bottom) = (both[0], both[1])
        select("one", in: top, of: host)
        top.insertText("1", replacementRange: top.selectedRange())
        try await waitUntil { bottom.string == "1 two\n" }
        select("two", in: bottom, of: host)
        bottom.insertText("2", replacementRange: bottom.selectedRange())
        try await waitUntil { top.string == "1 2\n" }
        #expect(host.document.text == "1 2\n")
        try #require(bottom.undoManager).undo()
        #expect(try await waitUntil { host.document.text == "1 two\n" && top.string == "1 two\n" })
        #expect(bottom.string == host.document.text)
    }

    @Test func undoInSourceUpdatesTheDocument() async throws {
        let host = try await host("one two\n", language: LanguageRegistry.plainText, mode: .source)
        let editor = try await editors(CodeTextView.self, in: host)[0]
        select("two", in: editor, of: host)
        editor.insertText("2", replacementRange: editor.selectedRange())
        #expect(host.document.text == "one 2\n")
        // Let the typing undo group close, the way it does after a key press.
        try await Task.sleep(for: .milliseconds(50))
        try #require(editor.undoManager).undo()
        #expect(host.document.text == "one two\n")
    }

    @Test func undoInRichTextUpdatesTheDocument() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        let editor = try await editors(RichTextView.self, in: host)[0]
        select("fox", in: editor, of: host)
        editor.insertText("dog", replacementRange: editor.selectedRange())
        host.document.flushPendingEdits()
        #expect(host.document.text.contains("dog"))
        try await Task.sleep(for: .milliseconds(50))
        try #require(editor.undoManager).undo()
        host.document.flushPendingEdits()
        #expect(host.document.text == markdown)
    }

    // MARK: Linked selection

    @Test func selectingInRichSelectsTheSameTextInSource() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        splitWithSourceOnTop(host)
        let source = try await editors(CodeTextView.self, in: host)[0]
        let rich = try await editors(RichTextView.self, in: host)[0]
        select("brown", in: rich, of: host)
        #expect(try await waitUntil { selectedText(source) == "brown" }, "source selection: \(selectedText(source))")
    }

    @Test func selectingInSourceSelectsTheSameTextInRich() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        splitWithSourceOnTop(host)
        let source = try await editors(CodeTextView.self, in: host)[0]
        let rich = try await editors(RichTextView.self, in: host)[0]
        select("**brown** fox", in: source, of: host)
        #expect(try await waitUntil { selectedText(rich) == "brown fox" }, "rich selection: \(selectedText(rich))")
    }

    @Test func selectingRowsInTheTableSelectsTheirLinesInSource() async throws {
        let host = try await host(csv, language: LanguageRegistry.csv, mode: .table)
        splitWithSourceOnTop(host)
        let source = try await editors(CodeTextView.self, in: host)[0]
        let grid = try await editors(GridTableView.self, in: host)[0]
        host.window.makeFirstResponder(grid)
        grid.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(try await waitUntil { selectedText(source) == "Pear,12,0.80" }, "source selection: \(selectedText(source))")
        grid.selectRowIndexes(IndexSet([1, 2]), byExtendingSelection: false)
        #expect(try await waitUntil { selectedText(source) == "Pear,12,0.80\nPlum,7,2.10" }, "source selection: \(selectedText(source))")
    }

    @Test func selectingLinesInSourceSelectsTheirRowsInTheTable() async throws {
        let host = try await host(csv, language: LanguageRegistry.csv, mode: .table)
        splitWithSourceOnTop(host)
        let source = try await editors(CodeTextView.self, in: host)[0]
        let grid = try await editors(GridTableView.self, in: host)[0]
        select("Apple,3", in: source, of: host)
        #expect(try await waitUntil { grid.selectedRowIndexes == IndexSet(integer: 0) })
        select("12,0.80\nPlum", in: source, of: host)
        #expect(try await waitUntil { grid.selectedRowIndexes == IndexSet([1, 2]) })
    }

    @Test func switchingModeKeepsTheSelection() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        let rich = try await editors(RichTextView.self, in: host)[0]
        select("Second", in: rich, of: host)
        host.document.viewMode = .source
        let source = try await editors(CodeTextView.self, in: host)[0]
        #expect(try await waitUntil { selectedText(source) == "Second" }, "source selection: \(selectedText(source))")
        select("quick", in: source, of: host)
        host.document.viewMode = .rich
        let richAgain = try await editors(RichTextView.self, in: host)[0]
        #expect(try await waitUntil { selectedText(richAgain) == "quick" }, "rich selection: \(selectedText(richAgain))")
    }

    @Test func switchingFromTableToSourceKeepsTheSelectedRows() async throws {
        let host = try await host(csv, language: LanguageRegistry.csv, mode: .table)
        let grid = try await editors(GridTableView.self, in: host)[0]
        host.window.makeFirstResponder(grid)
        grid.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        host.document.viewMode = .source
        let source = try await editors(CodeTextView.self, in: host)[0]
        #expect(try await waitUntil { selectedText(source) == "Plum,7,2.10" }, "source selection: \(selectedText(source))")
    }

    @Test func richEditsAreSavedBeforeTheOtherPaneTakesFocus() async throws {
        let host = try await host(markdown, language: LanguageRegistry.markdown, mode: .rich)
        splitWithSourceOnTop(host)
        let source = try await editors(CodeTextView.self, in: host)[0]
        let rich = try await editors(RichTextView.self, in: host)[0]
        select("fox", in: rich, of: host)
        rich.insertText("dog", replacementRange: rich.selectedRange())
        // Focus moves to the source pane before the rich pane's own sync runs.
        host.window.makeFirstResponder(source)
        #expect(host.document.text.contains("brown** dog."))
        #expect(try await waitUntil { source.string.contains("brown** dog.") })
    }
}
