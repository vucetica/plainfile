import SwiftUI
import AppKit

/// Source editor for plain text, code, Markdown source and delimited text source.
struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var document: PlainDocument
    var settings: EditorSettings

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

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

        let theme = EditorTheme()
        textView.backgroundColor = theme.background
        textView.currentLineColor = theme.currentLineBackground
        textView.insertionPointColor = theme.text

        let highlighter = SyntaxHighlighter(textStorage: textView.textStorage!, language: document.language, theme: theme, font: settings.font)
        context.coordinator.highlighter = highlighter
        context.coordinator.textView = textView
        context.coordinator.lastPushedVersion = document.textVersion

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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView, let highlighter = coordinator.highlighter else { return }
        coordinator.document = document
        coordinator.undoManager = context.environment.undoManager

        if highlighter.language != document.language {
            highlighter.language = document.language
        }
        coordinator.apply(settings: settings, to: textView, scrollView: scrollView, force: false)

        if document.textVersion != coordinator.lastPushedVersion {
            // The text was changed elsewhere (table editor, rich editor, revert).
            coordinator.lastPushedVersion = document.textVersion
            if textView.string != document.text {
                let selection = textView.selectedRange()
                coordinator.isReloading = true
                textView.string = document.text
                coordinator.isReloading = false
                let length = (document.text as NSString).length
                let loc = min(selection.location, length)
                textView.setSelectedRange(NSRange(location: loc, length: 0))
                coordinator.updateStatus()
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
        weak var textView: CodeTextView?
        var highlighter: SyntaxHighlighter?
        var undoManager: UndoManager?
        var lastPushedVersion = 0
        var isReloading = false
        private var appliedSettings: EditorSettings?

        init(document: PlainDocument) {
            self.document = document
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
            document.formatHandler = { [weak self] command in self?.handleFormat(command) }
            document.flushPendingEdits = nil
            document.tableHandler = nil
        }

        func uninstallHandlers() {
            document.formatHandler = nil
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

        func textDidChange(_ notification: Notification) {
            guard !isReloading, let tv = textView else { return }
            document.replaceText(tv.string)
            lastPushedVersion = document.textVersion
            updateStatus()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateStatus()
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
            let status = document.status
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
                self.document.status.characters = counts.characters
                self.document.status.words = counts.words
            }
        }
    }
}
