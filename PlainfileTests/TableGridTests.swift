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

        // Column separators exist inside the rows and stop at the last row.
        func darkest(atY y: Int) -> CGFloat {
            var minBrightness: CGFloat = 1
            for x in Int((rect.minX - 5) * scale)...Int(rect.minX * scale) {
                if let c = rep.colorAt(x: x, y: y) { minBrightness = min(minBrightness, c.brightnessComponent) }
            }
            return minBrightness
        }
        // Reference pixel in the empty left part of the row-number column (numbers are right aligned).
        func beside(atY y: Int) -> CGFloat {
            rep.colorAt(x: Int((rect.minX - 24) * scale), y: y)?.brightnessComponent ?? 1
        }
        let rowY = Int((top + rect.height / 2) * scale)
        #expect(darkest(atY: rowY) < beside(atY: rowY) - 0.05, "separator missing inside the first row")

        let lastRow = h.scrollView.convert(h.tableView.rect(ofRow: h.tableView.numberOfRows - 1), from: h.tableView)
        let lastBottom = h.scrollView.isFlipped ? lastRow.maxY : h.scrollView.bounds.height - lastRow.minY
        for offset in [30, 60, 90] {
            let y = Int((lastBottom + CGFloat(offset)) * scale)
            #expect(abs(darkest(atY: y) - beside(atY: y)) < 0.02, "separator drawn \(offset)pt below the last row")
        }
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

    @Test func moveColumnReordersCellsAndHeaders() {
        let h = makeHarness()
        let undo = UndoManager()
        h.model.undoManager = undo
        h.model.moveColumn(from: 2, to: 0)
        h.sync()
        #expect(h.tableView.tableColumns.map(\.title) == ["#", "price", "name", "qty"])
        #expect(cellText(h, column: 1, row: 0) == "1.20")
        #expect(cellText(h, column: 2, row: 0) == "Apple")
        #expect(DelimitedText.serialize(h.model.table).hasPrefix("price,name,qty\n1.20,Apple,3"))

        #expect(undo.undoActionName == "Move Column")
        undo.undo()
        h.sync()
        #expect(h.tableView.tableColumns.map(\.title) == ["#", "name", "qty", "price"])
        #expect(cellText(h, column: 1, row: 0) == "Apple")
    }

    @Test func reorderKeepsSortAndWidths() {
        let h = makeHarness()
        h.model.sortOrder = [CellComparator(column: 1, order: .forward)]
        h.sync()
        h.tableView.tableColumns[2].width = 230
        h.model.moveColumn(from: 1, to: 2)
        h.sync()
        #expect(h.tableView.tableColumns.map(\.title) == ["#", "name", "price", "qty"])
        #expect(h.model.sortOrder == [CellComparator(column: 2, order: .forward)])
        #expect(h.tableView.sortDescriptors.first?.key == "col:2")
        #expect(h.tableView.tableColumns[3].width == 230)
        #expect(h.tableView.tableColumns[2].width == 160)
    }

    @Test func insertAndDeleteShiftSortAndWidths() {
        let h = makeHarness()
        h.model.sortOrder = [CellComparator(column: 2, order: .reverse)]
        h.sync()
        h.tableView.tableColumns[3].width = 210

        h.model.deleteColumn(0)
        h.sync()
        #expect(h.model.sortOrder == [CellComparator(column: 1, order: .reverse)])
        #expect(h.model.visibleRows.map { $0.cells[1] } == ["2.50", "1.20", "0.80"])
        #expect(h.tableView.tableColumns[2].title == "price")
        #expect(h.tableView.tableColumns[2].width == 210)

        h.model.insertColumn(named: "A", at: 0)
        h.sync()
        #expect(h.model.sortOrder == [CellComparator(column: 2, order: .reverse)])
        #expect(h.tableView.tableColumns.map(\.title) == ["#", "A", "qty", "price"])
        #expect(h.tableView.tableColumns[3].width == 210)

        h.model.deleteColumn(2)
        #expect(h.model.sortOrder.isEmpty, "deleting the sorted column drops the sort")
    }

    @Test func dragReorderUpdatesModel() {
        let h = makeHarness()
        #expect(!h.coordinator.tableView(h.tableView, shouldReorderColumn: 0, toColumn: 2))
        #expect(!h.coordinator.tableView(h.tableView, shouldReorderColumn: 2, toColumn: 0))
        #expect(h.coordinator.tableView(h.tableView, shouldReorderColumn: 1, toColumn: 3))

        h.tableView.moveColumn(1, toColumn: 3)
        h.coordinator.tableView(h.tableView, didDrag: h.tableView.tableColumns[3])
        h.sync()
        #expect(h.model.table.columns == ["qty", "price", "name"])
        #expect(h.tableView.tableColumns.map(\.identifier.rawValue) == ["rownum", "col:0", "col:1", "col:2"])
        #expect(cellText(h, column: 3, row: 0) == "Apple")
    }

    @Test func dragReorderWithDuplicateTitles() {
        let h = makeHarness("a,a\n1,2\n")
        h.tableView.moveColumn(2, toColumn: 1)
        h.coordinator.tableView(h.tableView, didDrag: h.tableView.tableColumns[1])
        h.sync()
        #expect(h.model.table.rows[0].cells == ["2", "1"])
        #expect(cellText(h, column: 1, row: 0) == "2")
        #expect(cellText(h, column: 2, row: 0) == "1")
    }

    @Test func headerContextMenu() throws {
        let h = makeHarness()
        let first = try #require(h.coordinator.columnMenu(for: 0))
        #expect(first.items.map(\.title) == ["Rename…", "Insert Column Left", "Insert Column Right", "", "Move Left", "Move Right", "", "Delete Column…"])
        #expect(!first.items[4].isEnabled)
        #expect(first.items[5].isEnabled)
        let last = try #require(h.coordinator.columnMenu(for: 2))
        #expect(last.items[4].isEnabled)
        #expect(!last.items[5].isEnabled)

        h.coordinator.moveColumnRight(first.items[5])
        #expect(h.model.table.columns == ["qty", "name", "price"])
        h.coordinator.insertColumnLeft(first.items[1])
        #expect(h.model.table.columns == ["Column 4", "qty", "name", "price"])
        h.coordinator.renameColumn(first.items[0])
        #expect(h.model.pendingRename?.id == 0)
        h.coordinator.deleteColumn(first.items[7])
        #expect(h.model.pendingDelete?.id == 0)

        let single = makeHarness("only\n1\n")
        let menu = try #require(single.coordinator.columnMenu(for: 0))
        #expect(!menu.items[7].isEnabled)
        #expect(!menu.items[4].isEnabled && !menu.items[5].isEnabled)
    }

    private func copyHarness() -> (Harness, NSPasteboard) {
        let h = makeHarness()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PlainfileTests.\(UUID().uuidString)"))
        h.coordinator.pasteboard = pasteboard
        return (h, pasteboard)
    }

    @Test func commandCopyWritesSelectedRows() {
        let (h, pasteboard) = copyHarness()
        defer { pasteboard.releaseGlobally() }
        h.tableView.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        #expect(h.tableView.validateUserInterfaceItem(NSMenuItem(title: "Copy", action: #selector(GridTableView.copy(_:)), keyEquivalent: "c")))
        h.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "Apple\t3\t1.20\nFig\t7\t2.50")
        #expect(pasteboard.string(forType: .html) == "<meta charset=\"utf-8\"><table><tr><td>Apple</td><td>3</td><td>1.20</td></tr><tr><td>Fig</td><td>7</td><td>2.50</td></tr></table>")

        h.tableView.deselectAll(nil)
        #expect(!h.tableView.validateUserInterfaceItem(NSMenuItem(title: "Copy", action: #selector(GridTableView.copy(_:)), keyEquivalent: "c")))
    }

    @Test func copyFollowsSortAndColumnOrder() {
        let (h, pasteboard) = copyHarness()
        defer { pasteboard.releaseGlobally() }
        h.model.sortOrder = [CellComparator(column: 1, order: .reverse)]
        h.model.moveColumn(from: 2, to: 0)
        h.sync()
        h.tableView.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        h.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "0.80\tPear\t12\n2.50\tFig\t7")
    }

    @Test func copyMenuItems() throws {
        let (h, pasteboard) = copyHarness()
        defer { pasteboard.releaseGlobally() }
        h.tableView.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)

        let menu = try #require(h.coordinator.rowMenu(for: 1, column: 2))
        #expect(Array(menu.items.map(\.title).prefix(3)) == ["Copy Cell", "Copy Rows", "Copy Rows with Header"])

        h.coordinator.copyCell(menu.items[0])
        #expect(pasteboard.string(forType: .string) == "0.80")
        #expect(pasteboard.string(forType: .html) == nil)

        h.coordinator.copyRowsWithHeader(menu.items[2])
        #expect(pasteboard.string(forType: .string) == "name\tqty\tprice\nApple\t3\t1.20\nPear\t12\t0.80")
        #expect(pasteboard.string(forType: .html)?.contains("<tr><th>name</th><th>qty</th><th>price</th></tr>") == true)

        // A row outside the selection copies only that row.
        let other = try #require(h.coordinator.rowMenu(for: 2))
        h.coordinator.copyRows(other.items[0])
        #expect(pasteboard.string(forType: .string) == "Fig\t7\t2.50")
    }

    @Test func clipboardFormatsKeepAwkwardCellsTogether() {
        let rows = [["a\tb", "line 1\nline 2", "say \"hi\""], ["<b>&", "", "plain"]]
        #expect(DelimitedText.clipboardText(rows) == "\"a\tb\"\t\"line 1\nline 2\"\t\"say \"\"hi\"\"\"\n<b>&\t\tplain")
        #expect(DelimitedText.clipboardHTML(rows) == "<meta charset=\"utf-8\"><table><tr><td>a\tb</td><td>line 1<br>line 2</td><td>say &quot;hi&quot;</td></tr><tr><td>&lt;b&gt;&amp;</td><td></td><td>plain</td></tr></table>")
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
        #expect(rowMenu.items.map(\.title) == ["Copy Row", "Copy Row with Header", "", "Insert Row Above", "Insert Row Below", "Duplicate Row", "", "Delete Row"])
        #expect(h.scrollView.menu?.items.map(\.title) == ["Add Row", "Add Column…"])

        let insertAbove = rowMenu.items[3]
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
        // About 0.7 s on an Apple silicon Mac and 1.7 s on a shared CI runner. The limit
        // only catches a large regression; the row view count above is the main check.
        #expect(elapsed < .seconds(4))
    }
}
