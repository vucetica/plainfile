import AppKit

/// Converts the rich editor's attributed string back into Markdown.
enum MarkdownSerializer {

    private struct Block {
        var text: String
        var quoteDepth: Int
        var isList: Bool
    }

    private struct TableCell {
        var row: Int
        var column: Int
        var text: String
        var alignment: NSTextAlignment
    }

    private final class TableAccumulator {
        let table: NSTextTable
        var cells: [TableCell] = []
        init(table: NSTextTable) { self.table = table }
    }

    static func serialize(_ attributed: NSAttributedString) -> String {
        let ns = attributed.string as NSString
        var blocks: [Block] = []
        var pos = 0

        var codeBlock: CodeTextBlock?
        var codeLines: [String] = []
        var codeQuoteDepth = 0
        var tableAcc: TableAccumulator?
        var tableQuoteDepth = 0
        var listLines: [String] = []
        var listQuoteDepth = 0
        var listCounters: [Int] = []
        var listRoot: NSTextList?

        func flushCode() {
            guard let block = codeBlock else { return }
            var fence = "```"
            while codeLines.contains(where: { $0.contains(fence) }) { fence += "`" }
            let body = codeLines.joined(separator: "\n")
            blocks.append(Block(text: fence + block.language + "\n" + body + "\n" + fence, quoteDepth: codeQuoteDepth, isList: false))
            codeBlock = nil
            codeLines = []
        }

        func flushTable() {
            guard let acc = tableAcc else { return }
            let columns = max(1, acc.table.numberOfColumns)
            let rows = (acc.cells.map(\.row).max() ?? 0) + 1
            var grid = Array(repeating: Array(repeating: "", count: columns), count: rows)
            var alignments = Array(repeating: NSTextAlignment.natural, count: columns)
            for cell in acc.cells where cell.row < rows && cell.column < columns {
                let existing = grid[cell.row][cell.column]
                grid[cell.row][cell.column] = existing.isEmpty ? cell.text : existing + " " + cell.text
                if cell.row == 0 { alignments[cell.column] = cell.alignment }
            }
            var lines: [String] = []
            lines.append("| " + grid[0].joined(separator: " | ") + " |")
            lines.append("| " + alignments.map { alignment -> String in
                switch alignment {
                case .center: ":---:"
                case .right: "---:"
                case .left: ":---"
                default: "---"
                }
            }.joined(separator: " | ") + " |")
            for r in 1..<max(1, rows) where r < rows {
                lines.append("| " + grid[r].joined(separator: " | ") + " |")
            }
            blocks.append(Block(text: lines.joined(separator: "\n"), quoteDepth: tableQuoteDepth, isList: false))
            tableAcc = nil
        }

        func flushList() {
            guard !listLines.isEmpty else { return }
            blocks.append(Block(text: listLines.joined(separator: "\n"), quoteDepth: listQuoteDepth, isList: true))
            listLines = []
            listCounters = []
            listRoot = nil
        }

        while pos < ns.length {
            let paragraphRange = ns.paragraphRange(for: NSRange(location: pos, length: 0))
            guard paragraphRange.length > 0 else { break }
            pos = paragraphRange.upperBound

            var contentRange = paragraphRange
            if ns.character(at: paragraphRange.upperBound - 1) == 0x0A { contentRange.length -= 1 }

            let attrs = attributed.attributes(at: paragraphRange.location, effectiveRange: nil)
            let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let textBlocks = paragraphStyle?.textBlocks ?? []
            let quoteDepth = textBlocks.filter { $0 is QuoteTextBlock }.count

            // Tables
            if let tableBlock = textBlocks.last as? NSTextTableBlock {
                flushCode(); flushList()
                if let acc = tableAcc, acc.table !== tableBlock.table { flushTable() }
                if tableAcc == nil {
                    tableAcc = TableAccumulator(table: tableBlock.table)
                    tableQuoteDepth = quoteDepth
                }
                let text = inline(attributed, range: contentRange, ignoreBold: tableBlock.startingRow == 0).replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
                tableAcc?.cells.append(TableCell(row: tableBlock.startingRow, column: tableBlock.startingColumn, text: text, alignment: paragraphStyle?.alignment ?? .natural))
                continue
            }
            flushTable()

            // Code blocks
            if let block = textBlocks.compactMap({ $0 as? CodeTextBlock }).first {
                flushList()
                if let current = codeBlock, current !== block { flushCode() }
                if codeBlock == nil {
                    codeBlock = block
                    codeQuoteDepth = quoteDepth
                }
                codeLines.append(ns.substring(with: contentRange).replacingOccurrences(of: "\u{2028}", with: "\n"))
                continue
            }
            flushCode()

            if attrs[.pfThematicBreak] != nil {
                flushList()
                blocks.append(Block(text: "---", quoteDepth: quoteDepth, isList: false))
                continue
            }

            if attrs[.pfRaw] != nil, attrs[.pfInlineCode] == nil, !(attrs[.font] is NSFont && (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == false && false) {
                // Raw HTML block (only when the whole paragraph is raw).
                var isWholeRaw = true
                attributed.enumerateAttribute(.pfRaw, in: contentRange, options: []) { value, _, stop in
                    if value == nil { isWholeRaw = false; stop.pointee = true }
                }
                if isWholeRaw {
                    flushList()
                    blocks.append(Block(text: ns.substring(with: contentRange), quoteDepth: quoteDepth, isList: false))
                    continue
                }
            }

            if let level = attrs[.pfHeadingLevel] as? Int, level > 0 {
                flushList()
                let text = inline(attributed, range: contentRange, stripListMarker: true)
                blocks.append(Block(text: String(repeating: "#", count: level) + " " + text, quoteDepth: quoteDepth, isList: false))
                continue
            }

            // List items
            if let lists = paragraphStyle?.textLists, !lists.isEmpty {
                if !listLines.isEmpty, listQuoteDepth != quoteDepth { flushList() }
                if let root = listRoot, root !== lists[0] { flushList() }
                listRoot = lists[0]
                listQuoteDepth = quoteDepth
                let depth = lists.count
                if listCounters.count < depth { listCounters.append(contentsOf: Array(repeating: 0, count: depth - listCounters.count)) }
                if listCounters.count > depth { listCounters.removeLast(listCounters.count - depth) }
                let list = lists[depth - 1]
                let ordered = Self.isOrdered(list.markerFormat)
                let (text, hadMarker, task) = inlineListItem(attributed, range: contentRange)
                let indent = String(repeating: "    ", count: depth - 1)
                if hadMarker {
                    listCounters[depth - 1] += 1
                    let number = list.startingItemNumber + listCounters[depth - 1] - 1
                    var marker = ordered ? "\(number). " : "- "
                    if let task { marker += task ? "[x] " : "[ ] " }
                    listLines.append(indent + marker + text)
                } else {
                    // Continuation paragraph inside a list item.
                    if !listLines.isEmpty { listLines.append("") }
                    listLines.append(indent + (ordered ? "   " : "  ") + text)
                }
                continue
            }
            flushList()

            let text = inline(attributed, range: contentRange)
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            blocks.append(Block(text: text, quoteDepth: quoteDepth, isList: false))
        }
        flushCode(); flushTable(); flushList()

        // Join blocks. Adjacent quoted blocks share one quote with a ">" separator line.
        var output = ""
        var previous: Block?
        for block in blocks {
            let prefix = String(repeating: "> ", count: block.quoteDepth)
            let quoted = block.text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                line.isEmpty ? String(prefix.dropLast()) : prefix + line
            }.joined(separator: "\n")
            if let previous {
                if previous.quoteDepth > 0, block.quoteDepth == previous.quoteDepth {
                    output += "\n" + String(repeating: ">", count: block.quoteDepth) + "\n"
                } else if previous.quoteDepth > 0, block.quoteDepth == 0 {
                    output += "\n\n"
                } else {
                    output += "\n\n"
                }
            }
            output += quoted
            previous = block
        }
        if !output.isEmpty { output += "\n" }
        return output
    }

    private static func isOrdered(_ format: NSTextList.MarkerFormat) -> Bool {
        MarkdownStyle.isOrdered(format)
    }

    // MARK: Inline

    private struct Segment {
        var text: String
        var bold = false
        var italic = false
        var code = false
        var strike = false
        var link: String? = nil
        var raw = false
        var image: ImageReference? = nil
    }

    /// Serializes a list item paragraph, stripping the leading "\tmarker\t" and
    /// reading the task state from a checkbox marker.
    private static func inlineListItem(_ attributed: NSAttributedString, range: NSRange) -> (String, Bool, Bool?) {
        let ns = attributed.string as NSString
        var r = range
        var hadMarker = false
        var task: Bool? = nil
        if r.length > 0, ns.character(at: r.location) == 0x09 {
            var j = r.location + 1
            while j < r.upperBound, ns.character(at: j) != 0x09 { j += 1 }
            if j < r.upperBound {
                hadMarker = true
                let marker = ns.substring(with: NSRange(location: r.location + 1, length: j - r.location - 1)).trimmingCharacters(in: .whitespaces)
                if MarkdownStyle.isTaskMarker(marker) {
                    task = marker == "☑"
                    if let value = attributed.attribute(.pfTask, at: r.location + 1, effectiveRange: nil) as? Bool { task = value }
                }
                let consumed = j + 1 - r.location
                r = NSRange(location: j + 1, length: r.length - consumed)
            }
        }
        // Older documents kept the checkbox after the marker.
        if task == nil, r.length >= 1 {
            let c = ns.character(at: r.location)
            if c == 0x2610 || c == 0x2611 {
                task = c == 0x2611
                var skip = 1
                if r.length >= 2, ns.character(at: r.location + 1) == 0x20 { skip = 2 }
                r = NSRange(location: r.location + skip, length: r.length - skip)
            }
        }
        return (inline(attributed, range: r), hadMarker, task)
    }

    static func inline(_ attributed: NSAttributedString, range: NSRange, stripListMarker: Bool = false, ignoreBold: Bool = false) -> String {
        var range = range
        if stripListMarker {
            let ns = attributed.string as NSString
            if range.length > 0, ns.character(at: range.location) == 0x09 {
                var j = range.location + 1
                while j < range.upperBound, ns.character(at: j) != 0x09 { j += 1 }
                if j < range.upperBound {
                    let consumed = j + 1 - range.location
                    range = NSRange(location: j + 1, length: range.length - consumed)
                }
            }
        }
        guard range.length > 0 else { return "" }
        var segments: [Segment] = []
        let ns = attributed.string as NSString
        attributed.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            let text = ns.substring(with: r)
            var seg = Segment(text: text)
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                seg.bold = traits.contains(.bold)
                seg.italic = traits.contains(.italic)
            }
            if let level = attrs[.pfHeadingLevel] as? Int, level > 0 { seg.bold = false }
            if ignoreBold { seg.bold = false }
            seg.code = attrs[.pfInlineCode] != nil
            if let s = attrs[.strikethroughStyle] as? Int, s != 0 { seg.strike = true }
            if let link = attrs[.link] {
                if let url = link as? URL { seg.link = url.absoluteString } else if let s = link as? String { seg.link = s }
            }
            seg.raw = attrs[.pfRaw] != nil
            seg.image = attrs[.pfImage] as? ImageReference
            segments.append(seg)
        }
        // Merge adjacent segments with equal styling.
        var merged: [Segment] = []
        for seg in segments {
            if var last = merged.last, sameStyle(last, seg), seg.image == nil, last.image == nil {
                last.text += seg.text
                merged[merged.count - 1] = last
            } else {
                merged.append(seg)
            }
        }
        var out = ""
        for (i, seg) in merged.enumerated() {
            out += render(seg, atLineStart: i == 0)
        }
        return out.replacingOccurrences(of: "\u{2028}", with: "  \n")
    }

    private static func sameStyle(_ a: Segment, _ b: Segment) -> Bool {
        a.bold == b.bold && a.italic == b.italic && a.code == b.code && a.strike == b.strike && a.link == b.link && a.raw == b.raw
    }

    private static func render(_ seg: Segment, atLineStart: Bool) -> String {
        if let image = seg.image {
            var s = "![\(image.alt)](\(image.source)"
            if let title = image.title, !title.isEmpty { s += " \"\(title)\"" }
            return s + ")"
        }
        if seg.raw { return seg.text }
        // Keep whitespace outside the emphasis markers.
        let leading = seg.text.prefix { $0 == " " || $0 == "\t" }
        let trailing = seg.text.reversed().prefix { $0 == " " || $0 == "\t" }
        let core = seg.text.dropFirst(leading.count).dropLast(trailing.count)
        if core.isEmpty { return seg.text }
        var inner: String
        if seg.code {
            var fence = "`"
            while core.contains(fence) { fence += "`" }
            let padded = core.hasPrefix("`") || core.hasSuffix("`") ? " \(core) " : String(core)
            inner = fence + padded + fence
        } else {
            inner = escape(String(core), atLineStart: atLineStart && leading.isEmpty)
        }
        if seg.bold { inner = "**" + inner + "**" }
        if seg.italic { inner = "*" + inner + "*" }
        if seg.strike { inner = "~~" + inner + "~~" }
        if let link = seg.link, !link.isEmpty {
            inner = "[" + inner + "](" + link + ")"
        }
        return String(leading) + inner + String(trailing.reversed())
    }

    static func escape(_ text: String, atLineStart: Bool) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            switch ch {
            case "\\", "*", "`":
                out.append("\\"); out.append(ch)
            case "_":
                let prev = i > 0 ? chars[i - 1] : " "
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if prev.isLetter || prev.isNumber, next.isLetter || next.isNumber {
                    out.append(ch)
                } else {
                    out.append("\\_")
                }
            case "[":
                out.append("\\[")
            case "<":
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if next.isLetter || next == "/" || next == "!" { out.append("\\<") } else { out.append(ch) }
            default:
                out.append(ch)
            }
        }
        if atLineStart {
            let trimmed = out.drop { $0 == " " }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix(">") || trimmed.hasPrefix("+ ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("|") {
                out = "\\" + out
            } else if let dot = trimmed.firstIndex(where: { !$0.isNumber }), dot != trimmed.startIndex, trimmed[dot] == "." || trimmed[dot] == ")" {
                let after = trimmed.index(after: dot)
                if after == trimmed.endIndex || trimmed[after] == " " {
                    out = String(trimmed[..<dot]) + "\\" + String(trimmed[dot...])
                }
            }
        }
        return out
    }
}
