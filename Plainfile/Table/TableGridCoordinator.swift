import AppKit

/// NSTableView subclass that routes keyboard and context menu events to the coordinator.
final class GridTableView: NSTableView {
    var onBeginEdit: ((Int) -> Void)?
    var onDeleteRows: (() -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?

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
        return menuProvider?(row)
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

    static let rowNumberID = NSUserInterfaceItemIdentifier("rownum")
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
    }

    // MARK: Setup

    func makeScrollView() -> NSScrollView {
        let table = GridTableView()
        table.usesAutomaticRowHeights = false
        table.rowSizeStyle = .custom
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 3, height: 2)
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.allowsColumnSelection = false
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsTypeSelect = false
        table.usesAlternatingRowBackgroundColors = true
        table.style = .plain
        table.gridStyleMask = [.solidVerticalGridLineMask]
        table.headerView = NSTableHeaderView()
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked(_:))
        table.onBeginEdit = { [weak self] row in
            guard let self else { return }
            beginEditing(row: row, column: lastEditedColumn)
        }
        table.onDeleteRows = { [weak self] in self?.model.deleteSelectedRows() }
        table.menuProvider = { [weak self] row in self?.rowMenu(for: row) }

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
            reconcileColumns(columns)
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
        for column in tableView.tableColumns where column.identifier != Self.rowNumberID {
            if let index = Self.columnIndex(column.identifier) { columnWidths[index] = column.width }
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

    func rowMenu(for row: Int) -> NSMenu? {
        guard row >= 0, row < model.visibleRows.count else { return nil }
        let id = model.visibleRows[row].id
        let menu = NSMenu()
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

    private func item(_ title: String, _ action: Selector, _ id: UUID?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id.map { $0 as NSUUID }
        return item
    }

    private func rowID(from sender: Any?) -> UUID? {
        ((sender as? NSMenuItem)?.representedObject as? NSUUID) as UUID?
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
}
