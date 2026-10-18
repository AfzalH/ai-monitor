import AppKit

enum MenuBarIcon {
    /// A vector template keeps the small gauge crisp on Retina displays and
    /// lets macOS choose its color for the menu bar's current appearance.
    static let gauge: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let rim = NSBezierPath()
            rim.lineWidth = 1.8
            rim.lineCapStyle = .round
            rim.appendArc(withCenter: NSPoint(x: 10, y: 5), radius: 8,
                          startAngle: 180, endAngle: 0, clockwise: true)
            rim.stroke()

            let ticks = NSBezierPath()
            ticks.lineWidth = 1.4
            ticks.lineCapStyle = .round
            for angle in [45.0, 90.0, 135.0] {
                let radians = angle * .pi / 180
                ticks.move(to: NSPoint(x: 10 + cos(radians) * 7.7,
                                       y: 5 + sin(radians) * 7.7))
                ticks.line(to: NSPoint(x: 10 + cos(radians) * 5.9,
                                       y: 5 + sin(radians) * 5.9))
            }
            ticks.stroke()

            let needle = NSBezierPath()
            needle.move(to: NSPoint(x: 8.9, y: 5.8))
            needle.line(to: NSPoint(x: 13.2, y: 9.8))
            needle.line(to: NSPoint(x: 11.1, y: 4.2))
            needle.close()
            needle.fill()
            NSBezierPath(ovalIn: NSRect(x: 8.5, y: 3.5, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
