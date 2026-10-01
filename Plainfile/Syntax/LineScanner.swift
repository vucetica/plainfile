import Foundation

/// Tokenizes a single line of text given the state at the end of the previous line.
/// All scanners operate on UTF-16 code units so token ranges map directly to `NSRange`.
nonisolated enum LineScanner {

    static func scan(_ line: [UInt16], state: LineState, language: Language) -> ([Token], LineState) {
        switch language.scanner {
        case .plain:    return ([], .initial)
        case .generic:  return GenericScanner(line: line, language: language).scan(state: state)
        case .markdown: return MarkdownScanner.scan(line, state: state)
        case .json:     return JSONScanner.scan(line, state: state)
        case .yaml:     return YAMLScanner.scan(line, state: state)
        case .html:     return HTMLScanner.scan(line, state: state)
        case .css:      return CSSScanner.scan(line, state: state)
        }
    }
}

// MARK: - Character helpers

nonisolated enum Chars {
    static let space: UInt16 = 0x20, tab: UInt16 = 0x09, cr: UInt16 = 0x0D, nl: UInt16 = 0x0A
    static let underscore: UInt16 = 0x5F, dollar: UInt16 = 0x24, at: UInt16 = 0x40, hash: UInt16 = 0x23
    static let dot: UInt16 = 0x2E, backslash: UInt16 = 0x5C, quote: UInt16 = 0x22, apostrophe: UInt16 = 0x27
    static let lparen: UInt16 = 0x28, rparen: UInt16 = 0x29, lbrace: UInt16 = 0x7B, rbrace: UInt16 = 0x7D
    static let lbracket: UInt16 = 0x5B, rbracket: UInt16 = 0x5D, colon: UInt16 = 0x3A, comma: UInt16 = 0x2C
    static let lt: UInt16 = 0x3C, gt: UInt16 = 0x3E, slash: UInt16 = 0x2F, minus: UInt16 = 0x2D, plus: UInt16 = 0x2B
    static let star: UInt16 = 0x2A, equals: UInt16 = 0x3D, exclaim: UInt16 = 0x21, question: UInt16 = 0x3F
    static let pipe: UInt16 = 0x7C, backtick: UInt16 = 0x60, tilde: UInt16 = 0x7E, amp: UInt16 = 0x26
    static let semicolon: UInt16 = 0x3B, percent: UInt16 = 0x25, caret: UInt16 = 0x5E

    @inline(__always) static func isSpace(_ c: UInt16) -> Bool { c == space || c == tab || c == cr || c == nl }
    @inline(__always) static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    @inline(__always) static func isUpper(_ c: UInt16) -> Bool { c >= 0x41 && c <= 0x5A }
    @inline(__always) static func isLower(_ c: UInt16) -> Bool { c >= 0x61 && c <= 0x7A }
    @inline(__always) static func isAlpha(_ c: UInt16) -> Bool { isUpper(c) || isLower(c) }
    @inline(__always) static func isHex(_ c: UInt16) -> Bool { isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66) }
    @inline(__always) static func isIdentStart(_ c: UInt16) -> Bool { isAlpha(c) || c == underscore || c > 127 }
    @inline(__always) static func isIdentChar(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }

    static func utf16(_ s: String) -> [UInt16] { Array(s.utf16) }

    @inline(__always) static func matches(_ line: [UInt16], at i: Int, _ pattern: [UInt16]) -> Bool {
        guard !pattern.isEmpty, i + pattern.count <= line.count else { return false }
        for k in 0..<pattern.count where line[i + k] != pattern[k] { return false }
        return true
    }

    static func string(_ line: [UInt16], _ range: Range<Int>) -> String {
        String(utf16CodeUnits: Array(line[range]), count: range.count)
    }
}

// MARK: - Generic scanner (C-like and most languages)

nonisolated struct GenericScanner {
    let line: [UInt16]
    let language: Language

    // Pre-encoded rules
    private let lineComments: [[UInt16]]
    private let blockComments: [(start: [UInt16], end: [UInt16], nested: Bool)]
    private let strings: [(rule: StringRule, prefixes: [[UInt16]], open: [UInt16], close: [UInt16])]
    private let preprocessor: [[UInt16]]
    private let annotations: [[UInt16]]
    private let variables: [[UInt16]]
    private let identExtra: Set<UInt16>

    init(line: [UInt16], language: Language) {
        self.line = line
        self.language = language
        lineComments = language.lineComments.map(Chars.utf16)
        blockComments = language.blockComments.map { (Chars.utf16($0.start), Chars.utf16($0.end), $0.nested) }
        strings = language.strings
            .sorted { $0.open.count > $1.open.count }
            .map { ($0, $0.prefixes.map(Chars.utf16), Chars.utf16($0.open), Chars.utf16($0.close)) }
        preprocessor = language.preprocessorPrefixes.map(Chars.utf16)
        annotations = language.annotationPrefixes.map(Chars.utf16)
        variables = language.variablePrefixes.map(Chars.utf16)
        identExtra = Set(language.identifierChars.utf16)
    }

    private static let modeBlockComment = 1
    private static let modeString = 2

    func scan(state: LineState) -> ([Token], LineState) {
        var tokens: [Token] = []
        var i = 0
        let n = line.count
        var atLineStart = true

        // Resume multi-line constructs.
        if state.mode == Self.modeBlockComment, state.a < blockComments.count {
            let rule = blockComments[state.a]
            var depth = max(1, state.b)
            let end = scanBlockCommentBody(from: 0, end: rule.end, start: rule.start, nested: rule.nested, depth: &depth)
            if let end {
                tokens.append(Token(range: NSRange(location: 0, length: end), kind: .comment))
                i = end
                atLineStart = false
            } else {
                tokens.append(Token(range: NSRange(location: 0, length: n), kind: .comment))
                return (tokens, LineState(mode: Self.modeBlockComment, a: state.a, b: depth))
            }
        } else if state.mode == Self.modeString, state.a < strings.count {
            let s = strings[state.a]
            if let end = scanStringBody(from: 0, close: s.close, escape: s.rule.escape) {
                tokens.append(Token(range: NSRange(location: 0, length: end), kind: .string))
                i = end
                atLineStart = false
            } else {
                tokens.append(Token(range: NSRange(location: 0, length: n), kind: .string))
                return (tokens, state)
            }
        }

        while i < n {
            let c = line[i]
            if Chars.isSpace(c) { i += 1; continue }

            // Preprocessor directives at line start.
            if atLineStart {
                var matched = false
                for p in preprocessor where Chars.matches(line, at: i, p) {
                    var j = i + p.count
                    while j < n, Chars.isSpace(line[j]) { j += 1 }
                    while j < n, Chars.isIdentChar(line[j]) { j += 1 }
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .preprocessor))
                    i = j
                    matched = true
                    break
                }
                atLineStart = false
                if matched { continue }
            }
            atLineStart = false

            // Line comments.
            var handled = false
            for lc in lineComments where Chars.matches(line, at: i, lc) {
                tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                return (tokens, .initial)
            }

            // Block comments.
            for (idx, rule) in blockComments.enumerated() where Chars.matches(line, at: i, rule.start) {
                var depth = 1
                let bodyStart = i + rule.start.count
                if let end = scanBlockCommentBody(from: bodyStart, end: rule.end, start: rule.start, nested: rule.nested, depth: &depth) {
                    tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .comment))
                    i = end
                } else {
                    tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                    return (tokens, LineState(mode: Self.modeBlockComment, a: idx, b: depth))
                }
                handled = true
                break
            }
            if handled { continue }

            // Strings (with optional prefixes).
            for (idx, s) in strings.enumerated() {
                var start = -1
                if Chars.matches(line, at: i, s.open) {
                    start = i + s.open.count
                } else {
                    for p in s.prefixes where Chars.matches(line, at: i, p) && Chars.matches(line, at: i + p.count, s.open) {
                        start = i + p.count + s.open.count
                        break
                    }
                }
                guard start >= 0 else { continue }
                if let end = scanStringBody(from: start, close: s.close, escape: s.rule.escape) {
                    if let maxLen = s.rule.maxLength, end - i > maxLen { continue }
                    tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .string))
                    i = end
                } else if s.rule.maxLength != nil {
                    continue
                } else if s.rule.multiline {
                    tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .string))
                    return (tokens, LineState(mode: Self.modeString, a: idx, b: 0))
                } else {
                    tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .string))
                    return (tokens, .initial)
                }
                handled = true
                break
            }
            if handled { continue }

            // Numbers.
            if Chars.isDigit(c) || (c == Chars.dot && i + 1 < n && Chars.isDigit(line[i + 1])) {
                let end = scanNumber(from: i)
                tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .number))
                i = end
                continue
            }

            // Annotations and variables: prefix + identifier.
            for a in annotations where Chars.matches(line, at: i, a) {
                let start = i + a.count
                if start < n, Chars.isIdentStart(line[start]) {
                    var j = start
                    while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.dot { j += 1 }
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .attribute))
                    i = j
                    handled = true
                    break
                }
            }
            if handled { continue }
            for v in variables where Chars.matches(line, at: i, v) {
                let start = i + v.count
                var j = start
                if j < n, line[j] == Chars.lbrace {
                    while j < n, line[j] != Chars.rbrace { j += 1 }
                    if j < n { j += 1 }
                } else if j < n, Chars.isIdentStart(line[j]) || Chars.isDigit(line[j]) {
                    while j < n, Chars.isIdentChar(line[j]) { j += 1 }
                } else if j < n, "@#?!*-".utf16.contains(line[j]) {
                    j += 1
                } else {
                    continue
                }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .variable))
                i = j
                handled = true
                break
            }
            if handled { continue }

            // Identifiers and keywords.
            if Chars.isIdentStart(c) || identExtra.contains(c) {
                var j = i + 1
                while j < n, Chars.isIdentChar(line[j]) || identExtra.contains(line[j]) { j += 1 }
                let word = Chars.string(line, i..<j)
                let lookup = language.caseInsensitiveKeywords ? word.lowercased() : word
                let kind: TokenKind?
                if language.keywords.contains(lookup) {
                    kind = .keyword
                } else if language.literals.contains(lookup) {
                    kind = .literal
                } else if language.types.contains(word) {
                    kind = .type
                } else {
                    var k = j
                    while k < n, line[k] == Chars.space { k += 1 }
                    if k < n, line[k] == Chars.lparen {
                        kind = .function
                    } else if language.uppercaseIdentifiersAreTypes, Chars.isUpper(c) {
                        kind = .type
                    } else {
                        kind = nil
                    }
                }
                if let kind { tokens.append(Token(range: NSRange(location: i, length: j - i), kind: kind)) }
                i = j
                continue
            }

            i += 1
        }
        return (tokens, .initial)
    }

    /// Returns the index just past the closing delimiter, or nil if the line ended first.
    private func scanBlockCommentBody(from: Int, end: [UInt16], start: [UInt16], nested: Bool, depth: inout Int) -> Int? {
        var i = from
        while i < line.count {
            if nested, Chars.matches(line, at: i, start) {
                depth += 1
                i += start.count
                continue
            }
            if Chars.matches(line, at: i, end) {
                depth -= 1
                i += end.count
                if depth <= 0 { return i }
                continue
            }
            i += 1
        }
        return nil
    }

    private func scanStringBody(from: Int, close: [UInt16], escape: Bool) -> Int? {
        var i = from
        while i < line.count {
            if escape, line[i] == Chars.backslash {
                i += 2
                continue
            }
            if Chars.matches(line, at: i, close) { return i + close.count }
            i += 1
        }
        return nil
    }

    private func scanNumber(from: Int) -> Int {
        var i = from
        let n = line.count
        if line[i] == 0x30, i + 1 < n, "xXbBoO".utf16.contains(line[i + 1]) {
            i += 2
            while i < n, Chars.isHex(line[i]) || line[i] == Chars.underscore { i += 1 }
            while i < n, Chars.isAlpha(line[i]) { i += 1 }
            return i
        }
        while i < n, Chars.isDigit(line[i]) || line[i] == Chars.underscore { i += 1 }
        if i < n, line[i] == Chars.dot, i + 1 < n, Chars.isDigit(line[i + 1]) {
            i += 1
            while i < n, Chars.isDigit(line[i]) || line[i] == Chars.underscore { i += 1 }
        }
        if i < n, line[i] == 0x65 || line[i] == 0x45 { // e / E
            var j = i + 1
            if j < n, line[j] == Chars.plus || line[j] == Chars.minus { j += 1 }
            if j < n, Chars.isDigit(line[j]) {
                i = j
                while i < n, Chars.isDigit(line[i]) { i += 1 }
            }
        }
        while i < n, Chars.isAlpha(line[i]) { i += 1 } // suffixes: f, L, u, n, ...
        return i
    }
}

// MARK: - JSON

nonisolated enum JSONScanner {
    static func scan(_ line: [UInt16], state: LineState) -> ([Token], LineState) {
        var tokens: [Token] = []
        var i = 0
        let n = line.count
        while i < n {
            let c = line[i]
            if Chars.isSpace(c) { i += 1; continue }
            if c == Chars.quote {
                var j = i + 1
                while j < n {
                    if line[j] == Chars.backslash { j += 2; continue }
                    if line[j] == Chars.quote { break }
                    j += 1
                }
                let end = min(j + 1, n)
                var k = end
                while k < n, Chars.isSpace(line[k]) { k += 1 }
                let isKey = k < n && line[k] == Chars.colon
                tokens.append(Token(range: NSRange(location: i, length: end - i), kind: isKey ? .key : .string))
                i = end
                continue
            }
            if Chars.matches(line, at: i, Chars.utf16("//")) {
                tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                return (tokens, .initial)
            }
            if Chars.isDigit(c) || c == Chars.minus {
                var j = i + 1
                while j < n, Chars.isDigit(line[j]) || line[j] == Chars.dot || line[j] == 0x65 || line[j] == 0x45 || line[j] == Chars.plus || line[j] == Chars.minus { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .number))
                i = j
                continue
            }
            if Chars.isAlpha(c) {
                var j = i + 1
                while j < n, Chars.isAlpha(line[j]) { j += 1 }
                let word = Chars.string(line, i..<j)
                if ["true", "false", "null"].contains(word) {
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .literal))
                }
                i = j
                continue
            }
            if "{}[]:,".utf16.contains(c) {
                tokens.append(Token(range: NSRange(location: i, length: 1), kind: .punctuation))
            }
            i += 1
        }
        return (tokens, .initial)
    }
}

// MARK: - YAML

nonisolated enum YAMLScanner {
    private static let modeBlockScalar = 9

    static func scan(_ line: [UInt16], state: LineState) -> ([Token], LineState) {
        var tokens: [Token] = []
        let n = line.count
        var indent = 0
        while indent < n, line[indent] == Chars.space { indent += 1 }
        let blank = indent == n

        if state.mode == modeBlockScalar {
            if blank { return ([], state) }
            if indent > state.a {
                tokens.append(Token(range: NSRange(location: indent, length: n - indent), kind: .string))
                return (tokens, state)
            }
        }

        var i = indent
        // Document markers.
        if Chars.matches(line, at: 0, Chars.utf16("---")) || Chars.matches(line, at: 0, Chars.utf16("...")) {
            tokens.append(Token(range: NSRange(location: 0, length: 3), kind: .punctuation))
            i = 3
        }
        // List item marker.
        if i < n, line[i] == Chars.minus, (i + 1 == n || Chars.isSpace(line[i + 1])) {
            tokens.append(Token(range: NSRange(location: i, length: 1), kind: .punctuation))
            i += 1
            while i < n, line[i] == Chars.space { i += 1 }
        }
        // Key detection: scan for ":" followed by space or end, before any quote/comment.
        var keyEnd = -1
        var scanKey = i
        if scanKey < n, line[scanKey] == Chars.quote || line[scanKey] == Chars.apostrophe {
            let q = line[scanKey]
            var j = scanKey + 1
            while j < n, line[j] != q { j += 1 }
            var k = j + 1
            while k < n, line[k] == Chars.space { k += 1 }
            if k < n, line[k] == Chars.colon, (k + 1 == n || Chars.isSpace(line[k + 1])) { keyEnd = j + 1; scanKey = k }
        } else {
            var j = scanKey
            while j < n {
                let c = line[j]
                if c == Chars.hash, j > 0, Chars.isSpace(line[j - 1]) { break }
                if c == Chars.colon, (j + 1 == n || Chars.isSpace(line[j + 1])) {
                    keyEnd = j
                    scanKey = j
                    break
                }
                if c == Chars.quote || c == Chars.apostrophe || c == Chars.lbrace || c == Chars.lbracket { break }
                j += 1
            }
        }
        if keyEnd > i {
            tokens.append(Token(range: NSRange(location: i, length: keyEnd - i), kind: .key))
            tokens.append(Token(range: NSRange(location: scanKey, length: 1), kind: .punctuation))
            i = scanKey + 1
        }

        var nextState = LineState.initial
        while i < n {
            let c = line[i]
            if Chars.isSpace(c) { i += 1; continue }
            if c == Chars.hash, i == 0 || Chars.isSpace(line[i - 1]) {
                tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                break
            }
            if c == Chars.quote || c == Chars.apostrophe {
                var j = i + 1
                while j < n {
                    if c == Chars.quote, line[j] == Chars.backslash { j += 2; continue }
                    if line[j] == c { break }
                    j += 1
                }
                let end = min(j + 1, n)
                tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .string))
                i = end
                continue
            }
            if (c == Chars.pipe || c == Chars.gt) {
                var j = i + 1
                while j < n, line[j] == Chars.minus || line[j] == Chars.plus || Chars.isDigit(line[j]) { j += 1 }
                var k = j
                while k < n, line[k] == Chars.space { k += 1 }
                if k == n || line[k] == Chars.hash {
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .punctuation))
                    nextState = LineState(mode: modeBlockScalar, a: indent, b: 0)
                    i = j
                    continue
                }
            }
            if c == Chars.amp || c == Chars.star || c == Chars.exclaim {
                var j = i + 1
                while j < n, !Chars.isSpace(line[j]), line[j] != Chars.comma, line[j] != Chars.rbracket, line[j] != Chars.rbrace { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .attribute))
                i = j
                continue
            }
            if Chars.isDigit(c) || ((c == Chars.minus || c == Chars.plus) && i + 1 < n && Chars.isDigit(line[i + 1])) {
                var j = i + 1
                while j < n, Chars.isDigit(line[j]) || line[j] == Chars.dot || line[j] == Chars.underscore || line[j] == Chars.minus || line[j] == Chars.colon || line[j] == 0x65 || line[j] == 0x45 || line[j] == 0x54 || line[j] == 0x5A { j += 1 }
                if j == n || Chars.isSpace(line[j]) || line[j] == Chars.comma || line[j] == Chars.rbracket || line[j] == Chars.rbrace {
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .number))
                    i = j
                    continue
                }
                i = j
                continue
            }
            if Chars.isAlpha(c) {
                var j = i + 1
                while j < n, Chars.isIdentChar(line[j]) { j += 1 }
                let word = Chars.string(line, i..<j).lowercased()
                if ["true", "false", "null", "yes", "no", "on", "off", "~"].contains(word) {
                    var k = j
                    while k < n, line[k] == Chars.space { k += 1 }
                    if k == n || line[k] == Chars.hash || line[k] == Chars.comma || line[k] == Chars.rbracket || line[k] == Chars.rbrace {
                        tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .literal))
                    }
                }
                i = j
                continue
            }
            if "{}[],".utf16.contains(c) {
                tokens.append(Token(range: NSRange(location: i, length: 1), kind: .punctuation))
            }
            i += 1
        }
        return (tokens, nextState)
    }
}

// MARK: - HTML / XML

nonisolated enum HTMLScanner {
    private static let modeComment = 4
    private static let modeTag = 5
    private static let modeScript = 6

    static func scan(_ line: [UInt16], state: LineState) -> ([Token], LineState) {
        var tokens: [Token] = []
        var i = 0
        let n = line.count
        var st = state
        let commentEnd = Chars.utf16("-->")
        let commentStart = Chars.utf16("<!--")

        while i < n {
            switch st.mode {
            case modeComment:
                var j = i
                while j < n, !Chars.matches(line, at: j, commentEnd) { j += 1 }
                if j < n {
                    tokens.append(Token(range: NSRange(location: i, length: j + 3 - i), kind: .comment))
                    i = j + 3
                    st = .initial
                } else {
                    tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                    return (tokens, st)
                }
            case modeTag:
                // Inside a tag: attributes and values until ">"
                let c = line[i]
                if Chars.isSpace(c) { i += 1; continue }
                if c == Chars.gt || (c == Chars.slash && i + 1 < n && line[i + 1] == Chars.gt) || (c == Chars.question && i + 1 < n && line[i + 1] == Chars.gt) {
                    let len = c == Chars.gt ? 1 : 2
                    tokens.append(Token(range: NSRange(location: i, length: len), kind: .tag))
                    i += len
                    st = st.a == 1 ? LineState(mode: modeScript, a: 0, b: 0) : .initial
                    continue
                }
                if c == Chars.quote || c == Chars.apostrophe {
                    var j = i + 1
                    while j < n, line[j] != c { j += 1 }
                    let end = min(j + 1, n)
                    tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .string))
                    i = end
                    continue
                }
                if c == Chars.equals {
                    tokens.append(Token(range: NSRange(location: i, length: 1), kind: .punctuation))
                    i += 1
                    continue
                }
                if Chars.isIdentStart(c) || c == Chars.minus || c == Chars.colon || c == Chars.at {
                    var j = i + 1
                    while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus || line[j] == Chars.colon || line[j] == Chars.dot { j += 1 }
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .attributeName))
                    i = j
                    continue
                }
                i += 1
            case modeScript:
                // Inside <script> or <style>: look only for the closing tag.
                var j = i
                var found = false
                while j < n {
                    if line[j] == Chars.lt, j + 1 < n, line[j + 1] == Chars.slash {
                        let rest = Chars.string(line, j..<min(n, j + 9)).lowercased()
                        if rest.hasPrefix("</script") || rest.hasPrefix("</style") { found = true; break }
                    }
                    j += 1
                }
                if found {
                    i = j
                    st = .initial
                } else {
                    return (tokens, st)
                }
            default:
                let c = line[i]
                if c == Chars.lt {
                    if Chars.matches(line, at: i, commentStart) {
                        st = LineState(mode: modeComment, a: 0, b: 0)
                        continue
                    }
                    var j = i + 1
                    if j < n, line[j] == Chars.slash || line[j] == Chars.exclaim || line[j] == Chars.question { j += 1 }
                    let nameStart = j
                    while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus || line[j] == Chars.colon || line[j] == Chars.dot { j += 1 }
                    if j > nameStart {
                        tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .tag))
                        let name = Chars.string(line, nameStart..<j).lowercased()
                        let isOpening = line[i + 1] != Chars.slash
                        let raw = isOpening && (name == "script" || name == "style")
                        st = LineState(mode: modeTag, a: raw ? 1 : 0, b: 0)
                        i = j
                        continue
                    }
                    i += 1
                    continue
                }
                if c == Chars.amp {
                    var j = i + 1
                    while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.hash { j += 1 }
                    if j < n, line[j] == Chars.semicolon {
                        tokens.append(Token(range: NSRange(location: i, length: j + 1 - i), kind: .escape))
                        i = j + 1
                        continue
                    }
                }
                i += 1
            }
        }
        return (tokens, st)
    }
}

// MARK: - CSS / SCSS

nonisolated enum CSSScanner {
    private static let modeInBlock = 8
    private static let modeComment = 1

    static func scan(_ line: [UInt16], state: LineState) -> ([Token], LineState) {
        var tokens: [Token] = []
        var i = 0
        let n = line.count
        var inBlock = state.mode == modeInBlock || (state.mode == modeComment && state.b == 1)
        let commentEnd = Chars.utf16("*/")

        if state.mode == modeComment {
            var j = 0
            while j < n, !Chars.matches(line, at: j, commentEnd) { j += 1 }
            if j < n {
                tokens.append(Token(range: NSRange(location: 0, length: j + 2), kind: .comment))
                i = j + 2
            } else {
                tokens.append(Token(range: NSRange(location: 0, length: n), kind: .comment))
                return (tokens, state)
            }
        }

        while i < n {
            let c = line[i]
            if Chars.isSpace(c) { i += 1; continue }
            if c == Chars.slash, i + 1 < n, line[i + 1] == Chars.star {
                var j = i + 2
                while j < n, !Chars.matches(line, at: j, commentEnd) { j += 1 }
                if j < n {
                    tokens.append(Token(range: NSRange(location: i, length: j + 2 - i), kind: .comment))
                    i = j + 2
                } else {
                    tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                    return (tokens, LineState(mode: modeComment, a: 0, b: inBlock ? 1 : 0))
                }
                continue
            }
            if c == Chars.slash, i + 1 < n, line[i + 1] == Chars.slash {
                tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                break
            }
            if c == Chars.lbrace { inBlock = true; tokens.append(Token(range: NSRange(location: i, length: 1), kind: .punctuation)); i += 1; continue }
            if c == Chars.rbrace { inBlock = false; tokens.append(Token(range: NSRange(location: i, length: 1), kind: .punctuation)); i += 1; continue }
            if c == Chars.quote || c == Chars.apostrophe {
                var j = i + 1
                while j < n {
                    if line[j] == Chars.backslash { j += 2; continue }
                    if line[j] == c { break }
                    j += 1
                }
                let end = min(j + 1, n)
                tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .string))
                i = end
                continue
            }
            if c == Chars.at {
                var j = i + 1
                while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .keyword))
                i = j
                continue
            }
            if c == Chars.dollar {
                var j = i + 1
                while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .variable))
                i = j
                continue
            }
            if c == Chars.hash, inBlock {
                var j = i + 1
                while j < n, Chars.isHex(line[j]) { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .number))
                i = j
                continue
            }
            if Chars.isDigit(c) || (c == Chars.dot && i + 1 < n && Chars.isDigit(line[i + 1])) || (c == Chars.minus && i + 1 < n && Chars.isDigit(line[i + 1]) && inBlock) {
                var j = i + 1
                while j < n, Chars.isDigit(line[j]) || line[j] == Chars.dot { j += 1 }
                while j < n, Chars.isAlpha(line[j]) || line[j] == Chars.percent { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .number))
                i = j
                continue
            }
            if Chars.isIdentStart(c) || c == Chars.minus {
                var j = i + 1
                while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus { j += 1 }
                if inBlock {
                    var k = j
                    while k < n, line[k] == Chars.space { k += 1 }
                    if k < n, line[k] == Chars.colon {
                        tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .key))
                    } else if k < n, line[k] == Chars.lparen {
                        tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .function))
                    }
                } else {
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .tag))
                }
                i = j
                continue
            }
            if c == Chars.dot || c == Chars.hash, !inBlock {
                var j = i + 1
                while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .type))
                i = j
                continue
            }
            if c == Chars.colon, !inBlock {
                var j = i + 1
                while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus || line[j] == Chars.colon { j += 1 }
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .attribute))
                i = j
                continue
            }
            i += 1
        }
        return (tokens, inBlock ? LineState(mode: modeInBlock, a: 0, b: 0) : .initial)
    }
}

// MARK: - Markdown

nonisolated enum MarkdownScanner {
    private static let modeFence = 3

    static func scan(_ line: [UInt16], state: LineState) -> ([Token], LineState) {
        var tokens: [Token] = []
        let n = line.count
        var indent = 0
        while indent < n, line[indent] == Chars.space || line[indent] == Chars.tab { indent += 1 }

        // Fenced code blocks.
        if state.mode == modeFence {
            let fenceChar = UInt16(state.a)
            var j = indent
            while j < n, line[j] == fenceChar { j += 1 }
            var rest = j
            while rest < n, Chars.isSpace(line[rest]) { rest += 1 }
            if j - indent >= state.b, rest == n {
                tokens.append(Token(range: NSRange(location: indent, length: j - indent), kind: .punctuation))
                return (tokens, .initial)
            }
            if n > 0 { tokens.append(Token(range: NSRange(location: 0, length: n), kind: .codeSpan)) }
            return (tokens, state)
        }
        if indent < n, line[indent] == Chars.backtick || line[indent] == Chars.tilde {
            let fc = line[indent]
            var j = indent
            while j < n, line[j] == fc { j += 1 }
            if j - indent >= 3 {
                tokens.append(Token(range: NSRange(location: indent, length: j - indent), kind: .punctuation))
                if j < n { tokens.append(Token(range: NSRange(location: j, length: n - j), kind: .type)) }
                return (tokens, LineState(mode: modeFence, a: Int(fc), b: j - indent))
            }
        }

        var i = indent
        // Headings.
        if i < n, line[i] == Chars.hash {
            var j = i
            while j < n, line[j] == Chars.hash { j += 1 }
            if j - i <= 6, j == n || Chars.isSpace(line[j]) {
                tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .heading))
                return (tokens, .initial)
            }
        }
        // Thematic breaks.
        if i < n, line[i] == Chars.minus || line[i] == Chars.star || line[i] == Chars.underscore {
            var count = 0
            var j = i
            var onlyMarker = true
            while j < n {
                if line[j] == line[i] { count += 1 } else if !Chars.isSpace(line[j]) { onlyMarker = false; break }
                j += 1
            }
            if onlyMarker, count >= 3 {
                tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .punctuation))
                return (tokens, .initial)
            }
        }
        // Block quotes and list markers (can repeat / nest).
        var progressed = true
        while progressed, i < n {
            progressed = false
            if line[i] == Chars.gt {
                tokens.append(Token(range: NSRange(location: i, length: 1), kind: .listMarker))
                i += 1
                while i < n, line[i] == Chars.space { i += 1 }
                progressed = true
                continue
            }
            if (line[i] == Chars.minus || line[i] == Chars.plus || line[i] == Chars.star), i + 1 < n, Chars.isSpace(line[i + 1]) {
                tokens.append(Token(range: NSRange(location: i, length: 1), kind: .listMarker))
                i += 2
                // Task list checkbox.
                if i + 2 < n, line[i] == Chars.lbracket, line[i + 2] == Chars.rbracket, (line[i + 1] == Chars.space || line[i + 1] == 0x78 || line[i + 1] == 0x58) {
                    tokens.append(Token(range: NSRange(location: i, length: 3), kind: .listMarker))
                    i += 3
                }
                while i < n, line[i] == Chars.space { i += 1 }
                progressed = true
                continue
            }
            if Chars.isDigit(line[i]) {
                var j = i
                while j < n, Chars.isDigit(line[j]) { j += 1 }
                if j < n, line[j] == Chars.dot || line[j] == Chars.rparen, j + 1 < n, Chars.isSpace(line[j + 1]) {
                    tokens.append(Token(range: NSRange(location: i, length: j + 1 - i), kind: .listMarker))
                    i = j + 2
                    while i < n, line[i] == Chars.space { i += 1 }
                    progressed = true
                    continue
                }
            }
        }

        // Table rows: highlight pipes.
        // Inline content.
        while i < n {
            let c = line[i]
            if c == Chars.backslash, i + 1 < n {
                tokens.append(Token(range: NSRange(location: i, length: 2), kind: .escape))
                i += 2
                continue
            }
            if c == Chars.backtick {
                var open = i
                while open < n, line[open] == Chars.backtick { open += 1 }
                let count = open - i
                var j = open
                var closed = -1
                while j < n {
                    if line[j] == Chars.backtick {
                        var k = j
                        while k < n, line[k] == Chars.backtick { k += 1 }
                        if k - j == count { closed = k; break }
                        j = k
                        continue
                    }
                    j += 1
                }
                if closed > 0 {
                    tokens.append(Token(range: NSRange(location: i, length: closed - i), kind: .codeSpan))
                    i = closed
                } else {
                    i = open
                }
                continue
            }
            if c == Chars.star || c == Chars.underscore {
                let marker = c
                var open = i
                while open < n, line[open] == marker { open += 1 }
                let count = min(open - i, 2)
                if open < n, !Chars.isSpace(line[open]) {
                    let closeSeq = Array(repeating: marker, count: count)
                    var j = open
                    var closed = -1
                    while j < n {
                        if Chars.matches(line, at: j, closeSeq), !Chars.isSpace(line[j - 1]) {
                            closed = j + count
                            break
                        }
                        j += 1
                    }
                    if closed > 0 {
                        tokens.append(Token(range: NSRange(location: i, length: closed - i), kind: count == 2 ? .strong : .emphasis))
                        i = closed
                        continue
                    }
                }
                i = open
                continue
            }
            if c == Chars.tilde, i + 1 < n, line[i + 1] == Chars.tilde {
                var j = i + 2
                var closed = -1
                while j + 1 < n {
                    if line[j] == Chars.tilde, line[j + 1] == Chars.tilde { closed = j + 2; break }
                    j += 1
                }
                if closed > 0 {
                    tokens.append(Token(range: NSRange(location: i, length: closed - i), kind: .emphasis))
                    i = closed
                    continue
                }
                i += 2
                continue
            }
            if c == Chars.exclaim, i + 1 < n, line[i + 1] == Chars.lbracket {
                i += 1
                continue
            }
            if c == Chars.lbracket {
                var j = i + 1
                var depth = 1
                while j < n, depth > 0 {
                    if line[j] == Chars.lbracket { depth += 1 } else if line[j] == Chars.rbracket { depth -= 1 }
                    j += 1
                }
                if depth == 0, j < n, line[j] == Chars.lparen {
                    var k = j + 1
                    while k < n, line[k] != Chars.rparen { k += 1 }
                    if k < n {
                        let start = (i > 0 && line[i - 1] == Chars.exclaim) ? i - 1 : i
                        tokens.append(Token(range: NSRange(location: start, length: j - start), kind: .link))
                        tokens.append(Token(range: NSRange(location: j, length: k + 1 - j), kind: .url))
                        i = k + 1
                        continue
                    }
                }
                i += 1
                continue
            }
            if c == Chars.lt {
                var j = i + 1
                if j < n, line[j] == Chars.slash { j += 1 }
                let nameStart = j
                while j < n, Chars.isIdentChar(line[j]) || line[j] == Chars.minus { j += 1 }
                if j > nameStart {
                    var k = j
                    while k < n, line[k] != Chars.gt { k += 1 }
                    if k < n {
                        tokens.append(Token(range: NSRange(location: i, length: k + 1 - i), kind: .tag))
                        i = k + 1
                        continue
                    }
                }
                i += 1
                continue
            }
            if c == Chars.pipe {
                tokens.append(Token(range: NSRange(location: i, length: 1), kind: .punctuation))
                i += 1
                continue
            }
            i += 1
        }
        return (tokens, .initial)
    }
}
