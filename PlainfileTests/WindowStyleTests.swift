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

    @Test func tableScrollViewHasNoPocketWithoutFullSizeContentView() {
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
        func hasPocket(_ view: NSView) -> Bool {
            if String(describing: type(of: view)) == "NSScrollPocket", view.frame.height > 0 { return true }
            return view.subviews.contains { hasPocket($0) }
        }
        #expect(!hasPocket(scrollView), "AppKit added a scroll pocket above the table")
        #expect(scrollView.contentInsets.top == 0)
    }
}
