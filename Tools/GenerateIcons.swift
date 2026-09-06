//
//  GenerateIcons.swift
//  NotchTune
//
//  Draws the app icon and the menu bar glyphs, then writes every size as PNG.
//  Run with:  swift Tools/GenerateIcons.swift
//
//  Everything is drawn from one 256 unit design, so each size is rendered
//  rather than scaled up from a small bitmap.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Geometry, all in a 256 unit square

/// Apple's rounded square, a superellipse. Drawn from the formula rather than
/// guessed Bezier handles, which bulge at the corners and look like a blob.
func squirclePath(in rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    let n: CGFloat = 5          // exponent; 5 is close to Apple's shape
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let steps = 360

    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

/// Tilt applied to the whole megaphone. The system volume icon is always level,
/// so tipping this one is the cheapest way to tell them apart.
let megaphoneTilt: CGFloat = 0  // tilting separated the parts; kept level

/// The cone body, narrow at the left, flaring right, stopping short of the rim.
func hornPath(_ u: (CGFloat) -> CGFloat, _ v: (CGFloat) -> CGFloat) -> CGPath {
    let p = CGMutablePath()
    let r = u(12) - u(0)
    p.move(to: CGPoint(x: u(56), y: v(116)))
    p.addArc(tangent1End: CGPoint(x: u(166), y: v(76)),
             tangent2End: CGPoint(x: u(166), y: v(180)), radius: r)
    p.addArc(tangent1End: CGPoint(x: u(166), y: v(180)),
             tangent2End: CGPoint(x: u(56), y: v(140)), radius: r)
    p.addArc(tangent1End: CGPoint(x: u(56), y: v(140)),
             tangent2End: CGPoint(x: u(56), y: v(116)), radius: r * 0.8)
    p.addArc(tangent1End: CGPoint(x: u(56), y: v(116)),
             tangent2End: CGPoint(x: u(166), y: v(76)), radius: r * 0.8)
    p.closeSubpath()
    return p
}

/// The flared lip at the mouth. A speaker has no rim, so this is the second
/// thing that separates the two shapes.
func rimPath(_ u: (CGFloat) -> CGFloat, _ v: (CGFloat) -> CGFloat) -> CGPath {
    let rect = CGRect(x: u(158), y: v(190), width: u(184) - u(158), height: v(66) - v(190))
    return CGPath(roundedRect: rect, cornerWidth: u(13) - u(0),
                  cornerHeight: u(13) - u(0), transform: nil)
}

/// The grip, hanging clearly below the cone rather than tucked against it.
func gripPath(_ u: (CGFloat) -> CGFloat, _ v: (CGFloat) -> CGFloat) -> CGPath {
    let rect = CGRect(x: u(86), y: v(214), width: u(112) - u(86), height: v(148) - v(214))
    return CGPath(roundedRect: rect, cornerWidth: u(11) - u(0),
                  cornerHeight: u(11) - u(0), transform: nil)
}

/// The mouthpiece cap on the narrow end.
func capPath(_ u: (CGFloat) -> CGFloat, _ v: (CGFloat) -> CGFloat) -> CGPath {
    let rect = CGRect(x: u(40), y: v(142), width: u(60) - u(40), height: v(114) - v(142))
    return CGPath(roundedRect: rect, cornerWidth: u(8) - u(0),
                  cornerHeight: u(8) - u(0), transform: nil)
}

/// Rounded bar used for the blocking stroke, rotated about the icon centre.
func slashPath(_ u: (CGFloat) -> CGFloat, _ v: (CGFloat) -> CGFloat,
               top: CGFloat, height: CGFloat) -> CGPath {
    let rect = CGRect(x: u(24), y: v(top + height), width: u(232) - u(24), height: v(0) - v(height))
    let rounded = CGPath(roundedRect: rect, cornerWidth: abs(v(0) - v(height)) / 2,
                         cornerHeight: abs(v(0) - v(height)) / 2, transform: nil)
    let centre = CGPoint(x: u(128), y: v(127))
    var t = CGAffineTransform(translationX: centre.x, y: centre.y)
        .rotated(by: 38 * .pi / 180)
        .translatedBy(x: -centre.x, y: -centre.y)
    return rounded.copy(using: &t) ?? rounded
}

// MARK: - Drawing

func drawAppIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Apple leaves a margin around the icon body rather than filling the tile.
    let inset = size * 0.10
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let s = body.width / 256
    func u(_ n: CGFloat) -> CGFloat { body.minX + n * s }
    // Flipped: the design is described top down, CoreGraphics counts up.
    func v(_ n: CGFloat) -> CGFloat { body.maxY - n * s }

    let space = CGColorSpaceCreateDeviceRGB()

    // Background
    ctx.saveGState()
    ctx.addPath(squirclePath(in: body))
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.173, green: 0.208, blue: 0.314, alpha: 1).cgColor,
        NSColor(srgbRed: 0.102, green: 0.125, blue: 0.212, alpha: 1).cgColor,
        NSColor(srgbRed: 0.055, green: 0.071, blue: 0.125, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY), options: [])

    // Light from above
    let sheen = CGGradient(colorsSpace: space, colors: [
        NSColor(white: 1, alpha: 0.16).cgColor,
        NSColor(white: 1, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(
        sheen,
        startCenter: CGPoint(x: body.midX, y: body.maxY + body.height * 0.15), startRadius: 0,
        endCenter: CGPoint(x: body.midX, y: body.maxY + body.height * 0.15),
        endRadius: body.width * 0.6, options: []
    )
    ctx.restoreGState()

    // Megaphone, tilted as a group
    ctx.saveGState()
    let pivot = CGPoint(x: u(120), y: v(128))
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.rotate(by: megaphoneTilt)
    ctx.translateBy(x: -pivot.x, y: -pivot.y)

    let metal = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).cgColor,
        NSColor(srgbRed: 0.894, green: 0.914, blue: 0.949, alpha: 1).cgColor,
        NSColor(srgbRed: 0.686, green: 0.722, blue: 0.800, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.5, 1])!
    let dark = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.678, green: 0.714, blue: 0.792, alpha: 1).cgColor,
        NSColor(srgbRed: 0.435, green: 0.475, blue: 0.573, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!

    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.014),
                  blur: size * 0.024, color: NSColor(white: 0, alpha: 0.4).cgColor)

    // grip first, so the cone overlaps it
    ctx.saveGState()
    ctx.addPath(gripPath(u, v)); ctx.clip()
    ctx.drawLinearGradient(dark, start: CGPoint(x: u(0), y: v(148)),
                           end: CGPoint(x: u(0), y: v(214)), options: [])
    ctx.restoreGState()

    // mouthpiece cap
    ctx.saveGState()
    ctx.addPath(capPath(u, v)); ctx.clip()
    ctx.drawLinearGradient(dark, start: CGPoint(x: u(0), y: v(114)),
                           end: CGPoint(x: u(0), y: v(142)), options: [])
    ctx.restoreGState()

    // cone
    ctx.saveGState()
    ctx.addPath(hornPath(u, v)); ctx.clip()
    ctx.drawLinearGradient(metal, start: CGPoint(x: u(56), y: v(76)),
                           end: CGPoint(x: u(166), y: v(180)), options: [])
    ctx.restoreGState()

    // rim at the mouth
    ctx.saveGState()
    ctx.addPath(rimPath(u, v)); ctx.clip()
    ctx.drawLinearGradient(metal, start: CGPoint(x: u(158), y: v(66)),
                           end: CGPoint(x: u(184), y: v(190)), options: [])
    ctx.restoreGState()

    // shade the underside of the cone so it reads as round
    ctx.saveGState()
    ctx.addPath(hornPath(u, v)); ctx.clip()
    let shade = CGGradient(colorsSpace: space, colors: [
        NSColor(white: 0, alpha: 0).cgColor,
        NSColor(srgbRed: 0.35, green: 0.39, blue: 0.49, alpha: 0.85).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: u(0), y: v(126)),
                           end: CGPoint(x: u(0), y: v(184)), options: [])
    ctx.restoreGState()

    ctx.restoreGState()

    // Blocking bar
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008),
                  blur: size * 0.016, color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.addPath(slashPath(u, v, top: 114, height: 24))
    ctx.clip()
    let red = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 1.0, green: 0.42, blue: 0.37, alpha: 1).cgColor,
        NSColor(srgbRed: 0.827, green: 0.204, blue: 0.165, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(red, start: CGPoint(x: u(24), y: v(112)),
                           end: CGPoint(x: u(232), y: v(142)), options: [])
    ctx.restoreGState()

    // Highlight along the top of the bar
    ctx.saveGState()
    ctx.addPath(slashPath(u, v, top: 116, height: 7))
    ctx.setFillColor(NSColor(white: 1, alpha: 0.22).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Flat black glyph for the menu bar. Rendered as a template, so macOS
/// recolours it for light and dark automatically. `slashed` adds the bar, which
/// marks muting as switched on.
func drawMenuBarGlyph(size: CGFloat, slashed: Bool) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Design the glyph in a 32 unit box with a little breathing room.
    let pad = size * 0.06
    let box = CGRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
    let s = box.width / 32
    func u(_ n: CGFloat) -> CGFloat { box.minX + n * s }
    func v(_ n: CGFloat) -> CGFloat { box.maxY - n * s }

    // Full weight, to match the other menu bar icons.
    let ink = NSColor(white: 0, alpha: 1)
    ctx.setFillColor(ink.cgColor)
    ctx.setStrokeColor(ink.cgColor)

    // Cone
    let horn = CGMutablePath()
    horn.move(to: CGPoint(x: u(7), y: v(13)))
    horn.addArc(tangent1End: CGPoint(x: u(21), y: v(8)),
                tangent2End: CGPoint(x: u(21), y: v(24)), radius: 1.6 * s)
    horn.addArc(tangent1End: CGPoint(x: u(21), y: v(24)),
                tangent2End: CGPoint(x: u(7), y: v(19)), radius: 1.6 * s)
    horn.addArc(tangent1End: CGPoint(x: u(7), y: v(19)),
                tangent2End: CGPoint(x: u(7), y: v(13)), radius: 1.2 * s)
    horn.addArc(tangent1End: CGPoint(x: u(7), y: v(13)),
                tangent2End: CGPoint(x: u(21), y: v(8)), radius: 1.2 * s)
    horn.closeSubpath()
    ctx.addPath(horn)
    ctx.fillPath()

    // Rim at the mouth, the main thing that separates this from a speaker
    ctx.addPath(CGPath(roundedRect:
        CGRect(x: u(20), y: v(26), width: u(24) - u(20), height: v(6) - v(26)),
        cornerWidth: 1.8 * s, cornerHeight: 1.8 * s, transform: nil))
    ctx.fillPath()

    // Mouthpiece
    ctx.addPath(CGPath(roundedRect:
        CGRect(x: u(2), y: v(19), width: u(8) - u(2), height: v(13) - v(19)),
        cornerWidth: 1.4 * s, cornerHeight: 1.4 * s, transform: nil))
    ctx.fillPath()

    // Grip
    ctx.addPath(CGPath(roundedRect:
        CGRect(x: u(11), y: v(28), width: u(15) - u(11), height: v(18) - v(28)),
        cornerWidth: 1.6 * s, cornerHeight: 1.6 * s, transform: nil))
    ctx.fillPath()

    if slashed {
        /// A bar across the whole glyph, at `height` units thick.
        func bar(_ height: CGFloat) -> CGPath {
            let rect = CGRect(x: u(-3), y: v(16 + height / 2),
                              width: u(35) - u(-3), height: v(0) - v(height))
            let rounded = CGPath(roundedRect: rect, cornerWidth: (v(0) - v(height)) / 2,
                                 cornerHeight: (v(0) - v(height)) / 2, transform: nil)
            let centre = CGPoint(x: u(16), y: v(16))
            var t = CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: 38 * .pi / 180)
                .translatedBy(x: -centre.x, y: -centre.y)
            return rounded.copy(using: &t) ?? rounded
        }

        // Cut a wider channel out of the horn first, so the bar reads as
        // lying on top rather than merging into it.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(bar(6.4))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(bar(3.2))
        ctx.fillPath()
    }


    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Writing

func write(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("could not encode \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
    print("  \(path)")
}

let root = FileManager.default.currentDirectoryPath
let appIconDir = "\(root)/NotchTune/Assets.xcassets/AppIcon.appiconset"
let onDir = "\(root)/NotchTune/Assets.xcassets/MenuBarOn.imageset"
let offDir = "\(root)/NotchTune/Assets.xcassets/MenuBarOff.imageset"

print("app icon:")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    write(drawAppIcon(size: CGFloat(size)), to: "\(appIconDir)/icon_\(size).png")
}

print("menu bar:")
for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
    write(drawMenuBarGlyph(size: CGFloat(18 * scale), slashed: true),
          to: "\(onDir)/on\(suffix).png")
    write(drawMenuBarGlyph(size: CGFloat(18 * scale), slashed: false),
          to: "\(offDir)/off\(suffix).png")
}

print("done")
