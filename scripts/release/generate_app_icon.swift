#!/usr/bin/env swift

import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let fileManager = FileManager.default

let iconDefinitions: [(filename: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func makeBaseIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Failed to create graphics context")
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225

    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.055
    shadow.shadowOffset = NSSize(width: 0, height: -(size * 0.02))
    shadow.shadowColor = rgba(7, 18, 38, 0.25)
    shadow.set()

    let roundedRect = NSBezierPath(roundedRect: canvas.insetBy(dx: size * 0.03, dy: size * 0.03), xRadius: cornerRadius, yRadius: cornerRadius)
    roundedRect.addClip()

    let gradient = NSGradient(colors: [
        rgba(18, 74, 146),
        rgba(35, 135, 220),
        rgba(131, 224, 214)
    ])!
    gradient.draw(in: roundedRect, angle: 55)

    context.saveGState()
    let overlayPath = NSBezierPath(roundedRect: canvas.insetBy(dx: size * 0.03, dy: size * 0.03), xRadius: cornerRadius, yRadius: cornerRadius)
    overlayPath.addClip()
    let overlayColors = [rgba(255, 255, 255, 0.18).cgColor, rgba(255, 255, 255, 0.0).cgColor] as CFArray
    let overlayLocations: [CGFloat] = [0.0, 1.0]
    if let overlay = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: overlayColors, locations: overlayLocations) {
        context.drawLinearGradient(
            overlay,
            start: CGPoint(x: size * 0.2, y: size * 0.95),
            end: CGPoint(x: size * 0.8, y: size * 0.2),
            options: []
        )
    }
    context.restoreGState()

    let barArea = CGRect(x: size * 0.2, y: size * 0.24, width: size * 0.42, height: size * 0.46)
    let barWidth = size * 0.09
    let barSpacing = size * 0.05
    let barHeights: [CGFloat] = [0.34, 0.56, 0.82]
    for (index, heightFactor) in barHeights.enumerated() {
        let barHeight = barArea.height * heightFactor
        let rect = CGRect(
            x: barArea.minX + CGFloat(index) * (barWidth + barSpacing),
            y: barArea.minY,
            width: barWidth,
            height: barHeight
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: barWidth * 0.45, yRadius: barWidth * 0.45)
        rgba(248, 251, 255, 0.96).setFill()
        path.fill()
    }

    let ringRect = CGRect(x: size * 0.53, y: size * 0.3, width: size * 0.26, height: size * 0.26)
    let ringWidth = max(size * 0.05, 2.0)
    let ringPath = NSBezierPath()
    ringPath.appendArc(withCenter: CGPoint(x: ringRect.midX, y: ringRect.midY), radius: ringRect.width / 2, startAngle: 140, endAngle: 500, clockwise: false)
    ringPath.lineWidth = ringWidth
    ringPath.lineCapStyle = .round
    rgba(248, 251, 255, 0.92).setStroke()
    ringPath.stroke()

    let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
    let minuteLength = ringRect.width * 0.22
    let hourLength = ringRect.width * 0.15
    let handWidth = max(size * 0.018, 1.8)

    let minuteHand = NSBezierPath()
    minuteHand.move(to: center)
    minuteHand.line(to: CGPoint(x: center.x, y: center.y + minuteLength))
    minuteHand.lineWidth = handWidth
    minuteHand.lineCapStyle = .round
    rgba(248, 251, 255, 0.98).setStroke()
    minuteHand.stroke()

    let hourHand = NSBezierPath()
    hourHand.move(to: center)
    hourHand.line(to: CGPoint(x: center.x + hourLength * 0.82, y: center.y + hourLength * 0.48))
    hourHand.lineWidth = handWidth
    hourHand.lineCapStyle = .round
    rgba(248, 251, 255, 0.98).setStroke()
    hourHand.stroke()

    let pivot = NSBezierPath(ovalIn: CGRect(x: center.x - handWidth, y: center.y - handWidth, width: handWidth * 2, height: handWidth * 2))
    rgba(248, 251, 255, 1.0).setFill()
    pivot.fill()

    return image
}

func pngData(from image: NSImage, size: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1.0)
        context.flushGraphics()
    }
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let baseIcon = makeBaseIcon(size: 1024)

for definition in iconDefinitions {
    let destination = outputDirectory.appendingPathComponent(definition.filename)
    guard let data = pngData(from: baseIcon, size: definition.size) else {
        fatalError("Failed to render \(definition.filename)")
    }
    try data.write(to: destination)
    print("Wrote \(destination.path)")
}
