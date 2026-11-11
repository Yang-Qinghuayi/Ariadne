#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let size = 1024
let canvasRect = CGRect(x: 0, y: 0, width: size, height: size)

guard let rep = NSBitmapImageRep(
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
    fputs("Failed to allocate bitmap representation\n", stderr)
    exit(1)
}

rep.size = NSSize(width: size, height: size)

guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx
let ctx = nsCtx.cgContext
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// Outer macOS icon margin (~10% padding around 824x824 squircle)
let inset: CGFloat = 100
let iconRect = canvasRect.insetBy(dx: inset, dy: inset)
let cornerRadius: CGFloat = 185

let squircle = CGPath(
    roundedRect: iconRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

// Drop shadow behind icon tile
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -18),
    blur: 36,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
)
ctx.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.16, alpha: 1.0))
ctx.addPath(squircle)
ctx.fillPath()
ctx.restoreGState()

// Clip to squircle for interior artwork
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgColors = [
    CGColor(red: 0.10, green: 0.12, blue: 0.24, alpha: 1.0),
    CGColor(red: 0.05, green: 0.06, blue: 0.13, alpha: 1.0)
] as CFArray
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
        options: []
    )
}

// Soft radial glow in center-upper area
let glowColors = [
    CGColor(red: 0.28, green: 0.44, blue: 0.96, alpha: 0.28),
    CGColor(red: 0.28, green: 0.44, blue: 0.96, alpha: 0.0)
] as CFArray
if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 512, y: 560),
        startRadius: 20,
        endCenter: CGPoint(x: 512, y: 512),
        endRadius: 430,
        options: []
    )
}

// Subtle concentric labyrinth rings
let center = CGPoint(x: 512, y: 512)
let radii: [CGFloat] = [300, 225, 150]
for (idx, radius) in radii.enumerated() {
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.56, green: 0.67, blue: 1.0, alpha: 0.14 + Double(idx) * 0.04))
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    let startAngle = CGFloat(idx) * 0.8 + 0.35
    let endAngle = startAngle + CGFloat.pi * 1.55
    ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
}

// Glowing golden Ariadne thread winding to a bright anchor node
let threadPath = CGMutablePath()
threadPath.move(to: CGPoint(x: 245, y: 315))
threadPath.addCurve(
    to: CGPoint(x: 510, y: 515),
    control1: CGPoint(x: 345, y: 270),
    control2: CGPoint(x: 410, y: 575)
)
threadPath.addCurve(
    to: CGPoint(x: 775, y: 690),
    control1: CGPoint(x: 615, y: 455),
    control2: CGPoint(x: 690, y: 610)
)

// Outer glow on thread
ctx.saveGState()
ctx.setShadow(
    offset: .zero,
    blur: 28,
    color: CGColor(red: 1.0, green: 0.72, blue: 0.24, alpha: 0.85)
)
ctx.setStrokeColor(CGColor(red: 1.0, green: 0.78, blue: 0.32, alpha: 1.0))
ctx.setLineWidth(28)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(threadPath)
ctx.strokePath()
ctx.restoreGState()

// Crisp bright thread core
ctx.saveGState()
ctx.setStrokeColor(CGColor(red: 1.0, green: 0.93, blue: 0.68, alpha: 1.0))
ctx.setLineWidth(12)
ctx.setLineCap(.round)
ctx.addPath(threadPath)
ctx.strokePath()
ctx.restoreGState()

// Start & end glowing nodes (Code / Terminal endpoints)
let nodes: [(CGPoint, CGFloat, CGColor)] = [
    (CGPoint(x: 245, y: 315), 28, CGColor(red: 0.36, green: 0.75, blue: 1.0, alpha: 1.0)),
    (CGPoint(x: 510, y: 515), 22, CGColor(red: 1.0, green: 0.82, blue: 0.35, alpha: 1.0)),
    (CGPoint(x: 775, y: 690), 34, CGColor(red: 1.0, green: 0.75, blue: 0.25, alpha: 1.0))
]

for (pt, r, fill) in nodes {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 20, color: fill)
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: pt.x - r * 0.42, y: pt.y - r * 0.42, width: r * 0.84, height: r * 0.84))
    ctx.restoreGState()
}

// Subtle top highlight rim inside squircle
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
ctx.setLineWidth(4)
ctx.addPath(squircle)
ctx.strokePath()

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
