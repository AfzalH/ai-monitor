import AppKit
import Foundation

// Uses the same original gauge geometry as the menu bar icon.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let face = NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 180, yRadius: 180)
        NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.64, blue: 0.61, alpha: 1), ending: NSColor(calibratedRed: 0.09, green: 0.36, blue: 0.42, alpha: 1))!.draw(in: face, angle: -45)
        NSColor.white.setStroke(); NSColor.white.setFill()
        let rim = NSBezierPath(); rim.lineWidth = 48; rim.lineCapStyle = .round
        rim.appendArc(withCenter: NSPoint(x: 512, y: 360), radius: 286, startAngle: 180, endAngle: 0, clockwise: true); rim.stroke()
        for angle in [45.0, 90.0, 135.0] {
            let r = angle * .pi / 180
            let tick = NSBezierPath(); tick.lineWidth = 36; tick.lineCapStyle = .round
            tick.move(to: NSPoint(x: 512 + cos(r) * 280, y: 360 + sin(r) * 280))
            tick.line(to: NSPoint(x: 512 + cos(r) * 218, y: 360 + sin(r) * 218)); tick.stroke()
        }
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: 481, y: 382)); needle.line(to: NSPoint(x: 635, y: 535)); needle.line(to: NSPoint(x: 543, y: 338)); needle.close(); needle.fill()
        NSBezierPath(ovalIn: NSRect(x: 468, y: 316, width: 88, height: 88)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
