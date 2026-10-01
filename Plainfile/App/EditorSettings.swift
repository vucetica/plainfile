import SwiftUI
import AppKit

nonisolated enum SettingsKey {
    static let fontName = "editor.fontName"
    static let fontSize = "editor.fontSize"
    static let showLineNumbers = "editor.showLineNumbers"
    static let wrapLines = "editor.wrapLines"
    static let tabWidth = "editor.tabWidth"
    static let insertSpaces = "editor.insertSpaces"
    static let autoIndent = "editor.autoIndent"
    static let highlightCurrentLine = "editor.highlightCurrentLine"
    static let markdownFontSize = "markdown.fontSize"
    static let markdownDefaultMode = "markdown.defaultMode"
    static let markdownMaxWidth = "markdown.maxWidth"
    static let alwaysShowTabBar = "window.alwaysShowTabBar"
}

/// Snapshot of the editor preferences, read through `@AppStorage` in views and
/// passed by value into the AppKit representables.
struct EditorSettings: Equatable {
    var fontName: String = ""
    var fontSize: Double = 13
    var showLineNumbers = true
    var wrapLines = true
    var tabWidth = 4
    var insertSpaces = true
    var autoIndent = true
    var highlightCurrentLine = true
    var markdownFontSize: Double = 14
    var markdownMaxWidth: Double = 760

    var font: NSFont {
        let size = CGFloat(max(8, min(72, fontSize)))
        if !fontName.isEmpty, let f = NSFont(name: fontName, size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.fontName: "",
            SettingsKey.fontSize: 13.0,
            SettingsKey.showLineNumbers: true,
            SettingsKey.wrapLines: true,
            SettingsKey.tabWidth: 4,
            SettingsKey.insertSpaces: true,
            SettingsKey.autoIndent: true,
            SettingsKey.highlightCurrentLine: true,
            SettingsKey.markdownFontSize: 14.0,
            SettingsKey.markdownDefaultMode: ViewMode.rich.rawValue,
            SettingsKey.markdownMaxWidth: 760.0,
            SettingsKey.alwaysShowTabBar: true,
        ])
    }
}

/// A property wrapper bundle so views can read every setting with a single declaration.
@propertyWrapper
struct EditorSettingsReader: DynamicProperty {
    @AppStorage(SettingsKey.fontName) private var fontName = ""
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.showLineNumbers) private var showLineNumbers = true
    @AppStorage(SettingsKey.wrapLines) private var wrapLines = true
    @AppStorage(SettingsKey.tabWidth) private var tabWidth = 4
    @AppStorage(SettingsKey.insertSpaces) private var insertSpaces = true
    @AppStorage(SettingsKey.autoIndent) private var autoIndent = true
    @AppStorage(SettingsKey.highlightCurrentLine) private var highlightCurrentLine = true
    @AppStorage(SettingsKey.markdownFontSize) private var markdownFontSize = 14.0
    @AppStorage(SettingsKey.markdownMaxWidth) private var markdownMaxWidth = 760.0

    var wrappedValue: EditorSettings {
        EditorSettings(
            fontName: fontName, fontSize: fontSize, showLineNumbers: showLineNumbers, wrapLines: wrapLines,
            tabWidth: tabWidth, insertSpaces: insertSpaces, autoIndent: autoIndent,
            highlightCurrentLine: highlightCurrentLine, markdownFontSize: markdownFontSize,
            markdownMaxWidth: markdownMaxWidth
        )
    }
}
