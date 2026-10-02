import SwiftUI
import AppKit

/// Forces every document window into one native tab group so the app behaves as a
/// single window with tabs. Attached to the document view's background.
struct WindowTabbingConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }
    func updateNSView(_ nsView: ConfiguratorView, context: Context) {}

    /// Defaults key (through `NSWindow.saveFrame(usingName:)`) holding the frame of the
    /// document window the user last moved or resized. The first window of a launch
    /// reopens with it; later windows join the tab group and share its frame anyway.
    static let frameName = "PlainfileDocumentWindow"

    /// How often to check whether a new window is on screen, and how long after that
    /// to wait for SwiftUI and the tab bar to finish sizing it. Tests shorten both.
    static var visibilityPollInterval: TimeInterval = 0.1
    static var settleDelay: TimeInterval = 0.3

    final class ConfiguratorView: NSView {
        private weak var configuredWindow: NSWindow?
        nonisolated(unsafe) private var frameObservers: [NSObjectProtocol] = []
        /// Saving starts once the window has its final frame, so the intermediate sizes
        /// AppKit goes through while adding the title and tab bar are never remembered.
        private var isSavingEnabled = false

        deinit {
            for observer in frameObservers { NotificationCenter.default.removeObserver(observer) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window
            // The first window of a launch reopens at the remembered frame. This early
            // pass makes it appear near its final size; the window is not on screen yet,
            // so AppKit treats the frame as content and adds the title and tab bar on
            // top. The exact frame is applied again below once the window is visible.
            let isFirstWindow = WindowTabbingConfigurator.isFirstDocumentWindow(window)
            if isFirstWindow {
                window.setFrameUsingName(WindowTabbingConfigurator.frameName)
            }
            observeFrame(of: window)
            // SwiftUI gives document windows a full size content view. The editors do not
            // scroll under the title bar, and on macOS 26 that style makes AppKit add a
            // glass "scroll pocket" above every scroll view that mirrors the top of the
            // content into the title bar (grid lines appeared to run through it).
            window.styleMask.remove(.fullSizeContentView)
            // Keep the tabbing identifier SwiftUI assigns to document windows so a new
            // window matches the existing ones at the moment AppKit places it.
            window.tabbingMode = .preferred
            WindowTabbingConfigurator.configuredAt[window.windowNumber] = Date()
            // The window may already be on screen when this view is attached, in which
            // case AppKit has placed it on its own. Join the existing group explicitly.
            WindowTabbingConfigurator.attachWhenVisible(window, attempt: 0) { [weak self, weak window] in
                guard let self else { return }
                guard isFirstWindow else {
                    isSavingEnabled = true
                    return
                }
                // The tab bar applies its frame change after this callback, so wait a
                // moment before applying the exact remembered frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + WindowTabbingConfigurator.settleDelay) { [weak self, weak window] in
                    guard let self, let window else { return }
                    window.setFrameUsingName(WindowTabbingConfigurator.frameName)
                    isSavingEnabled = true
                }
            }
        }

        /// Remembers the frame whenever the window moves or resizes (including zoom and
        /// scripted resizes, which never post the live-resize notifications) and when it closes.
        private func observeFrame(of window: NSWindow) {
            for observer in frameObservers { NotificationCenter.default.removeObserver(observer) }
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification]
            frameObservers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.isSavingEnabled, let window, !window.isMiniaturized else { return }
                        window.saveFrame(usingName: WindowTabbingConfigurator.frameName)
                    }
                }
            }
        }
    }

    /// True when no other document window is on screen, so this window is the one
    /// that should pick up the remembered frame.
    static func isFirstDocumentWindow(_ window: NSWindow) -> Bool {
        !NSApp.orderedWindows.contains { other in
            other !== window && other.isVisible && other.tabbingIdentifier == window.tabbingIdentifier
        }
    }

    /// Waits until the window is on screen (the view can be attached before the window
    /// is ordered front), then joins the existing tab group and shows the tab bar.
    /// `completion` runs after the window joined its group and the tab bar is in place,
    /// when the window chrome is final.
    static func attachWhenVisible(_ window: NSWindow, attempt: Int, completion: @escaping @MainActor @Sendable () -> Void = {}) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : visibilityPollInterval)) { [weak window] in
            guard let window else { return }
            if !window.isVisible, attempt < 20 {
                attachWhenVisible(window, attempt: attempt + 1, completion: completion)
                return
            }
            attachToExistingGroup(window)
            let alwaysShow = UserDefaults.standard.bool(forKey: SettingsKey.alwaysShowTabBar)
            if alwaysShow, window.isVisible, let group = window.tabGroup, !group.isTabBarVisible {
                window.toggleTabBar(nil)
            }
            completion()
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
