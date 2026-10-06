import SwiftUI

/// View menu additions: view mode, line numbers, wrapping, zoom and syntax.
struct ViewCommands: Commands {
    @FocusedValue(\.plainDocument) private var document
    @AppStorage(SettingsKey.showLineNumbers) private var showLineNumbers = true
    @AppStorage(SettingsKey.wrapLines) private var wrapLines = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.markdownFontSize) private var markdownFontSize = 14.0

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ViewModeMenuItems(document: document)
            Divider()
            Toggle("Line Numbers", isOn: $showLineNumbers)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Toggle("Wrap Lines", isOn: $wrapLines)
                .keyboardShortcut("w", modifiers: [.command, .option])
            Divider()
            Button("Bigger Text") { zoom(1) }
                .keyboardShortcut("+", modifiers: [.command])
            Button("Smaller Text") { zoom(-1) }
                .keyboardShortcut("-", modifiers: [.command])
            Button("Actual Size") {
                fontSize = 13
                markdownFontSize = 14
            }
            .keyboardShortcut("0", modifiers: [.command])
            Divider()
            SyntaxMenu(document: document)
            Divider()
        }
    }

    private func zoom(_ delta: Double) {
        if let document, document.isMarkdown, document.viewMode == .rich {
            markdownFontSize = min(40, max(9, markdownFontSize + delta))
        } else {
            fontSize = min(48, max(8, fontSize + delta))
        }
    }
}

private struct ViewModeMenuItems: View {
    let document: PlainDocument?

    var body: some View {
        if let document {
            ObservedViewModeItems(document: document)
        } else {
            Button("Show Source") {}.disabled(true)
            Divider()
            Button("Split Editor") {}.disabled(true)
        }
    }
}

private struct ObservedViewModeItems: View {
    @ObservedObject var document: PlainDocument

    var body: some View {
        if document.isMarkdown {
            Picker("Markdown", selection: $document.viewMode) {
                Text("Rich Text").tag(ViewMode.rich)
                Text("Source").tag(ViewMode.source)
            }
            .pickerStyle(.inline)
            Button(document.viewMode == .rich ? "Show Source" : "Show Rich Text") {
                document.viewMode = document.viewMode == .rich ? .source : .rich
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        } else if document.isDelimited {
            Picker("Data", selection: $document.viewMode) {
                Text("Table").tag(ViewMode.table)
                Text("Source").tag(ViewMode.source)
            }
            .pickerStyle(.inline)
            Button(document.viewMode == .table ? "Show Source" : "Show Table") {
                document.viewMode = document.viewMode == .table ? .source : .table
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        } else {
            Button("Show Source") {}.disabled(true)
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
        Divider()
        if document.layout.isSplit {
            Button("Remove Split") { document.layout.unsplit() }
        } else {
            Button("Split Editor") { document.layout.split(document: document) }
        }
    }
}

struct SyntaxMenu: View {
    let document: PlainDocument?

    var body: some View {
        if let document {
            ObservedSyntaxMenu(document: document)
        } else {
            Menu("Syntax") { Text("No Document") }.disabled(true)
        }
    }
}

private struct ObservedSyntaxMenu: View {
    @ObservedObject var document: PlainDocument

    private var groups: [(String, [Language])] {
        let all = LanguageRegistry.all
        func pick(_ ids: [String]) -> [Language] { ids.compactMap { LanguageRegistry.byID[$0] } }
        return [
            ("Text", pick(["plain", "markdown", "csv", "tsv"])),
            ("Languages", all.filter { !["plain", "markdown", "csv", "tsv", "html", "xml", "css", "json", "yaml", "toml", "ini", "makefile", "dockerfile", "shell", "powershell", "sql", "graphql"].contains($0.id) }.sorted { $0.name < $1.name }),
            ("Scripts & Queries", pick(["shell", "powershell", "sql", "graphql"])),
            ("Markup & Data", pick(["html", "xml", "css", "json", "yaml", "toml", "ini", "makefile", "dockerfile"])),
        ]
    }

    var body: some View {
        Menu("Syntax") {
            Picker("Syntax", selection: $document.language) {
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { language in
                            Text(language.name).tag(language)
                        }
                    }
                }
            }
            .pickerStyle(.inline)
        }
    }
}

/// Format menu: Markdown formatting for both the rich and the source editor.
struct FormatCommands: Commands {
    @FocusedValue(\.plainDocument) private var document

    private var enabled: Bool { document?.isMarkdown == true && document?.viewMode != .table }

    var body: some Commands {
        CommandMenu("Format") {
            Group {
                Button("Bold") { send(.bold) }.keyboardShortcut("b", modifiers: [.command])
                Button("Italic") { send(.italic) }.keyboardShortcut("i", modifiers: [.command])
                Button("Strikethrough") { send(.strikethrough) }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Inline Code") { send(.inlineCode) }.keyboardShortcut("e", modifiers: [.command])
                Divider()
                Menu("Heading") {
                    Button("Paragraph") { send(.heading(0)) }.keyboardShortcut("0", modifiers: [.command, .option])
                    Divider()
                    ForEach(1...6, id: \.self) { level in
                        Button("Heading \(level)") { send(.heading(level)) }
                            .keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: [.command, .option])
                    }
                }
                Divider()
                Button("Bulleted List") { send(.bulletList) }.keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered List") { send(.numberedList) }.keyboardShortcut("7", modifiers: [.command, .shift])
                Button("Task List") { send(.taskList) }.keyboardShortcut("9", modifiers: [.command, .shift])
                Button("Block Quote") { send(.blockQuote) }.keyboardShortcut(".", modifiers: [.command, .shift])
                Button("Code Block") { send(.codeBlock) }.keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Link…") { send(.link) }.keyboardShortcut("k", modifiers: [.command])
                Button("Image") { send(.image) }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Table") { send(.table) }.keyboardShortcut("t", modifiers: [.command, .option])
                Button("Horizontal Rule") { send(.horizontalRule) }.keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .disabled(!enabled)
        }
    }

    private func send(_ command: FormatCommand) {
        document?.formatHandler?(command)
    }
}

/// Data menu for CSV / TSV table editing.
struct TableCommands: Commands {
    @FocusedValue(\.plainDocument) private var document

    private var enabled: Bool { document?.viewMode == .table }

    var body: some Commands {
        CommandMenu("Data") {
            Group {
                Button("Add Row") { send(.addRow) }.keyboardShortcut("n", modifiers: [.command, .option])
                Button("Duplicate Rows") { send(.duplicateRow) }.keyboardShortcut("d", modifiers: [.command])
                Button("Delete Selected Rows") { send(.deleteSelectedRows) }.keyboardShortcut(.delete, modifiers: [.command])
                Divider()
                Button("Add Column…") { send(.addColumn) }.keyboardShortcut("n", modifiers: [.command, .option, .shift])
                Divider()
                Button("First Row Is Header") { send(.toggleHeaderRow) }
                Button("Clear Filter") { send(.clearFilter) }
                Button("Clear Sort") { send(.clearSort) }
            }
            .disabled(!enabled)
        }
    }

    private func send(_ command: TableCommand) {
        document?.tableHandler?(command)
    }
}

/// Help menu: opens one bundled sample of each supported file type as tabs.
struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Divider()
            Button("Open Sample Files") { SampleFiles.open() }
        }
    }
}

enum SampleFiles {
    static let names = ["notes.txt", "README.md", "people.csv", "Program.cs"]

    /// Copies the bundled samples into the app's Documents folder (so they are
    /// writable) and opens them. Existing copies are kept.
    static func open() {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("Samples", isDirectory: true) else { return }
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let target = documents.appendingPathComponent("Plainfile Samples", isDirectory: true)
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            NSApp.presentError(error)
            return
        }
        for name in names {
            let from = source.appendingPathComponent(name)
            let to = target.appendingPathComponent(name)
            if !fm.fileExists(atPath: to.path) {
                do {
                    try fm.copyItem(at: from, to: to)
                } catch {
                    NSApp.presentError(error)
                    continue
                }
            }
            NSDocumentController.shared.openDocument(withContentsOf: to, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
    }
}
