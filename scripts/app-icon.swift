// Draws the Plainfile app icon and the website's social preview image.
//
//   swift scripts/app-icon.swift <output-folder>
//
// Writes icon-1024.png (the master icon) and og-image.png (1200x630) into the
// folder. scripts/build-app-icon.sh turns the master into every icon size.
//
// The design is a placeholder: a blue rounded square that fills the canvas,
// with a white page that has a folded corner. The page shows a heading line,
// text lines, and a small table, which stand for the three kinds of files Plainfile edits.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift app-icon.swift <output-folder>\n".data(using: .utf8)!)
    exit(1)
}
let outputFolder = URL(fileURLWithPath: arguments[1], isDirectory: true)

// The tile uses the same diagonal blue gradient as the ScreenSnipe icon.
let blueDark = NSColor(srgbRed: 0.19, green: 0.43, blue: 0.87, alpha: 1)
let blueLight = NSColor(srgbRed: 0.31, green: 0.64, blue: 0.97, alpha: 1)
let ink = NSColor(srgbRed: 0.17, green: 0.40, blue: 0.84, alpha: 1)
let inkSoft = NSColor(srgbRed: 0.74, green: 0.81, blue: 0.92, alpha: 1)
let paper = NSColor(srgbRed: 0.995, green: 0.99, blue: 0.98, alpha: 1)
let fold = NSColor(srgbRed: 0.86, green: 0.90, blue: 0.96, alpha: 1)

/// Renders `draw` into a bitmap of the given pixel size and saves it as PNG.
func render(width: Int, height: Int, to url: URL, draw: (CGContext) -> Void) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create a bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
    try! data.write(to: url)
}

/// Draws the icon artwork into a 1024x1024 coordinate space at `origin`, scaled by `scale`.
func drawIcon(in cg: CGContext, origin: CGPoint, scale: CGFloat) {
    cg.saveGState()
    cg.translateBy(x: origin.x, y: origin.y)
    cg.scaleBy(x: scale, y: scale)

    // Like the ScreenSnipe icon, the rounded square fills the whole canvas.
    let tile = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 228, yRadius: 228)

    // Darker in the top-left corner, lighter in the bottom-right corner.
    NSGradient(starting: blueDark, ending: blueLight)!.draw(in: tilePath, angle: -45)

    // Page with a folded top-right corner.
    let page = CGRect(x: 262, y: 196, width: 500, height: 632)
    let foldSize: CGFloat = 130
    let pagePath = NSBezierPath()
    pagePath.move(to: CGPoint(x: page.minX + 36, y: page.minY))
    pagePath.line(to: CGPoint(x: page.maxX - 36, y: page.minY))
    pagePath.curve(to: CGPoint(x: page.maxX, y: page.minY + 36),
                   controlPoint1: CGPoint(x: page.maxX - 16, y: page.minY),
                   controlPoint2: CGPoint(x: page.maxX, y: page.minY + 16))
    pagePath.line(to: CGPoint(x: page.maxX, y: page.maxY - foldSize))
    pagePath.line(to: CGPoint(x: page.maxX - foldSize, y: page.maxY))
    pagePath.line(to: CGPoint(x: page.minX + 36, y: page.maxY))
    pagePath.curve(to: CGPoint(x: page.minX, y: page.maxY - 36),
                   controlPoint1: CGPoint(x: page.minX + 16, y: page.maxY),
                   controlPoint2: CGPoint(x: page.minX, y: page.maxY - 16))
    pagePath.line(to: CGPoint(x: page.minX, y: page.minY + 36))
    pagePath.curve(to: CGPoint(x: page.minX + 36, y: page.minY),
                   controlPoint1: CGPoint(x: page.minX, y: page.minY + 16),
                   controlPoint2: CGPoint(x: page.minX + 16, y: page.minY))
    pagePath.close()

    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    pageShadow.shadowOffset = NSSize(width: 0, height: -10)
    pageShadow.shadowBlurRadius = 22
    pageShadow.set()
    paper.setFill()
    pagePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The folded corner.
    let corner = NSBezierPath()
    corner.move(to: CGPoint(x: page.maxX - foldSize, y: page.maxY))
    corner.line(to: CGPoint(x: page.maxX - foldSize, y: page.maxY - foldSize + 24))
    corner.curve(to: CGPoint(x: page.maxX - foldSize + 24, y: page.maxY - foldSize),
                 controlPoint1: CGPoint(x: page.maxX - foldSize, y: page.maxY - foldSize + 10),
                 controlPoint2: CGPoint(x: page.maxX - foldSize + 10, y: page.maxY - foldSize))
    corner.line(to: CGPoint(x: page.maxX, y: page.maxY - foldSize))
    corner.close()
    fold.setFill()
    corner.fill()

    func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), xRadius: height / 2, yRadius: height / 2).fill()
    }

    // Heading and text lines.
    let left = page.minX + 64
    bar(left, 690, 220, 34, ink)
    bar(left, 626, 340, 20, inkSoft)
    bar(left, 586, 372, 20, inkSoft)
    bar(left, 546, 300, 20, inkSoft)

    // A small table: header row in blue, then two rows of cells.
    let tableTop: CGFloat = 470
    let cellWidth: CGFloat = 112
    let cellGap: CGFloat = 14
    for column in 0..<3 {
        let x = left + CGFloat(column) * (cellWidth + cellGap)
        bar(x, tableTop, cellWidth, 26, ink)
        bar(x, tableTop - 52, cellWidth, 20, inkSoft)
        bar(x, tableTop - 96, cellWidth, 20, inkSoft)
        bar(x, tableTop - 140, cellWidth, 20, inkSoft)
    }

    cg.restoreGState()
}

try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

render(width: 1024, height: 1024, to: outputFolder.appendingPathComponent("icon-1024.png")) { cg in
    drawIcon(in: cg, origin: .zero, scale: 1)
}

// Social preview: icon on the left, name and tagline on the right.
render(width: 1200, height: 630, to: outputFolder.appendingPathComponent("og-image.png")) { cg in
    let background = NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1),
                                ending: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.94, alpha: 1))!
    background.draw(in: CGRect(x: 0, y: 0, width: 1200, height: 630), angle: -90)
    drawIcon(in: cg, origin: CGPoint(x: 70, y: 85), scale: 460.0 / 1024.0)

    let title = NSAttributedString(string: "Plainfile", attributes: [
        .font: NSFont.systemFont(ofSize: 96, weight: .bold),
        .foregroundColor: NSColor(srgbRed: 0.10, green: 0.13, blue: 0.14, alpha: 1),
    ])
    title.draw(at: CGPoint(x: 580, y: 330))
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 6
    let tagline = NSAttributedString(string: "A plain, fast editor for text,\nMarkdown and CSV on macOS.", attributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.30, green: 0.36, blue: 0.38, alpha: 1),
        .paragraphStyle: paragraph,
    ])
    tagline.draw(in: CGRect(x: 584, y: 160, width: 600, height: 150))
}

print("wrote \(outputFolder.path)/icon-1024.png and og-image.png")
