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

    func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        let out = NSMutableAttributedString()
        for child in document.children {
            renderBlock(child, into: out, context: BlockContext())
        }
        if out.length == 0 {
            out.append(NSAttributedString(string: "", attributes: style.bodyAttributes()))
        }
        return out
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
            content.append(NSAttributedString(string: "\n", attributes: attrs))
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
            content.append(NSAttributedString(string: "\n", attributes: attrs))
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
            Self.highlight(rendered, language: code.language)
            out.append(rendered)

        case let quote as BlockQuote:
            var ctx = context
            ctx.quotes.append(QuoteTextBlock())
            let children = Array(quote.children)
            if children.isEmpty {
                var attrs = style.bodyAttributes()
                attrs[.paragraphStyle] = paragraphStyle(base: style.bodyParagraphStyle(), context: ctx)
                out.append(NSAttributedString(string: "\n", attributes: attrs))
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
            out.append(NSAttributedString(string: "\u{00A0}\n", attributes: attrs))

        case let html as HTMLBlock:
            let p = paragraphStyle(base: style.bodyParagraphStyle(), context: context)
            let attrs: [NSAttributedString.Key: Any] = [.font: style.codeFont, .foregroundColor: style.secondaryColor, .paragraphStyle: p, .pfRaw: true]
            var text = html.rawHTML
            if text.hasSuffix("\n") { text.removeLast() }
            out.append(NSAttributedString(string: text + "\n", attributes: attrs))

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
                content.append(NSAttributedString(string: node.format(), attributes: attrs))
            }
            content.append(NSAttributedString(string: "\n", attributes: attrs))
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
            let marker = NSMutableAttributedString(string: "\t" + markerText + "\t", attributes: markerAttrs)
            let children = Array(item.children)
            let position = ListPosition(first: i == 0, last: i == items.count - 1)
            if children.isEmpty {
                let p = paragraphStyle(base: style.bodyParagraphStyle(), context: ctx, listPosition: position)
                let m = NSMutableAttributedString(attributedString: marker)
                m.append(NSAttributedString(string: "\n", attributes: style.bodyAttributes()))
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
            content.append(NSAttributedString(string: "\n", attributes: attrs))
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
        out.append(NSAttributedString(string: "\n", attributes: attrs))
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
            out.append(NSAttributedString(string: text.string, attributes: attributes(base: base, inline: inline)))
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
            out.append(NSAttributedString(string: code.code, attributes: attributes(base: base, inline: s)))
        case let link as Markdown.Link:
            var s = inline; s.link = link.destination ?? ""
            let children = Array(link.children)
            if children.isEmpty {
                out.append(NSAttributedString(string: link.destination ?? "", attributes: attributes(base: base, inline: s)))
            } else {
                for child in children { renderInline(child, into: out, base: base, inline: s) }
            }
        case let image as Markdown.Image:
            renderImage(image, into: out, base: base, inline: inline)
        case is SoftBreak:
            out.append(NSAttributedString(string: " ", attributes: attributes(base: base, inline: inline)))
        case is LineBreak:
            out.append(NSAttributedString(string: "\u{2028}", attributes: attributes(base: base, inline: inline)))
        case let html as InlineHTML:
            var attrs = attributes(base: base, inline: inline)
            attrs[.pfRaw] = true
            attrs[.font] = style.codeFont
            attrs[.foregroundColor] = style.secondaryColor
            out.append(NSAttributedString(string: html.rawHTML, attributes: attrs))
        case let symbol as SymbolLink:
            var s = inline; s.code = true
            out.append(NSAttributedString(string: symbol.destination ?? "", attributes: attributes(base: base, inline: s)))
        default:
            if let container = node as? InlineContainer {
                for child in container.children { renderInline(child, into: out, base: base, inline: inline) }
            } else {
                out.append(NSAttributedString(string: node.format(), attributes: attributes(base: base, inline: inline)))
            }
        }
    }

    private func renderImage(_ image: Markdown.Image, into out: NSMutableAttributedString, base: [NSAttributedString.Key: Any], inline: InlineStyle) {
        let source = image.source ?? ""
        let alt = image.plainText
        let reference = ImageReference(source: source, alt: alt, title: image.title)
        var attrs = attributes(base: base, inline: inline)
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
