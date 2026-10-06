import AppKit
import Observation

/// A selection in source text coordinates (UTF-16 ranges in `document.text`) that the
/// user made in one pane. Panes in a different view mode follow it.
struct LinkedSelection: Equatable {
    var ranges: [NSRange]
    var originPaneID: UUID
    var originMode: ViewMode
    var version: Int

    /// Whether `pane` should show this selection: it came from another pane that
    /// shows the document in a different way.
    func applies(to pane: EditorPane) -> Bool {
        originPaneID != pane.id && originMode != pane.viewMode
    }
}

/// One editor area of a document window. A window shows one pane, or two when split.
@Observable
final class EditorPane: Identifiable {
    let id = UUID()
    var viewMode: ViewMode {
        // Write back unsaved rich text edits before the editor for the old mode goes away.
        willSet { if newValue != viewMode { flushPendingEdits?() } }
    }
    /// The table model while the pane shows the table view. Each table pane has its own,
    /// so the two panes can filter and select independently.
    var tableModel: TableModel?
    let status = EditorStatus()

    // Installed by whichever editor the pane shows.
    @ObservationIgnored var formatHandler: ((FormatCommand) -> Void)?
    @ObservationIgnored var tableHandler: ((TableCommand) -> Void)?
    @ObservationIgnored var flushPendingEdits: (() -> Void)?

    /// The pane's selection in source text coordinates, so it survives a mode switch.
    @ObservationIgnored var lastSourceSelection: [NSRange] = []

    nonisolated init(viewMode: ViewMode) {
        _viewMode = viewMode
    }

    /// Creates the table model when the pane shows the table and drops it otherwise,
    /// so the table always starts from the current document text.
    func syncTableModel(for document: PlainDocument) {
        if document.isDelimited, viewMode == .table {
            if tableModel == nil { tableModel = Self.makeTableModel(for: document) }
        } else if tableModel != nil {
            tableModel = nil
        }
    }

    static func makeTableModel(for document: PlainDocument) -> TableModel {
        let table = DelimitedText.parse(document.text, delimiter: document.delimiter, hasHeaderRow: document.hasHeaderRow)
        let model = TableModel(table: table)
        model.updateSourceRanges(for: document.text)
        return model
    }
}

/// The panes of a document window and the selection they share.
@Observable
final class EditorLayout {
    /// Top pane first. Holds one pane, or two when the window is split.
    private(set) var panes: [EditorPane]
    private(set) var activePaneID: UUID
    /// Share of the height that the top pane takes when split.
    var topFraction: CGFloat = 0.5
    private(set) var linkedSelection: LinkedSelection?

    static let minimumPaneHeight: CGFloat = 60

    nonisolated init(viewMode: ViewMode) {
        let pane = EditorPane(viewMode: viewMode)
        _panes = [pane]
        _activePaneID = pane.id
    }

    var isSplit: Bool { panes.count > 1 }

    /// The pane that last had keyboard focus. Menus and the status bar act on it.
    var activePane: EditorPane {
        panes.first { $0.id == activePaneID } ?? panes[panes.count - 1]
    }

    /// Makes `pane` the active one. Unsaved rich text edits in the other pane are
    /// written back first, so they are not lost when this pane changes the text.
    func activate(_ pane: EditorPane) {
        guard pane.id != activePaneID, panes.contains(where: { $0.id == pane.id }) else { return }
        for other in panes where other.id != pane.id { other.flushPendingEdits?() }
        _activePaneID = pane.id
    }

    /// Adds a pane above the existing one. It starts in the active pane's mode at the
    /// same selection.
    func split(topFraction fraction: CGFloat = 0.5, document: PlainDocument) {
        guard !isSplit else { return }
        let source = activePane
        source.flushPendingEdits?()
        let pane = EditorPane(viewMode: source.viewMode)
        pane.lastSourceSelection = source.lastSourceSelection
        pane.syncTableModel(for: document)
        topFraction = min(max(fraction, 0.1), 0.9)
        panes.insert(pane, at: 0)
    }

    func removePane(_ pane: EditorPane) {
        guard isSplit, let index = panes.firstIndex(where: { $0.id == pane.id }) else { return }
        pane.flushPendingEdits?()
        panes.remove(at: index)
        if activePaneID == pane.id { activePaneID = panes[0].id }
    }

    func unsplit() {
        guard isSplit else { return }
        removePane(panes[0])
    }

    /// Called by a pane's editor when the user changes the selection there.
    func publishSelection(_ ranges: [NSRange], from pane: EditorPane) {
        pane.lastSourceSelection = ranges
        let version = (linkedSelection?.version ?? 0) &+ 1
        linkedSelection = LinkedSelection(ranges: ranges, originPaneID: pane.id, originMode: pane.viewMode, version: version)
    }
}
