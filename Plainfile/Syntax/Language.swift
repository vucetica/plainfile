import Foundation

/// The kind of a highlighted token. Colors are assigned by `EditorTheme`.
nonisolated enum TokenKind: Sendable, Hashable {
    case keyword
    case type
    case string
    case comment
    case number
    case literal          // true / false / null / nil
    case preprocessor
    case attribute        // @Annotation, #[derive], decorators
    case function
    case variable         // $var in shell / php / perl
    case key              // JSON / YAML / TOML / CSS property keys
    case tag              // HTML / XML tag names
    case attributeName    // HTML / XML attribute names
    case punctuation
    case heading          // Markdown
    case emphasis         // Markdown *em*
    case strong           // Markdown **strong**
    case codeSpan         // Markdown `code`
    case link             // Markdown [text](url)
    case url
    case listMarker       // Markdown "- ", "1. ", "> "
    case escape
}

nonisolated struct Token: Sendable, Equatable {
    /// UTF-16 range, relative to the start of the scanned line.
    var range: NSRange
    var kind: TokenKind
}

/// Scanner state carried from the end of one line to the start of the next.
/// `mode` values are defined by each scanner; 0 is always "normal".
nonisolated struct LineState: Sendable, Equatable {
    var mode: Int = 0
    var a: Int = 0
    var b: Int = 0

    static let initial = LineState()
    /// Marks a line whose end state has not been computed yet.
    static let unknown = LineState(mode: -1, a: 0, b: 0)
}

nonisolated struct BlockCommentRule: Sendable {
    var start: String
    var end: String
    var nested: Bool = false
}

nonisolated struct StringRule: Sendable {
    var open: String
    var close: String
    /// Backslash escapes the closing delimiter.
    var escape: Bool = true
    /// The string may span multiple lines.
    var multiline: Bool = false
    /// Optional prefixes such as `f`, `r`, `$`, `@` that may precede the opening delimiter.
    var prefixes: [String] = []
    /// If the closing delimiter is not found within this many characters, the
    /// opening delimiter is not treated as a string start (used for char literals).
    var maxLength: Int? = nil
}

nonisolated enum ScannerKind: Sendable {
    case generic
    case plain
    case markdown
    case json
    case yaml
    case html
    case css
}

nonisolated struct Language: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    var extensions: [String] = []
    var fileNames: [String] = []
    var keywords: Set<String> = []
    var types: Set<String> = []
    var literals: Set<String> = []
    var lineComments: [String] = []
    var blockComments: [BlockCommentRule] = []
    var strings: [StringRule] = []
    /// Extra characters allowed inside identifiers (for example `$`).
    var identifierChars: String = ""
    /// Prefixes recognised at the start of a line (after whitespace), e.g. `#` for C.
    var preprocessorPrefixes: [String] = []
    /// Prefixes immediately followed by an identifier, e.g. `@` for annotations.
    var annotationPrefixes: [String] = []
    /// Prefixes immediately followed by an identifier, e.g. `$` for shell variables.
    var variablePrefixes: [String] = []
    var caseInsensitiveKeywords = false
    /// Treat identifiers that start with an uppercase letter as types.
    var uppercaseIdentifiersAreTypes = false
    var scanner: ScannerKind = .generic

    static func == (lhs: Language, rhs: Language) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var isMarkdown: Bool { scanner == .markdown }
    var isDelimited: Bool { id == "csv" || id == "tsv" }
}
