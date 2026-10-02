import Testing
import AppKit
import SwiftUI
@testable import Plainfile

/// Lays the status bar out at several window widths and checks that its controls
/// never overlap. The bar used to draw the mode picker as a centered overlay, which
/// landed on top of the table controls on narrow windows.
@MainActor
struct StatusBarLayoutTests {

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<StatusBarView>
    }

    private func makeDocument(csv: Bool) -> (PlainDocument, TableModel?) {
        let document = PlainDocument()
        if csv {
            document.text = "name,qty,price\nApple,3,1.20\nPear,12,0.80\n"
            document.language = LanguageRegistry.csv
            document.viewMode = .table
            let model = TableModel(table: DelimitedText.parse(document.text, delimiter: ",", hasHeaderRow: true))
            return (document, model)
        }
        document.text = "hello world\n"
        document.language = LanguageRegistry.plainText
        document.viewMode = .source
        return (document, nil)
    }

    private func host(csv: Bool, width: CGFloat) async -> Host {
        let (document, model) = makeDocument(csv: csv)
        let hosting = NSHostingView(rootView: StatusBarView(document: document, tableModel: model))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 28)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(80))
        hosting.layoutSubtreeIfNeeded()
        return Host(window: window, hosting: hosting)
    }

    /// One frame per control, in window coordinates. SwiftUI draws most controls itself
    /// on this OS, but it keeps one direct child view per control under the hosting view
    /// (focus ring views and platform view hosts), which is enough to measure layout.
    private func controls(in root: NSView) -> [(NSView, NSRect)] {
        root.subviews
            .filter { !$0.isHidden && $0.frame.width > 0 }
            .map { ($0, $0.convert($0.bounds, to: nil)) }
    }

    @Test(arguments: [true, false])
    func controlsDoNotOverlapAtAnyWidth(csv: Bool) async {
        for width: CGFloat in [1300, 1000, 800, 640, 500] {
            let h = await host(csv: csv, width: width)
            let items = controls(in: h.hosting)
            #expect(items.count >= 3, "expected controls at width \(width), found \(items.count)")
            let bar = h.hosting.convert(h.hosting.bounds, to: nil)
            for (view, frame) in items {
                #expect(bar.insetBy(dx: -1, dy: -1).contains(frame), "\(type(of: view)) \(frame) leaves the bar at width \(width)")
            }
            for i in items.indices {
                for j in items.indices where j > i {
                    let (a, fa) = items[i]
                    let (b, fb) = items[j]
                    if a.isDescendant(of: b) || b.isDescendant(of: a) { continue }
                    let overlap = fa.insetBy(dx: 0.5, dy: 0.5).intersection(fb.insetBy(dx: 0.5, dy: 0.5))
                    #expect(overlap.isEmpty, "\(type(of: a)) \(fa) overlaps \(type(of: b)) \(fb) at width \(width)")
                }
            }
        }
    }

    /// Writes the bar at a few widths to the container's tmp folder so the layout can be
    /// inspected without screen access.
    @Test func renderSnapshots() async throws {
        for width: CGFloat in [1300, 900, 640] {
            let h = await host(csv: true, width: width)
            h.window.appearance = NSAppearance(named: .aqua)
            let rep = try #require(h.hosting.bitmapImageRepForCachingDisplay(in: h.hosting.bounds))
            h.hosting.cacheDisplay(in: h.hosting.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("status-bar-\(Int(width)).png"))
        }
    }

    /// The plus, minus and column buttons sit side by side and must be the same height,
    /// even though their symbols are not.
    @Test func iconButtonsShareOneHeight() async {
        let h = await host(csv: true, width: 1300)
        let rings = controls(in: h.hosting).filter { String(describing: type(of: $0.0)).contains("FocusRing") }
        let firstThree = rings.sorted { $0.1.minX < $1.1.minX }.prefix(3)
        #expect(firstThree.count == 3)
        let heights = Set(firstThree.map { $0.1.height })
        #expect(heights.count == 1, "button heights differ: \(firstThree.map { $0.1 })")
    }

    @Test func pickersFoldIntoOverflowMenuWhenNarrow() async {
        let wide = await host(csv: true, width: 1400)
        let narrow = await host(csv: true, width: 640)
        func count(_ h: Host) -> Int { controls(in: h.hosting).count }
        func hasSegmented(_ h: Host) -> Bool {
            controls(in: h.hosting).contains { String(describing: type(of: $0.0)).contains("SegmentedControl") }
        }
        #expect(hasSegmented(wide))
        #expect(hasSegmented(narrow), "the mode picker must stay visible")
        #expect(count(narrow) < count(wide), "wide \(count(wide)) controls, narrow \(count(narrow))")
    }
}
