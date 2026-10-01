import SwiftUI
import AppKit

/// Forces every document window into one native tab group so the app behaves as a
/// single window with tabs. Attached to the document view's background.
struct WindowTabbingConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }
    func updateNSView(_ nsView: ConfiguratorView, context: Context) {}

    final class ConfiguratorView: NSView {
        private var configuredWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window
            // Keep the tabbing identifier SwiftUI assigns to document windows so a new
            // window matches the existing ones at the moment AppKit places it.
            window.tabbingMode = .preferred
            WindowTabbingConfigurator.configuredAt[window.windowNumber] = Date()
            // The window may already be on screen when this view is attached, in which
            // case AppKit has placed it on its own. Join the existing group explicitly.
            WindowTabbingConfigurator.attachWhenVisible(window, attempt: 0)
        }
    }

    /// Waits until the window is on screen (the view can be attached before the window
    /// is ordered front), then joins the existing tab group and shows the tab bar.
    static func attachWhenVisible(_ window: NSWindow, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.1)) { [weak window] in
            guard let window else { return }
            if !window.isVisible, attempt < 20 {
                attachWhenVisible(window, attempt: attempt + 1)
                return
            }
            attachToExistingGroup(window)
            let alwaysShow = UserDefaults.standard.bool(forKey: SettingsKey.alwaysShowTabBar)
            if alwaysShow, window.isVisible, let group = window.tabGroup, !group.isTabBarVisible {
                window.toggleTabBar(nil)
            }
        }
    }

    /// Windows configured recently, keyed by window number. Used to tell windows that
    /// arrive together (for example Help > Open Sample Files) from the window the user
    /// was already working in.
    nonisolated(unsafe) static var configuredAt: [Int: Date] = [:]
    private static let batchWindow: TimeInterval = 1.5

    /// Moves `window` into the tab group of the document window the user was using:
    /// the frontmost document window that was not created in the same batch.
    static func attachToExistingGroup(_ window: NSWindow) {
        let now = Date()
        configuredAt[window.windowNumber] = configuredAt[window.windowNumber] ?? now
        configuredAt = configuredAt.filter { now.timeIntervalSince($0.value) < 60 }

        // Front to back order, so the first match is the window the user sees on top.
        let identifier = window.tabbingIdentifier
        let candidates = NSApp.orderedWindows.filter {
            $0 !== window && $0.tabbingIdentifier == identifier && $0.isVisible && !$0.isMiniaturized
        }
        guard !candidates.isEmpty else { return }
        let established = candidates.filter { candidate in
            guard let stamp = configuredAt[candidate.windowNumber] else { return true }
            return now.timeIntervalSince(stamp) > batchWindow
        }
        let host = established.first ?? candidates[0]
        guard let hostGroup = host.tabGroup else {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let current = window.tabGroup, current === hostGroup { return }
        if let current = window.tabGroup, current.windows.count > 1 {
            current.removeWindow(window)
        }
        hostGroup.addWindow(window)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Tab operations on the key window's tab group.
enum TabActions {
    struct Neighbors {
        var left: [NSWindow]
        var right: [NSWindow]
        var others: [NSWindow] { left + right }
    }

    static var keyWindow: NSWindow? { NSApp.keyWindow }
    static var keyTabGroup: NSWindowTabGroup? { keyWindow?.tabGroup }

    /// Splits the group's windows around `window`, in tab order.
    static func neighbors(of window: NSWindow, in windows: [NSWindow]) -> Neighbors {
        guard let index = windows.firstIndex(where: { $0 === window }) else {
            return Neighbors(left: [], right: [])
        }
        return Neighbors(left: Array(windows[..<index]), right: Array(windows[(index + 1)...]))
    }

    static var neighbors: Neighbors? {
        guard let window = keyWindow, let group = window.tabGroup else { return nil }
        return neighbors(of: window, in: group.windows)
    }

    static func closeOtherTabs() { close(neighbors?.others ?? []) }
    static func closeTabsToTheRight() { close(neighbors?.right ?? []) }
    static func closeTabsToTheLeft() { close(neighbors?.left ?? []) }

    static func showNextTab() { keyWindow?.selectNextTab(nil) }
    static func showPreviousTab() { keyWindow?.selectPreviousTab(nil) }

    /// Closes windows through `performClose`, so edited documents prompt to save.
    private static func close(_ windows: [NSWindow]) {
        for window in windows.reversed() {
            window.performClose(nil)
        }
    }
}

/// Window menu items for tab management.
struct TabCommands: Commands {
    @FocusedValue(\.plainDocument) private var document

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Close Other Tabs") { TabActions.closeOtherTabs() }
                .keyboardShortcut("w", modifiers: [.command, .option, .shift])
                .disabled(TabActions.neighbors?.others.isEmpty ?? true)
            Button("Close Tabs to the Right") { TabActions.closeTabsToTheRight() }
                .disabled(TabActions.neighbors?.right.isEmpty ?? true)
            Button("Close Tabs to the Left") { TabActions.closeTabsToTheLeft() }
                .disabled(TabActions.neighbors?.left.isEmpty ?? true)
            Divider()
            Button("Show Previous Tab") { TabActions.showPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((TabActions.keyTabGroup?.windows.count ?? 0) < 2)
            Button("Show Next Tab") { TabActions.showNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((TabActions.keyTabGroup?.windows.count ?? 0) < 2)
            Divider()
        }
    }
}
