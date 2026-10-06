import AppKit

/// NSTableView subclass that routes keyboard and context menu events to the coordinator.
final class GridTableView: NSTableView {
    var onBeginEdit: ((Int) -> Void)?
    var onDeleteRows: (() -> Void)?
    var onCopy: (() -> Void)?
    /// Builds the context menu for a row. The second value is the clicked column's
    /// position in `tableColumns`, or -1.
    var menuProvider: ((Int, Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, Enter
            if selectedRow >= 0 {
                onBeginEdit?(selectedRow)
                return
            }
        case 51, 117: // Delete, Forward Delete
            if !selectedRowIndexes.isEmpty {
                onDeleteRows?()
                return
            }
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuProvider?(row, column(at: point))
    }

    /// Edit > Copy (Command-C) while the grid has focus. A cell being edited has
    /// the field editor as first responder, so its own text copy still works.
    @objc func copy(_ sender: Any?) {
        onCopy?()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return !selectedRowIndexes.isEmpty }
        return super.validateUserInterfaceItem(item)
    }
}

/// Header view that shows a context menu for the column under the pointer.
final class GridHeaderView: NSTableHeaderView {
    var menuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let position = column(at: point)
        guard let tableView, position >= 0,
              let index = TableGridCoordinator.columnIndex(tableView.tableColumns[position].identifier) else { return nil }
        return menuProvider?(index)
    }
}

/// The cell a Copy Cell menu item refers to.
final class CellReference: NSObject {
    let rowID: UUID
    let column: Int

    init(rowID: UUID, column: Int) {
        self.rowID = rowID
        self.column = column
    }
}

/// Row view that draws the vertical column separators. Doing this per row instead
/// of with `gridStyleMask` keeps the lines inside the rows: AppKit otherwise extends
/// them over the empty area, the floating header and the title bar.
final class GridRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard let table = superview as? NSTableView else { return }
        let spacing = table.intercellSpacing.width
        NSColor.gridColor.setFill()
        for index in 0..<table.numberOfColumns {
            let column = convert(table.rect(ofColumn: index), from: table)
            let x = (column.maxX + spacing / 2).rounded(.down)
            let line = NSRect(x: x, y: 0, width: 1, height: bounds.height)
            if line.intersects(dirtyRect) { line.fill() }
        }
    }
}

/// Cell view that keeps its text field covering the whole cell. Autoresizing masks
/// alone do not work here because the view is created with a zero frame.
final class GridCellView: NSTableCellView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        textField?.frame = bounds
    }

    override func layout() {
        super.layout()
        textField?.frame = bounds
    }
}

/// Owns the AppKit grid for a `TableModel`. Cells are plain `NSTextField`s reused
/// through `makeView(withIdentifier:owner:)`, so scrolling only touches the rows on screen.
final class TableGridCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let model: TableModel
    private(set) var scrollView: NSScrollView!
    private(set) var tableView: GridTableView!

    private var appliedGeneration = -1
    private var appliedColumnTitles: [String]?
    private var appliedSortOrder: [CellComparator] = []
    private var isSyncingSelection = false
    private var isSyncingSort = false
    private var editingTarget: (rowID: UUID, column: Int)?
    private var lastEditedColumn = 0
    private var columnWidths: [Int: CGFloat] = [:]
    /// Where copies go. Tests swap in a private pasteboard.
    var pasteboard = NSPasteboard.general

    static let rowNumberID = NSUserInterfaceItemIdentifier("rownum")
    static let rowViewID = NSUserInterfaceItemIdentifier("row")
    static let cellID = NSUserInterfaceItemIdentifier("cell")
    static let rowHeight: CGFloat = 22
    private static let cellFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let rowNumberFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    static func columnID(_ index: Int) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("col:\(index)")
    }

    static func columnIndex(_ id: NSUserInterfaceItemIdentifier) -> Int? {
        guard id.rawValue.hasPrefix("col:") else { return nil }
        return Int(id.rawValue.dropFirst(4))
    }

    init(model: TableModel) {
        self.model = model
        super.init()
        model.onColumnsRemapped = { [weak self] newIndex in
            guard let self else { return }
            var widths: [Int: CGFloat] = [:]
            for (old, width) in columnWidths {
                if let new = newIndex(old) { widths[new] = width }
            }
            columnWidths = widths
            lastEditedColumn = newIndex(lastEditedColumn) ?? 0
        }
    }

    // MARK: Setup

    func makeScrollView() -> NSScrollView {
        let table = GridTableView()
        table.usesAutomaticRowHeights = false
        table.rowSizeStyle = .custom
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 3, height: 2)
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsColumnSelection = false
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsTypeSelect = false
        table.usesAlternatingRowBackgroundColors = true
        table.style = .plain
        table.gridStyleMask = []
        let header = GridHeaderView()
        header.menuProvider = { [weak self] index in self?.columnMenu(for: index) }
        table.headerView = header
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked(_:))
        table.onBeginEdit = { [weak self] row in
            guard let self else { return }
            beginEditing(row: row, column: lastEditedColumn)
        }
        table.onDeleteRows = { [weak self] in self?.model.deleteSelectedRows() }
        table.onCopy = { [weak self] in self?.copySelectedRows() }
        table.menuProvider = { [weak self] row, position in
            guard let self else { return nil }
            let column = position >= 0 ? Self.columnIndex(tableView.tableColumns[position].identifier) : nil
            return rowMenu(for: row, column: column)
        }

        let rowNumber = NSTableColumn(identifier: Self.rowNumberID)
        rowNumber.title = "#"
        rowNumber.minWidth = 36
        rowNumber.width = 44
        rowNumber.maxWidth = 80
        rowNumber.resizingMask = .userResizingMask
        rowNumber.headerCell.alignment = .right
        table.addTableColumn(rowNumber)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.usesPredominantAxisScrolling = true
        scroll.menu = backgroundMenu()

        tableView = table
        scrollView = scroll
        return scroll
    }

    /// Pushes the model's current state into the table. Never writes to the model.
    func apply(columns: [ColumnInfo], generation: Int, selection: Set<UUID>, sortOrder: [CellComparator]) {
        let titles = columns.map(\.title)
        if titles != appliedColumnTitles {
            // Removing the sorted column clears the table's sort descriptors. That is
            // not a user choice, so keep it out of the model and set the sort again below.
            isSyncingSort = true
            reconcileColumns(columns)
            isSyncingSort = false
            appliedSortOrder = []
            appliedColumnTitles = titles
        }
        if sortOrder != appliedSortOrder {
            isSyncingSort = true
            tableView.sortDescriptors = sortOrder.first.map { [NSSortDescriptor(key: "col:\($0.column)", ascending: $0.order == .forward)] } ?? []
            isSyncingSort = false
            appliedSortOrder = sortOrder
        }
        if generation != appliedGeneration {
            isSyncingSelection = true
            tableView.reloadData()
            isSyncingSelection = false
            appliedGeneration = generation
        }
        syncSelection(selection)
    }

    private func reconcileColumns(_ columns: [ColumnInfo]) {
        // Widths are not read back here: `columnWidths` is kept current by
        // `tableViewColumnDidResize` and remapped when columns move.
        for column in tableView.tableColumns where column.identifier != Self.rowNumberID {
            tableView.removeTableColumn(column)
        }
        for info in columns {
            let column = NSTableColumn(identifier: Self.columnID(info.id))
            column.title = info.title
            column.minWidth = 60
            column.width = columnWidths[info.id] ?? 160
            column.resizingMask = .userResizingMask
            column.sortDescriptorPrototype = NSSortDescriptor(key: "col:\(info.id)", ascending: true)
            tableView.addTableColumn(column)
        }
    }

    private func syncSelection(_ selection: Set<UUID>) {
        var indexes = IndexSet()
        for id in selection {
            if let index = model.visibleIndexByID[id] { indexes.insert(index) }
        }
        guard indexes != tableView.selectedRowIndexes else { return }
        isSyncingSelection = true
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        isSyncingSelection = false
    }

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.visibleRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        if tableColumn.identifier == Self.rowNumberID {
            let view = tableView.makeView(withIdentifier: Self.rowNumberID, owner: self) as? NSTableCellView ?? makeRowNumberView()
            let number = row < model.visibleRowNumbers.count ? model.visibleRowNumbers[row] : 0
            view.textField?.stringValue = String(number)
            return view
        }
        guard let column = Self.columnIndex(tableColumn.identifier) else { return nil }
        let view = tableView.makeView(withIdentifier: Self.cellID, owner: self) as? NSTableCellView ?? makeCellView()
        view.textField?.stringValue = model.cell(atVisibleRow: row, column: column)
        return view
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        if let view = tableView.makeView(withIdentifier: Self.rowViewID, owner: self) as? GridRowView { return view }
        let view = GridRowView()
        view.identifier = Self.rowViewID
        return view
    }

    private func makeCellView() -> NSTableCellView {
        let field = NSTextField()
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.font = Self.cellFont
        field.delegate = self
        if let cell = field.cell as? NSTextFieldCell {
            cell.isScrollable = true
            cell.wraps = false
            cell.allowsUndo = false
        }
        return wrap(field, identifier: Self.cellID)
    }

    private func makeRowNumberView() -> NSTableCellView {
        let field = NSTextField(labelWithString: "")
        field.font = Self.rowNumberFont
        field.textColor = .secondaryLabelColor
        field.alignment = .right
        field.lineBreakMode = .byClipping
        return wrap(field, identifier: Self.rowNumberID)
    }

    private func wrap(_ field: NSTextField, identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let view = GridCellView(frame: NSRect(x: 0, y: 0, width: 100, height: Self.rowHeight))
        view.identifier = identifier
        field.frame = view.bounds
        view.addSubview(field)
        view.textField = field
        return view
    }

    // MARK: Delegate

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        let rows = model.visibleRows
        var selected = Set<UUID>()
        for index in tableView.selectedRowIndexes where index < rows.count { selected.insert(rows[index].id) }
        if selected != model.selection { model.selection = selected }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncingSort else { return }
        if tableView.sortDescriptors.count > 1 {
            isSyncingSort = true
            tableView.sortDescriptors = Array(tableView.sortDescriptors.prefix(1))
            isSyncingSort = false
        }
        guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key,
              let column = Self.columnIndex(NSUserInterfaceItemIdentifier(key)) else {
            appliedSortOrder = []
            if !model.sortOrder.isEmpty { model.sortOrder = [] }
            return
        }
        let order: [CellComparator] = [CellComparator(column: column, order: descriptor.ascending ? .forward : .reverse)]
        appliedSortOrder = order
        if model.sortOrder != order { model.sortOrder = order }
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              let index = Self.columnIndex(column.identifier) else { return }
        columnWidths[index] = column.width
    }

    /// Keeps the row number column in first place.
    func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
        columnIndex > 0 && newColumnIndex > 0
    }

    /// Called once when a header drag ends. The table has already moved its columns,
    /// so their identifiers (the old model indexes) give the new order.
    func tableView(_ tableView: NSTableView, didDrag tableColumn: NSTableColumn) {
        let order = tableView.tableColumns.compactMap { Self.columnIndex($0.identifier) }
        // The moved columns keep their old identifiers, so rebuild them on the next
        // apply even when the titles read the same (two columns can share a title).
        appliedColumnTitles = nil
        model.reorderColumns(order)
    }

    // MARK: Editing

    @objc private func doubleClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        let column = tableView.clickedColumn
        guard row >= 0, column >= 0,
              let index = Self.columnIndex(tableView.tableColumns[column].identifier) else { return }
        beginEditing(row: row, column: index)
    }

    /// Starts editing a cell addressed by visible row and model column index.
    func beginEditing(row: Int, column: Int) {
        guard row >= 0, row < model.visibleRows.count else { return }
        let tableColumn = tableView.column(withIdentifier: Self.columnID(column))
        guard tableColumn >= 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        tableView.editColumn(tableColumn, row: row, with: nil, select: true)
    }

    /// Visible row and model column of the cell a text field belongs to.
    private func position(of field: NSTextField) -> (row: Int, column: Int)? {
        let row = tableView.row(for: field)
        let columnPosition = tableView.column(for: field)
        guard row >= 0, row < model.visibleRows.count, columnPosition >= 0,
              let column = Self.columnIndex(tableView.tableColumns[columnPosition].identifier) else { return nil }
        return (row, column)
    }

    /// Remembers which cell is being edited by row id, so the commit survives a row
    /// index shift. Called on the first keystroke; the end-of-edit path falls back to
    /// the field's position when no keystroke happened.
    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let p = position(of: field) else { return }
        editingTarget = (model.visibleRows[p.row].id, p.column)
        lastEditedColumn = p.column
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let target = editingTarget ?? position(of: field).map { (model.visibleRows[$0.row].id, $0.column) }
        editingTarget = nil
        guard let target else { return }
        lastEditedColumn = target.column
        model.setCell(rowID: target.rowID, column: target.column, value: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField, let p = position(of: field) else { return false }
        let (row, column) = p
        let columnCount = model.table.columnCount

        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finishEditing(thenEdit: (row + 1, column))
        case #selector(NSResponder.insertTab(_:)):
            if column + 1 < columnCount {
                finishEditing(thenEdit: (row, column + 1))
            } else {
                finishEditing(thenEdit: (row + 1, 0))
            }
        case #selector(NSResponder.insertBacktab(_:)):
            if column > 0 {
                finishEditing(thenEdit: (row, column - 1))
            } else if row > 0 {
                finishEditing(thenEdit: (row - 1, columnCount - 1))
            } else {
                finishEditing(thenEdit: nil)
            }
        case #selector(NSResponder.cancelOperation(_:)):
            let original = model.cell(atVisibleRow: row, column: column)
            editingTarget = nil
            field.abortEditing()
            field.stringValue = original
            tableView.window?.makeFirstResponder(tableView)
        default:
            return false
        }
        return true
    }

    /// Ends the current edit (which commits through `controlTextDidEndEditing`) and
    /// moves to the next cell on the next turn so the commit's reload lands first.
    private func finishEditing(thenEdit next: (row: Int, column: Int)?) {
        tableView.window?.makeFirstResponder(tableView)
        guard let next else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard next.row < model.visibleRows.count else { return }
            beginEditing(row: next.row, column: next.column)
        }
    }

    // MARK: Menus

    /// `column` is the model index of the clicked cell, which adds Copy Cell.
    func rowMenu(for row: Int, column: Int? = nil) -> NSMenu? {
        guard row >= 0, row < model.visibleRows.count else { return nil }
        let id = model.visibleRows[row].id
        let menu = NSMenu()
        if let column {
            let copyCell = NSMenuItem(title: "Copy Cell", action: #selector(copyCell(_:)), keyEquivalent: "")
            copyCell.target = self
            copyCell.representedObject = CellReference(rowID: id, column: column)
            menu.addItem(copyCell)
        }
        let selected = tableView.selectedRowIndexes.contains(row) ? tableView.selectedRowIndexes.count : 1
        menu.addItem(item(selected > 1 ? "Copy Rows" : "Copy Row", #selector(copyRows(_:)), id))
        if model.table.hasHeaderRow {
            menu.addItem(item(selected > 1 ? "Copy Rows with Header" : "Copy Row with Header", #selector(copyRowsWithHeader(_:)), id))
        }
        menu.addItem(.separator())
        menu.addItem(item("Insert Row Above", #selector(insertRowAbove(_:)), id))
        menu.addItem(item("Insert Row Below", #selector(insertRowBelow(_:)), id))
        menu.addItem(item("Duplicate Row", #selector(duplicateRow(_:)), id))
        menu.addItem(.separator())
        menu.addItem(item("Delete Row", #selector(deleteRow(_:)), id))
        return menu
    }

    func backgroundMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Add Row", #selector(addRow(_:)), nil))
        menu.addItem(item("Add Column…", #selector(addColumn(_:)), nil))
        return menu
    }

    func columnMenu(for index: Int) -> NSMenu? {
        let count = model.table.columns.count
        guard index >= 0, index < count else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(columnItem("Rename…", #selector(renameColumn(_:)), index))
        menu.addItem(columnItem("Insert Column Left", #selector(insertColumnLeft(_:)), index))
        menu.addItem(columnItem("Insert Column Right", #selector(insertColumnRight(_:)), index))
        menu.addItem(.separator())
        menu.addItem(columnItem("Move Left", #selector(moveColumnLeft(_:)), index, enabled: index > 0))
        menu.addItem(columnItem("Move Right", #selector(moveColumnRight(_:)), index, enabled: index < count - 1))
        menu.addItem(.separator())
        menu.addItem(columnItem("Delete Column…", #selector(deleteColumn(_:)), index, enabled: count > 1))
        return menu
    }

    private func columnItem(_ title: String, _ action: Selector, _ index: Int, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = index as NSNumber
        item.isEnabled = enabled
        return item
    }

    private func columnIndex(from sender: Any?) -> Int? {
        ((sender as? NSMenuItem)?.representedObject as? NSNumber)?.intValue
    }

    private func columnInfo(from sender: Any?) -> ColumnInfo? {
        guard let index = columnIndex(from: sender) else { return nil }
        return model.columnInfos.first { $0.id == index }
    }

    private func item(_ title: String, _ action: Selector, _ id: UUID?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id.map { $0 as NSUUID }
        return item
    }

    private func rowID(from sender: Any?) -> UUID? {
        ((sender as? NSMenuItem)?.representedObject as? NSUUID) as UUID?
    }

    // MARK: Copy

    /// Rows to copy for a menu item: the selection when it holds the clicked row,
    /// otherwise only the clicked row. Rows keep the order they have on screen.
    private func rowsToCopy(clicked id: UUID?) -> [[String]] {
        let selected = tableView.selectedRowIndexes
        if let id, let index = model.visibleIndexByID[id], !selected.contains(index) {
            return [model.visibleRows[index].cells]
        }
        return selected.compactMap { $0 < model.visibleRows.count ? model.visibleRows[$0].cells : nil }
    }

    func copySelectedRows() {
        write(rowsToCopy(clicked: nil), header: nil)
    }

    @objc func copyRows(_ sender: Any?) {
        write(rowsToCopy(clicked: rowID(from: sender)), header: nil)
    }

    @objc func copyRowsWithHeader(_ sender: Any?) {
        write(rowsToCopy(clicked: rowID(from: sender)), header: model.table.columns)
    }

    @objc func copyCell(_ sender: Any?) {
        guard let cell = (sender as? NSMenuItem)?.representedObject as? CellReference else { return }
        let value = model.cellValue(rowID: cell.rowID, column: cell.column)
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    /// Writes plain tab-separated text and an HTML table, so spreadsheets and
    /// documents can each take the format they handle best.
    private func write(_ rows: [[String]], header: [String]?) {
        guard !rows.isEmpty else { return }
        let all = header.map { [$0] + rows } ?? rows
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .html], owner: nil)
        pasteboard.setString(DelimitedText.clipboardText(all), forType: .string)
        pasteboard.setString(DelimitedText.clipboardHTML(rows, header: header), forType: .html)
    }

    @objc func insertRowAbove(_ sender: Any?) {
        guard let id = rowID(from: sender) else { return }
        model.insertRow(before: id)
    }

    @objc func insertRowBelow(_ sender: Any?) {
        guard let id = rowID(from: sender) else { return }
        model.addRow(after: id)
    }

    @objc func duplicateRow(_ sender: Any?) {
        guard let id = rowID(from: sender) else { return }
        model.selection = [id]
        model.duplicateSelectedRows()
    }

    @objc func deleteRow(_ sender: Any?) {
        guard let id = rowID(from: sender) else { return }
        model.deleteRow(id: id)
    }

    @objc func addRow(_ sender: Any?) {
        model.addRow()
    }

    @objc func addColumn(_ sender: Any?) {
        model.showAddColumn = true
    }

    @objc func renameColumn(_ sender: Any?) {
        guard let column = columnInfo(from: sender) else { return }
        model.renameText = column.title
        model.pendingRename = column
    }

    @objc func insertColumnLeft(_ sender: Any?) {
        guard let index = columnIndex(from: sender) else { return }
        model.insertColumn(at: index)
    }

    @objc func insertColumnRight(_ sender: Any?) {
        guard let index = columnIndex(from: sender) else { return }
        model.insertColumn(at: index + 1)
    }

    @objc func moveColumnLeft(_ sender: Any?) {
        guard let index = columnIndex(from: sender) else { return }
        model.moveColumn(from: index, to: index - 1)
    }

    @objc func moveColumnRight(_ sender: Any?) {
        guard let index = columnIndex(from: sender) else { return }
        model.moveColumn(from: index, to: index + 1)
    }

    @objc func deleteColumn(_ sender: Any?) {
        guard let column = columnInfo(from: sender) else { return }
        model.pendingDelete = column
    }
}
