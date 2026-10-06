import SwiftUI
import AppKit

/// WYSIWYG Markdown editor. Edits are serialized back into `document.text`.
struct RichMarkdownEditorView: NSViewRepresentable {
    @ObservedObject var document: PlainDocument
    let pane: EditorPane
    var fileURL: URL?
    var settings: EditorSettings
    /// The selection made in another pane. Passed in so a change runs `updateNSView`.
    var linkedSelection: LinkedSelection?

    func makeCoordinator() -> Coordinator { Coordinator(document: document, pane: pane) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = RichTextView.make()
        textView.delegate = context.coordinator
        textView.onFocus = { [weak coordinator = context.coordinator] in coordinator?.didFocus() }
        textView.backgroundColor = .textBackgroundColor
        let container = CenteredTextContainerView(textView: textView)
        container.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        scrollView.documentView = container
        context.coordinator.textView = textView
        context.coordinator.apply(settings: settings, to: textView)
        context.coordinator.load(fileURL: fileURL)
        context.coordinator.appliedLinkedVersion = linkedSelection?.version
        context.coordinator.installHandlers()
        context.coordinator.restoreSelection()
        context.coordinator.observeEdits(of: textView.textStorage!)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }
        coordinator.document = document
        coordinator.pane = pane
        coordinator.fileURL = fileURL
        coordinator.undoManager = context.environment.undoManager
        coordinator.apply(settings: settings, to: textView)
        if let linkedSelection, linkedSelection.version != coordinator.appliedLinkedVersion {
            coordinator.appliedLinkedVersion = linkedSelection.version
            if linkedSelection.applies(to: pane) { coordinator.pendingSelection = linkedSelection.ranges }
        }
        if document.textVersion != coordinator.lastPushedVersion {
            // A pane that is not being edited follows the other pane's typing at a
            // slower pace, so Markdown is not rendered again on every key press.
            let layout = document.layout
            coordinator.reload(immediately: !layout.isSplit || layout.activePaneID == pane.id)
        }
        coordinator.applyPendingSelection()
        coordinator.installHandlers()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
        coordinator.uninstallHandlers()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: PlainDocument
        var pane: EditorPane
        var fileURL: URL?
        weak var textView: RichTextView?
        var undoManager: UndoManager?
        var lastPushedVersion = 0
        var appliedLinkedVersion: Int?
        /// A selection from another pane, waiting for a pending reload.
        var pendingSelection: [NSRange]?
        private var appliedSettings: EditorSettings?
        private var syncTask: Task<Void, Never>?
        private var reloadTask: Task<Void, Never>?
        private var dirty = false
        private var isLoading = false
        private var isApplyingSelection = false

        // The source map belongs to `renderedText`, a rendering of `document.text`.
        // While the rich text is edited the two drift apart, and `TextAlignment`
        // bridges the difference.
        private var sourceMap = MarkdownSourceMap(entries: [])
        private var renderedText: NSString = ""
        private var renderedMatchesView = true
        private var sourceMapIsStale = false

        nonisolated(unsafe) private var editObserver: NSObjectProtocol?

        init(document: PlainDocument, pane: EditorPane) {
            self.document = document
            self.pane = pane
        }

        deinit {
            if let editObserver { NotificationCenter.default.removeObserver(editObserver) }
        }

        /// Schedules a sync for every edit. Edits are watched on the text storage
        /// because undo and redo change it without the text view's `textDidChange`.
        func observeEdits(of storage: NSTextStorage) {
            editObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.storageDidProcessEditing() }
            }
        }

        private func storageDidProcessEditing() {
            guard !isLoading else { return }
            renderedMatchesView = false
            scheduleSync()
            updateStatus()
        }

        func didFocus() {
            document.layout.activate(pane)
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
            reloadTask?.cancel()
            reloadTask = nil
            isLoading = true
            let renderer = MarkdownRenderer(style: textView.style, baseURL: fileURL)
            let (rendered, map) = renderer.renderMapped(document.text)
            sourceMap = map
            renderedText = rendered.string as NSString
            renderedMatchesView = true
            sourceMapIsStale = false
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
            pane.flushPendingEdits = { [weak self] in self?.flush() }
            pane.formatHandler = { [weak self] command in self?.handleFormat(command) }
            pane.tableHandler = nil
        }

        func uninstallHandlers() {
            pane.flushPendingEdits = nil
            pane.formatHandler = nil
        }

        // MARK: Selection sync

        /// Reloads now, or within 150 ms when `immediately` is false. Later changes
        /// during the wait are picked up by the same reload.
        func reload(immediately: Bool) {
            if immediately {
                load(fileURL: fileURL)
                return
            }
            guard reloadTask == nil else { return }
            reloadTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                self.reloadTask = nil
                if self.document.textVersion != self.lastPushedVersion { self.load(fileURL: self.fileURL) }
                self.applyPendingSelection()
            }
        }

        func applyPendingSelection() {
            guard reloadTask == nil, let ranges = pendingSelection else { return }
            pendingSelection = nil
            applySourceSelection(ranges, reveal: true)
        }

        private func refreshSourceMapIfNeeded() {
            guard sourceMapIsStale, let textView else { return }
            sourceMapIsStale = false
            let (rendered, map) = MarkdownRenderer(style: textView.style, baseURL: fileURL).renderMapped(document.text)
            sourceMap = map
            renderedText = rendered.string as NSString
            renderedMatchesView = renderedText.isEqual(to: textView.string)
        }

        /// The source ranges of rich text ranges.
        func sourceRanges(for ranges: [NSRange]) -> [NSRange] {
            guard let textView else { return [] }
            refreshSourceMapIfNeeded()
            let alignment = renderedMatchesView ? nil : TextAlignment(from: textView.string as NSString, to: renderedText)
            return ranges.map { sourceMap.sourceRange(forRendered: alignment?.map($0) ?? $0) }
        }

        /// The rich text ranges of source ranges.
        func renderedRanges(for ranges: [NSRange]) -> [NSRange] {
            guard let textView else { return [] }
            refreshSourceMapIfNeeded()
            let alignment = renderedMatchesView ? nil : TextAlignment(from: renderedText, to: textView.string as NSString)
            let length = (textView.string as NSString).length
            return CodeEditorView.Coordinator.clamped(ranges.map { r in
                let rendered = sourceMap.renderedRange(forSource: r)
                return alignment?.map(rendered) ?? rendered
            }, to: length)
        }

        func applySourceSelection(_ ranges: [NSRange], reveal: Bool) {
            guard let textView, !ranges.isEmpty else { return }
            let rendered = renderedRanges(for: ranges)
            isApplyingSelection = true
            textView.selectedRanges = rendered.map { NSValue(range: $0) }
            isApplyingSelection = false
            pane.lastSourceSelection = ranges
            if reveal { textView.scrollRangeToVisible(rendered[0]) }
            updateStatus()
        }

        /// Puts back the pane's selection when the editor is created. Waits a turn so
        /// layout can scroll.
        func restoreSelection() {
            let ranges = pane.lastSourceSelection
            guard !ranges.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.applySourceSelection(ranges, reveal: true)
            }
        }

        /// Stores the selection in source coordinates, and shares it with the other pane
        /// when the user made it here.
        private func recordSelection() {
            guard let textView else { return }
            let ranges = sourceRanges(for: textView.selectedRanges.map(\.rangeValue))
            let layout = document.layout
            if layout.isSplit, textView.window?.firstResponder === textView {
                layout.publishSelection(ranges, from: pane)
            } else {
                pane.lastSourceSelection = ranges
            }
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
            // The source changed, so the selection's source ranges did too.
            sourceMapIsStale = true
            recordSelection()
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

        func textViewDidChangeSelection(_ notification: Notification) {
            updateStatus()
            guard !isLoading, !isApplyingSelection else { return }
            recordSelection()
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
            pane.status.line = line
            pane.status.column = sel.location - lastStart + 1
            pane.status.location = sel.location
            pane.status.selectionLength = sel.length
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
                self.pane.status.characters = counts.characters
                self.pane.status.words = counts.words
                self.pane.status.lines = lines
            }
        }
    }
}
