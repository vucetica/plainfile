#!/usr/bin/env swift

// Renders the DMG installer window background.
//
// The design is a warm paper gradient with a blue arrow that arcs from the app
// icon to the Applications folder, and a short label under the drop target.
//
// Run via scripts/build-dmg-background.sh, which also packs the 1x and 2x
// renders into distribution/dmg/background.tiff. The .tiff is committed so CI
// never has to depend on fonts or rendering being identical on the runner.

import AppKit

// MARK: - Canvas
//
// How much of this artwork Finder actually shows varies per user: "Show Path
// Bar" and "Show Status Bar" are *global* View-menu preferences, not per-window
// ones, so writing ShowStatusBar=False into the .DS_Store does not turn them
// off. With both on they take ~52pt off the bottom of the content view.
//
// So the canvas is split. Every design element lives inside the top
// designHeight points, which is the height guaranteed visible even with both
// bars showing. Below that is plain gradient bleed: users with the bars hidden
// simply see more empty margin, which reads as intentional, and no one ever
// loses part of the composition.

let canvasWidth: CGFloat = 640
let designHeight: CGFloat = 400
let bleedHeight: CGFloat = 60
let canvasHeight: CGFloat = designHeight + bleedHeight

// Icon centers must match icon_locations in distribution/dmg/dmgbuild-settings.py.
let appIconCenter = CGPoint(x: 168, y: 170)
let applicationsIconCenter = CGPoint(x: 472, y: 170)

// MARK: - Palette (matches the website in docs/)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let paperTop = color(0xFDFBF7)
let paperBottom = color(0xF1EAE0)
let inkBlue = color(0x3B7AED)
let labelColor = color(0x4A5A5C)

// MARK: - Drawing

/// The arrow annotation arcing from the app icon over to the Applications alias.
func drawArrowAnnotation(in ctx: CGContext) {
    let start = CGPoint(x: 248, y: 156)
    let control1 = CGPoint(x: 296, y: 88)
    let control2 = CGPoint(x: 348, y: 116)
    let end = CGPoint(x: 404, y: 144)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                  color: inkBlue.withAlphaComponent(0.22).cgColor)

    let shaft = CGMutablePath()
    shaft.move(to: start)
    shaft.addCurve(to: end, control1: control1, control2: control2)
    ctx.addPath(shaft)
    ctx.setStrokeColor(inkBlue.cgColor)
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Arrowhead, aligned to the curve's tangent at the end point.
    let tangent = CGVector(dx: end.x - control2.x, dy: end.y - control2.y)
    let angle = atan2(tangent.dy, tangent.dx)
    let headLength: CGFloat = 22
    let headHalfWidth: CGFloat = 11
    let tip = CGPoint(x: end.x + cos(angle) * 7, y: end.y + sin(angle) * 7)

    ctx.translateBy(x: tip.x, y: tip.y)
    ctx.rotate(by: angle)
    let head = CGMutablePath()
    head.move(to: .zero)
    head.addLine(to: CGPoint(x: -headLength, y: -headHalfWidth))
    head.addQuadCurve(to: CGPoint(x: -headLength, y: headHalfWidth),
                      control: CGPoint(x: -headLength + 7, y: 0))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.setFillColor(inkBlue.cgColor)
    ctx.fillPath()

    ctx.restoreGState()
}

/// The label under the Applications folder.
func drawLabel(in ctx: CGContext) {
    let attributed = NSAttributedString(string: "Drag Plainfile to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: labelColor,
    ])
    let size = attributed.size()

    ctx.saveGState()
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    attributed.draw(at: CGPoint(x: (canvasWidth - size.width) / 2, y: 318))
    NSGraphicsContext.current = previous
    ctx.restoreGState()
}

func render(scale: CGFloat) -> Data {
    let pixelWidth = Int(canvasWidth * scale)
    let pixelHeight = Int(canvasHeight * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        fatalError("could not create bitmap context")
    }

    // Flip to a top-left origin so the layout math matches Finder's coordinates.
    ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Paper.
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [paperTop.cgColor, paperBottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 0, y: canvasHeight),
        options: []
    )

    drawArrowAnnotation(in: ctx)
    drawLabel(in: ctx)

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG")
    }
    return data
}

// MARK: - Entry point

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
    try! render(scale: scale).write(to: url)
    print("wrote \(url.path) (\(Int(canvasWidth * scale))x\(Int(canvasHeight * scale)))")
}
