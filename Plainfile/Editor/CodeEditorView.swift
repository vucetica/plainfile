import SwiftUI
import AppKit

/// Source editor for plain text, code, Markdown source and delimited text source.
struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var document: PlainDocument
    let pane: EditorPane
    var settings: EditorSettings
    /// The selection made in another pane. Passed in so a change runs `updateNSView`.
    var linkedSelection: LinkedSelection?

    func makeCoordinator() -> Coordinator { Coordinator(document: document, pane: pane) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = CodeTextView(usingTextLayoutManager: true)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 6
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = document.text
        textView.onFocus = { [weak coordinator = context.coordinator] in coordinator?.didFocus() }

        let theme = EditorTheme()
        textView.backgroundColor = theme.background
        textView.currentLineColor = theme.currentLineBackground
        textView.insertionPointColor = theme.text

        let highlighter = SyntaxHighlighter(textStorage: textView.textStorage!, language: document.language, theme: theme, font: settings.font)
        context.coordinator.highlighter = highlighter
        context.coordinator.textView = textView
        context.coordinator.lastPushedVersion = document.textVersion
        context.coordinator.appliedLinkedVersion = linkedSelection?.version

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        ruler.highlighter = highlighter
        ruler.theme = theme
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = settings.showLineNumbers
        scrollView.documentView = textView

        context.coordinator.apply(settings: settings, to: textView, scrollView: scrollView, force: true)
        context.coordinator.installHandlers()
        highlighter.rehighlightAll()
        context.coordinator.updateStatus()
        context.coordinator.restoreSelection()
        context.coordinator.observeEdits(of: textView.textStorage!)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView, let highlighter = coordinator.highlighter else { return }
        coordinator.document = document
        coordinator.pane = pane
        coordinator.undoManager = context.environment.undoManager

        if highlighter.language != document.language {
            highlighter.language = document.language
        }
        coordinator.apply(settings: settings, to: textView, scrollView: scrollView, force: false)

        if document.textVersion != coordinator.lastPushedVersion {
            // The text was changed elsewhere (the other pane, revert).
            coordinator.reloadText()
        }
        if let linkedSelection, linkedSelection.version != coordinator.appliedLinkedVersion {
            coordinator.appliedLinkedVersion = linkedSelection.version
            if linkedSelection.applies(to: pane) {
                coordinator.applySourceSelection(linkedSelection.ranges, reveal: true)
            }
        }
        coordinator.installHandlers()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.uninstallHandlers()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: PlainDocument
        var pane: EditorPane
        weak var textView: CodeTextView?
        var highlighter: SyntaxHighlighter?
        var undoManager: UndoManager?
        var lastPushedVersion = 0
        var appliedLinkedVersion: Int?
        var isReloading = false
        private var isApplyingSelection = false
        private var appliedSettings: EditorSettings?
        nonisolated(unsafe) private var editObserver: NSObjectProtocol?

        init(document: PlainDocument, pane: EditorPane) {
            self.document = document
            self.pane = pane
        }

        deinit {
            if let editObserver { NotificationCenter.default.removeObserver(editObserver) }
        }

        /// Pushes every text change to the document. Edits are watched on the text
        /// storage because undo and redo change it without the text view's
        /// `textDidChange`.
        func observeEdits(of storage: NSTextStorage) {
            editObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.storageDidProcessEditing() }
            }
        }

        private func storageDidProcessEditing() {
            guard !isReloading, let storage = textView?.textStorage, storage.editedMask.contains(.editedCharacters) else { return }
            document.replaceText(storage.string)
            lastPushedVersion = document.textVersion
            updateStatus()
        }

        // MARK: Text and selection sync

        /// Brings in text changed elsewhere by replacing only the part that differs,
        /// so the caret, the scroll position and the highlighting of the rest stay.
        func reloadText() {
            lastPushedVersion = document.textVersion
            guard let tv = textView, let storage = tv.textStorage else { return }
            let old = storage.string as NSString
            let new = document.text as NSString
            guard !old.isEqual(to: new as String) else { return }
            let alignment = TextAlignment(from: old, to: new)
            let selections = tv.selectedRanges.map { alignment.map($0.rangeValue) }
            let changed = NSRange(location: alignment.prefix, length: old.length - alignment.prefix - alignment.suffix)
            let replacement = new.substring(with: NSRange(location: alignment.prefix, length: new.length - alignment.prefix - alignment.suffix))
            isReloading = true
            storage.beginEditing()
            storage.replaceCharacters(in: changed, with: replacement)
            storage.endEditing()
            tv.selectedRanges = Self.clamped(selections, to: new.length).map { NSValue(range: $0) }
            isReloading = false
            // Undo steps recorded here no longer match the text.
            undoManager?.removeAllActions(withTarget: tv)
            undoManager?.removeAllActions(withTarget: storage)
            updateStatus()
        }

        static func clamped(_ ranges: [NSRange], to length: Int) -> [NSRange] {
            let result = ranges.map { r -> NSRange in
                let start = min(max(0, r.location), length)
                return NSRange(location: start, length: min(max(0, r.length), length - start))
            }
            return result.isEmpty ? [NSRange(location: 0, length: 0)] : result
        }

        /// Selects source ranges chosen in another view, and optionally scrolls to them.
        func applySourceSelection(_ ranges: [NSRange], reveal: Bool) {
            guard let tv = textView, !ranges.isEmpty else { return }
            let clamped = Self.clamped(ranges, to: (tv.string as NSString).length)
            isApplyingSelection = true
            tv.selectedRanges = clamped.map { NSValue(range: $0) }
            isApplyingSelection = false
            pane.lastSourceSelection = clamped
            if reveal { tv.scrollRangeToVisible(clamped[0]) }
            updateStatus()
        }

        /// Puts back the pane's selection when the editor is created, for example after
        /// a mode switch or when a split opens. Waits a turn so layout can scroll.
        func restoreSelection() {
            let ranges = pane.lastSourceSelection
            guard !ranges.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.applySourceSelection(ranges, reveal: true)
            }
        }

        func didFocus() {
            document.layout.activate(pane)
        }

        func apply(settings: EditorSettings, to textView: CodeTextView, scrollView: NSScrollView, force: Bool) {
            guard force || settings != appliedSettings else { return }
            let previous = appliedSettings
            appliedSettings = settings

            textView.tabWidth = settings.tabWidth
            textView.insertsSpacesForTab = settings.insertSpaces
            textView.autoIndents = settings.autoIndent
            textView.highlightsCurrentLine = settings.highlightCurrentLine
            scrollView.rulersVisible = settings.showLineNumbers

            let font = settings.font
            if force || previous?.font != font || previous?.tabWidth != settings.tabWidth {
                let paragraph = NSMutableParagraphStyle()
                let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
                paragraph.defaultTabInterval = spaceWidth * CGFloat(settings.tabWidth)
                paragraph.tabStops = []
                paragraph.lineBreakMode = .byWordWrapping
                textView.defaultParagraphStyle = paragraph
                textView.typingAttributes = [.font: font, .foregroundColor: EditorTheme().text, .paragraphStyle: paragraph]
                textView.font = font
                if let storage = textView.textStorage, storage.length > 0 {
                    storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
                }
                if let highlighter, highlighter.font != font {
                    highlighter.font = font
                }
                (scrollView.verticalRulerView as? LineNumberRulerView)?.font = NSFont.monospacedDigitSystemFont(ofSize: max(9, font.pointSize - 2), weight: .regular)
            }

            if force || previous?.wrapLines != settings.wrapLines {
                setWrapping(settings.wrapLines, textView: textView, scrollView: scrollView)
            }
        }

        private func setWrapping(_ wrap: Bool, textView: CodeTextView, scrollView: NSScrollView) {
            guard let container = textView.textContainer else { return }
            if wrap {
                container.widthTracksTextView = true
                container.size = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
                textView.frame.size.width = scrollView.contentSize.width
                scrollView.hasHorizontalScroller = false
            } else {
                container.widthTracksTextView = false
                container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = []
                scrollView.hasHorizontalScroller = true
            }
            textView.needsLayout = true
        }

        // MARK: Handlers

        func installHandlers() {
            pane.formatHandler = { [weak self] command in self?.handleFormat(command) }
            pane.flushPendingEdits = nil
            pane.tableHandler = nil
        }

        func uninstallHandlers() {
            pane.formatHandler = nil
        }

        private func handleFormat(_ command: FormatCommand) {
            guard let tv = textView else { return }
            switch command {
            case .bold: tv.wrapSelection(prefix: "**", suffix: "**")
            case .italic: tv.wrapSelection(prefix: "*", suffix: "*")
            case .strikethrough: tv.wrapSelection(prefix: "~~", suffix: "~~")
            case .inlineCode: tv.wrapSelection(prefix: "`", suffix: "`")
            case .heading(let level): tv.toggleLinePrefix("", headingLevel: level)
            case .bulletList: tv.toggleLinePrefix("- ")
            case .numberedList: tv.toggleLinePrefix("", numbered: true)
            case .taskList: tv.toggleLinePrefix("- [ ] ")
            case .blockQuote: tv.toggleLinePrefix("> ")
            case .codeBlock: tv.wrapSelectionInCodeBlock()
            case .link:
                let sel = tv.selectedRange()
                let text = (tv.string as NSString).substring(with: sel)
                if text.isEmpty {
                    tv.insertText("[link text](https://)", replacementRange: sel)
                    tv.setSelectedRange(NSRange(location: sel.location + 1, length: 9))
                } else {
                    tv.insertText("[\(text)](https://)", replacementRange: sel)
                    tv.setSelectedRange(NSRange(location: sel.location + sel.length + 3, length: 8))
                }
            case .image:
                let sel = tv.selectedRange()
                tv.insertText("![alt text](image.png)", replacementRange: sel)
                tv.setSelectedRange(NSRange(location: sel.location + 2, length: 8))
            case .table:
                tv.insertBlock("| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| | | |\n| | | |")
            case .horizontalRule:
                tv.insertBlock("---")
            }
        }

        // MARK: NSTextViewDelegate

        func textViewDidChangeSelection(_ notification: Notification) {
            updateStatus()
            guard !isReloading, !isApplyingSelection, let tv = textView else { return }
            let ranges = tv.selectedRanges.map(\.rangeValue)
            let layout = document.layout
            if layout.isSplit, tv.window?.firstResponder === tv {
                layout.publishSelection(ranges, from: pane)
            } else {
                pane.lastSourceSelection = ranges
            }
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        private var statsTask: Task<Void, Never>?
        private var statsGeneration = 0

        func updateStatus() {
            guard let tv = textView, let highlighter else { return }
            let sel = tv.selectedRange()
            let line = highlighter.lineIndex(for: sel.location)
            let column = sel.location - highlighter.lineStarts[line]
            let status = pane.status
            status.line = line + 1
            status.column = column + 1
            status.location = sel.location
            status.selectionLength = sel.length
            status.lines = highlighter.lineCount
            scheduleStatistics(for: tv.string)
        }

        /// Character and word counts are computed off the main thread with a short
        /// debounce so typing in large files is not slowed down.
        private func scheduleStatistics(for text: String) {
            statsGeneration &+= 1
            let generation = statsGeneration
            statsTask?.cancel()
            statsTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let counts = await Task.detached(priority: .utility) { TextStatistics.count(text) }.value
                guard let self, self.statsGeneration == generation else { return }
                self.pane.status.characters = counts.characters
                self.pane.status.words = counts.words
            }
        }
    }
}
