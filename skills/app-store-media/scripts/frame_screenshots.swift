#!/usr/bin/env swift
//
// frame_screenshots.swift: frame raw simulator captures for App Store Connect.
//
// One config file per app (JSON, schema in ../references/config.md) names the
// brand colours and fonts, the device canvases, the caption copy and where raw
// captures live. Each output is an opaque PNG at an exact App Store size: a
// brand gradient, a headline + accent rule + subheadline, and the capture
// seated in a drawn device bezel.
//
// Usage:
//   swift frame_screenshots.swift <config.json> [--captions top|alternate] [--out <dir>] [--only <deviceKey>,...]
//
// Paths in the config resolve relative to the config file's directory; --out
// resolves relative to the working directory.
//
// Caption layouts:
//   top        every caption above the device; the device hangs off the bottom
//              edge when it is a little too tall (up to maxOverflow of its height),
//              and shrinks to fit when it is much too tall (short canvases such as
//              5.5" and 4.7", where hanging off would hide the app's bottom controls).
//   alternate  captions alternate top, bottom, top...; the device always fits whole,
//              and the gradient flips so text always sits on the darker colour.
//
// Device frames are allowed on screenshots and banned in App Preview video
// (Apple, "App Previews"), so a preview must not reuse this treatment.

import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

// MARK: - Config

struct Config: Decodable {
    struct Brand: Decodable {
        let gradientTop: String       // under the caption in the top layout; the darker colour
        let gradientBottom: String
        let accent: String            // the rule between headline and subheadline
        let headline: String?
        let subheadline: String?      // may carry alpha as #RRGGBBAA
        let headlineFont: String      // PostScript name
        let subheadlineFont: String
        let fontFiles: [String]?      // registered for this process only
    }
    struct Device: Decodable {
        let key: String               // output folder name
        let raw: String               // raw capture folder under rawDir
        let copy: String              // key into "copy"
        let width: Int
        let height: Int
        let screenCornerRadius: Double  // fraction of screen width
        let fontScale: Double         // text is sized from canvas width x this
        let sideMargin: Double?       // fraction of width each side of the bezel
        let note: String?
    }
    struct Screen: Decodable {
        let file: String
        let headline: String
        let subheadline: String
    }
    let rawDir: String
    let outDir: String
    let brand: Brand
    let devices: [Device]
    let copy: [String: [Screen]]
    let layout: [String: Double]?
}

func color(_ hex: String) -> NSColor {
    var s = hex.trimmingCharacters(in: .whitespaces)
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

// MARK: - Layout (fractions; overridable from config "layout")

struct Layout {
    var captionZone = 0.205      // of canvas height
    var sideMargin = 0.085       // of canvas width, each side
    var bezelThickness = 0.018   // of bezel width
    var shadowBlur = 0.030
    var shadowOffset = 0.012
    var headlineFont = 0.072     // of canvas width x fontScale
    var subheadlineFont = 0.034
    var headlineGap = 0.024
    var ruleWidth = 0.075
    var ruleHeight = 0.006
    var maxOverflow = 0.05       // top layout: how much of the device may hang off the edge
    var edgeMargin = 0.03        // of canvas height, between a fitted device and the far edge

    init(_ o: [String: Double]?) {
        guard let o else { return }
        captionZone = o["captionZone"] ?? captionZone
        sideMargin = o["sideMargin"] ?? sideMargin
        bezelThickness = o["bezelThickness"] ?? bezelThickness
        headlineFont = o["headlineFont"] ?? headlineFont
        subheadlineFont = o["subheadlineFont"] ?? subheadlineFont
        maxOverflow = o["maxOverflow"] ?? maxOverflow
        edgeMargin = o["edgeMargin"] ?? edgeMargin
    }
}

// MARK: - Drawing

func drawGradient(ctx: CGContext, w: CGFloat, h: CGFloat, dark: NSColor, light: NSColor, darkAtTop: Bool) {
    let colors = [dark.cgColor, light.cgColor] as CFArray
    guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
    // CoreGraphics origin is bottom-left.
    let start = CGPoint(x: w / 2, y: darkAtTop ? h : 0), end = CGPoint(x: w / 2, y: darkAtTop ? 0 : h)
    ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func textSize(_ s: NSAttributedString, maxWidth: CGFloat) -> CGSize {
    CTFramesetterSuggestFrameSizeWithConstraints(
        CTFramesetterCreateWithAttributedString(s), CFRangeMake(0, 0), nil,
        CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
}

@discardableResult
func drawText(_ s: NSAttributedString, ctx: CGContext, canvasWidth: CGFloat, maxWidth: CGFloat, topY: CGFloat) -> CGFloat {
    let fs = CTFramesetterCreateWithAttributedString(s)
    let size = textSize(s, maxWidth: maxWidth)
    let rect = CGRect(x: (canvasWidth - maxWidth) / 2, y: topY - size.height, width: maxWidth, height: size.height)
    CTFrameDraw(CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil), ctx)
    return size.height
}

func font(_ name: String, _ size: CGFloat, heavy: Bool) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: heavy ? .heavy : .semibold)
}

/// Caption block centred vertically in its zone. zoneTop/zoneBottom are CG y values.
func drawCaption(ctx: CGContext, screen: Config.Screen, brand: Config.Brand, device: Config.Device, L: Layout,
                 w: CGFloat, zoneTop: CGFloat, zoneBottom: CGFloat) {
    let maxWidth = w * (1 - L.sideMargin * 2)
    let unit = w * device.fontScale
    let gap = unit * L.headlineGap, ruleH = unit * L.ruleHeight, ruleW = unit * L.ruleWidth
    let hp = NSMutableParagraphStyle(); hp.alignment = .center; hp.lineHeightMultiple = 1.0
    let sp = NSMutableParagraphStyle(); sp.alignment = .center; sp.lineHeightMultiple = 1.12
    let head = NSAttributedString(string: screen.headline, attributes: [
        .font: font(brand.headlineFont, unit * L.headlineFont, heavy: true),
        .foregroundColor: color(brand.headline ?? "#FFFFFF"), .paragraphStyle: hp])
    let sub = NSAttributedString(string: screen.subheadline, attributes: [
        .font: font(brand.subheadlineFont, unit * L.subheadlineFont, heavy: false),
        .foregroundColor: color(brand.subheadline ?? "#FFFFFFE0"), .paragraphStyle: sp])
    let block = textSize(head, maxWidth: maxWidth).height + gap + ruleH + gap + textSize(sub, maxWidth: maxWidth).height
    if block > zoneTop - zoneBottom {
        fputs("Warning: \(device.key)/\(screen.file): caption (\(Int(block))px) taller than its zone (\(Int(zoneTop - zoneBottom))px)\n", stderr)
    }
    var y = zoneTop - ((zoneTop - zoneBottom) - block) / 2
    y -= drawText(head, ctx: ctx, canvasWidth: w, maxWidth: maxWidth, topY: y)
    y -= gap
    ctx.saveGState()
    ctx.setFillColor(color(brand.accent).cgColor)
    let rule = CGRect(x: (w - ruleW) / 2, y: y - ruleH, width: ruleW, height: ruleH)
    ctx.addPath(CGPath(roundedRect: rule, cornerWidth: ruleH / 2, cornerHeight: ruleH / 2, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    y -= ruleH + gap
    drawText(sub, ctx: ctx, canvasWidth: w, maxWidth: maxWidth, topY: y)
}

/// The capture in a drawn bezel. `anchorY` is the edge next to the caption zone;
/// `captionOnTop` says which way the device extends from it.
func drawDevice(ctx: CGContext, image: CGImage, device: Config.Device, L: Layout, w: CGFloat, h: CGFloat,
                captionOnTop: Bool, forceFit: Bool) {
    let side = device.sideMargin ?? L.sideMargin
    var bezelW = w * (1 - side * 2)
    let aspect = CGFloat(image.height) / CGFloat(image.width)
    func bezelHeight(_ bw: CGFloat) -> CGFloat {
        let t = bw * L.bezelThickness
        return (bw - 2 * t) * aspect + 2 * t
    }
    let space = h * (1 - L.captionZone)
    let overflow = bezelHeight(bezelW) - space
    if forceFit || overflow > bezelHeight(bezelW) * L.maxOverflow {
        let target = space - h * L.edgeMargin
        if bezelHeight(bezelW) > target {
            // bezelHeight is linear in bw: scale to fit exactly.
            bezelW *= target / bezelHeight(bezelW)
        }
    }
    let t = bezelW * L.bezelThickness
    let screenW = bezelW - 2 * t, screenH = screenW * aspect, bezelH = screenH + 2 * t
    let anchor = captionOnTop ? h * (1 - L.captionZone) : h * L.captionZone
    let y = captionOnTop ? anchor - bezelH : anchor
    let bezel = CGRect(x: (w - bezelW) / 2, y: y, width: bezelW, height: bezelH)
    let screenR = screenW * device.screenCornerRadius, bezelR = screenR + t

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -w * L.shadowOffset), blur: w * L.shadowBlur,
                  color: NSColor(white: 0, alpha: 0.40).cgColor)
    ctx.addPath(CGPath(roundedRect: bezel, cornerWidth: bezelR, cornerHeight: bezelR, transform: nil))
    ctx.setFillColor(NSColor(white: 0.09, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    let screenRect = bezel.insetBy(dx: t, dy: t)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: screenR, cornerHeight: screenR, transform: nil)
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: screenRect)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
    ctx.setLineWidth(max(1, t * 0.2))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Main

func main() {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let configPath = args.first, !configPath.hasPrefix("-") else {
        fputs("usage: frame_screenshots.swift <config.json> [--captions top|alternate] [--out <dir>] [--only a,b]\n", stderr)
        exit(2)
    }
    args.removeFirst()
    var captions = "top", outOverride: String?, only: Set<String>?
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--captions": captions = args.removeFirst()
        case "--out": outOverride = args.removeFirst()
        case "--only": only = Set(args.removeFirst().split(separator: ",").map(String.init))
        default: fputs("unknown argument \(a)\n", stderr); exit(2)
        }
    }
    guard captions == "top" || captions == "alternate" else { fputs("--captions top|alternate\n", stderr); exit(2) }

    let configURL = URL(fileURLWithPath: configPath).standardizedFileURL
    let base = configURL.deletingLastPathComponent()
    let config: Config
    do { config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL)) } catch {
        fputs("Error: \(configURL.path): \(error)\n", stderr); exit(1)
    }
    func resolve(_ p: String) -> URL {
        let e = (p as NSString).expandingTildeInPath
        return e.hasPrefix("/") ? URL(fileURLWithPath: e) : base.appendingPathComponent(e)
    }
    for f in config.brand.fontFiles ?? [] { CTFontManagerRegisterFontsForURL(resolve(f) as CFURL, .process, nil) }
    if NSFont(name: config.brand.headlineFont, size: 12) == nil {
        fputs("Warning: font \(config.brand.headlineFont) not available; using the system font\n", stderr)
    }
    let L = Layout(config.layout)
    let dark = color(config.brand.gradientTop), light = color(config.brand.gradientBottom)
    let rawBase = resolve(config.rawDir)
    // --out is relative to the working directory; config paths are relative to the config.
    let outBase = outOverride.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
        ?? resolve(config.outDir)
    var total = 0, errors = 0

    for device in config.devices where only?.contains(device.key) ?? true {
        guard let screens = config.copy[device.copy] else { fputs("Error: no copy \"\(device.copy)\"\n", stderr); errors += 1; continue }
        let rawDir = rawBase.appendingPathComponent(device.raw)
        guard FileManager.default.fileExists(atPath: rawDir.path) else {
            fputs("Skip \(device.key): no raw captures at \(rawDir.path)\n", stderr); continue
        }
        let outDir = outBase.appendingPathComponent(device.key)
        try? FileManager.default.removeItem(at: outDir)
        try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let w = CGFloat(device.width), h = CGFloat(device.height)

        for (i, screen) in screens.enumerated() {
            let rawURL = rawDir.appendingPathComponent(screen.file)
            guard let img = NSImage(contentsOf: rawURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fputs("Error: cannot load \(rawURL.path)\n", stderr); errors += 1; continue
            }
            // Opaque context: App Store Connect rejects screenshots with an alpha channel.
            guard let ctx = CGContext(data: nil, width: device.width, height: device.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { errors += 1; continue }
            ctx.setShouldSmoothFonts(true); ctx.setShouldAntialias(true)
            let onTop = captions == "top" || i % 2 == 0
            drawGradient(ctx: ctx, w: w, h: h, dark: dark, light: light, darkAtTop: onTop)
            drawDevice(ctx: ctx, image: img, device: device, L: L, w: w, h: h, captionOnTop: onTop,
                       forceFit: captions == "alternate")
            let zone = h * L.captionZone
            drawCaption(ctx: ctx, screen: screen, brand: config.brand, device: device, L: L, w: w,
                        zoneTop: onTop ? h : zone, zoneBottom: onTop ? h - zone : 0)

            let name = String(format: "%02d-%@.png", i + 1, (screen.file as NSString).deletingPathExtension)
            let outURL = outDir.appendingPathComponent(name)
            guard let image = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { errors += 1; continue }
            CGImageDestinationAddImage(dest, image, nil)
            if CGImageDestinationFinalize(dest) { total += 1; print("  \(device.key)/\(name)") } else { errors += 1 }
        }
    }
    print("Framed \(total) images (\(captions) captions), \(errors) errors -> \(outBase.path)/")
    if errors > 0 { exit(1) }
}

main()
