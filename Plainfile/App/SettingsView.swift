import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(SettingsKey.fontName) private var fontName = ""
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.showLineNumbers) private var showLineNumbers = true
    @AppStorage(SettingsKey.wrapLines) private var wrapLines = true
    @AppStorage(SettingsKey.tabWidth) private var tabWidth = 4
    @AppStorage(SettingsKey.insertSpaces) private var insertSpaces = true
    @AppStorage(SettingsKey.autoIndent) private var autoIndent = true
    @AppStorage(SettingsKey.highlightCurrentLine) private var highlightCurrentLine = true
    @AppStorage(SettingsKey.markdownFontSize) private var markdownFontSize = 14.0
    @AppStorage(SettingsKey.markdownDefaultMode) private var markdownDefaultMode = ViewMode.rich.rawValue
    @AppStorage(SettingsKey.markdownMaxWidth) private var markdownMaxWidth = 760.0
    @AppStorage(SettingsKey.alwaysShowTabBar) private var alwaysShowTabBar = true

    private var monospacedFamilies: [String] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted()
    }

    var body: some View {
        TabView {
            editorTab
                .tabItem { Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right") }
            markdownTab
                .tabItem { Label("Markdown", systemImage: "doc.richtext") }
        }
        .frame(width: 440)
        .padding(.top, 8)
    }

    private var editorTab: some View {
        Form {
            Picker("Font", selection: $fontName) {
                Text("System Monospaced").tag("")
                Divider()
                ForEach(monospacedFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(value: $fontSize, in: 8...48, step: 1) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(fontSize)) pt").foregroundStyle(.secondary)
                }
            }
            Toggle("Always show tab bar", isOn: $alwaysShowTabBar)
            Toggle("Show line numbers", isOn: $showLineNumbers)
            Toggle("Wrap long lines", isOn: $wrapLines)
            Toggle("Highlight current line", isOn: $highlightCurrentLine)
            Toggle("Auto-indent new lines", isOn: $autoIndent)
            Picker("Indent with", selection: $insertSpaces) {
                Text("Spaces").tag(true)
                Text("Tabs").tag(false)
            }
            Stepper(value: $tabWidth, in: 1...16) {
                HStack {
                    Text("Tab width")
                    Spacer()
                    Text("\(tabWidth)").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var markdownTab: some View {
        Form {
            Picker("Open Markdown files as", selection: $markdownDefaultMode) {
                Text("Rich Text").tag(ViewMode.rich.rawValue)
                Text("Source").tag(ViewMode.source.rawValue)
            }
            Stepper(value: $markdownFontSize, in: 9...40, step: 1) {
                HStack {
                    Text("Text size")
                    Spacer()
                    Text("\(Int(markdownFontSize)) pt").foregroundStyle(.secondary)
                }
            }
            Stepper(value: $markdownMaxWidth, in: 400...2000, step: 40) {
                HStack {
                    Text("Maximum content width")
                    Spacer()
                    Text("\(Int(markdownMaxWidth)) pt").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
