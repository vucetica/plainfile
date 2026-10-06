import AppKit

/// TextKit 1 based rich text view used for WYSIWYG Markdown editing.
/// TextKit 1 is used deliberately because `NSTextTable` (tables) requires it.
final class RichTextView: NSTextView {

    var style = MarkdownStyle()

    override var acceptsFirstResponder: Bool { true }

    /// Called when the view becomes first responder, so its pane becomes the active one.
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    static func make() -> RichTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = RichTextView(frame: .zero, textContainer: container)
        view.isRichText = true
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.usesFontPanel = false
        view.usesRuler = false
        view.importsGraphics = false
        view.allowsImageEditing = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = false
        view.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        view.smartInsertDeleteEnabled = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = []
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // No text container inset: the gesture based selection path in recent macOS
        // releases does not account for it, which sends clicks to the end of the line.
        // Horizontal padding lives in the text container, vertical padding in the
        // enclosing `CenteredTextContainerView`.
        view.textContainerInset = .zero
        container.lineFragmentPadding = 20
        view.layoutManager?.allowsNonContiguousLayout = false
        return view
    }

    // MARK: Paragraph helpers

    private var storage: NSTextStorage { textStorage! }

    private func paragraphRanges(in range: NSRange) -> [NSRange] {
        let ns = string as NSString
        var result: [NSRange] = []
        var pos = range.location
        let end = max(range.location, range.upperBound)
        repeat {
            let pr = ns.paragraphRange(for: NSRange(location: min(pos, ns.length), length: 0))
            result.append(pr)
            pos = pr.upperBound
            if pr.length == 0 { break }
        } while pos < end
        return result
    }

    private func attributes(atParagraph range: NSRange) -> [NSAttributedString.Key: Any] {
        if range.location < storage.length {
            return storage.attributes(at: range.location, effectiveRange: nil)
        }
        return typingAttributes
    }

    private func paragraphStyle(at range: NSRange) -> NSParagraphStyle? {
        attributes(atParagraph: range)[.paragraphStyle] as? NSParagraphStyle
    }

    private func perform(_ actionName: String, _ body: () -> Void) {
        guard let um = undoManager else { body(); return }
        um.beginUndoGrouping()
        body()
        um.setActionName(actionName)
        um.endUndoGrouping()
    }

    // MARK: Key handling

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        let attrs = attributes(atParagraph: paragraph)
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        let blocks = ps?.textBlocks ?? []
        var contentEnd = paragraph.upperBound
        if paragraph.length > 0, ns.character(at: paragraph.upperBound - 1) == 0x0A { contentEnd -= 1 }
        let atEnd = sel.location >= contentEnd
        let isEmpty = paragraph.location == contentEnd

        // Leaving a heading creates a body paragraph.
        if attrs[.pfHeadingLevel] != nil, atEnd {
            super.insertNewline(sender)
            var body = style.bodyAttributes()
            body[.paragraphStyle] = stripped(ps, keepingQuotes: true) ?? style.bodyParagraphStyle()
            typingAttributes = body
            let newParagraph = (string as NSString).paragraphRange(for: NSRange(location: selectedRange().location, length: 0))
            if newParagraph.length > 0 {
                storage.setAttributes(body, range: newParagraph)
            }
            return
        }
        // Enter on an empty quoted paragraph leaves the quote.
        if blocks.contains(where: { $0 is QuoteTextBlock }), isEmpty, !blocks.contains(where: { $0 is CodeTextBlock }) {
            convertParagraphs(in: paragraph, to: .body)
            return
        }
        // Thematic breaks are not editable; move past them.
        if attrs[.pfThematicBreak] != nil {
            setSelectedRange(NSRange(location: paragraph.upperBound, length: 0))
            insertParagraphAfter(paragraph)
            return
        }
        // Enter on an empty list item ends the list (in addition to AppKit's own handling).
        if let lists = ps?.textLists, !lists.isEmpty {
            let text = ns.substring(with: NSRange(location: paragraph.location, length: contentEnd - paragraph.location))
            let stripped = text.split(separator: "\t", omittingEmptySubsequences: false).dropFirst(2).joined(separator: "\t")
            if stripped.trimmingCharacters(in: .whitespaces).isEmpty || (text.first != "\t" && text.trimmingCharacters(in: .whitespaces).isEmpty) {
                convertParagraphs(in: paragraph, to: .body)
                return
            }
        }
        super.insertNewline(sender)
    }

    private func insertParagraphAfter(_ paragraph: NSRange) {
        var body = style.bodyAttributes()
        body[.paragraphStyle] = style.bodyParagraphStyle()
        let insertAt = paragraph.upperBound
        let s = NSAttributedString(string: "\n", attributes: body)
        guard shouldChangeText(in: NSRange(location: insertAt, length: 0), replacementString: "\n") else { return }
        storage.insert(s, at: insertAt)
        didChangeText()
        setSelectedRange(NSRange(location: insertAt, length: 0))
        typingAttributes = body
    }

    /// Returns a copy of the paragraph style without list/code/rule blocks.
    private func stripped(_ ps: NSParagraphStyle?, keepingQuotes: Bool) -> NSMutableParagraphStyle? {
        guard let ps else { return nil }
        let quotes = ps.textBlocks.filter { $0 is QuoteTextBlock }
        let p = style.bodyParagraphStyle()
        if keepingQuotes { p.textBlocks = quotes }
        return p
    }

    // MARK: Block formatting

    enum ParagraphKind {
        case body
        case heading(Int)
        case bulletList
        case numberedList
        case taskList
        case blockQuote
        case codeBlock
    }

    func toggleParagraphKind(_ kind: ParagraphKind) {
        let sel = selectedRange()
        let ns = string as NSString
        let range = ns.paragraphRange(for: sel)
        let attrs = attributes(atParagraph: range)
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        let alreadyApplied: Bool
        switch kind {
        case .body: alreadyApplied = false
        case .heading(let level): alreadyApplied = (attrs[.pfHeadingLevel] as? Int) == level
        case .bulletList:
            alreadyApplied = (ps?.textLists.last).map { !MarkdownSerializerBridge.isOrdered($0.markerFormat) && $0.markerFormat != MarkdownStyle.taskMarkerFormat } ?? false
        case .taskList:
            alreadyApplied = (ps?.textLists.last).map { $0.markerFormat == MarkdownStyle.taskMarkerFormat } ?? false
        case .numberedList:
            alreadyApplied = (ps?.textLists.last).map { MarkdownSerializerBridge.isOrdered($0.markerFormat) } ?? false
        case .blockQuote: alreadyApplied = ps?.textBlocks.contains { $0 is QuoteTextBlock } ?? false
        case .codeBlock: alreadyApplied = ps?.textBlocks.contains { $0 is CodeTextBlock } ?? false
        }
        convertParagraphs(in: range, to: alreadyApplied ? .body : kind)
    }

    private func listMarkerInfo(paragraphRange: NSRange) -> (markerLength: Int, task: Bool?) {
        let ns = string as NSString
        guard paragraphRange.length > 0, ns.character(at: paragraphRange.location) == 0x09 else { return (0, nil) }
        var j = paragraphRange.location + 1
        while j < paragraphRange.upperBound, ns.character(at: j) != 0x09 { j += 1 }
        guard j < paragraphRange.upperBound else { return (0, nil) }
        var length = j + 1 - paragraphRange.location
        var task: Bool? = nil
        let marker = ns.substring(with: NSRange(location: paragraphRange.location + 1, length: j - paragraphRange.location - 1)).trimmingCharacters(in: .whitespaces)
        if MarkdownStyle.isTaskMarker(marker) {
            task = marker == "☑"
        } else {
            // Older documents kept the checkbox after the marker.
            let after = paragraphRange.location + length
            if after < paragraphRange.upperBound {
                let c = ns.character(at: after)
                if c == 0x2610 || c == 0x2611 {
                    task = c == 0x2611
                    length += 1
                    if after + 1 < paragraphRange.upperBound, ns.character(at: after + 1) == 0x20 { length += 1 }
                }
            }
        }
        return (length, task)
    }

    private func convertParagraphs(in range: NSRange, to kind: ParagraphKind) {
        let ns = string as NSString
        let full = ns.paragraphRange(for: range)
        guard shouldChangeText(in: full, replacementString: nil) else { return }
        let originalSelection = selectedRange()
        var caretDelta = 0
        var convertedLength = 0
        perform("Change Paragraph Style") {
            storage.beginEditing()
            var paragraphs = paragraphRanges(in: full)
            // Handle an empty document / empty trailing paragraph.
            if paragraphs.isEmpty { paragraphs = [NSRange(location: full.location, length: 0)] }
            var sharedCode: CodeTextBlock? = nil
            var sharedQuote: QuoteTextBlock? = nil
            var sharedList: NSTextList? = nil
            var itemNumber = 0
            var totalDelta = 0
            // Process from the end so earlier ranges stay valid.
            for paragraph in paragraphs.reversed() {
                let attrs = attributes(atParagraph: paragraph)
                let oldStyle = attrs[.paragraphStyle] as? NSParagraphStyle
                let quotes = oldStyle?.textBlocks.filter { $0 is QuoteTextBlock } ?? []
                let caretInParagraph = originalSelection.location >= paragraph.location && originalSelection.location <= paragraph.upperBound
                // Strip an existing list marker.
                let (markerLength, _) = listMarkerInfo(paragraphRange: paragraph)
                var paragraph = paragraph
                var paragraphDelta = 0
                if markerLength > 0 {
                    storage.replaceCharacters(in: NSRange(location: paragraph.location, length: markerLength), with: "")
                    paragraph.length -= markerLength
                    paragraphDelta -= markerLength
                }
                // Remember inline fonts before the base font is replaced.
                var inlineRuns: [(NSRange, NSFontDescriptor.SymbolicTraits, Bool)] = []
                let scanRange = NSRange(location: paragraph.location, length: max(0, paragraph.length - (paragraph.length > 0 && (storage.string as NSString).character(at: paragraph.upperBound - 1) == 0x0A ? 1 : 0)))
                storage.enumerateAttribute(.font, in: scanRange, options: []) { value, r, _ in
                    guard let old = value as? NSFont else { return }
                    let isCode = storage.attribute(.pfInlineCode, at: r.location, effectiveRange: nil) != nil
                    inlineRuns.append((r, old.fontDescriptor.symbolicTraits, isCode))
                }
                var contentRange = paragraph
                let hasNewline = paragraph.length > 0 && (storage.string as NSString).character(at: paragraph.upperBound - 1) == 0x0A
                if hasNewline { contentRange.length -= 1 }
                if !hasNewline {
                    // Make sure every paragraph ends with a newline so styles attach cleanly.
                    storage.replaceCharacters(in: NSRange(location: paragraph.upperBound, length: 0), with: "\n")
                    paragraph.length += 1
                }

                var newAttrs: [NSAttributedString.Key: Any] = [:]
                var newStyle: NSMutableParagraphStyle
                var removeInlineFormatting = false
                switch kind {
                case .body:
                    newStyle = style.bodyParagraphStyle()
                    newStyle.textBlocks = quotes
                    newAttrs[.font] = style.bodyFont
                case .heading(let level):
                    newStyle = style.headingParagraphStyle(level: level)
                    newStyle.textBlocks = quotes
                    newAttrs[.font] = style.headingFont(level: level)
                    newAttrs[.pfHeadingLevel] = level
                case .bulletList, .numberedList, .taskList:
                    if sharedList == nil {
                        let format: NSTextList.MarkerFormat
                        switch kind {
                        case .numberedList: format = MarkdownStyle.orderedMarkerFormat
                        case .taskList: format = MarkdownStyle.taskMarkerFormat
                        default: format = .disc
                        }
                        sharedList = NSTextList(markerFormat: format, options: 0)
                    }
                    newStyle = style.listParagraphStyle(lists: [sharedList!], base: style.bodyParagraphStyle())
                    newStyle.textBlocks = quotes
                    newAttrs[.font] = style.bodyFont
                case .blockQuote:
                    if sharedQuote == nil { sharedQuote = QuoteTextBlock() }
                    newStyle = style.bodyParagraphStyle()
                    if let lists = oldStyle?.textLists, !lists.isEmpty {
                        newStyle = style.listParagraphStyle(lists: lists, base: newStyle)
                    }
                    newStyle.textBlocks = [sharedQuote!]
                    newAttrs[.font] = style.bodyFont
                case .codeBlock:
                    if sharedCode == nil { sharedCode = CodeTextBlock(language: "") }
                    newStyle = style.codeParagraphStyle(block: sharedCode!)
                    newStyle.textBlocks = quotes + [sharedCode!]
                    newAttrs[.font] = style.codeFont
                    removeInlineFormatting = true
                }
                newAttrs[.paragraphStyle] = newStyle
                newAttrs[.foregroundColor] = style.textColor

                // Reset block-level attributes, keep inline attributes where sensible.
                storage.removeAttribute(.pfHeadingLevel, range: paragraph)
                storage.removeAttribute(.pfThematicBreak, range: paragraph)
                storage.addAttributes(newAttrs, range: paragraph)
                if removeInlineFormatting {
                    storage.removeAttribute(.pfInlineCode, range: paragraph)
                    storage.removeAttribute(.backgroundColor, range: paragraph)
                    storage.removeAttribute(.link, range: paragraph)
                    storage.removeAttribute(.strikethroughStyle, range: paragraph)
                } else {
                    // Re-apply bold/italic on top of the new base font.
                    let base = newAttrs[.font] as! NSFont
                    let isHeading = newAttrs[.pfHeadingLevel] != nil
                    for (r, traits, isCode) in inlineRuns {
                        var font = base
                        if isCode { font = NSFont.monospacedSystemFont(ofSize: base.pointSize * 0.9, weight: .regular) }
                        if traits.contains(.bold), !isHeading { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                        if traits.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                        storage.addAttribute(.font, value: font, range: r)
                    }
                }
                // Insert a marker for list kinds.
                if let list = sharedList {
                    itemNumber += 1
                    let marker = "\t" + list.marker(forItemNumber: 1) + "\t"
                    var markerAttrs = newAttrs
                    markerAttrs[.foregroundColor] = style.markerColor
                    if case .taskList = kind { markerAttrs[.pfTask] = false }
                    let markerString = NSAttributedString(string: marker, attributes: markerAttrs)
                    storage.replaceCharacters(in: NSRange(location: paragraph.location, length: 0), with: markerString)
                    paragraphDelta += markerString.length
                    paragraph.length += markerString.length
                }
                if caretInParagraph { caretDelta = paragraphDelta }
                totalDelta += paragraphDelta
                convertedLength += paragraph.length
            }
            storage.endEditing()
            _ = totalDelta
        }
        didChangeText()
        // Fix numbering of ordered lists after insertion.
        if case .numberedList = kind { renumberLists(in: ns.paragraphRange(for: range)) }
        // Restore the caret: NSTextView moves it to the end of the edited range otherwise.
        if originalSelection.length == 0 {
            let location = max(full.location, min(originalSelection.location + caretDelta, storage.length))
            setSelectedRange(NSRange(location: location, length: 0))
        } else {
            setSelectedRange(NSRange(location: full.location, length: min(convertedLength, storage.length - full.location)))
        }
        typingAttributes = attributes(atParagraph: (string as NSString).paragraphRange(for: NSRange(location: selectedRange().location, length: 0)))
    }

    private func renumberLists(in range: NSRange) {
        let ns = string as NSString
        var counters: [ObjectIdentifier: Int] = [:]
        var pos = ns.paragraphRange(for: NSRange(location: range.location, length: 0)).location
        // Walk backwards to the start of the list.
        while pos > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: pos - 1, length: 0))
            guard let ps = paragraphStyle(at: prev), !ps.textLists.isEmpty else { break }
            pos = prev.location
        }
        storage.beginEditing()
        var edits: [(NSRange, String)] = []
        var p = pos
        while p < ns.length {
            let pr = ns.paragraphRange(for: NSRange(location: p, length: 0))
            guard let ps = paragraphStyle(at: pr), let list = ps.textLists.last else { break }
            let (markerLength, _) = listMarkerInfo(paragraphRange: pr)
            if markerLength > 0, MarkdownSerializerBridge.isOrdered(list.markerFormat) {
                let key = ObjectIdentifier(list)
                let n = (counters[key] ?? (list.startingItemNumber - 1)) + 1
                counters[key] = n
                var j = pr.location + 1
                while j < pr.upperBound, ns.character(at: j) != 0x09 { j += 1 }
                edits.append((NSRange(location: pr.location + 1, length: j - pr.location - 1), list.marker(forItemNumber: n)))
            }
            p = pr.upperBound
            if pr.length == 0 { break }
        }
        for (r, marker) in edits.reversed() {
            storage.replaceCharacters(in: r, with: marker)
        }
        storage.endEditing()
    }

    // MARK: Inline formatting

    func toggleBold() { toggleTrait(.boldFontMask, actionName: "Bold") }
    func toggleItalic() { toggleTrait(.italicFontMask, actionName: "Italic") }

    private func toggleTrait(_ trait: NSFontTraitMask, actionName: String) {
        let sel = selectedRange()
        let fm = NSFontManager.shared
        if sel.length == 0 {
            var attrs = typingAttributes
            let font = (attrs[.font] as? NSFont) ?? style.bodyFont
            let has = fm.traits(of: font).contains(trait)
            attrs[.font] = has ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait)
            typingAttributes = attrs
            return
        }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        var allHave = true
        storage.enumerateAttribute(.font, in: sel, options: []) { value, _, stop in
            if let f = value as? NSFont, !fm.traits(of: f).contains(trait) { allHave = false; stop.pointee = true }
        }
        perform(actionName) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: sel, options: []) { value, r, _ in
                let f = (value as? NSFont) ?? style.bodyFont
                let newFont = allHave ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
                storage.addAttribute(.font, value: newFont, range: r)
            }
            storage.endEditing()
        }
        didChangeText()
    }

    func toggleStrikethrough() {
        let sel = selectedRange()
        if sel.length == 0 {
            var attrs = typingAttributes
            let has = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            if has { attrs.removeValue(forKey: .strikethroughStyle) } else { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            typingAttributes = attrs
            return
        }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        var allHave = true
        storage.enumerateAttribute(.strikethroughStyle, in: sel, options: []) { value, _, stop in
            if (value as? Int ?? 0) == 0 { allHave = false; stop.pointee = true }
        }
        perform("Strikethrough") {
            if allHave {
                storage.removeAttribute(.strikethroughStyle, range: sel)
            } else {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: sel)
            }
        }
        didChangeText()
    }

    func toggleInlineCode() {
        let sel = selectedRange()
        let fm = NSFontManager.shared
        func codeFont(from font: NSFont) -> NSFont {
            var f = NSFont.monospacedSystemFont(ofSize: style.bodyFont.pointSize * 0.9, weight: .regular)
            let traits = fm.traits(of: font)
            if traits.contains(.boldFontMask) { f = fm.convert(f, toHaveTrait: .boldFontMask) }
            if traits.contains(.italicFontMask) { f = fm.convert(f, toHaveTrait: .italicFontMask) }
            return f
        }
        func plainFont(from font: NSFont, paragraphAttrs: [NSAttributedString.Key: Any]) -> NSFont {
            var f = style.bodyFont
            if let level = paragraphAttrs[.pfHeadingLevel] as? Int { f = style.headingFont(level: level) }
            let traits = fm.traits(of: font)
            if traits.contains(.boldFontMask) { f = fm.convert(f, toHaveTrait: .boldFontMask) }
            if traits.contains(.italicFontMask) { f = fm.convert(f, toHaveTrait: .italicFontMask) }
            return f
        }
        if sel.length == 0 {
            var attrs = typingAttributes
            if attrs[.pfInlineCode] != nil {
                attrs.removeValue(forKey: .pfInlineCode)
                attrs.removeValue(forKey: .backgroundColor)
                attrs[.font] = plainFont(from: (attrs[.font] as? NSFont) ?? style.bodyFont, paragraphAttrs: attrs)
            } else {
                attrs[.pfInlineCode] = true
                attrs[.backgroundColor] = MarkdownStyle.inlineCodeBackground
                attrs[.font] = codeFont(from: (attrs[.font] as? NSFont) ?? style.bodyFont)
            }
            typingAttributes = attrs
            return
        }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        var allHave = true
        storage.enumerateAttribute(.pfInlineCode, in: sel, options: []) { value, _, stop in
            if value == nil { allHave = false; stop.pointee = true }
        }
        perform("Inline Code") {
            storage.beginEditing()
            storage.enumerateAttributes(in: sel, options: []) { attrs, r, _ in
                let font = (attrs[.font] as? NSFont) ?? style.bodyFont
                if allHave {
                    storage.removeAttribute(.pfInlineCode, range: r)
                    storage.removeAttribute(.backgroundColor, range: r)
                    storage.addAttribute(.font, value: plainFont(from: font, paragraphAttrs: attrs), range: r)
                } else {
                    storage.addAttribute(.pfInlineCode, value: true, range: r)
                    storage.addAttribute(.backgroundColor, value: MarkdownStyle.inlineCodeBackground, range: r)
                    storage.addAttribute(.font, value: codeFont(from: font), range: r)
                }
            }
            storage.endEditing()
        }
        didChangeText()
    }

    // MARK: Insertions

    func insertLink() {
        let sel = selectedRange()
        if sel.length > 0 {
            orderFrontLinkPanel(nil)
        } else {
            let text = NSAttributedString(string: "link", attributes: typingAttributes.merging([.link: URL(string: "https://example.com")!]) { $1 })
            insertText(text, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location, length: 4))
            orderFrontLinkPanel(nil)
        }
    }

    func insertTable(rows: Int = 3, columns: Int = 3) {
        let header: String = Array(repeating: "Header", count: columns).joined(separator: " | ")
        let divider: String = Array(repeating: "---", count: columns).joined(separator: " | ")
        let emptyRow: String = Array(repeating: " ", count: columns).joined(separator: " | ")
        var lines: [String] = [header, divider]
        for _ in 0..<max(1, rows - 1) { lines.append(emptyRow) }
        let markdown = lines.map { "| " + $0 + " |" }.joined(separator: "\n")
        insertRenderedMarkdown(markdown)
    }

    func insertHorizontalRule() {
        insertRenderedMarkdown("---")
    }

    func insertImagePlaceholder() {
        insertRenderedMarkdown("![alt text](image.png)")
    }

    /// Renders a Markdown fragment and inserts it as its own block at the caret.
    func insertRenderedMarkdown(_ markdown: String) {
        let renderer = MarkdownRenderer(style: style, baseURL: nil)
        let rendered = renderer.render(markdown)
        let ns = string as NSString
        let sel = selectedRange()
        let paragraph = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        var insertAt = paragraph.location
        var contentEnd = paragraph.upperBound
        if paragraph.length > 0, ns.character(at: paragraph.upperBound - 1) == 0x0A { contentEnd -= 1 }
        let paragraphIsEmpty = paragraph.location == contentEnd
        let combined = NSMutableAttributedString()
        if !paragraphIsEmpty {
            insertAt = paragraph.upperBound
            if contentEnd == paragraph.upperBound {
                combined.append(NSAttributedString(string: "\n", attributes: style.bodyAttributes()))
            }
        }
        combined.append(rendered)
        guard shouldChangeText(in: NSRange(location: insertAt, length: 0), replacementString: combined.string) else { return }
        storage.insert(combined, at: insertAt)
        didChangeText()
        let target = min(insertAt + combined.length, storage.length)
        setSelectedRange(NSRange(location: target, length: 0))
        typingAttributes = style.bodyAttributes()
    }
}

/// Small bridge so the text view can reuse the serializer's ordered-list check.
enum MarkdownSerializerBridge {
    static func isOrdered(_ format: NSTextList.MarkerFormat) -> Bool {
        MarkdownStyle.isOrdered(format)
    }
}

/// Scroll view document view that centers the rich text view in a column of at most
/// `maxContentWidth` points, using plain view geometry so hit testing stays exact.
final class CenteredTextContainerView: NSView {
    let textView: RichTextView
    var maxContentWidth: CGFloat = 760 {
        didSet { needsLayout = true }
    }
    var horizontalMargin: CGFloat = 24
    var verticalPadding: CGFloat = 28

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(textView: RichTextView) {
        self.textView = textView
        super.init(frame: .zero)
        autoresizingMask = [.width]
        addSubview(textView)
        textView.postsFrameChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHeight()
                self?.needsLayout = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Column geometry for a given available width.
    nonisolated static func columnFrame(availableWidth: CGFloat, maxContentWidth: CGFloat, margin: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let width = max(120, min(maxContentWidth, availableWidth - 2 * margin))
        let x = floor(max(margin, (availableWidth - width) / 2))
        return (x, width)
    }

    override func layout() {
        super.layout()
        let column = Self.columnFrame(availableWidth: bounds.width, maxContentWidth: maxContentWidth, margin: horizontalMargin)
        let clipHeight = enclosingScrollView?.contentSize.height ?? 0
        textView.minSize = NSSize(width: 0, height: max(0, clipHeight - 2 * verticalPadding))
        let origin = NSPoint(x: column.x, y: verticalPadding)
        if textView.frame.origin != origin { textView.setFrameOrigin(origin) }
        if abs(textView.frame.width - column.width) > 0.5 {
            textView.setFrameSize(NSSize(width: column.width, height: textView.frame.height))
        }
        // Give the text view its final height now so the scrollable area is right
        // in the same layout pass.
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            lm.ensureLayout(for: tc)
        }
        textView.sizeToFit()
        updateHeight()
    }

    private func updateHeight() {
        let clipHeight = enclosingScrollView?.contentSize.height ?? 0
        let height = ceil(max(clipHeight, textView.frame.maxY + verticalPadding))
        if abs(frame.height - height) > 0.5 {
            setFrameSize(NSSize(width: frame.width, height: height))
        }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        needsLayout = true
    }

    /// Clicks in the margins focus the text view and put the caret at the end.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }
}
