import SwiftUI

/// Root view for a document window. Picks the editor for the document's kind and mode.
/// There is no window toolbar: the status bar carries the controls for every file type,
/// so switching between tabs of different kinds keeps the same layout.
struct DocumentView: View {
    @ObservedObject var document: PlainDocument
    let fileURL: URL?
    @EditorSettingsReader private var settings
    @State private var tableModel: TableModel?

    init(document: PlainDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _tableModel = State(initialValue: Self.makeTableModel(for: document))
    }

    var body: some View {
        // The ZStack keeps the hierarchy non-empty while the editor switches, so the
        // modifiers below (status bar, tabbing, onAppear) always take effect.
        ZStack {
            editor
        }
            .frame(minWidth: 480, minHeight: 320)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView(document: document, tableModel: tableModel)
            }
            .focusedSceneValue(\.plainDocument, document)
            .background(WindowTabbingConfigurator())
            .onAppear { syncTableModel() }
            .onChange(of: document.viewMode) { _, _ in syncTableModel() }
            .onChange(of: document.language) { _, _ in syncTableModel() }
    }

    @ViewBuilder
    private var editor: some View {
        switch document.viewMode {
        case .rich where document.isMarkdown:
            RichMarkdownEditorView(document: document, fileURL: fileURL, settings: settings)
                .id("rich")
        case .table where document.isDelimited:
            if let tableModel {
                TableEditorView(document: document, model: tableModel)
                    .id("table-\(document.language.id)")
            } else {
                Color.clear
            }
        default:
            CodeEditorView(document: document, settings: settings)
                .id("source")
        }
    }

    /// Creates the table model when entering the table view and drops it when leaving,
    /// so the table always starts from the current document text.
    private func syncTableModel() {
        if document.isDelimited, document.viewMode == .table {
            if tableModel == nil { tableModel = Self.makeTableModel(for: document) }
        } else {
            tableModel = nil
        }
    }

    private static func makeTableModel(for document: PlainDocument) -> TableModel? {
        guard document.isDelimited, document.viewMode == .table else { return nil }
        let table = DelimitedText.parse(document.text, delimiter: document.delimiter, hasHeaderRow: document.hasHeaderRow)
        return TableModel(table: table)
    }
}
