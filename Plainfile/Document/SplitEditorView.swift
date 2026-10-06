import SwiftUI

/// The editor area of a document window. A bar at the top splits it into two panes
/// when dragged down. The bar between two panes resizes them, and dragging it to an
/// edge (or double-clicking it) closes the split.
struct SplitEditorView: View {
    @ObservedObject var document: PlainDocument
    let fileURL: URL?
    /// Where the line that previews a new split is drawn while the top bar is dragged.
    @State private var splitPreview: CGFloat?

    static let barHeight: CGFloat = 7
    private static let space = "SplitEditor"

    private var layout: EditorLayout { document.layout }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            VStack(spacing: 0) {
                if !layout.isSplit {
                    SplitBar(help: "Drag down to split the editor")
                        .gesture(splitGesture(height: height))
                }
                ForEach(layout.panes) { pane in
                    if layout.isSplit, pane.id == layout.panes.last?.id {
                        SplitBar(help: "Drag to resize, or drag to an edge to close the split")
                            .gesture(dividerGesture(height: height))
                            .onTapGesture(count: 2) { layout.unsplit() }
                    }
                    let fixed = topPaneHeight(for: pane, total: height)
                    EditorPaneView(document: document, pane: pane, fileURL: fileURL)
                        .frame(minHeight: fixed ?? 0, maxHeight: fixed ?? .infinity)
                        .clipped()
                }
            }
            .overlay(alignment: .topLeading) {
                if let splitPreview {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: splitPreview)
                        .allowsHitTesting(false)
                }
            }
        }
        .coordinateSpace(.named(Self.space))
    }

    /// The fixed height of the top pane when split, or nil for a pane that fills
    /// the remaining space.
    private func topPaneHeight(for pane: EditorPane, total: CGFloat) -> CGFloat? {
        guard layout.isSplit, pane.id == layout.panes.first?.id else { return nil }
        return max(0, (total - Self.barHeight) * layout.topFraction)
    }

    private func splitGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                splitPreview = min(max(0, value.location.y), height)
            }
            .onEnded { value in
                splitPreview = nil
                let y = value.location.y
                let minimum = EditorLayout.minimumPaneHeight
                guard y >= minimum, height - y >= minimum else { return }
                layout.split(topFraction: y / height, document: document)
            }
    }

    private func dividerGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let usable = max(1, height - Self.barHeight)
                layout.topFraction = min(max(0, value.location.y / usable), 1)
            }
            .onEnded { value in
                let usable = height - Self.barHeight
                let top = value.location.y
                let minimum = EditorLayout.minimumPaneHeight
                if top < minimum {
                    layout.removePane(layout.panes[0])
                } else if usable - top < minimum {
                    layout.removePane(layout.panes[layout.panes.count - 1])
                }
            }
    }
}

/// The grab bar at the top of the editor and between split panes.
private struct SplitBar: View {
    let help: String

    var body: some View {
        ZStack {
            Rectangle().fill(.bar)
            Capsule()
                .fill(.tertiary)
                .frame(width: 32, height: 3)
        }
        .frame(height: SplitEditorView.barHeight)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .pointerStyle(.rowResize)
        .help(help)
    }
}
