import AppKit
import Markdown

/// Converts Markdown into an attributed string for the rich editor.
final class MarkdownRenderer {

    let style: MarkdownStyle
    let baseURL: URL?

    init(style: MarkdownStyle, baseURL: URL?) {
        self.style = style
        self.baseURL = baseURL
    }

    private struct ListPosition {
        var first = false
        var last = false
    }

    private struct BlockContext {
        var lists: [NSTextList] = []
        var quotes: [QuoteTextBlock] = []
        var inTableCell = false
        var listPosition = ListPosition()
    }

    private struct InlineStyle {
        var bold = false
        var italic = false
        var code = false
        var strike = false
        var link: String? = nil
    }

    private var locator: SourceLocator?
    private var source: NSString = ""

    func render(_ markdown: String) -> NSAttributedString {
        renderMapped(markdown).text
    }

    /// Renders the Markdown and records which source range each rendered run came from.
    func renderMapped(_ markdown: String) -> (text: NSAttributedString, map: MarkdownSourceMap) {
        locator = SourceLocator(markdown)
        source = markdown as NSString
        defer { locator = nil; source = "" }
        let document = Document(parsing: markdown)
        let out = NSMutableAttributedString()
        for child in document.children {
            renderBlock(child, into: out, context: BlockContext())
        }
        if out.length == 0 {
            out.append(NSAttributedString(string: "", attributes: style.bodyAttributes()))
        }
        let map = MarkdownSourceMap.extract(from: out)
        return (out, map)
    }

    // MARK: Source ranges

    private func sourceRange(_ node: Markup) -> NSRange? {
        locator?.range(node.range)
    }

    /// An empty source range at the end of `node`, for the line break that ends a block.
    private func sourceEnd(_ node: Markup) -> NSRange? {
        sourceRange(node).map { NSRange(location: $0.upperBound, length: 0) }
    }

    private func sourceStart(_ node: Markup) -> NSRange? {
        sourceRange(node).map { NSRange(location: $0.location, length: 0) }
    }

    private func tagged(_ attrs: [NSAttributedString.Key: Any], _ range: NSRange?) -> [NSAttributedString.Key: Any] {
        guard let range else { return attrs }
        var attrs = attrs
        attrs[.pfSourceRange] = NSValue(range: range)
        return attrs
    }

    private func tag(_ string: NSMutableAttributedString, _ range: NSRange?) {
        guard let range, string.length > 0 else { return }
        string.addAttribute(.pfSourceRange, value: NSValue(range: range), range: NSRange(location: 0, length: string.length))
    }

    /// The source of an inline code span without its backticks.
    private func codeSpanRange(_ code: InlineCode) -> NSRange? {
        guard let range = sourceRange(code), range.upperBound <= source.length else { return nil }
        var ticks = 0
        while ticks < range.length / 2, source.character(at: range.location + ticks) == 0x60 { ticks += 1 }
        let inner = NSRange(location: range.location + ticks, length: range.length - 2 * ticks)
        // A single space inside the ticks on both sides is stripped by the parser.
        if inner.length >= 2, (code.code as NSString).length == inner.length - 2,
           source.character(at: inner.location) == 0x20, source.character(at: inner.upperBound - 1) == 0x20 {
            return NSRange(location: inner.location + 1, length: inner.length - 2)
        }
        return inner
    }

    /// The source of a code block's body: the lines between the fences, or the whole
    /// block for an indented code block.
    private func codeBodyRange(_ code: CodeBlock) -> NSRange? {
        guard let range = sourceRange(code), range.upperBound <= source.length, range.length > 0 else { return nil }
        let block = source.substring(with: range)
        let trimmed = block.drop { $0 == " " }
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return range }
        let firstLine = source.lineRange(for: NSRange(location: range.location, length: 0))
        let bodyStart = min(firstLine.upperBound, range.upperBound)
        var bodyEnd = range.upperBound
        // Drop the closing fence line when there is one.
        if bodyEnd > bodyStart {
            let lastLine = source.lineRange(for: NSRange(location: bodyEnd - 1, length: 0))
            let lastText = source.substring(with: lastLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if lastLine.location >= bodyStart, lastText.hasPrefix("```") || lastText.hasPrefix("~~~") {
                bodyEnd = lastLine.location
            }
        }
        // Without the final line break, which the rendered code also drops.
        if bodyEnd > bodyStart, source.character(at: bodyEnd - 1) == 0x0A { bodyEnd -= 1 }
        return NSRange(location: bodyStart, length: max(0, bodyEnd - bodyStart))
    }

    // MARK: Blocks

    private func renderBlock(_ node: Markup, into out: NSMutableAttributedString, context: BlockContext, listMarker: NSAttributedString? = nil) {
        switch node {
        case let paragraph as Paragraph:
            let p = paragraphStyle(base: style.bodyParagraphStyle(), context: context)
            var attrs = style.bodyAttributes()
            attrs[.paragraphStyle] = p
            if !context.quotes.isEmpty { attrs[.foregroundColor] = style.secondaryColor }
            let content = NSMutableAttributedString()
            if let listMarker { content.append(listMarker) }
            for child in paragraph.children { renderInline(child, into: content, base: attrs, inline: InlineStyle()) }
            content.append(NSAttributedString(string: "\n", attributes: tagged(attrs, sourceEnd(paragraph))))
            applyParagraphStyle(p, to: content)
            out.append(content)

        case let heading as Heading:
            let level = max(1, min(6, heading.level))
            let p = paragraphStyle(base: style.headingParagraphStyle(level: level), context: context)
            var attrs: [NSAttributedString.Key: Any] = [.font: style.headingFont(level: level), .foregroundColor: style.textColor, .paragraphStyle: p, .pfHeadingLevel: level]
            if let listMarker { out.append(listMarker) }
            let content = NSMutableAttributedString()
            for child in heading.children { renderInline(child, into: content, base: attrs, inline: InlineStyle()) }
            attrs[.pfHeadingLevel] = level
            content.append(NSAttributedString(string: "\n", attributes: tagged(attrs, sourceEnd(heading))))
            applyParagraphStyle(p, to: content)
            out.append(content)

        case let code as CodeBlock:
            let block = CodeTextBlock(language: code.language ?? "")
            let p = paragraphStyle(base: style.codeParagraphStyle(block: block), context: context, keepBlocks: true)
            let attrs: [NSAttributedString.Key: Any] = [.font: style.codeFont, .foregroundColor: style.textColor, .paragraphStyle: p]
            var text = code.code
            if text.hasSuffix("\n") { text.removeLast() }
            if text.isEmpty { text = " " }
            let rendered = NSMutableAttributedString(string: text + "\n", attributes: attrs)
            if let body = codeBodyRange(code) {
                rendered.addAttribute(.pfSourceRange, value: NSValue(range: body), range: NSRange(location: 0, length: rendered.length - 1))
                rendered.addAttribute(.pfSourceRange, value: NSValue(range: NSRange(location: sourceRange(code)?.upperBound ?? body.upperBound, length: 0)), range: NSRange(location: rendered.length - 1, length: 1))
            }
            Self.highlight(rendered, language: code.language)
            out.append(rendered)

        case let quote as BlockQuote:
            var ctx = context
            ctx.quotes.append(QuoteTextBlock())
            let children = Array(quote.children)
            if children.isEmpty {
                var attrs = style.bodyAttributes()
                attrs[.paragraphStyle] = paragraphStyle(base: style.bodyParagraphStyle(), context: ctx)
                out.append(NSAttributedString(string: "\n", attributes: tagged(attrs, sourceEnd(quote))))
            }
            for (i, child) in children.enumerated() {
                renderBlock(child, into: out, context: ctx, listMarker: i == 0 ? listMarker : nil)
            }

        case let list as UnorderedList:
            renderList(items: Array(list.listItems), ordered: false, into: out, context: context, listMarker: listMarker)

        case let list as OrderedList:
            renderList(items: Array(list.listItems), ordered: true, startIndex: Int(list.startIndex), into: out, context: context, listMarker: listMarker)

        case is ThematicBreak:
            let p = NSMutableParagraphStyle()
            p.textBlocks = [RuleTextBlock()]
            p.paragraphSpacing = 0
            p.minimumLineHeight = 2
            p.maximumLineHeight = 2
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 2), .paragraphStyle: p, .pfThematicBreak: true, .foregroundColor: NSColor.clear]
            out.append(NSAttributedString(string: "\u{00A0}\n", attributes: tagged(attrs, sourceRange(node))))

        case let html as HTMLBlock:
            let p = paragraphStyle(base: style.bodyParagraphStyle(), context: context)
            let attrs: [NSAttributedString.Key: Any] = [.font: style.codeFont, .foregroundColor: style.secondaryColor, .paragraphStyle: p, .pfRaw: true]
            var text = html.rawHTML
            if text.hasSuffix("\n") { text.removeLast() }
            var htmlRange = sourceRange(html)
            if let r = htmlRange, r.length > 0, r.upperBound <= source.length, source.character(at: r.upperBound - 1) == 0x0A {
                htmlRange = NSRange(location: r.location, length: r.length - 1)
            }
            out.append(NSAttributedString(string: text, attributes: tagged(attrs, htmlRange)))
            out.append(NSAttributedString(string: "\n", attributes: tagged(attrs, sourceEnd(html))))

        case let table as Markdown.Table:
            renderTable(table, into: out, context: context)

        case let item as ListItem:
            for child in item.children { renderBlock(child, into: out, context: context) }

        default:
            // Unknown block: render its inline children as a paragraph, or its text.
            let p = paragraphStyle(base: style.bodyParagraphStyle(), context: context)
            var attrs = style.bodyAttributes()
            attrs[.paragraphStyle] = p
            let content = NSMutableAttributedString()
            if let listMarker { content.append(listMarker) }
            if let inline = node as? InlineMarkup {
                renderInline(inline, into: content, base: attrs, inline: InlineStyle())
            } else {
                content.append(NSAttributedString(string: node.format(), attributes: tagged(attrs, sourceRange(node))))
            }
            content.append(NSAttributedString(string: "\n", attributes: tagged(attrs, sourceEnd(node))))
            applyParagraphStyle(p, to: content)
            out.append(content)
        }
    }

    private func renderList(items: [ListItem], ordered: Bool, startIndex: Int = 1, into out: NSMutableAttributedString, context: BlockContext, listMarker: NSAttributedString?) {
        let isTaskList = items.contains { $0.checkbox != nil }
        let format: NSTextList.MarkerFormat
        if ordered {
            format = MarkdownStyle.orderedMarkerFormat
        } else if isTaskList {
            format = MarkdownStyle.taskMarkerFormat
        } else {
            format = context.lists.count % 2 == 0 ? .disc : .circle
        }
        let list = NSTextList(markerFormat: format, options: 0)
        if ordered { list.startingItemNumber = max(1, startIndex) }
        var ctx = context
        ctx.lists.append(list)
        for (i, item) in items.enumerated() {
            let number = max(1, startIndex) + i
            var markerAttrs = style.bodyAttributes()
            markerAttrs[.foregroundColor] = style.markerColor
            let markerText: String
            if isTaskList {
                let checked = item.checkbox == .checked
                markerText = checked ? "☑" : "☐"
                markerAttrs[.pfTask] = checked
            } else {
                markerText = list.marker(forItemNumber: number)
            }
            let marker = NSMutableAttributedString(string: "\t" + markerText + "\t", attributes: tagged(markerAttrs, sourceStart(item)))
            let children = Array(item.children)
            let position = ListPosition(first: i == 0, last: i == items.count - 1)
            if children.isEmpty {
                let p = paragraphStyle(base: style.bodyParagraphStyle(), context: ctx, listPosition: position)
                let m = NSMutableAttributedString(attributedString: marker)
                m.append(NSAttributedString(string: "\n", attributes: tagged(style.bodyAttributes(), sourceEnd(item))))
                applyParagraphStyle(p, to: m)
                out.append(m)
                continue
            }
            for (ci, child) in children.enumerated() {
                var childContext = ctx
                childContext.listPosition = ListPosition(first: position.first && ci == 0, last: position.last && ci == children.count - 1)
                renderBlock(child, into: out, context: childContext, listMarker: ci == 0 ? marker : nil)
            }
        }
    }

    private func renderTable(_ table: Markdown.Table, into out: NSMutableAttributedString, context: BlockContext) {
        let columnCount = max(1, table.maxColumnCount)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm

        let alignments = table.columnAlignments

        // Size each column to its widest cell so the table does not stretch across the page.
        let headerCells = Array(table.head.cells)
        let bodyRows = table.body.rows.map { Array($0.cells) }
        let cellPadding: CGFloat = 8
        var columnWidths = Array(repeating: CGFloat(0), count: columnCount)
        for c in 0..<columnCount {
            var widest: CGFloat = 0
            if c < headerCells.count {
                let text = headerCells[c].plainText
                widest = max(widest, (text as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: style.baseSize)]).width)
            }
            for row in bodyRows where c < row.count {
                let text = row[c].plainText
                widest = max(widest, (text as NSString).size(withAttributes: [.font: style.bodyFont]).width)
            }
            columnWidths[c] = min(360, max(48, ceil(widest) + cellPadding * 2 + 4))
        }

        func appendCell(_ cell: Markdown.Table.Cell?, row: Int, column: Int, header: Bool) {
            let block = NSTextTableBlock(table: textTable, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
            block.setWidth(1, type: .absoluteValueType, for: .border)
            block.setBorderColor(NSColor.separatorColor)
            block.setWidth(cellPadding, type: .absoluteValueType, for: .padding)
            block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .minY)
            block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxY)
            block.setValue(columnWidths[column], type: .absoluteValueType, for: .width)
            if header { block.backgroundColor = MarkdownStyle.tableHeaderBackground }
            let p = NSMutableParagraphStyle()
            p.textBlocks = context.quotes + [block]
            p.lineBreakMode = .byWordWrapping
            if column < alignments.count, let alignment = alignments[column] {
                switch alignment {
                case .left: p.alignment = .left
                case .center: p.alignment = .center
                case .right: p.alignment = .right
                }
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: header ? NSFont.boldSystemFont(ofSize: style.baseSize) : style.bodyFont, .foregroundColor: style.textColor, .paragraphStyle: p]
            let content = NSMutableAttributedString()
            if let cell {
                for child in cell.children { renderInline(child, into: content, base: attrs, inline: InlineStyle(bold: header)) }
            }
            attrs[.paragraphStyle] = p
            content.append(NSAttributedString(string: "\n", attributes: tagged(attrs, cell.flatMap { sourceEnd($0) })))
            applyParagraphStyle(p, to: content)
            out.append(content)
        }

        for c in 0..<columnCount {
            appendCell(c < headerCells.count ? headerCells[c] : nil, row: 0, column: c, header: true)
        }
        for (r, row) in table.body.rows.enumerated() {
            let cells = Array(row.cells)
            for c in 0..<columnCount {
                appendCell(c < cells.count ? cells[c] : nil, row: r + 1, column: c, header: false)
            }
        }
        // A table must be followed by a normal paragraph so the caret can leave it.
        var attrs = style.bodyAttributes()
        attrs[.paragraphStyle] = paragraphStyle(base: style.bodyParagraphStyle(), context: context)
        out.append(NSAttributedString(string: "\n", attributes: tagged(attrs, sourceEnd(table))))
    }

    private func paragraphStyle(base: NSMutableParagraphStyle, context: BlockContext, keepBlocks: Bool = false, listPosition: ListPosition? = nil) -> NSMutableParagraphStyle {
        var p = base
        if !context.lists.isEmpty {
            let position = listPosition ?? context.listPosition
            p = style.listParagraphStyle(lists: context.lists, base: p, firstInList: position.first, lastInList: position.last)
        }
        if !context.quotes.isEmpty {
            p.textBlocks = context.quotes + p.textBlocks
        }
        return p
    }

    private func applyParagraphStyle(_ p: NSParagraphStyle, to string: NSMutableAttributedString) {
        string.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: string.length))
    }

    // MARK: Inline

    private func renderInline(_ node: Markup, into out: NSMutableAttributedString, base: [NSAttributedString.Key: Any], inline: InlineStyle) {
        switch node {
        case let text as Markdown.Text:
            out.append(NSAttributedString(string: text.string, attributes: tagged(attributes(base: base, inline: inline), sourceRange(text))))
        case let emphasis as Emphasis:
            var s = inline; s.italic = true
            for child in emphasis.children { renderInline(child, into: out, base: base, inline: s) }
        case let strong as Strong:
            var s = inline; s.bold = true
            for child in strong.children { renderInline(child, into: out, base: base, inline: s) }
        case let strike as Strikethrough:
            var s = inline; s.strike = true
            for child in strike.children { renderInline(child, into: out, base: base, inline: s) }
        case let code as InlineCode:
            var s = inline; s.code = true
            out.append(NSAttributedString(string: code.code, attributes: tagged(attributes(base: base, inline: s), codeSpanRange(code))))
        case let link as Markdown.Link:
            var s = inline; s.link = link.destination ?? ""
            let children = Array(link.children)
            if children.isEmpty {
                out.append(NSAttributedString(string: link.destination ?? "", attributes: tagged(attributes(base: base, inline: s), sourceRange(link))))
            } else {
                for child in children { renderInline(child, into: out, base: base, inline: s) }
            }
        case let image as Markdown.Image:
            renderImage(image, into: out, base: base, inline: inline)
        case is SoftBreak, is LineBreak:
            let string = node is SoftBreak ? " " : "\u{2028}"
            out.append(NSAttributedString(string: string, attributes: tagged(attributes(base: base, inline: inline), sourceRange(node))))
        case let html as InlineHTML:
            var attrs = attributes(base: base, inline: inline)
            attrs[.pfRaw] = true
            attrs[.font] = style.codeFont
            attrs[.foregroundColor] = style.secondaryColor
            out.append(NSAttributedString(string: html.rawHTML, attributes: tagged(attrs, sourceRange(html))))
        case let symbol as SymbolLink:
            var s = inline; s.code = true
            out.append(NSAttributedString(string: symbol.destination ?? "", attributes: tagged(attributes(base: base, inline: s), sourceRange(symbol))))
        default:
            if let container = node as? InlineContainer {
                for child in container.children { renderInline(child, into: out, base: base, inline: inline) }
            } else {
                out.append(NSAttributedString(string: node.format(), attributes: tagged(attributes(base: base, inline: inline), sourceRange(node))))
            }
        }
    }

    private func renderImage(_ image: Markdown.Image, into out: NSMutableAttributedString, base: [NSAttributedString.Key: Any], inline: InlineStyle) {
        let source = image.source ?? ""
        let alt = image.plainText
        let reference = ImageReference(source: source, alt: alt, title: image.title)
        var attrs = tagged(attributes(base: base, inline: inline), sourceRange(image))
        attrs[.pfImage] = reference

        if let url = resolve(source), let nsImage = NSImage(contentsOf: url), nsImage.size.width > 0 {
            let attachment = NSTextAttachment()
            attachment.image = nsImage
            let maxWidth = max(200, style.maxWidth - 80)
            var size = nsImage.size
            if size.width > maxWidth {
                let scale = maxWidth / size.width
                size = NSSize(width: maxWidth, height: size.height * scale)
            }
            attachment.bounds = NSRect(origin: .zero, size: size)
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttributes(attrs, range: NSRange(location: 0, length: attachmentString.length))
            out.append(attachmentString)
        } else {
            // Placeholder that keeps the reference so it round-trips.
            attrs[.font] = style.codeFont
            attrs[.foregroundColor] = style.secondaryColor
            attrs[.backgroundColor] = MarkdownStyle.inlineCodeBackground
            out.append(NSAttributedString(string: "🖼 \(alt.isEmpty ? source : alt)", attributes: attrs))
        }
    }

    /// Applies static syntax colours to a code block based on its fence language.
    static func highlight(_ text: NSMutableAttributedString, language: String?) {
        guard let language = Self.language(forFence: language) else { return }
        let theme = EditorTheme()
        let ns = text.string as NSString
        var state = LineState.initial
        var location = 0
        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            var contentLength = lineRange.length
            if contentLength > 0, ns.character(at: lineRange.upperBound - 1) == 0x0A { contentLength -= 1 }
            let chars = Array(ns.substring(with: NSRange(location: lineRange.location, length: contentLength)).utf16)
            let (tokens, next) = LineScanner.scan(chars, state: state, language: language)
            for token in tokens {
                let r = NSRange(location: lineRange.location + token.range.location, length: token.range.length)
                if r.upperBound <= ns.length {
                    text.addAttribute(.foregroundColor, value: theme.color(for: token.kind), range: r)
                }
            }
            state = next
            location = lineRange.upperBound
            if lineRange.length == 0 { break }
        }
    }

    static func language(forFence name: String?) -> Language? {
        guard let raw = name?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        let aliases: [String: String] = [
            "c#": "csharp", "cs": "csharp", "csharp": "csharp", "js": "javascript", "jsx": "javascript", "javascript": "javascript",
            "ts": "typescript", "tsx": "typescript", "typescript": "typescript", "py": "python", "python": "python",
            "sh": "shell", "bash": "shell", "zsh": "shell", "shell": "shell", "console": "shell", "yml": "yaml", "yaml": "yaml",
            "rb": "ruby", "ruby": "ruby", "rs": "rust", "rust": "rust", "kt": "kotlin", "kotlin": "kotlin", "objc": "objc",
            "objective-c": "objc", "c++": "cpp", "cpp": "cpp", "cc": "cpp", "h": "c", "c": "c", "go": "go", "golang": "go",
            "java": "java", "swift": "swift", "json": "json", "html": "html", "xml": "xml", "css": "css", "scss": "css",
            "sql": "sql", "php": "php", "lua": "lua", "r": "r", "dart": "dart", "scala": "scala", "perl": "perl",
            "toml": "toml", "ini": "ini", "makefile": "makefile", "make": "makefile", "dockerfile": "dockerfile",
            "docker": "dockerfile", "graphql": "graphql", "powershell": "powershell", "ps1": "powershell", "md": "markdown", "markdown": "markdown",
        ]
        if let id = aliases[raw], let language = LanguageRegistry.language(id: id) { return language }
        return LanguageRegistry.language(forFileName: "file." + raw)
    }

    private func resolve(_ source: String) -> URL? {
        if source.isEmpty { return nil }
        if let url = URL(string: source), url.scheme == "file" { return url }
        if source.hasPrefix("http://") || source.hasPrefix("https://") { return nil }
        if source.hasPrefix("/") { return URL(fileURLWithPath: source) }
        guard let baseURL else { return nil }
        return URL(fileURLWithPath: source.removingPercentEncoding ?? source, relativeTo: baseURL.deletingLastPathComponent()).standardizedFileURL
    }

    private func attributes(base: [NSAttributedString.Key: Any], inline: InlineStyle) -> [NSAttributedString.Key: Any] {
        var attrs = base
        var font = (base[.font] as? NSFont) ?? style.bodyFont
        if inline.code {
            font = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
            attrs[.pfInlineCode] = true
            attrs[.backgroundColor] = MarkdownStyle.inlineCodeBackground
        }
        let fm = NSFontManager.shared
        if inline.bold { font = fm.convert(font, toHaveTrait: .boldFontMask) }
        if inline.italic { font = fm.convert(font, toHaveTrait: .italicFontMask) }
        attrs[.font] = font
        if inline.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = inline.link {
            attrs[.link] = URL(string: link) ?? link
        }
        return attrs
    }
}
