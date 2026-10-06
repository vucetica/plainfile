import SwiftUI

/// One editor area of a document window. Picks the editor for the pane's view mode.
struct EditorPaneView: View {
    @ObservedObject var document: PlainDocument
    let pane: EditorPane
    let fileURL: URL?
    @EditorSettingsReader private var settings

    var body: some View {
        // The ZStack keeps the hierarchy non-empty while the editor switches, so the
        // modifiers below always take effect.
        ZStack {
            editor
        }
            .onAppear { pane.syncTableModel(for: document) }
            .onChange(of: pane.viewMode) { _, _ in pane.syncTableModel(for: document) }
            .onChange(of: document.language) { _, _ in pane.syncTableModel(for: document) }
    }

    @ViewBuilder
    private var editor: some View {
        let linkedSelection = document.layout.linkedSelection
        switch pane.viewMode {
        case .rich where document.isMarkdown:
            RichMarkdownEditorView(document: document, pane: pane, fileURL: fileURL, settings: settings, linkedSelection: linkedSelection)
                .id("rich")
        case .table where document.isDelimited:
            if let tableModel = pane.tableModel {
                TableEditorView(document: document, pane: pane, model: tableModel, linkedSelection: linkedSelection)
                    .id("table-\(document.language.id)")
            } else {
                Color.clear
            }
        default:
            CodeEditorView(document: document, pane: pane, settings: settings, linkedSelection: linkedSelection)
                .id("source")
        }
    }
}
