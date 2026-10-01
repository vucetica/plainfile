import AppKit

/// Incremental, line-based syntax highlighter attached to an `NSTextStorage`.
///
/// It keeps the scanner state at the end of every line. After an edit, only the
/// edited lines are re-scanned, continuing until the end state of a line matches
/// the state that was previously cached for it.
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {

    var language: Language {
        didSet { if language != oldValue { rehighlightAll() } }
    }
    var theme: EditorTheme
    var font: NSFont {
        didSet { rebuildFontCache(); rehighlightAll() }
    }
    var isEnabled = true

    /// UTF-16 offsets at which each line starts. Always has at least one entry (0).
    private(set) var lineStarts: [Int] = [0]

    private weak var textStorage: NSTextStorage?
    private var lineEndStates: [LineState] = [.unknown]
    private var generation = 0
    private var boldFont: NSFont
    private var italicFont: NSFont

    /// Documents above this many UTF-16 units are not highlighted to keep editing snappy.
    static let maximumHighlightedLength = 6_000_000
    static let maximumLineLength = 20_000
    private static let synchronousLineBudget = 4_000

    init(textStorage: NSTextStorage, language: Language, theme: EditorTheme, font: NSFont) {
        self.language = language
        self.theme = theme
        self.font = font
        self.textStorage = textStorage
        let fm = NSFontManager.shared
        boldFont = fm.convert(font, toHaveTrait: .boldFontMask)
        italicFont = fm.convert(font, toHaveTrait: .italicFontMask)
        super.init()
        textStorage.delegate = self
        rebuildLineStarts()
        lineEndStates = Array(repeating: .unknown, count: lineStarts.count)
    }

    private func rebuildFontCache() {
        let fm = NSFontManager.shared
        boldFont = fm.convert(font, toHaveTrait: .boldFontMask)
        italicFont = fm.convert(font, toHaveTrait: .italicFontMask)
    }

    // MARK: Line index

    private func rebuildLineStarts() {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        var starts = [0]
        let length = ns.length
        var i = 0
        // Scan for "\n" using NSString range search in chunks for speed.
        while i < length {
            let r = ns.range(of: "\n", options: [.literal], range: NSRange(location: i, length: length - i))
            if r.location == NSNotFound { break }
            starts.append(r.location + 1)
            i = r.location + 1
        }
        lineStarts = starts
    }

    /// Index of the line containing the given UTF-16 offset.
    func lineIndex(for offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func lineRange(_ index: Int) -> NSRange {
        let start = lineStarts[index]
        let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : (textStorage?.length ?? start)
        return NSRange(location: start, length: end - start)
    }

    var lineCount: Int { lineStarts.count }

    // MARK: NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let oldLineCount = lineEndStates.count
        rebuildLineStarts()
        let newLineCount = lineStarts.count

        let firstLine = lineIndex(for: editedRange.location)
        var insertedLines = 0
        var idx = firstLine + 1
        while idx < newLineCount, lineStarts[idx] <= editedRange.upperBound {
            insertedLines += 1
            idx += 1
        }
        let removedLines = max(0, oldLineCount - newLineCount + insertedLines)
        let replaceEnd = min(oldLineCount, firstLine + removedLines + 1)
        let replacement = Array(repeating: LineState.unknown, count: insertedLines + 1)
        if firstLine <= oldLineCount {
            lineEndStates.replaceSubrange(firstLine..<replaceEnd, with: replacement)
        }
        if lineEndStates.count != newLineCount {
            // Safety net: sizes drifted, recompute everything.
            lineEndStates = Array(repeating: .unknown, count: newLineCount)
        }
        highlight(fromLine: firstLine, forceThroughLine: firstLine + insertedLines)
    }

    // MARK: Highlighting

    func rehighlightAll() {
        rebuildLineStarts()
        lineEndStates = Array(repeating: .unknown, count: lineStarts.count)
        highlight(fromLine: 0, forceThroughLine: lineStarts.count - 1)
    }

    private func highlight(fromLine: Int, forceThroughLine: Int) {
        guard let storage = textStorage else { return }
        generation &+= 1
        let gen = generation
        if !isEnabled || storage.length > Self.maximumHighlightedLength || language.scanner == .plain {
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes([.font: font, .foregroundColor: theme.text], range: full)
            storage.endEditing()
            lineEndStates = Array(repeating: .initial, count: lineStarts.count)
            return
        }
        let stoppedAt = highlightLines(from: fromLine, forceThroughLine: forceThroughLine, budget: Self.synchronousLineBudget)
        if let stoppedAt {
            scheduleContinuation(from: stoppedAt, forceThroughLine: forceThroughLine, generation: gen)
        }
    }

    private func scheduleContinuation(from line: Int, forceThroughLine: Int, generation gen: Int) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.generation == gen else { return }
            if let next = self.highlightLines(from: line, forceThroughLine: forceThroughLine, budget: Self.synchronousLineBudget) {
                self.scheduleContinuation(from: next, forceThroughLine: forceThroughLine, generation: gen)
            }
        }
    }

    /// Highlights lines starting at `from`. Stops early when the end state converges
    /// with the cached state (past `forceThroughLine`) or when the budget is exhausted.
    /// Returns the next line to process if the budget ran out, or nil when done.
    @discardableResult
    private func highlightLines(from: Int, forceThroughLine: Int, budget: Int) -> Int? {
        guard let storage = textStorage else { return nil }
        let ns = storage.string as NSString
        let total = lineStarts.count
        guard from < total else { return nil }

        var line = from
        var state = from > 0 ? lineEndStates[from - 1] : .initial
        if state == .unknown { state = .initial }
        var processed = 0
        let batchStart = lineStarts[from]
        var batchEnd = batchStart
        var pending: [Token] = []
        var pendingOffsets: [Int] = []

        storage.beginEditing()
        defer { storage.endEditing() }

        func flushBatch() {
            let range = NSRange(location: batchStart, length: batchEnd - batchStart)
            guard range.length > 0 || !pending.isEmpty else { return }
            if range.length > 0 {
                storage.addAttributes([.font: font, .foregroundColor: theme.text], range: range)
            }
            for (token, offset) in zip(pending, pendingOffsets) {
                let r = NSRange(location: offset + token.range.location, length: token.range.length)
                guard r.upperBound <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: theme.color(for: token.kind), range: r)
                if language.scanner == .markdown {
                    let traits = theme.fontTraits(for: token.kind)
                    if traits.contains(.bold) { storage.addAttribute(.font, value: boldFont, range: r) }
                    else if traits.contains(.italic) { storage.addAttribute(.font, value: italicFont, range: r) }
                }
            }
            pending.removeAll(keepingCapacity: true)
            pendingOffsets.removeAll(keepingCapacity: true)
        }

        while line < total {
            let range = lineRange(line)
            let contentLength: Int
            if range.length > 0, ns.character(at: range.upperBound - 1) == 0x0A {
                contentLength = range.length - 1
            } else {
                contentLength = range.length
            }
            let tokens: [Token]
            let endState: LineState
            if contentLength > Self.maximumLineLength {
                tokens = []
                endState = .initial
            } else {
                let chars = Array(ns.substring(with: NSRange(location: range.location, length: contentLength)).utf16)
                (tokens, endState) = LineScanner.scan(chars, state: state, language: language)
            }
            for t in tokens {
                pending.append(t)
                pendingOffsets.append(range.location)
            }
            batchEnd = range.upperBound
            let previous = lineEndStates[line]
            lineEndStates[line] = endState
            state = endState
            processed += 1
            line += 1
            if line > forceThroughLine, previous == endState {
                break
            }
            if processed >= budget {
                flushBatch()
                return line < total ? line : nil
            }
        }
        flushBatch()
        return nil
    }
}
