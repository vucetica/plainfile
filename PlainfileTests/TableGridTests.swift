import Testing
import AppKit
@testable import Plainfile

/// Drives the AppKit grid in-process without SwiftUI.
@MainActor
struct TableGridTests {

    private struct Harness {
        let model: TableModel
        let coordinator: TableGridCoordinator
        let scrollView: NSScrollView
        let window: NSWindow
        var tableView: GridTableView { coordinator.tableView }

        func sync() {
            coordinator.apply(columns: model.columnInfos, generation: model.generation, selection: model.selection, sortOrder: model.sortOrder)
            tableView.layoutSubtreeIfNeeded()
        }
    }

    private static let sampleCSV = """
    name,qty,price
    Apple,3,1.20
    Pear,12,0.80
    Fig,7,2.50
    """

    private func makeHarness(_ csv: String = sampleCSV, size: NSSize = NSSize(width: 800, height: 400)) -> Harness {
        let model = TableModel(table: DelimitedText.parse(csv, delimiter: ",", hasHeaderRow: true))
        let coordinator = TableGridCoordinator(model: model)
        let scrollView = coordinator.makeScrollView()
        scrollView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeFirstResponder(coordinator.tableView)
        let harness = Harness(model: model, coordinator: coordinator, scrollView: scrollView, window: window)
        harness.sync()
        return harness
    }

    /// The text field being edited (the field editor's delegate) and its table position.
    private func editing(_ h: Harness) -> (field: NSTextField, row: Int, column: Int)? {
        guard let editor = h.window.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField else { return nil }
        return (field, h.tableView.row(for: field), h.tableView.column(for: field))
    }

    private func cellText(_ h: Harness, column: Int, row: Int) -> String? {
        (h.tableView.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
    }

    @Test func columnsAndRowsMirrorModel() {
        let h = makeHarness()
        #expect(h.tableView.tableColumns.count == 4)
        #expect(h.tableView.tableColumns.map(\.title) == ["#", "name", "qty", "price"])
        #expect(h.tableView.numberOfRows == 3)
        #expect(cellText(h, column: 0, row: 0) == "1")
        #expect(cellText(h, column: 1, row: 0) == "Apple")
        #expect(cellText(h, column: 3, row: 2) == "2.50")
    }

    /// The text field must fill the cell, otherwise its text is drawn outside the clipped row.
    @Test func cellFieldsFillTheirCells() throws {
        let h = makeHarness()
        h.tableView.layoutSubtreeIfNeeded()
        for column in 0..<h.tableView.tableColumns.count {
            let cell = try #require(h.tableView.view(atColumn: column, row: 0, makeIfNecessary: true) as? NSTableCellView)
            let field = try #require(cell.textField)
            #expect(cell.bounds.height == TableGridCoordinator.rowHeight)
            #expect(field.frame == cell.bounds, "column \(column): field \(field.frame) in cell \(cell.bounds)")
        }
    }

    /// Renders the grid and checks that a data cell contains non-background pixels.
    @Test func dataCellsRenderText() throws {
        let h = makeHarness()
        h.window.appearance = NSAppearance(named: .aqua)
        h.scrollView.layoutSubtreeIfNeeded()
        let rep = try #require(h.scrollView.bitmapImageRepForCachingDisplay(in: h.scrollView.bounds))
        h.scrollView.cacheDisplay(in: h.scrollView.bounds, to: rep)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("table-grid-snapshot.png")
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        let cell = try #require(h.tableView.view(atColumn: 1, row: 0, makeIfNecessary: true))
        let rect = h.scrollView.convert(cell.bounds, from: cell)
        let scale = CGFloat(rep.pixelsWide) / h.scrollView.bounds.width
        // Bitmap rows run top-down; the scroll view's coordinates may or may not be flipped.
        let top = h.scrollView.isFlipped ? rect.minY : h.scrollView.bounds.height - rect.maxY
        var dark = 0
        let x0 = Int(rect.minX * scale), x1 = Int(rect.maxX * scale)
        let y0 = Int(top * scale), y1 = Int((top + rect.height) * scale)
        for x in x0..<x1 {
            for y in y0..<y1 {
                if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.5 { dark += 1 }
            }
        }
        #expect(dark > 20, "expected text pixels in the first data cell, found \(dark)")
    }

    @Test func selectionSyncsBothWays() {
        let h = makeHarness()
        h.tableView.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        #expect(h.model.selection == Set([h.model.table.rows[0].id, h.model.table.rows[2].id]))

        h.model.selection = [h.model.table.rows[1].id]
        h.sync()
        #expect(h.tableView.selectedRowIndexes == IndexSet(integer: 1))
    }

    @Test func headerSortFeedsModel() {
        let h = makeHarness()
        h.tableView.sortDescriptors = [NSSortDescriptor(key: "col:1", ascending: false)]
        #expect(h.model.sortOrder == [CellComparator(column: 1, order: .reverse)])
        h.sync()
        #expect(h.model.visibleRows.map { $0.cells[0] } == ["Pear", "Fig", "Apple"])
        #expect(cellText(h, column: 1, row: 0) == "Pear")

        h.model.sortOrder = []
        h.sync()
        #expect(h.tableView.sortDescriptors.isEmpty)
    }

    @Test func editCommitsOnceWithUndo() throws {
        let h = makeHarness()
        let undo = UndoManager()
        h.model.undoManager = undo
        h.coordinator.beginEditing(row: 0, column: 0)
        let editor = try #require(h.window.firstResponder as? NSTextView)
        editor.string = "Apricot"
        h.window.makeFirstResponder(h.tableView)

        #expect(h.model.table.rows[0].cells[0] == "Apricot")
        #expect(undo.canUndo)
        #expect(undo.undoActionName == "Edit Cell")
        undo.undo()
        #expect(h.model.table.rows[0].cells[0] == "Apple")
        #expect(!undo.canUndo)
    }

    @Test func tabAndReturnNavigate() async throws {
        let h = makeHarness()
        h.coordinator.beginEditing(row: 0, column: 0)
        var current = try #require(editing(h))
        #expect(current.row == 0 && current.column == 1)
        var editor = try #require(h.window.firstResponder as? NSTextView)
        #expect(h.coordinator.control(current.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        try await Task.sleep(for: .milliseconds(50))
        current = try #require(editing(h))
        #expect(current.row == 0 && current.column == 2)

        editor = try #require(h.window.firstResponder as? NSTextView)
        #expect(h.coordinator.control(current.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        try await Task.sleep(for: .milliseconds(50))
        current = try #require(editing(h))
        #expect(current.row == 1 && current.column == 2)

        // Escape restores the original value and ends editing without a commit.
        editor = try #require(h.window.firstResponder as? NSTextView)
        editor.string = "scratch"
        #expect(h.coordinator.control(current.field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(editing(h) == nil)
        #expect(h.model.table.rows[1].cells[1] == "12")
    }

    @Test func filterAndColumnOpsReconcile() {
        let h = makeHarness()
        h.model.filter = "pear"
        h.sync()
        #expect(h.tableView.numberOfRows == 1)
        #expect(cellText(h, column: 0, row: 0) == "2", "row numbers keep file order")
        h.model.filter = ""
        h.sync()
        #expect(h.tableView.numberOfRows == 3)

        h.model.addColumn(named: "X")
        h.sync()
        #expect(h.tableView.tableColumns.count == 5)
        #expect(h.tableView.tableColumns.last?.title == "X")

        h.model.renameColumn(0, to: "Y")
        h.sync()
        #expect(h.tableView.tableColumns[1].title == "Y")

        h.model.deleteColumn(0)
        h.sync()
        #expect(h.tableView.tableColumns.count == 4)
        #expect(h.tableView.tableColumns.map(\.title) == ["#", "qty", "price", "X"])
    }

    @Test func deleteKeyRemovesSelection() throws {
        let h = makeHarness()
        h.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: h.window.windowNumber,
            context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51))
        h.tableView.keyDown(with: event)
        h.sync()
        #expect(h.model.table.rows.count == 2)
        #expect(h.model.selection.isEmpty)
        #expect(h.tableView.numberOfRows == 2)
    }

    @Test func contextMenus() throws {
        let h = makeHarness()
        let rowMenu = try #require(h.coordinator.rowMenu(for: 0))
        #expect(rowMenu.items.map(\.title) == ["Insert Row Above", "Insert Row Below", "Duplicate Row", "", "Delete Row"])
        #expect(h.scrollView.menu?.items.map(\.title) == ["Add Row", "Add Column…"])

        let insertAbove = rowMenu.items[0]
        h.coordinator.insertRowAbove(insertAbove)
        h.sync()
        #expect(h.model.table.rows.count == 4)
        #expect(h.model.table.rows[1].cells[0] == "Apple")
        #expect(h.tableView.numberOfRows == 4)

        h.coordinator.addColumn(nil)
        #expect(h.model.showAddColumn)
    }

    /// Scrolls through a large table and checks that the row views are reused rather
    /// than created per row. Prints the timing so it can be compared between runs.
    @Test func scrollBenchmark() {
        let rows = 50_000
        let columns = 12
        var csv = (0..<columns).map { "col\($0)" }.joined(separator: ",") + "\n"
        csv.reserveCapacity(rows * columns * 8)
        for r in 0..<rows {
            csv += (0..<columns).map { "r\(r)c\($0)" }.joined(separator: ",")
            csv += "\n"
        }
        let h = makeHarness(csv, size: NSSize(width: 1200, height: 600))
        #expect(h.tableView.numberOfRows == rows)

        let clip = h.scrollView.contentView
        let maxY = h.tableView.bounds.height - clip.bounds.height
        let steps = 100
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for i in 0...steps {
                let y = maxY * CGFloat(i) / CGFloat(steps)
                clip.scroll(to: NSPoint(x: 0, y: y))
                h.scrollView.reflectScrolledClipView(clip)
                h.tableView.layoutSubtreeIfNeeded()
                h.tableView.displayIfNeeded()
            }
        }
        print("TableGrid scroll benchmark: \(rows) rows x \(columns) columns, \(steps) steps in \(elapsed)")

        let visible = h.tableView.rows(in: h.tableView.visibleRect).length
        let rowViews = h.tableView.subviews.filter { $0 is NSTableRowView }.count
        #expect(rowViews <= visible + 10, "row views are reused, got \(rowViews) for \(visible) visible rows")
        #expect(elapsed < .seconds(1.5))
    }
}
