#!/usr/bin/env swift
//
// preview_overlays.swift: render the still layers of an App Preview video from
// a preview config (schema in ../references/preview-config.md).
//
// Usage:
//   swift preview_overlays.swift <preview.json> --out <dir>
//
// Writes into <dir>:
//   background.png        opaque, full frame: the brand gradient, with the top
//                         band filled in the gradient's top colour
//   band_NN_<beat>.png    one per beat, full frame, transparent except the band
//                         text: the logo, app name and tagline ("logo" band), or
//                         a one-line caption plus an optional disclosure line
//                         ("caption" band)
//   overlays.json         the geometry and every word drawn, which
//                         preview_cut.py compares with the config so it never
//                         composites overlays rendered from a stale config
//
// Why Core Graphics rather than ffmpeg drawtext: some ffmpeg builds (Homebrew's
// among them) have no drawtext filter, and rendering here means the film uses
// the same brand fonts as the framed screenshots. The `brand` block is the
// framer's (frame_screenshots.swift), inline or as a path to the framer's config.
//
// The band text sits on the solid band in background.png, so a caption that
// fades in or out never changes the band colour, only the words.
//
// Paths in the config resolve relative to the config file; --out relative to
// the working directory.

import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

// MARK: - Config

struct Brand: Decodable {
    let gradientTop: String       // also the band colour; text sits on it
    let gradientBottom: String
    let accent: String?           // unused in the film; accepted so the framer's block decodes as is
    let headline: String?         // caption and app-name colour, default white
    let subheadline: String?      // disclosure and tagline colour, may carry alpha as #RRGGBBAA
    let headlineFont: String      // PostScript name
    let subheadlineFont: String
    let fontFiles: [String]?      // registered for this process only
}

/// `brand` is either the framer's brand object or a path to the framer's config.
enum BrandSource: Decodable {
    case inline(Brand)
    case file(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let path = try? c.decode(String.self) { self = .file(path) } else { self = .inline(try c.decode(Brand.self)) }
    }
}

struct Beat: Decodable {
    let name: String
    let band: String?             // "logo" or "caption"; default caption when a caption is given, else logo
    let caption: String?
    let disclosure: String?
    let tagline: String?          // logo band only; overrides the config's tagline
    let card: Bool?               // a full-frame brand card: gradient, large caption, optional subline
    let subline: String?          // card only
}

struct Config: Decodable {
    let brand: BrandSource
    let logo: String?
    let appName: String
    let tagline: String?
    let width: Int?
    let height: Int?
    let bandRatio: Double?
    let textScale: Double?
    let beats: [Beat]
}

struct FramerConfig: Decodable { let brand: Brand }

func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n", stderr)
    exit(1)
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

func font(_ name: String, _ size: CGFloat, heavy: Bool) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: heavy ? .bold : .medium)
}

/// yuv420p needs even dimensions; preview_cut.py computes the band the same way.
func evenBand(_ height: Int, _ ratio: Double) -> Int {
    let v = Int((Double(height) * ratio).rounded())
    return v % 2 == 0 ? v : v - 1
}

// MARK: - Layout (fractions of frame width, times textScale)

/// 55 px at 886 wide: reads at the product page's playback size on a phone.
let captionFontRatio: CGFloat = 0.062
/// Small, but above the size at which framed screenshots' sub-headlines stay legible.
let disclosureFontRatio: CGFloat = 0.030
let appNameFontRatio: CGFloat = 0.100
/// Logo height, sized to sit on the app name's cap height.
let logoRatio: CGFloat = 0.115
let taglineFontRatio: CGFloat = 0.038
let logoGapRatio: CGFloat = 0.02
let rowGapRatio: CGFloat = 0.012
let sideMarginRatio: CGFloat = 0.06
/// A caption shrunk below this fraction of its size to stay on one line is too long.
let minShrink: CGFloat = 0.75
/// Card caption and subline sizes, and the most lines each may wrap to.
let cardCaptionFontRatio: CGFloat = 0.085
let cardSublineFontRatio: CGFloat = 0.040
let cardGapRatio: CGFloat = 0.035
let cardCaptionMaxLines = 3
let cardSublineMaxLines = 2

// MARK: - Drawing

func makeContext(width: Int, height: Int, opaque: Bool) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)
    else { fail("could not create a \(width)x\(height) context") }
    ctx.setShouldSmoothFonts(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) {
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("could not write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { fail("could not write \(url.path)") }
}

/// One line of text, shrunk to fit `maxWidth` if needed. Never wraps.
struct Line {
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    var height: CGFloat { ascent + descent }

    init(_ text: String, fontName: String, size: CGFloat, heavy: Bool, color: NSColor, maxWidth: CGFloat, label: String) {
        var s = size
        var made: (CTLine, CGFloat, CGFloat, CGFloat)!
        for _ in 0..<4 {
            let str = NSAttributedString(string: text, attributes: [.font: font(fontName, s, heavy: heavy), .foregroundColor: color])
            let l = CTLineCreateWithAttributedString(str)
            var a: CGFloat = 0, d: CGFloat = 0, lead: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(l, &a, &d, &lead))
            made = (l, w, a, d)
            if w <= maxWidth { break }
            s *= maxWidth / w * 0.995
        }
        if made.1 > maxWidth { fail("\(label): \"\(text)\" does not fit on one line") }
        if s < size * minShrink {
            fputs("Warning: \(label): \"\(text)\" shrunk to \(Int(s / size * 100))% to fit one line; shorten it\n", stderr)
        }
        (line, width, ascent, descent) = made
    }

    /// Draws centred on `centerX` with its top at `top` (CG coordinates, origin bottom-left).
    func draw(_ ctx: CGContext, centerX: CGFloat, top: CGFloat) {
        ctx.textPosition = CGPoint(x: centerX - width / 2, y: top - ascent)
        CTLineDraw(line, ctx)
    }
}

// MARK: - Main

var args = Array(CommandLine.arguments.dropFirst())
guard let configPath = args.first, !configPath.hasPrefix("-") else {
    fputs("usage: preview_overlays.swift <preview.json> --out <dir>\n", stderr)
    exit(2)
}
args.removeFirst()
var outPath: String?
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--out": outPath = args.isEmpty ? nil : args.removeFirst()
    default: fputs("unknown argument \(a)\n", stderr); exit(2)
    }
}
guard let outPath else { fputs("usage: preview_overlays.swift <preview.json> --out <dir>\n", stderr); exit(2) }

let configURL = URL(fileURLWithPath: (configPath as NSString).expandingTildeInPath).standardizedFileURL
let base = configURL.deletingLastPathComponent()
func resolve(_ p: String, from dir: URL) -> URL {
    let e = (p as NSString).expandingTildeInPath
    return e.hasPrefix("/") ? URL(fileURLWithPath: e) : dir.appendingPathComponent(e).standardizedFileURL
}
let config: Config
do { config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL)) } catch {
    fail("\(configURL.path): \(error)")
}

// The brand block, and the directory its fontFiles resolve against.
let brand: Brand
let brandDir: URL
switch config.brand {
case .inline(let b): brand = b; brandDir = base
case .file(let p):
    let url = resolve(p, from: base)
    do { brand = try JSONDecoder().decode(FramerConfig.self, from: Data(contentsOf: url)).brand } catch {
        fail("brand config \(url.path): \(error)")
    }
    brandDir = url.deletingLastPathComponent()
}
for f in brand.fontFiles ?? [] {
    let url = resolve(f, from: brandDir)
    if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
        fputs("Warning: could not register font file \(url.path)\n", stderr)
    }
}
for name in [brand.headlineFont, brand.subheadlineFont] where NSFont(name: name, size: 12) == nil {
    fputs("Warning: font \(name) not available; using the system font\n", stderr)
}

let width = config.width ?? 886
let height = config.height ?? 1920
let bandRatio = config.bandRatio ?? 0.14
guard bandRatio > 0, bandRatio < 0.5 else { fail("bandRatio must be between 0 and 0.5") }
let bandHeight = evenBand(height, bandRatio)
let scale = CGFloat(config.textScale ?? 1.0)
let w = CGFloat(width), h = CGFloat(height), band = CGFloat(bandHeight)
let maxWidth = w * (1 - sideMarginRatio * 2)
let textColor = color(brand.headline ?? "#FFFFFF")
let secondaryColor = color(brand.subheadline ?? "#FFFFFFE0")
let bandColor = color(brand.gradientTop)

let outDir = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath).standardizedFileURL
do { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) } catch {
    fail("could not create \(outDir.path): \(error)")
}
// Stale bands from an earlier config would otherwise sit beside the new ones.
for name in (try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? []
where name.hasPrefix("band_") && name.hasSuffix(".png") {
    try? FileManager.default.removeItem(at: outDir.appendingPathComponent(name))
}

func drawGradient(_ ctx: CGContext) {
    let colors = [bandColor.cgColor, color(brand.gradientBottom).cgColor] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: w / 2, y: h), end: CGPoint(x: w / 2, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

/// Centred text wrapped to `maxWidth`; fails when it needs more than `maxLines` lines.
func wrapped(_ text: String, fontName: String, size: CGFloat, heavy: Bool, color c: NSColor, maxLines: Int,
             label: String) -> (CTFramesetter, CGFloat) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = 1.05
    let str = NSAttributedString(string: text, attributes: [
        .font: font(fontName, size, heavy: heavy), .foregroundColor: c, .paragraphStyle: para])
    let fs = CTFramesetterCreateWithAttributedString(str)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), nil,
                                                           CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
    let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0),
                                         CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: fit.height + 1), transform: nil), nil)
    let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
    if lines.count > maxLines {
        fail("\(label): \"\(text)\" wraps to \(lines.count) lines at this size; at most \(maxLines). Shorten it")
    }
    return (fs, ceil(fit.height))
}

// Background: gradient, band filled solid on top.
do {
    let ctx = makeContext(width: width, height: height, opaque: true)
    drawGradient(ctx)
    ctx.setFillColor(bandColor.cgColor)
    ctx.fill(CGRect(x: 0, y: h - band, width: w, height: band))
    writePNG(ctx, to: outDir.appendingPathComponent("background.png"))
}

// The logo, loaded once if any beat needs it.
var logoImage: CGImage?
func loadLogo() -> CGImage? {
    if let logoImage { return logoImage }
    guard let p = config.logo else { return nil }
    let url = resolve(p, from: base)
    guard let img = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("cannot load logo \(url.path)")
    }
    logoImage = img
    return img
}

var seen = Set<String>()
var beatEntries: [[String: Any]] = []
for (i, beat) in config.beats.enumerated() {
    guard seen.insert(beat.name).inserted else { fail("beat name \(beat.name) is used twice") }
    let kind = beat.card == true ? "card" : (beat.band ?? (beat.caption != nil ? "caption" : "logo"))
    let file = String(format: "band_%02d_%@.png", i + 1, beat.name)
    // A card is the whole frame, opaque; a band image is transparent outside its text.
    let ctx = makeContext(width: width, height: height, opaque: kind == "card")
    var entry: [String: Any] = ["name": beat.name, "band": kind, "file": file]

    switch kind {
    case "caption":
        guard let caption = beat.caption, !caption.isEmpty else { fail("beat \(beat.name): a caption band needs a caption") }
        if caption.contains("\n") { fail("beat \(beat.name): a caption is one line") }
        let cap = Line(caption, fontName: brand.headlineFont, size: w * captionFontRatio * scale, heavy: true,
                       color: textColor, maxWidth: maxWidth, label: "beat \(beat.name) caption")
        let disc = beat.disclosure.map {
            Line($0, fontName: brand.subheadlineFont, size: w * disclosureFontRatio * scale, heavy: false,
                 color: secondaryColor, maxWidth: maxWidth, label: "beat \(beat.name) disclosure")
        }
        let gap = w * rowGapRatio * scale
        let block = cap.height + (disc.map { gap + $0.height } ?? 0)
        if block > band { fail("beat \(beat.name): caption block (\(Int(block)) px) is taller than the band (\(bandHeight) px)") }
        var top = h - (band - block) / 2
        cap.draw(ctx, centerX: w / 2, top: top)
        top -= cap.height + gap
        disc?.draw(ctx, centerX: w / 2, top: top)
        entry["caption"] = caption
        if let d = beat.disclosure { entry["disclosure"] = d }

    case "logo":
        guard let tagline = beat.tagline ?? config.tagline, !tagline.isEmpty else {
            fail("beat \(beat.name): a logo band needs a tagline (beat \"tagline\" or the config's \"tagline\")")
        }
        let logo = loadLogo()
        if logo == nil && i == 0 { fputs("Warning: no \"logo\" in the config; the logo band shows the app name only\n", stderr) }
        let logoH = w * logoRatio * scale
        let logoW = logo.map { logoH * CGFloat($0.width) / CGFloat($0.height) } ?? 0
        let logoGap = logo == nil ? 0 : w * logoGapRatio * scale
        let name = Line(config.appName, fontName: brand.headlineFont, size: w * appNameFontRatio * scale, heavy: true,
                        color: textColor, maxWidth: maxWidth - logoW - logoGap, label: "appName")
        let tag = Line(tagline, fontName: brand.subheadlineFont, size: w * taglineFontRatio * scale, heavy: false,
                       color: secondaryColor, maxWidth: maxWidth, label: "beat \(beat.name) tagline")
        let gap = w * rowGapRatio * scale
        let rowH = max(logo == nil ? 0 : logoH, name.height)
        let block = rowH + gap + tag.height
        if block > band { fail("beat \(beat.name): logo block (\(Int(block)) px) is taller than the band (\(bandHeight) px)") }
        let top = h - (band - block) / 2
        let rowCenterY = top - rowH / 2
        var x = (w - (logoW + logoGap + name.width)) / 2
        if let logo {
            ctx.interpolationQuality = .high
            ctx.draw(logo, in: CGRect(x: x, y: rowCenterY - logoH / 2, width: logoW, height: logoH))
            x += logoW + logoGap
        }
        // Centre the name's glyph box (ascent + descent) on the row.
        ctx.textPosition = CGPoint(x: x, y: rowCenterY - (name.ascent - name.descent) / 2)
        CTLineDraw(name.line, ctx)
        tag.draw(ctx, centerX: w / 2, top: top - rowH - gap)
        entry["appName"] = config.appName
        entry["tagline"] = tagline

    case "card":
        guard let caption = beat.caption, !caption.isEmpty else { fail("beat \(beat.name): a card needs a caption") }
        drawGradient(ctx)
        let (capFS, capH) = wrapped(caption, fontName: brand.headlineFont, size: w * cardCaptionFontRatio * scale,
                                    heavy: true, color: textColor, maxLines: cardCaptionMaxLines,
                                    label: "card \(beat.name) caption")
        let sub = beat.subline.map {
            wrapped($0, fontName: brand.subheadlineFont, size: w * cardSublineFontRatio * scale, heavy: false,
                    color: secondaryColor, maxLines: cardSublineMaxLines, label: "card \(beat.name) subline")
        }
        let gap = w * cardGapRatio * scale
        let block = capH + (sub.map { gap + $0.1 } ?? 0)
        if block > h * 0.8 { fail("card \(beat.name): text block (\(Int(block)) px) does not fit the frame") }
        let x = (w - maxWidth) / 2
        var top = h - (h - block) / 2
        CTFrameDraw(CTFramesetterCreateFrame(capFS, CFRangeMake(0, 0),
                                             CGPath(rect: CGRect(x: x, y: top - capH, width: maxWidth, height: capH), transform: nil), nil), ctx)
        top -= capH + gap
        if let (subFS, subH) = sub.map({ ($0.0, $0.1) }) {
            CTFrameDraw(CTFramesetterCreateFrame(subFS, CFRangeMake(0, 0),
                                                 CGPath(rect: CGRect(x: x, y: top - subH, width: maxWidth, height: subH), transform: nil), nil), ctx)
        }
        entry["caption"] = caption
        if let s = beat.subline { entry["subline"] = s }

    default:
        fail("beat \(beat.name): band must be \"logo\" or \"caption\" (or the beat a card), not \"\(kind)\"")
    }
    writePNG(ctx, to: outDir.appendingPathComponent(file))
    beatEntries.append(entry)
    print("  \(file)")
}

let manifest: [String: Any] = [
    "width": width, "height": height, "band_height": bandHeight, "band_ratio": bandRatio,
    "background": "background.png", "beats": beatEntries,
]
do {
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: outDir.appendingPathComponent("overlays.json"))
} catch { fail("could not write overlays.json: \(error)") }
print("Rendered background.png and \(beatEntries.count) bands (band \(bandHeight) px of \(height)) -> \(outDir.path)/")
