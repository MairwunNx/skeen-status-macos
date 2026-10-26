// Draws the app icon at 1024 px: `swiftc scripts/draw-icon.swift -o /tmp/draw-icon && /tmp/draw-icon media/icon.png`.

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

// macOS icon grid: 824pt squircle centered, with a soft drop shadow
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0, 0, 0, 0.35))
ctx.addPath(platePath); ctx.setFillColor(c(0.1, 0.1, 0.2)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(platePath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [c(0.06, 0.09, 0.27), c(0.10, 0.27, 0.62), c(0.05, 0.62, 0.70)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 150, y: 120), end: CGPoint(x: 880, y: 930), options: [])
// glass sheen on the top half
let sheen = CGGradient(colorsSpace: cs, colors: [c(1, 1, 1, 0.22), c(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
ctx.restoreGState()
// thin inner rim
ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(c(1, 1, 1, 0.18)); ctx.setLineWidth(4); ctx.strokePath()

let white = c(0.97, 0.98, 1)
// signal arcs above the router
ctx.setLineCap(.round)
for (i, r) in [CGFloat(120), 190].enumerated() {
    ctx.setStrokeColor(c(1, 1, 1, i == 0 ? 0.95 : 0.6))
    ctx.setLineWidth(34)
    ctx.addArc(center: CGPoint(x: 512, y: 560), radius: r, startAngle: .pi * 0.25, endAngle: .pi * 0.75, clockwise: false)
    ctx.strokePath()
}
// antennas
ctx.setStrokeColor(white); ctx.setLineWidth(30)
ctx.move(to: CGPoint(x: 360, y: 450)); ctx.addLine(to: CGPoint(x: 330, y: 560)); ctx.strokePath()
ctx.move(to: CGPoint(x: 664, y: 450)); ctx.addLine(to: CGPoint(x: 694, y: 560)); ctx.strokePath()
// router body with a soft shadow
let body = CGRect(x: 250, y: 290, width: 524, height: 170)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0, 0, 0, 0.3))
ctx.addPath(CGPath(roundedRect: body, cornerWidth: 58, cornerHeight: 58, transform: nil))
ctx.setFillColor(white); ctx.fillPath()
ctx.restoreGState()
// port lights
for (i, x) in [CGFloat(330), 400, 470].enumerated() {
    ctx.setFillColor(i == 0 ? c(0.10, 0.27, 0.62) : c(0.10, 0.27, 0.62, 0.35))
    ctx.fillEllipse(in: CGRect(x: x - 20, y: 355, width: 40, height: 40))
}
// green status dot with a glow
let dotCenter = CGPoint(x: 660, y: 375)
let glow = CGGradient(colorsSpace: cs, colors: [c(0.2, 0.95, 0.45, 0.65), c(0.2, 0.95, 0.45, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: dotCenter, startRadius: 0, endCenter: dotCenter, endRadius: 95, options: [])
let dot = CGGradient(colorsSpace: cs, colors: [c(0.55, 1, 0.65), c(0.13, 0.78, 0.36)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: dotCenter.x - 42, y: dotCenter.y - 42, width: 84, height: 84)); ctx.clip()
ctx.drawLinearGradient(dot, start: CGPoint(x: dotCenter.x, y: dotCenter.y + 42), end: CGPoint(x: dotCenter.x, y: dotCenter.y - 42), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
