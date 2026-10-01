import AppKit

extension NSAttributedString.Key {
    /// Int heading level (1...6) on heading paragraphs.
    static let pfHeadingLevel = NSAttributedString.Key("pf.headingLevel")
    /// Bool marking inline code spans.
    static let pfInlineCode = NSAttributedString.Key("pf.inlineCode")
    /// `ImageReference` attached to an attachment character.
    static let pfImage = NSAttributedString.Key("pf.image")
    /// Bool marking raw HTML that is preserved verbatim.
    static let pfRaw = NSAttributedString.Key("pf.raw")
    /// Bool marking a thematic break paragraph.
    static let pfThematicBreak = NSAttributedString.Key("pf.thematicBreak")
    /// Bool: task list checkbox state on the checkbox marker.
    static let pfTask = NSAttributedString.Key("pf.task")
}

nonisolated final class ImageReference: NSObject, Sendable {
    let source: String
    let alt: String
    let title: String?
    init(source: String, alt: String, title: String?) {
        self.source = source
        self.alt = alt
        self.title = title
    }
}

/// Text block used for fenced code blocks; identity groups the lines of one block.
nonisolated final class CodeTextBlock: NSTextBlock {
    var language: String

    init(language: String) {
        self.language = language
        super.init()
        setValue(100, type: .percentageValueType, for: .width)
        setWidth(12, type: .absoluteValueType, for: .padding)
        setWidth(6, type: .absoluteValueType, for: .padding, edge: .minY)
        setWidth(10, type: .absoluteValueType, for: .padding, edge: .maxY)
        setWidth(0, type: .absoluteValueType, for: .border)
        setWidth(6, type: .absoluteValueType, for: .margin, edge: .minY)
        setWidth(6, type: .absoluteValueType, for: .margin, edge: .maxY)
        backgroundColor = MarkdownStyle.codeBackground
    }

    required init?(coder: NSCoder) {
        language = ""
        super.init(coder: coder)
    }
}

/// Text block for block quotes: a left border and indentation.
nonisolated final class QuoteTextBlock: NSTextBlock {
    override init() {
        super.init()
        setValue(100, type: .percentageValueType, for: .width)
        setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        setWidth(0, type: .absoluteValueType, for: .border, edge: .maxX)
        setWidth(0, type: .absoluteValueType, for: .border, edge: .minY)
        setWidth(0, type: .absoluteValueType, for: .border, edge: .maxY)
        setWidth(14, type: .absoluteValueType, for: .padding, edge: .minX)
        setWidth(2, type: .absoluteValueType, for: .padding, edge: .minY)
        setWidth(2, type: .absoluteValueType, for: .padding, edge: .maxY)
        setWidth(4, type: .absoluteValueType, for: .margin, edge: .minY)
        setWidth(4, type: .absoluteValueType, for: .margin, edge: .maxY)
        setBorderColor(NSColor.tertiaryLabelColor)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }
}

/// Text block used to draw a horizontal rule.
nonisolated final class RuleTextBlock: NSTextBlock {
    override init() {
        super.init()
        setValue(100, type: .percentageValueType, for: .width)
        setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
        setWidth(0, type: .absoluteValueType, for: .border, edge: .maxY)
        setWidth(0, type: .absoluteValueType, for: .border, edge: .minX)
        setWidth(0, type: .absoluteValueType, for: .border, edge: .maxX)
        setWidth(14, type: .absoluteValueType, for: .margin, edge: .minY)
        setWidth(14, type: .absoluteValueType, for: .margin, edge: .maxY)
        setBorderColor(NSColor.separatorColor)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }
}

/// Fonts, colors and paragraph styles for the rich Markdown editor.
nonisolated struct MarkdownStyle {
    var baseSize: CGFloat = 14
    var maxWidth: CGFloat = 760

    static let codeBackground = EditorTheme.dynamic(light: "#F4F4F6", dark: "#2A2A2E")
    static let inlineCodeBackground = EditorTheme.dynamic(light: "#EEEEF1", dark: "#333338")
    static let tableHeaderBackground = EditorTheme.dynamic(light: "#F5F5F7", dark: "#2C2C30")

    /// Marker format for task list items. AppKit inserts this marker for new items.
    static let taskMarkerFormat = NSTextList.MarkerFormat(rawValue: "☐")
    static let orderedMarkerFormat = NSTextList.MarkerFormat(rawValue: "{decimal}.")

    var bodyFont: NSFont { .systemFont(ofSize: baseSize) }
    var codeFont: NSFont { .monospacedSystemFont(ofSize: baseSize * 0.88, weight: .regular) }
    var textColor: NSColor { .textColor }
    var secondaryColor: NSColor { .secondaryLabelColor }
    var markerColor: NSColor { .controlAccentColor }

    func headingFont(level: Int) -> NSFont {
        let scale: CGFloat
        switch level {
        case 1: scale = 1.9
        case 2: scale = 1.5
        case 3: scale = 1.25
        case 4: scale = 1.1
        case 5: scale = 1.0
        default: scale = 0.92
        }
        return .systemFont(ofSize: round(baseSize * scale), weight: level <= 2 ? .bold : .semibold)
    }

    func bodyParagraphStyle() -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.2
        p.paragraphSpacing = baseSize * 0.9
        p.lineBreakMode = .byWordWrapping
        return p
    }

    func headingParagraphStyle(level: Int) -> NSMutableParagraphStyle {
        let p = bodyParagraphStyle()
        switch level {
        case 1: p.paragraphSpacingBefore = baseSize * 0.6
        case 2: p.paragraphSpacingBefore = baseSize * 1.5
        default: p.paragraphSpacingBefore = baseSize * 1.1
        }
        p.paragraphSpacing = baseSize * 0.7
        p.lineHeightMultiple = 1.1
        return p
    }

    func codeParagraphStyle(block: CodeTextBlock) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.15
        p.paragraphSpacing = 0
        p.textBlocks = [block]
        p.lineBreakMode = .byCharWrapping
        return p
    }

    static let listIndent: CGFloat = 24

    func listParagraphStyle(lists: [NSTextList], base: NSMutableParagraphStyle, firstInList: Bool = false, lastInList: Bool = false) -> NSMutableParagraphStyle {
        let depth = CGFloat(lists.count)
        let p = base
        p.textLists = lists
        let markerStart = Self.listIndent * (depth - 1) + 8
        let textStart = Self.listIndent * depth + 8
        p.headIndent = textStart
        p.firstLineHeadIndent = markerStart
        p.tabStops = [
            NSTextTab(textAlignment: .natural, location: markerStart, options: [:]),
            NSTextTab(textAlignment: .natural, location: textStart, options: [:]),
        ]
        p.defaultTabInterval = Self.listIndent
        p.paragraphSpacing = lastInList && lists.count == 1 ? baseSize * 0.9 : baseSize * 0.3
        p.paragraphSpacingBefore = firstInList && lists.count == 1 ? baseSize * 0.2 : 0
        return p
    }

    func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: textColor, .paragraphStyle: bodyParagraphStyle()]
    }

    /// Ordered list detection by marker format.
    static func isOrdered(_ format: NSTextList.MarkerFormat) -> Bool {
        let ordered = ["{decimal}", "{lower-alpha}", "{upper-alpha}", "{lower-roman}", "{upper-roman}", "{lower-hexadecimal}", "{upper-hexadecimal}", "{octal}", "{lower-latin}", "{upper-latin}"]
        return ordered.contains { format.rawValue.contains($0) }
    }

    static func isTaskMarker(_ marker: String) -> Bool {
        marker == "☐" || marker == "☑"
    }
}
