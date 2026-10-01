import SwiftUI
import AppKit

/// WYSIWYG Markdown editor. Edits are serialized back into `document.text`.
struct RichMarkdownEditorView: NSViewRepresentable {
    @ObservedObject var document: PlainDocument
    var fileURL: URL?
    var settings: EditorSettings

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = RichTextView.make()
        textView.delegate = context.coordinator
        textView.backgroundColor = .textBackgroundColor
        let container = CenteredTextContainerView(textView: textView)
        container.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        scrollView.documentView = container
        context.coordinator.textView = textView
        context.coordinator.apply(settings: settings, to: textView)
        context.coordinator.load(fileURL: fileURL)
        context.coordinator.installHandlers()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }
        coordinator.document = document
        coordinator.fileURL = fileURL
        coordinator.undoManager = context.environment.undoManager
        coordinator.apply(settings: settings, to: textView)
        if document.textVersion != coordinator.lastPushedVersion {
            coordinator.load(fileURL: fileURL)
        }
        coordinator.installHandlers()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
        coordinator.uninstallHandlers()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: PlainDocument
        var fileURL: URL?
        weak var textView: RichTextView?
        var undoManager: UndoManager?
        var lastPushedVersion = 0
        private var appliedSettings: EditorSettings?
        private var syncTask: Task<Void, Never>?
        private var dirty = false
        private var isLoading = false

        init(document: PlainDocument) {
            self.document = document
        }

        func apply(settings: EditorSettings, to textView: RichTextView) {
            guard settings != appliedSettings else { return }
            let previous = appliedSettings
            appliedSettings = settings
            (textView.superview as? CenteredTextContainerView)?.maxContentWidth = CGFloat(settings.markdownMaxWidth)
            var style = MarkdownStyle()
            style.baseSize = CGFloat(settings.markdownFontSize)
            style.maxWidth = CGFloat(settings.markdownMaxWidth)
            textView.style = style
            if let previous, previous.markdownFontSize != settings.markdownFontSize || previous.markdownMaxWidth != settings.markdownMaxWidth {
                // Re-render with the new base size, preserving pending edits. Deferred
                // because this runs inside a SwiftUI view update.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.flush()
                    self.load(fileURL: self.fileURL)
                }
            }
        }

        func load(fileURL: URL?) {
            guard let textView, let storage = textView.textStorage else { return }
            isLoading = true
            let renderer = MarkdownRenderer(style: textView.style, baseURL: fileURL)
            let rendered = renderer.render(document.text)
            let selection = textView.selectedRange()
            storage.beginEditing()
            storage.setAttributedString(rendered)
            storage.endEditing()
            let loc = min(selection.location, storage.length)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
            textView.typingAttributes = loc < storage.length ? storage.attributes(at: loc, effectiveRange: nil) : textView.style.bodyAttributes()
            lastPushedVersion = document.textVersion
            dirty = false
            isLoading = false
            textView.undoManager?.removeAllActions(withTarget: textView)
            updateStatus()
        }

        func installHandlers() {
            document.flushPendingEdits = { [weak self] in self?.flush() }
            document.formatHandler = { [weak self] command in self?.handleFormat(command) }
            document.tableHandler = nil
        }

        func uninstallHandlers() {
            document.flushPendingEdits = nil
            document.formatHandler = nil
        }

        /// Serializes the rich text into the document immediately.
        func flush() {
            syncTask?.cancel()
            syncTask = nil
            guard dirty, let storage = textView?.textStorage else { return }
            dirty = false
            let markdown = MarkdownSerializer.serialize(storage)
            document.replaceText(markdown)
            lastPushedVersion = document.textVersion
        }

        private func scheduleSync() {
            dirty = true
            syncTask?.cancel()
            syncTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }

        private func handleFormat(_ command: FormatCommand) {
            guard let tv = textView else { return }
            switch command {
            case .bold: tv.toggleBold()
            case .italic: tv.toggleItalic()
            case .strikethrough: tv.toggleStrikethrough()
            case .inlineCode: tv.toggleInlineCode()
            case .heading(let level): tv.toggleParagraphKind(level == 0 ? .body : .heading(level))
            case .bulletList: tv.toggleParagraphKind(.bulletList)
            case .numberedList: tv.toggleParagraphKind(.numberedList)
            case .taskList: tv.toggleParagraphKind(.taskList)
            case .blockQuote: tv.toggleParagraphKind(.blockQuote)
            case .codeBlock: tv.toggleParagraphKind(.codeBlock)
            case .link: tv.insertLink()
            case .image: tv.insertImagePlaceholder()
            case .table: tv.insertTable()
            case .horizontalRule: tv.insertHorizontalRule()
            }
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isLoading else { return }
            scheduleSync()
            updateStatus()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateStatus()
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let s = link as? String, let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }

        private func updateStatus() {
            guard let tv = textView else { return }
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            var line = 1
            var lastStart = 0
            var i = 0
            let end = min(sel.location, ns.length)
            while i < end {
                let r = ns.range(of: "\n", options: [.literal], range: NSRange(location: i, length: end - i))
                if r.location == NSNotFound { break }
                line += 1
                lastStart = r.location + 1
                i = r.location + 1
            }
            document.status.line = line
            document.status.column = sel.location - lastStart + 1
            document.status.location = sel.location
            document.status.selectionLength = sel.length
            scheduleStatistics(for: tv.string)
        }

        private var statsTask: Task<Void, Never>?
        private var statsGeneration = 0

        private func scheduleStatistics(for text: String) {
            statsGeneration &+= 1
            let generation = statsGeneration
            statsTask?.cancel()
            statsTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let (counts, lines) = await Task.detached(priority: .utility) {
                    (TextStatistics.count(text), TextStatistics.lineCount(text))
                }.value
                guard let self, self.statsGeneration == generation else { return }
                self.document.status.characters = counts.characters
                self.document.status.words = counts.words
                self.document.status.lines = lines
            }
        }
    }
}
