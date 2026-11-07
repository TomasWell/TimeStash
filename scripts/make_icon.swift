import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generate TimeStash app icon: SF Symbols style — a bold progress ring with a
// checkmark, on a subtle vertical-gradient rounded background. 1024x1024 PNG.

let size: CGFloat = 1024
let center = CGPoint(x: size / 2, y: size / 2)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    // ⚠️ 无 alpha 通道 —— App Store 的图标必须是不透明的，
    // 带 alpha 通道的图标上传会被拒（ITMS-xxxxx）。
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

// Background: blue gradient (matches AccentColor #0A84FF family)
let bgColors = [
    CGColor(srgbRed: 0.11, green: 0.24, blue: 0.98, alpha: 1),   // #1C3DFA-ish deep blue
    CGColor(srgbRed: 0.04, green: 0.55, blue: 1.0, alpha: 1),    // #0A8CFF
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Ring
let ringRadius: CGFloat = size * 0.30
let ringWidth: CGFloat = size * 0.085
// Track (fainter ring)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
ctx.setLineWidth(ringWidth)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// Progress arc (from top, ~300 degrees)
let startAngle = CGFloat.pi / 2
let endAngle = CGFloat.pi / 2 - CGFloat.pi * 2 * (300.0 / 360.0)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(ringWidth)
ctx.addArc(center: center, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
ctx.strokePath()

// Checkmark inside the ring
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(size * 0.075)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let pts: [CGPoint] = [
    CGPoint(x: center.x - size * 0.145, y: center.y + size * 0.01),
    CGPoint(x: center.x - size * 0.035, y: center.y - size * 0.10),
    CGPoint(x: center.x + size * 0.155, y: center.y + size * 0.115),
]
ctx.addLines(between: pts)
ctx.strokePath()

let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: "/Users/mac/TimeStash/ios/TimeStash/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("icon written: \(outURL.path)")
