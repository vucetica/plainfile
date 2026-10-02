import Testing
import AppKit
@testable import Plainfile

/// The first document window of a launch reopens with the frame the user last used.
@MainActor
struct WindowFrameTests {
    private let defaultsKey = "NSWindow Frame \(WindowTabbingConfigurator.frameName)"

    private func makeWindow(size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(WindowTabbingConfigurator.ConfiguratorView())
        return window
    }

    @Test func firstWindowRestoresSavedFrame() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: defaultsKey)
        let (pollInterval, settleDelay) = (WindowTabbingConfigurator.visibilityPollInterval, WindowTabbingConfigurator.settleDelay)
        WindowTabbingConfigurator.visibilityPollInterval = 0.01
        WindowTabbingConfigurator.settleDelay = 0.01
        defer {
            if let previous { defaults.set(previous, forKey: defaultsKey) } else { defaults.removeObject(forKey: defaultsKey) }
            WindowTabbingConfigurator.visibilityPollInterval = pollInterval
            WindowTabbingConfigurator.settleDelay = settleDelay
        }
        defaults.removeObject(forKey: defaultsKey)

        let first = makeWindow(size: NSSize(width: 600, height: 400))
        // Sizes are only remembered once the window has settled (the configurator gives
        // up waiting for visibility after 20 polls).
        first.setFrame(NSRect(x: 40, y: 60, width: 900, height: 500), display: false)
        #expect(defaults.string(forKey: defaultsKey) == nil, "nothing saved before the window settled")
        try await Task.sleep(for: .milliseconds(600))
        // A plain setFrame posts didResizeNotification, the same as a zoom or scripted resize.
        first.setFrame(NSRect(x: 40, y: 60, width: 1100, height: 700), display: false)
        #expect(defaults.string(forKey: defaultsKey) != nil, "frame saved after a resize")
        first.close()

        let second = makeWindow(size: NSSize(width: 600, height: 400))
        #expect(second.frame.size == NSSize(width: 1100, height: 700), "got \(second.frame)")
        second.close()
    }

    @Test func windowWithoutSavedFrameKeepsItsSize() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: defaultsKey)
        defer {
            if let previous { defaults.set(previous, forKey: defaultsKey) } else { defaults.removeObject(forKey: defaultsKey) }
        }
        defaults.removeObject(forKey: defaultsKey)
        let window = makeWindow(size: NSSize(width: 640, height: 480))
        #expect(window.frame.size == NSSize(width: 640, height: 480) || window.frame.height > 480,
                "title bar may add height, got \(window.frame)")
        window.close()
    }
}
