import SwiftUI

@main
struct PlainfileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        EditorSettings.registerDefaults()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { PlainDocument() }) { configuration in
            DocumentView(document: configuration.document, fileURL: configuration.fileURL)
        }
        // Used when no remembered window frame exists yet (see WindowTabbingConfigurator).
        .defaultSize(width: 1200, height: 800)
        .commands {
            ViewCommands()
            FormatCommands()
            TableCommands()
            TabCommands()
            HelpCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        // Ask AppKit to open new document windows as tabs of the key window regardless
        // of the system "Prefer tabs" setting, so they never appear standalone first.
        UserDefaults.standard.register(defaults: ["AppleWindowTabbingMode": "always"])
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    /// Backs the "+" button on the native tab bar: AppKit shows it when a responder
    /// implements this selector. A new untitled document opens as a tab.
    @objc func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }
}
