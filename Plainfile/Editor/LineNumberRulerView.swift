import AppKit

/// A vertical ruler that draws line numbers for a TextKit 2 backed `NSTextView`.
final class LineNumberRulerView: NSRulerView {

    weak var highlighter: SyntaxHighlighter?
    var theme = EditorTheme()
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
        didSet { updateThickness() }
    }

    private weak var textView: CodeTextView?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(textView: CodeTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        updateThickness()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        })
        observers.append(center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.textDidChange() }
        })
        observers.append(center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        })
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        })
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    private func textDidChange() {
        updateThickness()
        needsDisplay = true
    }

    private func updateThickness() {
        let count = max(highlighter?.lineCount ?? 1, 1)
        let digits = max(3, String(count).count)
        let sample = String(repeating: "8", count: digits)
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        let thickness = ceil(width) + 20
        if abs(ruleThickness - thickness) > 0.5 {
            ruleThickness = thickness
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let tlm = textView.textLayoutManager, let tcm = tlm.textContentManager, let highlighter else { return }

        // Only paint the part of the gutter that sits beside the editor content, not any
        // area tucked under the title or tab bar.
        let topInset = (scrollView?.contentInsets.top ?? 0) + textView.safeAreaInsets.top
        let paintable = NSRect(x: bounds.minX, y: bounds.minY + topInset, width: bounds.width, height: max(0, bounds.height - topInset))
        theme.gutterBackground.setFill()
        paintable.fill()
        theme.gutterSeparator.setFill()
        NSRect(x: bounds.maxX - 1, y: paintable.minY, width: 1, height: paintable.height).intersection(rect).fill()

        let visible = textView.visibleRect
        let inset = textView.textContainerOrigin
        let selectedLine = highlighter.lineIndex(for: textView.selectedRange().location)
        let normalAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.lineNumber]
        let currentAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.currentLineNumber]

        let topPoint = CGPoint(x: 0, y: max(0, visible.minY - inset.y))
        let startLocation = tlm.textLayoutFragment(for: topPoint)?.rangeInElement.location ?? tlm.documentRange.location

        var lastLineDrawn = -1
        var lastFragmentMaxY: CGFloat = 0
        var reachedEnd = false
        let docStart = tlm.documentRange.location

        tlm.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let y = frame.minY + inset.y
            if y > visible.maxY { return false }
            let offset = tcm.offset(from: docStart, to: fragment.rangeInElement.location)
            let lineIndex = highlighter.lineIndex(for: offset)
            if lineIndex != lastLineDrawn {
                let firstLineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? frame.height
                self.drawNumber(lineIndex + 1, atY: y, lineHeight: firstLineHeight, attrs: lineIndex == selectedLine ? currentAttrs : normalAttrs, textView: textView)
                lastLineDrawn = lineIndex
            }
            lastFragmentMaxY = frame.maxY + inset.y
            if fragment.rangeInElement.endLocation.compare(tlm.documentRange.endLocation) == .orderedSame {
                reachedEnd = true
            }
            return true
        }

        // Trailing empty line (text ends with a newline) is not always represented by a fragment.
        let totalLines = highlighter.lineCount
        if (reachedEnd || lastLineDrawn == -1), lastLineDrawn < totalLines - 1 {
            let lineHeight = (font.ascender - font.descender + font.leading)
            let y = lastLineDrawn == -1 ? inset.y : lastFragmentMaxY
            if y <= visible.maxY {
                let index = totalLines - 1
                drawNumber(index + 1, atY: y, lineHeight: lineHeight, attrs: index == selectedLine ? currentAttrs : normalAttrs, textView: textView)
            }
        }
    }

    private func drawNumber(_ number: Int, atY y: CGFloat, lineHeight: CGFloat, attrs: [NSAttributedString.Key: Any], textView: NSTextView) {
        let string = String(number) as NSString
        let size = string.size(withAttributes: attrs)
        let point = convert(NSPoint(x: 0, y: y), from: textView)
        let x = ruleThickness - size.width - 12
        let baselineAdjust = (lineHeight - size.height) / 2
        string.draw(at: NSPoint(x: x, y: point.y + baselineAdjust), withAttributes: attrs)
    }
}
