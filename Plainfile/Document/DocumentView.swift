import SwiftUI

/// Root view for a document window: the editor area, which can be split into two
/// panes, above the status bar. There is no window toolbar: the status bar carries
/// the controls for every file type, so switching between tabs of different kinds
/// keeps the same layout.
struct DocumentView: View {
    @ObservedObject var document: PlainDocument
    let fileURL: URL?

    init(document: PlainDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        // Build table models up front so a table shows on the first frame.
        for pane in document.layout.panes { pane.syncTableModel(for: document) }
    }

    var body: some View {
        SplitEditorView(document: document, fileURL: fileURL)
            .frame(minWidth: 480, minHeight: 320)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView(document: document, tableModel: document.layout.activePane.tableModel)
            }
            .focusedSceneValue(\.plainDocument, document)
            .background(WindowTabbingConfigurator())
    }
}
