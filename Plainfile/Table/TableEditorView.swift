import SwiftUI

/// Spreadsheet style editor for CSV and tab-delimited files. The row, column and
/// filter controls live in the status bar and share the same `TableModel`.
struct TableEditorView: View {
    @ObservedObject var document: PlainDocument
    @Bindable var model: TableModel
    @State private var lastLoadedVersion: Int
    @Environment(\.undoManager) private var undoManager

    init(document: PlainDocument, model: TableModel) {
        self.document = document
        self.model = model
        _lastLoadedVersion = State(initialValue: document.textVersion)
    }

    var body: some View {
        tableView
            .onAppear { wire() }
            .onChange(of: document.textVersion) { _, version in
                guard version != lastLoadedVersion else { return }
                lastLoadedVersion = version
                model.reload(from: DelimitedText.parse(document.text, delimiter: document.delimiter, hasHeaderRow: document.hasHeaderRow))
            }
            .onChange(of: document.delimiter) { _, delimiter in
                if delimiter != model.table.delimiter { model.setDelimiter(delimiter) }
            }
            .onChange(of: document.hasHeaderRow) { _, flag in
                if flag != model.table.hasHeaderRow { model.setHasHeaderRow(flag) }
            }
            .onChange(of: undoManager) { _, um in model.undoManager = um }
            .alert("Rename Column", isPresented: Binding(get: { model.pendingRename != nil }, set: { if !$0 { model.pendingRename = nil } })) {
                TextField("Name", text: $model.renameText)
                Button("Rename") {
                    if let col = model.pendingRename { model.renameColumn(col.id, to: model.renameText) }
                    model.pendingRename = nil
                }
                Button("Cancel", role: .cancel) { model.pendingRename = nil }
            }
            .alert("Add Column", isPresented: $model.showAddColumn) {
                TextField("Name", text: $model.newColumnName)
                Button("Add") {
                    model.addColumn(named: model.newColumnName.isEmpty ? nil : model.newColumnName)
                    model.newColumnName = ""
                }
                Button("Cancel", role: .cancel) { model.newColumnName = "" }
            }
            .confirmationDialog("Delete column “\(model.pendingDelete?.title ?? "")”?", isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete Column", role: .destructive) {
                    if let col = model.pendingDelete { model.deleteColumn(col.id) }
                    model.pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { model.pendingDelete = nil }
            } message: {
                Text("All values in this column will be removed.")
            }
    }

    private var tableView: some View {
        TableGridView(
            model: model,
            columns: model.columnInfos,
            generation: model.generation,
            selection: model.selection,
            sortOrder: model.sortOrder
        )
    }

    private func wire() {
        model.undoManager = undoManager
        model.onChange = { table in
            // Mutations can originate from SwiftUI callbacks (focus changes, onChange),
            // so the document is updated on the next run loop turn to avoid publishing
            // while a view update is in progress.
            DispatchQueue.main.async {
                let text = DelimitedText.serialize(table)
                document.replaceText(text)
                lastLoadedVersion = document.textVersion
                if document.hasHeaderRow != table.hasHeaderRow { document.hasHeaderRow = table.hasHeaderRow }
                if document.delimiter != table.delimiter { document.delimiter = table.delimiter }
            }
        }
        document.tableHandler = { command in
            switch command {
            case .addRow: model.addRow()
            case .deleteSelectedRows: model.deleteSelectedRows()
            case .duplicateRow: model.duplicateSelectedRows()
            case .addColumn: model.showAddColumn = true
            case .renameColumn:
                if let first = model.columnInfos.first {
                    model.renameText = first.title
                    model.pendingRename = first
                }
            case .deleteColumn:
                if let last = model.columnInfos.last { model.pendingDelete = last }
            case .toggleHeaderRow: document.hasHeaderRow.toggle()
            case .clearFilter: model.filter = ""
            case .clearSort: model.sortOrder = []
            }
        }
        document.formatHandler = nil
        document.flushPendingEdits = nil
    }
}
