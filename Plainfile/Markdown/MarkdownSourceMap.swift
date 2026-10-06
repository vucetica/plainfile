import AppKit
import Markdown

nonisolated extension NSAttributedString.Key {
    /// Source range (`NSValue` holding an `NSRange` in UTF-16 units of the Markdown
    /// text) of a rendered run. Only present while `MarkdownRenderer` builds its
    /// output: the renderer turns it into a `MarkdownSourceMap` and removes it.
    static let pfSourceRange = NSAttributedString.Key("pf.sourceRange")
}

/// Turns swift-markdown source locations (1-based line, 1-based column counted in
/// UTF-8 bytes) into UTF-16 offsets in the Markdown text.
nonisolated struct SourceLocator {
    private let bytes: [UInt8]
    /// UTF-8 offset of the start of each line.
    private let lineStartBytes: [Int]
    /// UTF-16 offset of the start of each line.
    private let lineStartUnits: [Int]

    init(_ text: String) {
        bytes = Array(text.utf8)
        var byteStarts = [0]
        var unitStarts = [0]
        var units = 0
        for (i, byte) in bytes.enumerated() {
            units += Self.utf16Units(lead: byte)
            if byte == 0x0A {
                byteStarts.append(i + 1)
                unitStarts.append(units)
            }
        }
        lineStartBytes = byteStarts
        lineStartUnits = unitStarts
        totalUnits = units
    }

    let totalUnits: Int

    /// UTF-16 units contributed by a byte: a lead byte counts once, or twice when it
    /// starts a four byte sequence (a surrogate pair). Continuation bytes count zero.
    private static func utf16Units(lead byte: UInt8) -> Int {
        if byte & 0xC0 == 0x80 { return 0 }
        return byte >= 0xF0 ? 2 : 1
    }

    func offset(_ location: SourceLocation) -> Int {
        let line = location.line - 1
        guard line >= 0 else { return 0 }
        guard line < lineStartBytes.count else { return totalUnits }
        var byte = lineStartBytes[line]
        var units = lineStartUnits[line]
        let end = min(bytes.count, byte + max(0, location.column - 1))
        while byte < end {
            units += Self.utf16Units(lead: bytes[byte])
            byte += 1
        }
        return units
    }

    func range(_ range: SourceRange?) -> NSRange? {
        guard let range else { return nil }
        let start = offset(range.lowerBound)
        let end = max(start, offset(range.upperBound))
        return NSRange(location: start, length: end - start)
    }
}

/// Pairs ranges of the rich text with the ranges of Markdown source they came from,
/// so a selection can move between the Rich Text and Source views.
nonisolated struct MarkdownSourceMap: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        var rendered: NSRange
        var source: NSRange
    }

    /// Sorted by rendered location.
    private(set) var entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }

    /// Reads the temporary `.pfSourceRange` attribute into a map and removes it.
    static func extract(from text: NSMutableAttributedString) -> MarkdownSourceMap {
        var entries: [Entry] = []
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.pfSourceRange, in: full) { value, range, _ in
            guard let value = value as? NSValue else { return }
            entries.append(Entry(rendered: range, source: value.rangeValue))
        }
        text.removeAttribute(.pfSourceRange, range: full)
        return MarkdownSourceMap(entries: entries)
    }

    // MARK: Rendered to source

    func sourceRange(forRendered range: NSRange) -> NSRange {
        let start = sourceLocation(forRendered: range.location, preferEnd: false)
        guard range.length > 0 else { return NSRange(location: start, length: 0) }
        let end = max(start, sourceLocation(forRendered: range.upperBound, preferEnd: true))
        return NSRange(location: start, length: end - start)
    }

    /// `preferEnd` picks the entry that ends at `offset` over the one that starts
    /// there, which is what the end of a selection needs.
    func sourceLocation(forRendered offset: Int, preferEnd: Bool) -> Int {
        guard !entries.isEmpty else { return 0 }
        // Last entry that starts before (or at) the offset.
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            let start = entries[mid].rendered.location
            if preferEnd ? start < offset : start <= offset { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return entries[0].source.location }
        let entry = entries[low - 1]
        if offset >= entry.rendered.upperBound {
            return entry.source.upperBound
        }
        return Self.interpolate(offset - entry.rendered.location, from: entry.rendered.length, to: entry.source, preferEnd: preferEnd)
    }

    // MARK: Source to rendered

    func renderedRange(forSource range: NSRange) -> NSRange {
        let start = renderedLocation(forSource: range.location, preferEnd: false)
        guard range.length > 0 else { return NSRange(location: start, length: 0) }
        let end = max(start, renderedLocation(forSource: range.upperBound, preferEnd: true))
        return NSRange(location: start, length: end - start)
    }

    func renderedLocation(forSource offset: Int, preferEnd: Bool) -> Int {
        guard !entries.isEmpty else { return 0 }
        if preferEnd {
            for entry in entries.reversed() where entry.source.location < offset && offset <= entry.source.upperBound {
                return entry.rendered.location + Self.interpolate(offset - entry.source.location, from: entry.source.length, to: NSRange(location: 0, length: entry.rendered.length), preferEnd: true)
            }
            // The offset is in markup that is not shown, such as `**` or `# `.
            if let entry = entries.last(where: { $0.source.upperBound <= offset }) { return entry.rendered.upperBound }
            return entries[0].rendered.location
        }
        for entry in entries {
            let source = entry.source
            if source.location <= offset && (offset < source.upperBound || (source.length == 0 && offset == source.location)) {
                return entry.rendered.location + Self.interpolate(offset - source.location, from: source.length, to: NSRange(location: 0, length: entry.rendered.length), preferEnd: false)
            }
        }
        if let entry = entries.first(where: { $0.source.location >= offset }) { return entry.rendered.location }
        return entries[entries.count - 1].rendered.upperBound
    }

    /// Moves `offset` (within a run of `length`) into `target`. Runs of equal length
    /// map one character to one character. Other runs, such as text with escapes,
    /// map proportionally.
    private static func interpolate(_ offset: Int, from length: Int, to target: NSRange, preferEnd: Bool) -> Int {
        let k = min(max(0, offset), length)
        if length == target.length { return target.location + k }
        if length == 0 { return preferEnd ? target.upperBound : target.location }
        if k == length { return target.upperBound }
        return target.location + Int((Double(k) * Double(target.length) / Double(length)).rounded())
    }
}

/// Lines up two versions of a text that differ in one place (the rich text being
/// edited and the text the source map was built for), using their common prefix and
/// suffix. Offsets in the changed middle snap to its start.
nonisolated struct TextAlignment {
    let prefix: Int
    let suffix: Int
    let fromLength: Int
    let toLength: Int

    init(from: NSString, to: NSString) {
        fromLength = from.length
        toLength = to.length
        let limit = min(fromLength, toLength)
        var p = 0
        while p < limit, from.character(at: p) == to.character(at: p) { p += 1 }
        var s = 0
        while s < limit - p, from.character(at: fromLength - 1 - s) == to.character(at: toLength - 1 - s) { s += 1 }
        prefix = p
        suffix = s
    }

    var isIdentity: Bool { prefix == fromLength && fromLength == toLength }

    func map(_ offset: Int) -> Int {
        if offset <= prefix { return offset }
        if offset >= fromLength - suffix { return offset - fromLength + toLength }
        return prefix
    }

    func map(_ range: NSRange) -> NSRange {
        let start = map(range.location)
        let end = max(start, map(range.upperBound))
        return NSRange(location: start, length: end - start)
    }

    var inverted: TextAlignment {
        TextAlignment(prefix: prefix, suffix: suffix, fromLength: toLength, toLength: fromLength)
    }

    private init(prefix: Int, suffix: Int, fromLength: Int, toLength: Int) {
        self.prefix = prefix
        self.suffix = suffix
        self.fromLength = fromLength
        self.toLength = toLength
    }
}
