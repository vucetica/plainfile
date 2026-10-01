import Testing
import AppKit
@testable import Plainfile

@MainActor
struct TabActionsTests {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
    }

    @Test func partitionsAroundTheKeyWindow() {
        let a = window(), b = window(), c = window(), d = window()
        let n = TabActions.neighbors(of: c, in: [a, b, c, d])
        #expect(n.left.map { ObjectIdentifier($0) } == [a, b].map { ObjectIdentifier($0) })
        #expect(n.right.map { ObjectIdentifier($0) } == [ObjectIdentifier(d)])
        #expect(n.others.count == 3)
    }

    @Test func edgesAndMissingWindow() {
        let a = window(), b = window()
        #expect(TabActions.neighbors(of: a, in: [a, b]).left.isEmpty)
        #expect(TabActions.neighbors(of: b, in: [a, b]).right.isEmpty)
        let n = TabActions.neighbors(of: window(), in: [a, b])
        #expect(n.left.isEmpty && n.right.isEmpty)
    }
}
