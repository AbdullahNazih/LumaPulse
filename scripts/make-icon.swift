import AppKit
import Foundation
let directory = URL(fileURLWithPath: ".build/LumaPulse.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let p = CGFloat(pixels)
        NSColor(red: 0.06, green: 0.09, blue: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.21, yRadius: p * 0.21).fill()
        let line = NSBezierPath(); line.lineWidth = max(2, p * 0.055); line.lineCapStyle = .round; line.lineJoinStyle = .round
        let points: [(CGFloat, CGFloat)] = [(0.20, 0.36), (0.34, 0.46), (0.45, 0.40), (0.58, 0.65), (0.70, 0.55), (0.80, 0.73)]
        line.move(to: NSPoint(x: points[0].0 * p, y: points[0].1 * p))
        for point in points.dropFirst() { line.line(to: NSPoint(x: point.0 * p, y: point.1 * p)) }
        NSColor(red: 0.27, green: 0.87, blue: 0.72, alpha: 1).setStroke(); line.stroke()
        NSColor(red: 0.88, green: 0.69, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: p * 0.74, y: p * 0.67, width: p * 0.12, height: p * 0.12)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
