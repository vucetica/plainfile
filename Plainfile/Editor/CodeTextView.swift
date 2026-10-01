import AppKit

/// NSTextView subclass backed by TextKit 2 with tab/indent handling and
/// Markdown source formatting helpers.
final class CodeTextView: NSTextView {

    var tabWidth = 4
    var insertsSpacesForTab = true
    var autoIndents = true
    var highlightsCurrentLine = true {
        didSet { needsDisplay = true }
    }
    var currentLineColor = NSColor.clear

    override var acceptsFirstResponder: Bool { true }

    // MARK: Typing behaviour

    override func insertTab(_ sender: Any?) {
        guard insertsSpacesForTab else { super.insertTab(sender); return }
        let sel = selectedRange()
        if sel.length > 0, (string as NSString).substring(with: sel).contains("\n") {
            indentSelectedLines(by: 1)
            return
        }
        let lineStart = (string as NSString).lineRange(for: NSRange(location: sel.location, length: 0)).location
        let column = sel.location - lineStart
        let spaces = tabWidth - (column % tabWidth)
        insertText(String(repeating: " ", count: spaces), replacementRange: sel)
    }

    override func insertBacktab(_ sender: Any?) {
        indentSelectedLines(by: -1)
    }

    override func insertNewline(_ sender: Any?) {
        guard autoIndents else { super.insertNewline(sender); return }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: lineRange)
        var indent = ""
        for ch in line {
            if ch == " " || ch == "\t" { indent.append(ch) } else { break }
        }
        // Do not carry indentation that lies after the insertion point.
        let column = sel.location - lineRange.location
        if indent.utf16.count > column { indent = String(indent.prefix(column)) }
        insertText("\n" + indent, replacementRange: sel)
    }

    /// Shifts the lines that intersect the selection by `delta` indentation levels.
    func indentSelectedLines(by delta: Int) {
        let ns = string as NSString
        let sel = selectedRange()
        let lines = ns.lineRange(for: sel)
        let text = ns.substring(with: lines)
        let unit = insertsSpacesForTab ? String(repeating: " ", count: tabWidth) : "\t"
        var out: [String] = []
        var pieces = text.components(separatedBy: "\n")
        let endsWithNewline = text.hasSuffix("\n")
        if endsWithNewline { pieces.removeLast() }
        for piece in pieces {
            if delta > 0 {
                out.append(piece.isEmpty ? piece : unit + piece)
            } else {
                var p = Substring(piece)
                if p.hasPrefix("\t") { p = p.dropFirst() }
                else {
                    var removed = 0
                    while removed < tabWidth, p.first == " " { p = p.dropFirst(); removed += 1 }
                }
                out.append(String(p))
            }
        }
        var replacement = out.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        guard shouldChangeText(in: lines, replacementString: replacement) else { return }
        replaceCharacters(in: lines, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: lines.location, length: replacement.utf16.count))
    }

    // MARK: Current line highlight

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard highlightsCurrentLine, selectedRange().length == 0, let tlm = textLayoutManager, let tcm = tlm.textContentManager else { return }
        let sel = selectedRange()
        guard let loc = tcm.location(tcm.documentRange.location, offsetBy: sel.location) else { return }
        var lineFrame: NSRect?
        tlm.enumerateTextSegments(in: NSTextRange(location: loc), type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            lineFrame = frame
            return false
        }
        var frame: NSRect
        if let lineFrame {
            frame = lineFrame
        } else if let fragment = tlm.textLayoutFragment(for: loc) {
            frame = fragment.layoutFragmentFrame
        } else {
            return
        }
        frame.origin.x = 0
        frame.size.width = bounds.width
        frame.origin.y += textContainerOrigin.y
        currentLineColor.setFill()
        frame.intersection(rect).fill()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if highlightsCurrentLine { needsDisplay = true }
    }

    // MARK: Markdown source helpers

    /// Wraps the selection (or the word at the caret) with the given markers.
    func wrapSelection(prefix: String, suffix: String) {
        let ns = string as NSString
        var sel = selectedRange()
        if sel.length == 0 {
            // Select the word around the caret.
            let wordRange = ns.rangeOfWord(at: sel.location)
            sel = wordRange
        }
        let selected = ns.substring(with: sel)
        let pl = prefix.utf16.count, sl = suffix.utf16.count
        if selected.hasPrefix(prefix), selected.hasSuffix(suffix), selected.utf16.count >= pl + sl {
            let inner = (selected as NSString).substring(with: NSRange(location: pl, length: selected.utf16.count - pl - sl))
            insertText(inner, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location, length: inner.utf16.count))
            return
        }
        // Already wrapped outside the selection?
        let before = NSRange(location: max(0, sel.location - pl), length: min(pl, sel.location))
        let after = NSRange(location: sel.upperBound, length: min(sl, ns.length - sel.upperBound))
        if before.length == pl, after.length == sl, ns.substring(with: before) == prefix, ns.substring(with: after) == suffix {
            let outer = NSRange(location: before.location, length: pl + sel.length + sl)
            insertText(selected, replacementRange: outer)
            setSelectedRange(NSRange(location: before.location, length: sel.length))
            return
        }
        insertText(prefix + selected + suffix, replacementRange: sel)
        setSelectedRange(NSRange(location: sel.location + pl, length: sel.length))
    }

    /// Toggles a prefix on each line in the selection. `numbered` produces "1. ", "2. " ...
    func toggleLinePrefix(_ prefix: String, numbered: Bool = false, headingLevel: Int? = nil) {
        let ns = string as NSString
        let sel = selectedRange()
        let lines = ns.lineRange(for: sel)
        let text = ns.substring(with: lines)
        var pieces = text.components(separatedBy: "\n")
        let endsWithNewline = text.hasSuffix("\n")
        if endsWithNewline { pieces.removeLast() }

        let allHave = pieces.allSatisfy { line in
            if let headingLevel {
                return Self.headingLevel(of: line) == headingLevel
            }
            if numbered { return Self.numberedPrefixRange(in: line) != nil }
            return line.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }
        var out: [String] = []
        for (i, line) in pieces.enumerated() {
            var stripped = line
            if let headingLevel {
                stripped = Self.stripHeading(line)
                out.append(allHave || headingLevel == 0 ? stripped : String(repeating: "#", count: headingLevel) + " " + stripped)
                continue
            }
            if let r = Self.numberedPrefixRange(in: line) {
                stripped = String(line[r.upperBound...])
            } else if let r = Self.listPrefixRange(in: line) {
                stripped = String(line[r.upperBound...])
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) {
                if let range = line.range(of: prefix) { stripped = String(line[range.upperBound...]) }
            }
            if allHave {
                out.append(stripped)
            } else if numbered {
                out.append("\(i + 1). " + stripped)
            } else {
                out.append(prefix + stripped)
            }
        }
        var replacement = out.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        insertText(replacement, replacementRange: lines)
        setSelectedRange(NSRange(location: lines.location, length: replacement.utf16.count))
    }

    func insertBlock(_ block: String) {
        let ns = string as NSString
        let sel = selectedRange()
        var prefix = ""
        if sel.location > 0, ns.character(at: sel.location - 1) != 0x0A { prefix = "\n" }
        if sel.location > 1, prefix == "\n", ns.character(at: sel.location - 2) != 0x0A { prefix = "\n\n" }
        else if sel.location > 0, prefix == "", sel.location >= 2, ns.character(at: sel.location - 2) != 0x0A { prefix = "\n" }
        insertText(prefix + block + "\n", replacementRange: sel)
    }

    func wrapSelectionInCodeBlock() {
        let ns = string as NSString
        let sel = selectedRange()
        let lines = ns.lineRange(for: sel)
        var text = ns.substring(with: lines)
        if !text.hasSuffix("\n") { text += "\n" }
        let replacement = "```\n" + text + "```\n"
        insertText(replacement, replacementRange: lines)
        setSelectedRange(NSRange(location: lines.location + 3, length: 0))
    }

    static func headingLevel(of line: String) -> Int {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#" { level += 1; idx = line.index(after: idx) }
        guard level > 0, level <= 6, idx == line.endIndex || line[idx] == " " else { return 0 }
        return level
    }

    static func stripHeading(_ line: String) -> String {
        let level = headingLevel(of: line)
        guard level > 0 else { return line }
        return String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
    }

    static func numberedPrefixRange(in line: String) -> Range<String.Index>? {
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == " " { idx = line.index(after: idx) }
        let digitsStart = idx
        while idx < line.endIndex, line[idx].isNumber { idx = line.index(after: idx) }
        guard idx > digitsStart, idx < line.endIndex, line[idx] == "." || line[idx] == ")" else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        return line.startIndex..<line.index(after: idx)
    }

    static func listPrefixRange(in line: String) -> Range<String.Index>? {
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == " " { idx = line.index(after: idx) }
        guard idx < line.endIndex, "-*+>".contains(line[idx]) else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        idx = line.index(after: idx)
        // Task list checkbox
        let rest = line[idx...]
        if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
            idx = line.index(idx, offsetBy: 4)
        }
        return line.startIndex..<idx
    }
}

extension NSString {
    /// The range of the "word" (identifier characters) around a location.
    func rangeOfWord(at location: Int) -> NSRange {
        let set = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        var start = location
        var end = location
        while start > 0 {
            let c = character(at: start - 1)
            guard let scalar = Unicode.Scalar(c), set.contains(scalar) else { break }
            start -= 1
        }
        while end < length {
            let c = character(at: end)
            guard let scalar = Unicode.Scalar(c), set.contains(scalar) else { break }
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }
}
