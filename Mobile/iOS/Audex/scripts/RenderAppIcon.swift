import AppKit
import CoreText
import Foundation

enum IconStyle: String {
    case brand
    case dark
    case tinted
}

struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
}

func renderIcon(style: IconStyle, size: Int) -> CGImage {
    let width = size
    let height = size
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Unable to create graphics context")
    }

    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)

    let scale = CGFloat(size) / 512
    ctx.scaleBy(x: scale, y: scale)

    switch style {
    case .brand:
        ctx.setFillColor(CGColor(srgbRed: 124 / 255, green: 77 / 255, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
    case .dark:
        ctx.setFillColor(CGColor(srgbRed: 26 / 255, green: 24 / 255, blue: 50 / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
    case .tinted:
        break
    }

    let glyph = CGColor(gray: 1, alpha: 1)
    drawHeadphones(in: ctx, color: glyph)
    drawWordmark(in: ctx, color: glyph)

    guard let image = ctx.makeImage() else {
        fatalError("Unable to create image")
    }
    return image
}

func drawHeadphones(in ctx: CGContext, color: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: 256, y: 240)

    ctx.setStrokeColor(color)
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: -120, y: 20))
    ctx.addCurve(
        to: CGPoint(x: 120, y: 20),
        control1: CGPoint(x: -120, y: -100),
        control2: CGPoint(x: 120, y: -100)
    )
    ctx.strokePath()

    ctx.setFillColor(color)
    let cups = [
        CGRect(x: -140, y: 10, width: 50, height: 80),
        CGRect(x: 90, y: 10, width: 50, height: 80)
    ]
    for cup in cups {
        let path = CGPath(roundedRect: cup, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
    }

    ctx.restoreGState()
}

func drawWordmark(in ctx: CGContext, color: CGColor) {
    let font = NSFont.systemFont(ofSize: 96, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white
    ]
    let text = NSAttributedString(string: "Audex", attributes: attributes)
    let line = CTLineCreateWithAttributedString(text)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

    ctx.saveGState()
    ctx.translateBy(x: (512 - width) / 2, y: 412)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode PNG")
    }
    try data.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: RenderAppIcon.swift <style> <output.png> [size]\n", stderr)
    exit(1)
}

guard let style = IconStyle(rawValue: args[1]) else {
    fputs("style must be brand, dark, or tinted\n", stderr)
    exit(1)
}

let size = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
let image = renderIcon(style: style, size: size)
try writePNG(image, to: URL(fileURLWithPath: args[2]))
