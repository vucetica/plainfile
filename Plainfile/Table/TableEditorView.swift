import SwiftUI

/// Spreadsheet style editor for CSV and tab-delimited files. The row, column and
/// filter controls live in the status bar and share the same `TableModel`.
struct TableEditorView: View {
    @ObservedObject var document: PlainDocument
    let pane: EditorPane
    @Bindable var model: TableModel
    /// The selection made in another pane.
    var linkedSelection: LinkedSelection?
    @State private var lastLoadedVersion: Int
    @State private var reloadTask: Task<Void, Never>?
    @State private var pendingSelection: [NSRange]?
    @Environment(\.undoManager) private var undoManager

    init(document: PlainDocument, pane: EditorPane, model: TableModel, linkedSelection: LinkedSelection? = nil) {
        self.document = document
        self.pane = pane
        self.model = model
        self.linkedSelection = linkedSelection
        _lastLoadedVersion = State(initialValue: document.textVersion)
    }

    var body: some View {
        tableView
            .onAppear {
                wire()
                if !pane.lastSourceSelection.isEmpty { applySourceSelection(pane.lastSourceSelection) }
            }
            .onChange(of: document.textVersion) { _, version in
                guard version != lastLoadedVersion else { return }
                // A pane that is not being edited follows the other pane's typing at a
                // slower pace, so a large table is not parsed on every key press.
                let layout = document.layout
                if !layout.isSplit || layout.activePaneID == pane.id {
                    reload()
                } else if reloadTask == nil {
                    reloadTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        reloadTask = nil
                        guard !Task.isCancelled else { return }
                        reload()
                    }
                }
            }
            .onChange(of: linkedSelection) { _, linked in
                guard let linked, linked.applies(to: pane) else { return }
                if reloadTask != nil || document.textVersion != lastLoadedVersion {
                    pendingSelection = linked.ranges
                } else {
                    applySourceSelection(linked.ranges)
                }
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
            sortOrder: model.sortOrder,
            revealRequest: model.revealRequest
        )
    }

    private func reload() {
        reloadTask?.cancel()
        reloadTask = nil
        lastLoadedVersion = document.textVersion
        let text = document.text
        model.reload(from: DelimitedText.parse(text, delimiter: document.delimiter, hasHeaderRow: document.hasHeaderRow))
        model.updateSourceRanges(for: text)
        // Undo steps recorded here would put back a table from before the change.
        undoManager?.removeAllActions(withTarget: model)
        if let ranges = pendingSelection {
            pendingSelection = nil
            applySourceSelection(ranges)
        }
    }

    /// Selects the rows that hold the given source ranges and scrolls to the first.
    private func applySourceSelection(_ ranges: [NSRange]) {
        pane.lastSourceSelection = ranges
        model.selectAndReveal(model.rowIDs(touching: ranges))
    }

    /// Shares the user's selection in the grid with the other pane.
    private func publish(_ ranges: [NSRange]) {
        let layout = document.layout
        if layout.isSplit {
            layout.publishSelection(ranges, from: pane)
        } else {
            pane.lastSourceSelection = ranges
        }
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
                model.updateSourceRanges(for: document.text)
                if document.hasHeaderRow != table.hasHeaderRow { document.hasHeaderRow = table.hasHeaderRow }
                if document.delimiter != table.delimiter { document.delimiter = table.delimiter }
            }
        }
        model.onFocus = { document.layout.activate(pane) }
        model.onUserSelectionChange = {
            publish(model.sourceRanges(forRows: model.selection))
        }
        model.onBeginEditingCell = { rowID, column in
            if let range = model.sourceRange(forCell: rowID, column: column) { publish([range]) }
        }
        pane.tableHandler = { command in
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
        pane.formatHandler = nil
        pane.flushPendingEdits = nil
    }
}
