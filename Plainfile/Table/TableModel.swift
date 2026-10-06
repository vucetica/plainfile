import SwiftUI

/// Sort comparator for a single column with numeric awareness.
nonisolated struct CellComparator: SortComparator, Hashable, Sendable {
    var column: Int
    var order: SortOrder = .forward

    func compare(_ lhs: DataRow, _ rhs: DataRow) -> ComparisonResult {
        let a = column < lhs.cells.count ? lhs.cells[column] : ""
        let b = column < rhs.cells.count ? rhs.cells[column] : ""
        let result = Self.compareValues(a, b)
        return order == .forward ? result : result.reversed
    }

    static func compareValues(_ a: String, _ b: String) -> ComparisonResult {
        if a == b { return .orderedSame }
        if a.isEmpty { return .orderedDescending }
        if b.isEmpty { return .orderedAscending }
        if let x = Double(a.replacingOccurrences(of: ",", with: "")), let y = Double(b.replacingOccurrences(of: ",", with: "")) {
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        }
        let c = a.localizedStandardCompare(b)
        return c
    }
}

nonisolated extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}

struct ColumnInfo: Identifiable, Hashable {
    let id: Int
    var title: String
}

/// View model for the table editor. Every mutation goes through `mutate`, which
/// registers undo and pushes the serialized text back to the document.
@Observable
final class TableModel {
    var table: DelimitedTable
    var filter = "" {
        didSet { rebuildVisible() }
    }
    var sortOrder: [CellComparator] = [] {
        didSet { applySort() }
    }
    var selection = Set<UUID>()
    // Alert state driven from the status bar and presented by the table view.
    var pendingRename: ColumnInfo?
    var renameText = ""
    var pendingDelete: ColumnInfo?
    var showAddColumn = false
    var newColumnName = ""
    private(set) var visibleRows: [DataRow] = []
    private(set) var rowNumbers: [UUID: Int] = [:]
    /// Row numbers (1-based, in file order) for each entry of `visibleRows`.
    private(set) var visibleRowNumbers: [Int] = []
    /// Position of each visible row inside `visibleRows`.
    private(set) var visibleIndexByID: [UUID: Int] = [:]
    /// Incremented whenever the visible rows change. The grid reloads when it moves.
    private(set) var generation = 0

    /// Where each row's record sits in the document text, set by `updateSourceRanges`.
    @ObservationIgnored private(set) var rowSourceRanges: [UUID: NSRange] = [:]
    /// Where each field of a row sits in the document text.
    @ObservationIgnored private(set) var fieldSourceRanges: [UUID: [NSRange]] = [:]

    weak var undoManager: UndoManager?
    var onChange: ((DelimitedTable) -> Void)?
    /// Called after the user changes the row selection in the grid.
    @ObservationIgnored var onUserSelectionChange: (() -> Void)?
    /// Called when the grid becomes first responder.
    @ObservationIgnored var onFocus: (() -> Void)?
    /// Called when the user starts editing a cell.
    @ObservationIgnored var onBeginEditingCell: ((UUID, Int) -> Void)?
    /// Bumped to ask the grid to scroll `revealRowID` into view.
    private(set) var revealRequest = 0
    @ObservationIgnored private(set) var revealRowID: UUID?
    /// Called when columns are inserted, deleted or moved, with a map from each old
    /// column index to its new index (`nil` for a deleted column).
    var onColumnsRemapped: (((Int) -> Int?) -> Void)?

    init(table: DelimitedTable) {
        self.table = table
        rebuildVisible()
    }

    var columnInfos: [ColumnInfo] {
        table.columns.enumerated().map { ColumnInfo(id: $0.offset, title: $0.element) }
    }

    func rebuildVisible() {
        var numbers: [UUID: Int] = [:]
        numbers.reserveCapacity(table.rows.count)
        for (i, row) in table.rows.enumerated() { numbers[row.id] = i + 1 }
        rowNumbers = numbers
        let needle = filter.trimmingCharacters(in: .whitespaces)
        if needle.isEmpty {
            visibleRows = table.rows
        } else {
            visibleRows = table.rows.filter { row in
                row.cells.contains { $0.localizedCaseInsensitiveContains(needle) }
            }
        }
        visibleRowNumbers = visibleRows.map { numbers[$0.id] ?? 0 }
        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(visibleRows.count)
        for (i, row) in visibleRows.enumerated() { indexByID[row.id] = i }
        visibleIndexByID = indexByID
        generation &+= 1
        selection = selection.filter { numbers[$0] != nil }
    }

    func reload(from newTable: DelimitedTable) {
        table = newTable
        rebuildVisible()
    }

    // MARK: Source ranges

    /// Records where each row lives in `text`, which must be the text this table was
    /// parsed from or serialized to.
    func updateSourceRanges(for text: String) {
        let records = DelimitedText.recordRanges(text, delimiter: table.delimiter)
        let offset = table.hasHeaderRow ? 1 : 0
        var rows: [UUID: NSRange] = [:]
        var fields: [UUID: [NSRange]] = [:]
        rows.reserveCapacity(table.rows.count)
        for (i, row) in table.rows.enumerated() where i + offset < records.count {
            rows[row.id] = records[i + offset].range
            fields[row.id] = records[i + offset].fields
        }
        rowSourceRanges = rows
        fieldSourceRanges = fields
    }

    /// The source ranges of the given rows, in file order. Rows next to each other
    /// become one range that includes the line break between them.
    func sourceRanges(forRows ids: Set<UUID>) -> [NSRange] {
        let ranges = ids.compactMap { rowSourceRanges[$0] }.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, range.location <= last.upperBound + 1 {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    func sourceRange(forCell rowID: UUID, column: Int) -> NSRange? {
        guard let fields = fieldSourceRanges[rowID], column >= 0, column < fields.count else { return nil }
        return fields[column]
    }

    /// The rows whose records touch any of `ranges`, in file order. A caret at the
    /// end of a line counts for that line.
    func rowIDs(touching ranges: [NSRange]) -> [UUID] {
        guard !ranges.isEmpty else { return [] }
        return table.rows.compactMap { row in
            guard let record = rowSourceRanges[row.id] else { return nil }
            let touches = ranges.contains { range in
                if range.length == 0 { return record.location <= range.location && range.location <= record.upperBound }
                if record.length == 0 { return range.location <= record.location && record.location < range.upperBound }
                return NSIntersectionRange(range, record).length > 0
            }
            return touches ? row.id : nil
        }
    }

    /// Selects rows chosen outside the grid and scrolls the first one into view.
    func selectAndReveal(_ ids: [UUID]) {
        let set = Set(ids)
        if selection != set { selection = set }
        if let first = ids.first {
            revealRowID = first
            revealRequest &+= 1
        }
    }

    // MARK: Mutation with undo

    func mutate(_ actionName: String, notify: Bool = true, _ body: (inout DelimitedTable) -> Void) {
        let before = table
        body(&table)
        table.normalize()
        rebuildVisible()
        registerUndo(actionName: actionName, previous: before)
        if notify { onChange?(table) }
    }

    private func registerUndo(actionName: String, previous: DelimitedTable) {
        undoManager?.registerUndo(withTarget: self) { model in
            let current = model.table
            model.table = previous
            model.rebuildVisible()
            model.registerUndo(actionName: actionName, previous: current)
            model.onChange?(model.table)
        }
        undoManager?.setActionName(actionName)
    }

    // MARK: Cell editing

    /// Fast, index based access used by the grid while scrolling.
    func cell(atVisibleRow row: Int, column: Int) -> String {
        guard row >= 0, row < visibleRows.count else { return "" }
        let cells = visibleRows[row].cells
        guard column >= 0, column < cells.count else { return "" }
        return cells[column]
    }

    func cellValue(rowID: UUID, column: Int) -> String {
        guard let index = rowNumbers[rowID].map({ $0 - 1 }), index < table.rows.count, column < table.rows[index].cells.count else { return "" }
        return table.rows[index].cells[column]
    }

    func setCell(rowID: UUID, column: Int, value: String) {
        guard let index = rowNumbers[rowID].map({ $0 - 1 }), index < table.rows.count, column < table.rows[index].cells.count else { return }
        guard table.rows[index].cells[column] != value else { return }
        mutate("Edit Cell") { t in
            t.rows[index].cells[column] = value
        }
    }

    // MARK: Row operations

    func addRow(after rowID: UUID? = nil) {
        let newRow = DataRow(cells: Array(repeating: "", count: table.columnCount))
        mutate("Add Row") { t in
            if let rowID, let idx = t.rows.firstIndex(where: { $0.id == rowID }) {
                t.rows.insert(newRow, at: idx + 1)
            } else if let last = selection.compactMap({ id in t.rows.firstIndex(where: { $0.id == id }) }).max() {
                t.rows.insert(newRow, at: last + 1)
            } else {
                t.rows.append(newRow)
            }
        }
        selection = [newRow.id]
    }

    func insertRow(before rowID: UUID) {
        let newRow = DataRow(cells: Array(repeating: "", count: table.columnCount))
        mutate("Insert Row") { t in
            if let idx = t.rows.firstIndex(where: { $0.id == rowID }) {
                t.rows.insert(newRow, at: idx)
            }
        }
        selection = [newRow.id]
    }

    func duplicateSelectedRows() {
        guard !selection.isEmpty else { return }
        var newIDs = Set<UUID>()
        mutate("Duplicate Rows") { t in
            let indices = t.rows.indices.filter { selection.contains(t.rows[$0].id) }.sorted(by: >)
            for idx in indices {
                let copy = DataRow(cells: t.rows[idx].cells)
                newIDs.insert(copy.id)
                t.rows.insert(copy, at: idx + 1)
            }
        }
        selection = newIDs
    }

    func deleteSelectedRows() {
        guard !selection.isEmpty else { return }
        let ids = selection
        mutate("Delete Rows") { t in
            t.rows.removeAll { ids.contains($0.id) }
        }
        selection = []
    }

    func deleteRow(id: UUID) {
        mutate("Delete Row") { t in
            t.rows.removeAll { $0.id == id }
        }
        selection.remove(id)
    }

    // MARK: Column operations

    func addColumn(named name: String? = nil, after index: Int? = nil) {
        insertColumn(named: name, at: index.map { $0 + 1 } ?? table.columns.count)
    }

    /// Inserts a column so that it ends up at position `at`.
    func insertColumn(named name: String? = nil, at: Int) {
        let at = min(max(at, 0), table.columns.count)
        mutate("Add Column") { t in
            let title = name ?? "Column \(t.columns.count + 1)"
            t.columns.insert(title, at: at)
            for i in t.rows.indices { t.rows[i].cells.insert("", at: min(at, t.rows[i].cells.count)) }
        }
        remapColumns { $0 >= at ? $0 + 1 : $0 }
    }

    func renameColumn(_ index: Int, to name: String) {
        guard index < table.columns.count, table.columns[index] != name else { return }
        mutate("Rename Column") { t in
            t.columns[index] = name
        }
    }

    func deleteColumn(_ index: Int) {
        guard table.columns.count > 1, index < table.columns.count else { return }
        mutate("Delete Column") { t in
            t.columns.remove(at: index)
            for i in t.rows.indices where index < t.rows[i].cells.count { t.rows[i].cells.remove(at: index) }
        }
        remapColumns { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) }
    }

    /// Moves the column at `from` so that it ends up at position `to`.
    func moveColumn(from: Int, to: Int) {
        let count = table.columns.count
        guard from >= 0, from < count, to >= 0, to < count, from != to else { return }
        var order = Array(0..<count)
        order.remove(at: from)
        order.insert(from, at: to)
        reorderColumns(order)
    }

    /// Puts the columns in a new order, where `order[newPosition]` is the old index.
    func reorderColumns(_ order: [Int]) {
        let count = table.columns.count
        guard order.count == count, Set(order) == Set(0..<count), order != Array(0..<count) else { return }
        var newIndex = [Int](repeating: 0, count: count)
        for (position, old) in order.enumerated() { newIndex[old] = position }
        mutate("Move Column") { t in
            t.columns = order.map { t.columns[$0] }
            for i in t.rows.indices {
                let cells = t.rows[i].cells
                t.rows[i].cells = order.map { $0 < cells.count ? cells[$0] : "" }
            }
        }
        remapColumns { $0 < count ? newIndex[$0] : $0 }
    }

    /// Moves position-keyed state (sort order, and the grid's widths through
    /// `onColumnsRemapped`) to the columns' new positions. `nil` drops the column.
    /// Runs after the table changed, because setting `sortOrder` sorts the rows.
    private func remapColumns(_ newIndex: @escaping (Int) -> Int?) {
        let remapped = sortOrder.compactMap { c in newIndex(c.column).map { CellComparator(column: $0, order: c.order) } }
        if remapped != sortOrder { sortOrder = remapped }
        onColumnsRemapped?(newIndex)
    }

    func setHasHeaderRow(_ flag: Bool) {
        guard flag != table.hasHeaderRow else { return }
        mutate(flag ? "Use First Row as Header" : "Treat Header as Data") { t in
            if flag {
                if let first = t.rows.first {
                    t.columns = first.cells
                    t.rows.removeFirst()
                }
            } else {
                t.rows.insert(DataRow(cells: t.columns), at: 0)
                t.columns = (0..<t.columns.count).map { "Column \($0 + 1)" }
            }
            t.hasHeaderRow = flag
        }
    }

    func setDelimiter(_ delimiter: Character) {
        guard delimiter != table.delimiter else { return }
        mutate("Change Delimiter") { t in t.delimiter = delimiter }
    }

    // MARK: Sorting

    func applySort() {
        guard let comparator = sortOrder.first else { return }
        let sorted = table.rows.sorted { comparator.compare($0, $1) == .orderedAscending }
        guard sorted != table.rows else { return }
        mutate("Sort") { t in t.rows = sorted }
    }
}
