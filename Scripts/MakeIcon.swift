#!/usr/bin/env swift
// Renders Resources/AppIcon.icns, a sunrise over a horizon in a rounded square.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                              pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(size)
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.235
    let body = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Sky: deep indigo at the top fading into dawn amber near the horizon.
    let sky = NSGradient(colorsAndLocations:
        (rgb(0.13, 0.15, 0.42), 1.00),
        (rgb(0.29, 0.24, 0.62), 0.72),
        (rgb(0.72, 0.33, 0.55), 0.47),
        (rgb(0.98, 0.55, 0.31), 0.26),
        (rgb(1.00, 0.76, 0.36), 0.00))!
    sky.draw(in: body, angle: 90)

    // Everything below is clipped to the rounded body.
    NSGraphicsContext.saveGraphicsState()
    body.addClip()

    let horizonY = rect.minY + rect.height * 0.275
    let sunR = rect.width * 0.215
    let sunC = NSPoint(x: rect.midX, y: horizonY + sunR * 0.34)

    // Glow halo around the sun.
    let glow = NSGradient(colorsAndLocations:
        (rgb(1.00, 0.90, 0.55, 0.55), 0.00),
        (rgb(1.00, 0.78, 0.40, 0.28), 0.45),
        (rgb(1.00, 0.70, 0.35, 0.00), 1.00))!
    glow.draw(fromCenter: sunC, radius: 0,
              toCenter: sunC, radius: sunR * 2.6, options: [])

    // Sun disc.
    let sunRect = NSRect(x: sunC.x - sunR, y: sunC.y - sunR, width: sunR * 2, height: sunR * 2)
    let sun = NSBezierPath(ovalIn: sunRect)
    let sunFill = NSGradient(colors: [rgb(1.00, 0.94, 0.66), rgb(1.00, 0.58, 0.16)])!
    sunFill.draw(in: sun, angle: -90)

    // Rays: short strokes fanning out of the top half of the sun.
    let rayColor = rgb(1.00, 0.88, 0.55, 0.85)
    rayColor.setStroke()
    for angle in stride(from: 20.0, through: 160.0, by: 28.0) {
        let rad = angle * .pi / 180
        let ray = NSBezierPath()
        ray.move(to: NSPoint(x: sunC.x + cos(rad) * sunR * 1.32,
                             y: sunC.y + sin(rad) * sunR * 1.32))
        ray.line(to: NSPoint(x: sunC.x + cos(rad) * sunR * 1.72,
                             y: sunC.y + sin(rad) * sunR * 1.72))
        ray.lineWidth = max(1, s * 0.026)
        ray.lineCapStyle = .round
        ray.stroke()
    }

    // Light path reflecting off the ground, straight down from the sun.
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: sunC.x - sunR * 0.42, y: horizonY))
    beam.line(to: NSPoint(x: sunC.x + sunR * 0.42, y: horizonY))
    beam.line(to: NSPoint(x: sunC.x + sunR * 1.55, y: rect.minY))
    beam.line(to: NSPoint(x: sunC.x - sunR * 1.55, y: rect.minY))
    beam.close()
    rgb(1.00, 0.83, 0.48, 0.30).setFill()
    beam.fill()

    // Ground: a flat dark band cutting the sun off at the horizon.
    let ground = NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY,
                                           width: rect.width, height: horizonY - rect.minY))
    let groundFill = NSGradient(colors: [rgb(0.16, 0.13, 0.30), rgb(0.09, 0.08, 0.20)])!
    groundFill.draw(in: ground, angle: 90)

    // Horizon highlight where the light grazes the ground.
    let edge = NSBezierPath()
    edge.move(to: NSPoint(x: rect.minX, y: horizonY))
    edge.line(to: NSPoint(x: rect.maxX, y: horizonY))
    edge.lineWidth = max(1, s * 0.014)
    rgb(1.00, 0.82, 0.48, 0.85).setStroke()
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()

    // Subtle inner rim so the tile reads as a solid object.
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.006, dy: s * 0.006),
                           xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, s * 0.010)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, px) in variants {
    try render(px).write(to: iconset.appendingPathComponent("\(name).png"))
}
print("iconset written to \(iconset.path)")
