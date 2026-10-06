import SwiftUI
import UniformTypeIdentifiers
import Combine
import Synchronization

nonisolated enum LineEnding: String, Sendable, CaseIterable, Identifiable {
    case lf = "LF"
    case crlf = "CRLF"
    case cr = "CR"

    var id: String { rawValue }
    var string: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    static func detect(in text: String) -> LineEnding {
        var sawCR = false
        for scalar in text.unicodeScalars {
            if scalar == "\r" {
                sawCR = true
            } else if scalar == "\n" {
                return sawCR ? .crlf : .lf
            } else if sawCR {
                return .cr
            }
        }
        return sawCR ? .cr : .lf
    }
}

/// How the document is currently being viewed.
enum ViewMode: String, Sendable, CaseIterable, Identifiable {
    case source
    case rich
    case table
    var id: String { rawValue }
}

/// Immutable data handed to the background writer.
nonisolated struct DocumentSnapshot: Sendable {
    var text: String
    var encoding: UInt
    var lineEnding: LineEnding
}

/// Live editor status shown in the status bar. Kept separate from the document so
/// cursor movement does not republish the whole document.
@Observable
final class EditorStatus {
    var line = 1
    var column = 1
    var selectionLength = 0
    /// Selection start measured in UTF-16 units from the start of the text.
    var location = 0
    var lines = 1
    var characters = 0
    var words = 0

    nonisolated init() {}
}

@MainActor
final class PlainDocument: ReferenceFileDocument {

    nonisolated static let readableContentTypes: [UTType] = [.text, .plainText, .sourceCode, .data]
    nonisolated static let writableContentTypes: [UTType] = [.plainText]

    // MARK: State
    //
    // State lives in a plain struct behind a lock. SwiftUI reads files and takes
    // save snapshots on background threads, so `init(configuration:)` and
    // `snapshot(contentType:)` are nonisolated. The computed properties publish
    // changes through `objectWillChange` like `@Published` would.

    nonisolated struct State: Sendable {
        var text: String
        var textVersion: Int = 0
        var language: Language
        var delimiter: Character
        var hasHeaderRow: Bool
        var encoding: String.Encoding
        var lineEnding: LineEnding
    }

    private let state: Mutex<State>

    private func read<T>(_ body: (State) -> T) -> T {
        state.withLock { body($0) }
    }

    private func write(_ body: (inout State) -> Void) {
        objectWillChange.send()
        state.withLock { body(&$0) }
    }

    var text: String {
        get { read { $0.text } }
        set { write { $0.text = newValue; $0.textVersion &+= 1 } }
    }
    /// Incremented on every text change. Editors compare this against the version
    /// they last pushed to detect external changes (revert, mode switches, table edits).
    var textVersion: Int { read { $0.textVersion } }

    var language: Language {
        get { read { $0.language } }
        set {
            guard newValue != language else { return }
            write { $0.language = newValue }
            languageDidChange()
        }
    }
    /// The view mode of the active pane.
    var viewMode: ViewMode {
        get { layout.activePane.viewMode }
        set {
            objectWillChange.send()
            layout.activePane.viewMode = newValue
        }
    }
    var delimiter: Character {
        get { read { $0.delimiter } }
        set { write { $0.delimiter = newValue } }
    }
    var hasHeaderRow: Bool {
        get { read { $0.hasHeaderRow } }
        set { write { $0.hasHeaderRow = newValue } }
    }
    var encoding: String.Encoding {
        get { read { $0.encoding } }
        set { write { $0.encoding = newValue } }
    }
    var lineEnding: LineEnding {
        get { read { $0.lineEnding } }
        set { write { $0.lineEnding = newValue } }
    }

    /// The editor panes of the document's window.
    let layout: EditorLayout

    /// Live statistics of the active pane.
    var status: EditorStatus { layout.activePane.status }

    // MARK: Editor hooks (installed by the editor each pane shows)

    var formatHandler: ((FormatCommand) -> Void)? { layout.activePane.formatHandler }
    var tableHandler: ((TableCommand) -> Void)? { layout.activePane.tableHandler }

    /// Called before the document is saved so rich editors can write back pending edits.
    func flushPendingEdits() {
        for pane in layout.panes { pane.flushPendingEdits?() }
    }

    // MARK: Init

    nonisolated init() {
        state = Mutex(State(text: "", language: LanguageRegistry.plainText, delimiter: ",", hasHeaderRow: true, encoding: .utf8, lineEnding: .lf))
        layout = EditorLayout(viewMode: .source)
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = TextDecoder.decode(data)
        let fileName = configuration.file.filename ?? configuration.file.preferredFilename ?? ""
        let lineEnding = LineEnding.detect(in: decoded.text)
        let normalized = lineEnding == .lf ? decoded.text : decoded.text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lang = LanguageRegistry.language(forFileName: fileName)
        if lang == nil, let first = normalized.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first {
            lang = LanguageRegistry.language(forShebang: first)
        }
        if lang == nil {
            if configuration.contentType.conforms(to: .commaSeparatedText) { lang = LanguageRegistry.csv }
            else if configuration.contentType.conforms(to: .tabSeparatedText) { lang = LanguageRegistry.tsv }
            else if configuration.contentType.identifier == "net.daringfireball.markdown" { lang = LanguageRegistry.markdown }
            else if configuration.contentType.conforms(to: .json) { lang = LanguageRegistry.json }
            else if configuration.contentType.conforms(to: .yaml) { lang = LanguageRegistry.yaml }
            else if configuration.contentType.conforms(to: .xml) { lang = LanguageRegistry.xml }
            else if configuration.contentType.conforms(to: .html) { lang = LanguageRegistry.html }
        }
        let language = lang ?? LanguageRegistry.plainText

        let delimiter: Character
        if language.id == "tsv" {
            delimiter = "\t"
        } else if language.id == "csv" {
            delimiter = DelimitedText.detectDelimiter(in: normalized)
        } else {
            delimiter = ","
        }

        state = Mutex(State(
            text: normalized,
            language: language,
            delimiter: delimiter,
            hasHeaderRow: true,
            encoding: decoded.encoding,
            lineEnding: lineEnding
        ))
        layout = EditorLayout(viewMode: PlainDocument.defaultViewMode(for: language))
    }

    nonisolated static func defaultViewMode(for language: Language) -> ViewMode {
        if language.isMarkdown {
            let stored = UserDefaults.standard.string(forKey: SettingsKey.markdownDefaultMode) ?? ViewMode.rich.rawValue
            return ViewMode(rawValue: stored) ?? .rich
        }
        if language.isDelimited { return .table }
        return .source
    }

    // MARK: Saving

    /// Called on the main thread for explicit saves and on a background queue for autosave,
    /// so it only touches the locked state. Pending rich text edits are flushed when possible.
    nonisolated func snapshot(contentType: UTType) throws -> DocumentSnapshot {
        if Thread.isMainThread {
            MainActor.assumeIsolated { flushPendingEdits() }
        }
        return state.withLock { DocumentSnapshot(text: $0.text, encoding: $0.encoding.rawValue, lineEnding: $0.lineEnding) }
    }

    nonisolated func fileWrapper(snapshot: DocumentSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        var output = snapshot.text
        if snapshot.lineEnding != .lf {
            output = output.replacingOccurrences(of: "\n", with: snapshot.lineEnding.string)
        }
        let encoding = String.Encoding(rawValue: snapshot.encoding)
        guard let data = output.data(using: encoding) ?? output.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: Helpers

    var isMarkdown: Bool { language.isMarkdown }
    var isDelimited: Bool { language.isDelimited }

    /// Replaces the text from an editor. Bumps `textVersion` so other editors reload.
    func replaceText(_ newText: String) {
        guard newText != text else { return }
        text = newText
    }

    private func languageDidChange() {
        if language.id == "tsv" {
            delimiter = "\t"
        } else if language.id == "csv", delimiter == "\t" {
            delimiter = DelimitedText.detectDelimiter(in: text)
        }
        let allowed = availableViewModes
        for pane in layout.panes where !allowed.contains(pane.viewMode) {
            pane.viewMode = PlainDocument.defaultViewMode(for: language)
        }
    }

    var availableViewModes: [ViewMode] {
        if isMarkdown { return [.rich, .source] }
        if isDelimited { return [.table, .source] }
        return [.source]
    }
}

// MARK: - Text decoding

nonisolated enum TextDecoder {
    struct Result: Sendable {
        var text: String
        var encoding: String.Encoding
    }

    static func decode(_ data: Data) -> Result {
        if data.isEmpty { return Result(text: "", encoding: .utf8) }
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF,
           let s = String(data: data.dropFirst(3), encoding: .utf8) {
            return Result(text: s, encoding: .utf8)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE, let s = String(data: data, encoding: .utf16LittleEndian) {
            return Result(text: s.trimmingBOM, encoding: .utf16LittleEndian)
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF, let s = String(data: data, encoding: .utf16BigEndian) {
            return Result(text: s.trimmingBOM, encoding: .utf16BigEndian)
        }
        if let s = String(data: data, encoding: .utf8) {
            return Result(text: s, encoding: .utf8)
        }
        if let s = String(data: data, encoding: .windowsCP1252) {
            return Result(text: s, encoding: .windowsCP1252)
        }
        if let s = String(data: data, encoding: .isoLatin1) {
            return Result(text: s, encoding: .isoLatin1)
        }
        return Result(text: String(decoding: data, as: UTF8.self), encoding: .utf8)
    }
}

nonisolated extension String {
    var trimmingBOM: String {
        if unicodeScalars.first == "\u{FEFF}" { return String(dropFirst()) }
        return self
    }
}

// MARK: - Commands sent from menus to the active editor

enum FormatCommand: Sendable {
    case bold, italic, strikethrough, inlineCode
    case heading(Int)          // 0 = paragraph
    case bulletList, numberedList, taskList
    case blockQuote, codeBlock
    case link, image, table, horizontalRule
}

enum TableCommand: Sendable {
    case addRow, deleteSelectedRows, duplicateRow
    case addColumn, renameColumn, deleteColumn
    case toggleHeaderRow
    case clearFilter, clearSort
}

// MARK: - Focused values

struct PlainDocumentKey: FocusedValueKey {
    typealias Value = PlainDocument
}

extension FocusedValues {
    var plainDocument: PlainDocument? {
        get { self[PlainDocumentKey.self] }
        set { self[PlainDocumentKey.self] = newValue }
    }
}
