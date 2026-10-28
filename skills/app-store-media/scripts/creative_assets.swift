#!/usr/bin/env swift
//
// creative_assets.swift: render App Store product-page header and search-results
// creative assets (iOS 27 and later) from the same brand config the screenshot
// framer uses, plus raw app captures.
//
// Usage:
//   swift creative_assets.swift <config.json> [--out <dir>] [--guides]
//
// The config is the framer's config with an extra "creative" array:
//   "creative": [
//     {"name": "header", "width": 3840, "height": 1646,
//      "safe": [1097, 493, 2743, 1154],            // x0, y0, x1, y1 from Apple's template, top-left origin
//      "layout": "phones-row",                       // or "text-left-phones-right"
//      "headline": "...", "subheadline": "...",      // optional
//      "phones": ["iphone_6.9/recording.png", ...],  // relative to rawDir
//      "phoneHeight": 1.15                          // fraction of the safe area's height
//     }
//   ]
//
// --guides draws Apple's safe area as a green outline, for review only; never upload those.
// Output: <out>/<name>.png, opaque. Safe areas come from Apple's Photoshop templates
// (references/apple-specs.md, "Creative assets").

import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

struct Creative: Decodable {
    let name: String
    let width: Int
    let height: Int
    let safe: [Double]
    let layout: String
    let headline: String?
    let subheadline: String?
    let phones: [String]
    let phoneHeight: Double?
    let screenCornerRadius: Double?
    let captionScale: Double?      // multiplies caption sizes (default 1)
}
struct Brand: Decodable {
    let gradientTop: String, gradientBottom: String, accent: String
    let headline: String?, subheadline: String?
    let headlineFont: String, subheadlineFont: String
    let fontFiles: [String]?
}
struct Config: Decodable {
    let rawDir: String
    let brand: Brand
    let creative: [Creative]?
}

func color(_ hex: String) -> NSColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    if s.count == 8 {
        return NSColor(srgbRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                       blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func font(_ name: String, _ size: CGFloat, heavy: Bool) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: heavy ? .heavy : .semibold)
}

/// Draws attributed text in a box whose top edge is `top` (CG coordinates), returns its height.
@discardableResult
func drawText(_ s: NSAttributedString, ctx: CGContext, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
    let fs = CTFramesetterCreateWithAttributedString(s)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), nil,
                                                            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    let rect = CGRect(x: x, y: top - size.height, width: width, height: size.height)
    CTFrameDraw(CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil), ctx)
    return size.height
}

/// One phone: drawn generic bezel (no Apple-specific details), capture clipped inside.
func drawPhone(ctx: CGContext, image: CGImage, rect bezel: CGRect, cornerRatio: CGFloat) {
    let t = bezel.width * 0.018
    let screen = bezel.insetBy(dx: t, dy: t)
    let sr = screen.width * cornerRatio, br = sr + t
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -bezel.width * 0.03), blur: bezel.width * 0.12,
                  color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: bezel, cornerWidth: br, cornerHeight: br, transform: nil))
    ctx.setFillColor(NSColor(white: 0.09, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: sr, cornerHeight: sr, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: screen)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: sr, cornerHeight: sr, transform: nil))
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
    ctx.setLineWidth(max(1, t * 0.2))
    ctx.strokePath()
    ctx.restoreGState()
}

func render(_ c: Creative, brand: Brand, rawBase: URL, guides: Bool) -> CGImage? {
    let w = CGFloat(c.width), h = CGFloat(c.height)
    guard let ctx = CGContext(data: nil, width: c.width, height: c.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.setShouldSmoothFonts(true); ctx.setShouldAntialias(true)
    // Safe area in CG coordinates (Apple's templates use a top-left origin).
    let safe = CGRect(x: c.safe[0], y: Double(h) - c.safe[3], width: c.safe[2] - c.safe[0], height: c.safe[3] - c.safe[1])

    // Background: brand gradient, darker at the top where the text sits.
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [color(brand.gradientTop).cgColor, color(brand.gradientBottom).cgColor] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: w / 2, y: h), end: CGPoint(x: w / 2, y: 0), options: [])

    let images: [CGImage] = c.phones.compactMap {
        NSImage(contentsOf: rawBase.appendingPathComponent($0))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    if images.count != c.phones.count { fputs("Error: \(c.name): could not load every phone image\n", stderr); return nil }
    let corner = CGFloat(c.screenCornerRadius ?? 0.092)
    let unit = safe.height

    func caption(_ ctx: CGContext, x: CGFloat, top: CGFloat, width: CGFloat, align: NSTextAlignment, scale: CGFloat) -> CGFloat {
        var y = top
        let hp = NSMutableParagraphStyle(); hp.alignment = align; hp.lineHeightMultiple = 0.98
        let sp = NSMutableParagraphStyle(); sp.alignment = align; sp.lineHeightMultiple = 1.1
        if let head = c.headline {
            y -= drawText(NSAttributedString(string: head, attributes: [
                .font: font(brand.headlineFont, unit * 0.16 * scale, heavy: true),
                .foregroundColor: color(brand.headline ?? "#FFFFFF"), .paragraphStyle: hp]),
                          ctx: ctx, x: x, top: y, width: width)
            y -= unit * 0.045 * scale
            let rw = unit * 0.14 * scale, rh = unit * 0.014 * scale
            let rx = align == .center ? x + (width - rw) / 2 : x
            ctx.setFillColor(color(brand.accent).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: rx, y: y - rh, width: rw, height: rh),
                               cornerWidth: rh / 2, cornerHeight: rh / 2, transform: nil))
            ctx.fillPath()
            y -= rh + unit * 0.045 * scale
        }
        if let sub = c.subheadline {
            y -= drawText(NSAttributedString(string: sub, attributes: [
                .font: font(brand.subheadlineFont, unit * 0.075 * scale, heavy: false),
                .foregroundColor: color(brand.subheadline ?? "#FFFFFFE0"), .paragraphStyle: sp]),
                          ctx: ctx, x: x, top: y, width: width)
        }
        return top - y
    }

    switch c.layout {
    case "phones-row":
        // Caption centred in the top of the safe area; a row of phones rises from
        // below it and runs off the bottom edge, under the App Store's overlay.
        let inset = safe.width * 0.06
        let capH = caption(ctx, x: safe.minX + inset, top: safe.maxY, width: safe.width - 2 * inset, align: .center,
                           scale: CGFloat(c.captionScale ?? 1))
        let ph = safe.height * CGFloat(c.phoneHeight ?? 1.15)
        let aspect = CGFloat(images[0].height) / CGFloat(images[0].width)
        let pw = ph / aspect
        let gap = pw * 0.16
        let total = CGFloat(images.count) * pw + CGFloat(images.count - 1) * gap
        var x = (w - total) / 2
        let top = safe.maxY - capH - unit * 0.08
        for (i, img) in images.enumerated() {
            // Outer phones sit a little lower, so the row reads as a gentle arc.
            let mid = CGFloat(images.count - 1) / 2
            let drop = abs(CGFloat(i) - mid) * ph * 0.06
            drawPhone(ctx: ctx, image: img, rect: CGRect(x: x, y: top - ph - drop, width: pw, height: ph), cornerRatio: corner)
            x += pw + gap
        }
    case "text-left-phones-right":
        // Caption on the left half of the safe area, phones on the right, both
        // inside the safe area so nothing that matters is cropped in search results.
        let ph = safe.height * CGFloat(c.phoneHeight ?? 1.0)
        let aspect = CGFloat(images[0].height) / CGFloat(images[0].width)
        let pw = ph / aspect
        let gap = pw * 0.12
        let phonesW = CGFloat(images.count) * pw + CGFloat(images.count - 1) * gap
        let textW = safe.width - phonesW - unit * 0.12
        // Measure the caption off-screen, then centre it against the phones.
        let scratch = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let cs = CGFloat(c.captionScale ?? 1)
        let capH = caption(scratch, x: 0, top: 0, width: textW, align: .left, scale: cs)
        _ = caption(ctx, x: safe.minX, top: safe.maxY - (ph - capH) / 2, width: textW, align: .left, scale: cs)
        var x = safe.maxX - phonesW
        for img in images {
            drawPhone(ctx: ctx, image: img, rect: CGRect(x: x, y: safe.maxY - ph, width: pw, height: ph), cornerRatio: corner)
            x += pw + gap
        }
    default:
        fputs("Error: unknown layout \(c.layout)\n", stderr); return nil
    }

    if guides {
        ctx.setStrokeColor(NSColor.systemGreen.cgColor)
        ctx.setLineWidth(6)
        ctx.stroke(safe)
    }
    return ctx.makeImage()
}

func main() {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let path = args.first else { fputs("usage: creative_assets.swift <config.json> [--out dir] [--guides]\n", stderr); exit(2) }
    args.removeFirst()
    var out: String?, guides = false
    while !args.isEmpty {
        let a = args.removeFirst()
        if a == "--out" { out = args.removeFirst() } else if a == "--guides" { guides = true } else { fputs("unknown \(a)\n", stderr); exit(2) }
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let base = url.deletingLastPathComponent()
    let config = try! JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    func resolve(_ p: String) -> URL {
        let e = (p as NSString).expandingTildeInPath
        return e.hasPrefix("/") ? URL(fileURLWithPath: e) : base.appendingPathComponent(e)
    }
    for f in config.brand.fontFiles ?? [] { CTFontManagerRegisterFontsForURL(resolve(f) as CFURL, .process, nil) }
    let outDir = URL(fileURLWithPath: ((out ?? "creative") as NSString).expandingTildeInPath)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    var errors = 0
    for c in config.creative ?? [] {
        guard let img = render(c, brand: config.brand, rawBase: resolve(config.rawDir), guides: guides),
              let dest = CGImageDestinationCreateWithURL(outDir.appendingPathComponent("\(c.name).png") as CFURL,
                                                         UTType.png.identifier as CFString, 1, nil)
        else { errors += 1; continue }
        CGImageDestinationAddImage(dest, img, nil)
        if CGImageDestinationFinalize(dest) { print("  \(c.name).png \(c.width)x\(c.height)") } else { errors += 1 }
    }
    if errors > 0 { exit(1) }
}

main()
