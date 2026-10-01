import AppKit

/// Dynamic colors that adapt to light and dark appearance.
nonisolated struct EditorTheme {

    static func dynamic(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    let text = NSColor.textColor
    let background = NSColor.textBackgroundColor
    let lineNumber = NSColor.tertiaryLabelColor
    let currentLineNumber = NSColor.secondaryLabelColor
    let currentLineBackground = dynamic(light: "#F3F4F7", dark: "#232529")
    let gutterBackground = NSColor.textBackgroundColor
    let gutterSeparator = NSColor.separatorColor

    let keyword = dynamic(light: "#9B2393", dark: "#FC5FA3")
    let type = dynamic(light: "#0B4F79", dark: "#5DD8FF")
    let string = dynamic(light: "#C41A16", dark: "#FC6A5D")
    let comment = dynamic(light: "#5D6C79", dark: "#7F8C98")
    let number = dynamic(light: "#1C00CF", dark: "#D0BF69")
    let literal = dynamic(light: "#1C00CF", dark: "#D0BF69")
    let preprocessor = dynamic(light: "#643820", dark: "#FD8F3F")
    let attribute = dynamic(light: "#947100", dark: "#BF8555")
    let function = dynamic(light: "#326D74", dark: "#67B7A4")
    let variable = dynamic(light: "#0F68A0", dark: "#41A1C0")
    let key = dynamic(light: "#3F6E75", dark: "#78C2B3")
    let tag = dynamic(light: "#9B2393", dark: "#FC5FA3")
    let attributeName = dynamic(light: "#947100", dark: "#D0BF69")
    let punctuation = NSColor.secondaryLabelColor
    let heading = dynamic(light: "#1C00CF", dark: "#9EC1FF")
    let emphasis = dynamic(light: "#804FB3", dark: "#C792EA")
    let codeSpan = dynamic(light: "#C41A16", dark: "#FC6A5D")
    let link = NSColor.linkColor
    let url = NSColor.secondaryLabelColor
    let listMarker = dynamic(light: "#9B2393", dark: "#FC5FA3")
    let escape = dynamic(light: "#0F68A0", dark: "#41A1C0")

    func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword: keyword
        case .type: type
        case .string: string
        case .comment: comment
        case .number: number
        case .literal: literal
        case .preprocessor: preprocessor
        case .attribute: attribute
        case .function: function
        case .variable: variable
        case .key: key
        case .tag: tag
        case .attributeName: attributeName
        case .punctuation: punctuation
        case .heading: heading
        case .emphasis: emphasis
        case .strong: emphasis
        case .codeSpan: codeSpan
        case .link: link
        case .url: url
        case .listMarker: listMarker
        case .escape: escape
        }
    }

    /// Font trait adjustments for Markdown source.
    func fontTraits(for kind: TokenKind) -> NSFontDescriptor.SymbolicTraits {
        switch kind {
        case .heading, .strong: [.bold]
        case .emphasis: [.italic]
        default: []
        }
    }
}

nonisolated extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
