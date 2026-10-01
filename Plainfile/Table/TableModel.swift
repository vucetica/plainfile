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

    weak var undoManager: UndoManager?
    var onChange: ((DelimitedTable) -> Void)?

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
        mutate("Add Column") { t in
            let title = name ?? "Column \(t.columns.count + 1)"
            let at = index.map { $0 + 1 } ?? t.columns.count
            t.columns.insert(title, at: at)
            for i in t.rows.indices { t.rows[i].cells.insert("", at: at) }
        }
    }

    func renameColumn(_ index: Int, to name: String) {
        guard index < table.columns.count, table.columns[index] != name else { return }
        mutate("Rename Column") { t in
            t.columns[index] = name
        }
    }

    func deleteColumn(_ index: Int) {
        guard table.columns.count > 1, index < table.columns.count else { return }
        sortOrder.removeAll { $0.column == index }
        mutate("Delete Column") { t in
            t.columns.remove(at: index)
            for i in t.rows.indices where index < t.rows[i].cells.count { t.rows[i].cells.remove(at: index) }
        }
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
