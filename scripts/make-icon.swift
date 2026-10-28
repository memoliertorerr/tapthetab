#!/usr/bin/env swift
// Draws the TapTheTab app icon at every size an .iconset needs and writes PNGs.
//
//   swift scripts/make-icon.swift <out.iconset>
//   iconutil -c icns <out.iconset> -o AppIcon.icns
//
// macOS only. Uses CoreGraphics + ImageIO (no AppKit, no window server), so it
// also runs on headless CI machines. Everything is drawn in a 1024×1024 design
// space (y pointing down) and scaled to the target pixel size.
//
// Design: a macOS-style squircle (≈10% margin, ≈22% corner radius) with a deep
// indigo→violet vertical gradient, and three stacked, offset "window" cards.
// The front card is opaque white with a small browser-style tab on its top-left.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// A rounded rectangle with continuous ("squircle") corners: each corner is a
/// superellipse quadrant, so the curvature eases into the straight edges the
/// way Apple's icon shape does. `radius` is the equivalent circular radius.
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let extent = min(radius * 1.528, rect.width / 2, rect.height / 2)
    let exponent = 3.3
    let steps = 48
    let path = CGMutablePath()

    // (corner centre, direction at t = 0, direction at t = π/2), clockwise on screen.
    let corners: [(CGPoint, CGVector, CGVector)] = [
        (CGPoint(x: rect.minX + extent, y: rect.minY + extent), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: rect.maxX - extent, y: rect.minY + extent), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
        (CGPoint(x: rect.maxX - extent, y: rect.maxY - extent), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: rect.minX + extent, y: rect.maxY - extent), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
    ]
    for (index, corner) in corners.enumerated() {
        let (centre, a, b) = corner
        for step in 0...steps {
            let t = Double(step) / Double(steps) * Double.pi / 2
            let u = CGFloat(pow(max(0, cos(t)), 2 / exponent)) * extent
            let v = CGFloat(pow(max(0, sin(t)), 2 / exponent)) * extent
            let point = CGPoint(x: centre.x + a.dx * u + b.dx * v, y: centre.y + a.dy * u + b.dy * v)
            if index == 0 && step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, rect.width / 2, rect.height / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// The browser-style tab sticking out of the front card's top edge: rounded
/// top corners and small concave fillets where its sides meet the card.
func tabPath(left: CGFloat, right: CGFloat, top: CGFloat, base: CGFloat) -> CGPath {
    let corner: CGFloat = 18
    let fillet: CGFloat = 16
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left - fillet, y: base + 40))
    path.addLine(to: CGPoint(x: left - fillet, y: base))
    path.addArc(tangent1End: CGPoint(x: left, y: base), tangent2End: CGPoint(x: left, y: base - fillet), radius: fillet)
    path.addLine(to: CGPoint(x: left, y: top + corner))
    path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + corner, y: top), radius: corner)
    path.addLine(to: CGPoint(x: right - corner, y: top))
    path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top + corner), radius: corner)
    path.addLine(to: CGPoint(x: right, y: base - fillet))
    path.addArc(tangent1End: CGPoint(x: right, y: base), tangent2End: CGPoint(x: right + fillet, y: base), radius: fillet)
    path.addLine(to: CGPoint(x: right + fillet, y: base + 40))
    path.closeSubpath()
    return path
}

// MARK: - Drawing

func drawIcon(_ ctx: CGContext, pixels: Int) {
    let px = CGFloat(pixels)
    let k = px / 1024 // design units → pixels (shadow offsets/blur are not scaled by the CTM)
    let small = pixels <= 32

    // Switch to the 1024-unit design space with the origin at the top-left.
    ctx.translateBy(x: 0, y: px)
    ctx.scaleBy(x: k, y: -k)

    // Body: 824×824 squircle centred on the canvas (Apple's icon grid).
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = squircle(bodyRect, radius: 185)
    let indigo = color(0x3730A3)
    let violet = color(0x7C3AED)

    if pixels >= 32 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: color(0x000000, 0.30))
        ctx.addPath(body)
        ctx.setFillColor(indigo)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    if let gradient = CGGradient(colorsSpace: sRGB, colors: [indigo, violet] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 512, y: bodyRect.minY),
            end: CGPoint(x: 512, y: bodyRect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    // Soft sheen on the upper half.
    if let sheen = CGGradient(
        colorsSpace: sRGB,
        colors: [color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: bodyRect.minY), end: CGPoint(x: 512, y: 560), options: [])
    }
    ctx.restoreGState()

    // Three stacked window cards; each one further back is offset up and right.
    let cardSize = CGSize(width: 470, height: 350)
    let step: CGFloat = 58
    let front = CGRect(x: 219, y: 395, width: cardSize.width, height: cardSize.height)
    let cardRadius: CGFloat = 48
    let backAlphas: [CGFloat] = small ? [0.45, 0.72] : [0.30, 0.55]

    for (depth, alpha) in zip([2, 1], backAlphas) {
        let rect = front.offsetBy(dx: step * CGFloat(depth), dy: -step * CGFloat(depth))
        ctx.addPath(roundedRect(rect, radius: cardRadius))
        ctx.setFillColor(color(0xFFFFFF, alpha))
        ctx.fillPath()
    }

    // Front card + tab, composited in one layer so they cast a single shadow.
    ctx.saveGState()
    if pixels >= 32 {
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 24 * k, color: color(0x1E1B4B, 0.35))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(roundedRect(front, radius: cardRadius))
    ctx.fillPath()
    ctx.addPath(tabPath(left: front.minX + 60, right: front.minX + 206, top: front.minY - 42, base: front.minY))
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Content hints on the front card, only where they stay crisp.
    if pixels >= 64 {
        let ink = color(0x4C1D95, 0.22)
        ctx.setFillColor(ink)
        ctx.addPath(roundedRect(CGRect(x: front.minX + 52, y: front.minY + 96, width: 280, height: 34), radius: 17))
        ctx.fillPath()
        ctx.addPath(roundedRect(CGRect(x: front.minX + 52, y: front.minY + 160, width: 190, height: 34), radius: 17))
        ctx.fillPath()
    }
}

func renderPNG(pixels: Int, scale: Int, to url: URL) {
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("could not create a \(pixels)px bitmap context") }

    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    drawIcon(ctx, pixels: pixels)

    guard let image = ctx.makeImage() else { fail("could not render \(url.lastPathComponent)") }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("could not create \(url.path)")
    }
    let dpi = 72 * scale
    let properties = [
        kCGImagePropertyDPIWidth as String: dpi,
        kCGImagePropertyDPIHeight as String: dpi,
    ] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { fail("could not write \(url.path)") }
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <out.iconset>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
} catch {
    fail("could not create \(outputDirectory.path): \(error)")
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@\(scale)x"
        let name = "icon_\(points)x\(points)\(suffix).png"
        renderPNG(pixels: points * scale, scale: scale, to: outputDirectory.appendingPathComponent(name))
    }
}
print("make-icon: wrote 10 PNGs to \(outputDirectory.path)")
