import Testing
import AppKit
@testable import Plainfile

/// Document windows must not use a full size content view. On macOS 26 that style
/// makes AppKit add a glass scroll pocket above every scroll view, which mirrors the
/// top of the content (grid lines, the ruler border) into the title bar.
@MainActor
struct WindowStyleTests {
    @Test func configuratorRemovesFullSizeContentView() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let configurator = WindowTabbingConfigurator.ConfiguratorView()
        window.contentView?.addSubview(configurator)
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(window.styleMask.contains(.titled))
    }

    @Test func tableScrollPocketStaysBelowTitleBar() {
        let model = TableModel(table: DelimitedText.parse("a,b\n1,2\n", delimiter: ",", hasHeaderRow: true))
        let coordinator = TableGridCoordinator(model: model)
        let scrollView = coordinator.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        scrollView.frame = window.contentView!.bounds
        window.contentView?.addSubview(scrollView)
        coordinator.apply(columns: model.columnInfos, generation: model.generation, selection: [], sortOrder: [])
        window.contentView?.layoutSubtreeIfNeeded()
        scrollView.displayIfNeeded()
        // macOS 26 adds a pocket for the table header even in a plain window, which is
        // fine. What must not happen is a pocket taller than the header, because that
        // extra part sits under the title bar and mirrors content into it.
        func pockets(_ view: NSView) -> [NSView] {
            let own = String(describing: type(of: view)) == "NSScrollPocket" && view.frame.height > 0 ? [view] : []
            return own + view.subviews.flatMap(pockets)
        }
        let headerHeight = coordinator.tableView.headerView?.frame.height ?? 0
        for pocket in pockets(scrollView) {
            #expect(pocket.frame.height <= headerHeight + 1, "scroll pocket \(pocket.frame) reaches above the table header (\(headerHeight)pt)")
        }
        #expect(scrollView.contentInsets.top == 0)
    }
}
