import SwiftUI

/// Hosts the AppKit grid. The inputs are plain values read from the model by the
/// SwiftUI shell, so observation re-runs `updateNSView` when any of them change and
/// the coordinator only applies what differs from the last update.
struct TableGridView: NSViewRepresentable {
    let model: TableModel
    let columns: [ColumnInfo]
    let generation: Int
    let selection: Set<UUID>
    let sortOrder: [CellComparator]

    func makeCoordinator() -> TableGridCoordinator {
        TableGridCoordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = context.coordinator.makeScrollView()
        context.coordinator.apply(columns: columns, generation: generation, selection: selection, sortOrder: sortOrder)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(columns: columns, generation: generation, selection: selection, sortOrder: sortOrder)
    }
}
