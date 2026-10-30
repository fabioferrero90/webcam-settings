// Draws the app icon (1024×1024) and saves it as PNG.
// Usage: swift make-icon.swift <output.png>
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: a)
}
func circle(_ c: CGPoint, _ r: Double) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

// Background: rounded square following the macOS icon grid (824 px with a 100 px margin)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, 0.35); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(0x1C1F26).setFill(); shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [color(0x3A3F4B), color(0x15171C)])!.draw(in: body, angle: -90)
NSGraphicsContext.restoreGraphicsState()

let c = CGPoint(x: 512, y: 552)

// Focus ring with tick marks
color(0x0B0C10).setFill(); circle(c, 330).fill()
NSGradient(colors: [color(0x5A606D), color(0x2A2E37)])!.draw(in: circle(c, 318), angle: -90)
color(0x0B0C10).setFill(); circle(c, 262).fill()
for i in 0..<60 {
    let a = Double(i) / 60 * 2 * .pi
    let long = i % 5 == 0
    let r1 = 272.0, r2 = long ? 308.0 : 294.0
    let p = NSBezierPath()
    p.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
    p.line(to: CGPoint(x: c.x + cos(a) * r2, y: c.y + sin(a) * r2))
    p.lineWidth = long ? 7 : 4
    p.lineCapStyle = .round
    color(0xD8DCE4, long ? 0.9 : 0.5).setStroke(); p.stroke()
}

// Locked-focus marker (orange, at the top)
let mark = NSBezierPath()
mark.move(to: CGPoint(x: c.x - 22, y: c.y + 345))
mark.line(to: CGPoint(x: c.x + 22, y: c.y + 345))
mark.line(to: CGPoint(x: c.x, y: c.y + 312))
mark.close()
color(0xFF9F0A).setFill(); mark.fill()

// Lens: rings and glass
NSGradient(colors: [color(0x2B2F38), color(0x0E1014)])!.draw(in: circle(c, 236), angle: -90)
color(0x000000).setFill(); circle(c, 196).fill()
NSGradient(colors: [color(0x1E5BD8), color(0x0A1A4A), color(0x020308)])!
    .draw(in: circle(c, 176), relativeCenterPosition: NSPoint(x: -0.15, y: 0.2))
color(0x000000).setFill(); circle(c, 74).fill()
NSGradient(colors: [color(0x16306E), color(0x000000)])!.draw(in: circle(c, 64), relativeCenterPosition: NSPoint(x: -0.2, y: 0.3))

// Reflections
ctx.saveGState()
color(0xFFFFFF, 0.85).setFill(); circle(CGPoint(x: c.x - 70, y: c.y + 78), 30).fill()
color(0xFFFFFF, 0.35).setFill(); circle(CGPoint(x: c.x - 22, y: c.y + 112), 12).fill()
color(0xFFFFFF, 0.18).setFill(); circle(CGPoint(x: c.x + 82, y: c.y - 92), 18).fill()
ctx.restoreGState()

// Adjustment sliders at the bottom
for (i, pos) in [0.3, 0.7, 0.5].enumerated() {
    let y = 170.0, x0 = 300.0 + Double(i) * 150, w = 124.0
    let track = NSBezierPath(roundedRect: CGRect(x: x0, y: y - 6, width: w, height: 12), xRadius: 6, yRadius: 6)
    color(0xFFFFFF, 0.18).setFill(); track.fill()
    let fill = NSBezierPath(roundedRect: CGRect(x: x0, y: y - 6, width: w * pos, height: 12), xRadius: 6, yRadius: 6)
    (i == 0 ? color(0xFF9F0A) : color(0x8FB4FF)).setFill(); fill.fill()
    color(0xF2F4F8).setFill(); circle(CGPoint(x: x0 + w * pos, y: y), 17).fill()
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
