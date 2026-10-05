import SwiftUI

/// Bottom status bar shared by every document type: statistics on the left, the view
/// mode switch in the middle, and the editing controls and menus on the right.
///
/// The bar adapts to the window width. The statistics give way first, then the
/// trailing controls fold their less used pickers into an overflow menu, so nothing
/// ever overlaps.
struct StatusBarView: View {
    @ObservedObject var document: PlainDocument
    var tableModel: TableModel?

    var body: some View {
        HStack(spacing: 10) {
            leading
                .layoutPriority(-1)
            Spacer(minLength: 8)
            if document.availableViewModes.count > 1 {
                modePicker
                Spacer(minLength: 8)
            }
            trailing
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Left

    @ViewBuilder
    private var leading: some View {
        if document.viewMode == .table, let tableModel {
            ViewThatFits(in: .horizontal) {
                TableStats(model: tableModel, compact: false)
                TableStats(model: tableModel, compact: true)
                Color.clear.frame(width: 0, height: 0)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                textStats(compact: false)
                textStats(compact: true)
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private func textStats(compact: Bool) -> some View {
        let status = document.status
        return HStack(spacing: 10) {
            if compact {
                HStack(spacing: 3) {
                    Text("Ln")
                    Text(status.line, format: .number).foregroundStyle(.primary)
                    Text("Col")
                    Text(status.column, format: .number).foregroundStyle(.primary)
                }
            } else {
                stat("Lines", status.lines)
                stat("Characters", status.characters)
                stat("Words", status.words)
                stat("Location", status.location)
                stat("Line", status.line)
                stat("Column", status.column)
            }
            if status.selectionLength > 0 {
                Text("\(status.selectionLength) selected")
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label + ":")
            Text(value, format: .number)
                .foregroundStyle(.primary)
        }
    }

    // MARK: Center

    private var modePicker: some View {
        Picker("View", selection: $document.viewMode) {
            ForEach(document.availableViewModes) { mode in
                Text(title(for: mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Switch between the rendered view and the source")
    }

    private func title(for mode: ViewMode) -> String {
        switch mode {
        case .source: "Source"
        case .rich: "Rich Text"
        case .table: "Table"
        }
    }

    // MARK: Right

    /// How much of the trailing group is shown directly. Pickers that do not fit move
    /// into the overflow menu.
    enum Density {
        case full, compact, minimal
    }

    private var trailing: some View {
        ViewThatFits(in: .horizontal) {
            trailingControls(.full)
            trailingControls(.compact)
            trailingControls(.minimal)
        }
    }

    private func trailingControls(_ density: Density) -> some View {
        HStack(spacing: 8) {
            if document.viewMode == .table, let tableModel {
                TableControls(model: tableModel, filterWidth: density == .full ? 150 : 100)
            }
            if density != .minimal {
                if document.isDelimited {
                    delimiterPicker
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                        .help("Field delimiter")
                    headerToggle
                }
                syntaxPicker
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help("Syntax highlighting")
            }
            if density == .full {
                encodingPicker
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help("Text encoding used when saving")
                lineEndingPicker
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help("Line endings used when saving")
            } else {
                overflowMenu(density)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// Holds the pickers that did not fit on the bar. Each picker becomes a submenu.
    private func overflowMenu(_ density: Density) -> some View {
        Menu {
            if density == .minimal {
                if document.isDelimited {
                    delimiterPicker
                    headerToggle
                }
                syntaxPicker
                Divider()
            }
            encodingPicker
            lineEndingPicker
        } label: {
            barIcon("ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More document settings")
    }

    private var headerToggle: some View {
        Toggle("Header Row", isOn: $document.hasHeaderRow)
            .toggleStyle(.checkbox)
    }

    private var delimiterPicker: some View {
        Picker("Delimiter", selection: $document.delimiter) {
            Text("Comma").tag(Character(","))
            Text("Semicolon").tag(Character(";"))
            Text("Tab").tag(Character("\t"))
            Text("Pipe").tag(Character("|"))
        }
    }

    private var syntaxPicker: some View {
        Picker("Syntax", selection: $document.language) {
            ForEach(LanguageRegistry.all.sorted { $0.name < $1.name }) { language in
                Text(language.name).tag(language)
            }
        }
    }

    private var encodingPicker: some View {
        Picker("Encoding", selection: $document.encoding) {
            Text("UTF-8").tag(String.Encoding.utf8)
            Text("UTF-16 LE").tag(String.Encoding.utf16LittleEndian)
            Text("UTF-16 BE").tag(String.Encoding.utf16BigEndian)
            Text("Latin-1").tag(String.Encoding.isoLatin1)
            Text("Windows-1252").tag(String.Encoding.windowsCP1252)
        }
    }

    private var lineEndingPicker: some View {
        Picker("Line Endings", selection: $document.lineEnding) {
            ForEach(LineEnding.allCases) { ending in
                Text(ending.rawValue).tag(ending)
            }
        }
    }
}

/// Row and column counts for the table view.
private struct TableStats: View {
    let model: TableModel
    var compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Text("Rows:")
                Text(model.table.rows.count, format: .number).foregroundStyle(.primary)
                if !model.filter.isEmpty {
                    Text("(\(model.visibleRows.count) shown)")
                }
            }
            if !compact {
                HStack(spacing: 3) {
                    Text("Columns:")
                    Text(model.table.columns.count, format: .number).foregroundStyle(.primary)
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

/// Symbol for a status bar button. SF Symbols have different heights (the minus glyph
/// is much shorter than the plus), and a bordered button sizes itself to its label, so
/// every icon gets the same frame to keep the buttons the same height.
func barIcon(_ name: String) -> some View {
    Image(systemName: name)
        .frame(width: 16, height: 14)
}

/// Row, column and filter controls for the table view.
private struct TableControls: View {
    @Bindable var model: TableModel
    var filterWidth: CGFloat = 150

    var body: some View {
        Button {
            model.addRow()
        } label: {
            barIcon("plus")
        }
        .help("Add a row below the selection")

        Button {
            model.deleteSelectedRows()
        } label: {
            barIcon("minus")
        }
        .disabled(model.selection.isEmpty)
        .help("Delete the selected rows")

        Menu {
            Button("Add Column…") { model.showAddColumn = true }
            Divider()
            ForEach(model.columnInfos) { column in
                Menu(column.title.isEmpty ? "Column \(column.id + 1)" : column.title) {
                    Button("Rename…") {
                        model.renameText = column.title
                        model.pendingRename = column
                    }
                    Button("Insert Column After") { model.addColumn(after: column.id) }
                    Button("Sort Ascending") { model.sortOrder = [CellComparator(column: column.id, order: .forward)] }
                    Button("Sort Descending") { model.sortOrder = [CellComparator(column: column.id, order: .reverse)] }
                    Divider()
                    Button("Delete Column", role: .destructive) { model.pendingDelete = column }
                        .disabled(model.table.columns.count <= 1)
                }
            }
        } label: {
            barIcon("tablecells")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Column operations")

        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
            TextField("Filter", text: $model.filter)
                .textFieldStyle(.plain)
            if !model.filter.isEmpty {
                Button {
                    model.filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
        .frame(width: filterWidth)
        .help("Show only rows containing this text")
    }
}
