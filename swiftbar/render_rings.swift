import AppKit

// Compact twin-ring gauge for the SwiftBar menu bar item.
// args: sessUsed weekUsed outPath [stale]   (percentages 0-100 = USED)
//
// IMPORTANT: SwiftBar 2.x only shows a menu-bar image up to ~100px WIDE.
// This renderer keeps the PNG ~88px wide (44pt @2x) by putting each
// percentage INSIDE its ring — no separate labels, no reset text.
// The reset countdown is shown as title text by the plugin instead.
let a = CommandLine.arguments
guard a.count >= 4, let sess = Int(a[1]), let week = Int(a[2]) else {
    FileHandle.standardError.write("usage: render_rings <sessUsed> <weekUsed> <out.png> [stale]\n".data(using: .utf8)!)
    exit(1)
}
let outPath = a[3]
let stale = a.count >= 5 && a[4] == "stale"

let scale: CGFloat = 2.0
let logicalH: CGFloat = 22
let ring: CGFloat = 17     // ring diameter (pt)
let lineW: CGFloat = 2.5
let gap: CGFloat = 6
let pad: CGFloat = 2
let W = pad + ring + gap + ring + pad          // 44pt -> 88px @2x (< 100px SwiftBar cap)

func colorFor(_ used: Int) -> NSColor {
    if stale { return NSColor(srgbRed: 0x8A/255, green: 0x93/255, blue: 0xA0/255, alpha: 1) }           // grey
    if used >= 85 { return NSColor(srgbRed: 0xC4/255, green: 0x52/255, blue: 0x4F/255, alpha: 1) }      // red
    if used >= 60 { return NSColor(srgbRed: 0xD6/255, green: 0xC4/255, blue: 0x86/255, alpha: 1) }      // sand
    return NSColor(srgbRed: 0x8F/255, green: 0xBA/255, blue: 0xA0/255, alpha: 1)                        // sage
}

let pxW = Int(W * scale), pxH = Int(logicalH * scale)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: scale, y: scale)
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsctx

func drawRing(cx: CGFloat, cy: CGFloat, used: Int) {
    let clamped = max(0, min(100, used))
    let r = ring/2 - lineW/2
    // faint full track
    let track = NSBezierPath()
    track.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: 360)
    NSColor(white: 0.5, alpha: 0.28).setStroke()
    track.lineWidth = lineW
    track.stroke()
    // colored USED arc, filling clockwise from 12 o'clock as usage grows
    let sweep = CGFloat(clamped) / 100.0 * 360.0
    if sweep > 0 {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                      startAngle: 90, endAngle: 90 - sweep, clockwise: true)
        colorFor(clamped).setStroke()
        arc.lineWidth = lineW
        arc.lineCapStyle = .round
        arc.stroke()
    }
    // percentage centered inside the ring (3-digit "100" gets a smaller font)
    let s = "\(clamped)"
    let fsize: CGFloat = s.count >= 3 ? 6 : 8
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: fsize, weight: .semibold),
        .foregroundColor: colorFor(clamped)
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: cx - sz.width/2, y: cy - sz.height/2))
}

let cy = logicalH/2
drawRing(cx: pad + ring/2, cy: cy, used: sess)
drawRing(cx: pad + ring + gap + ring/2, cy: cy, used: week)

NSGraphicsContext.current = nil
guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
rep.size = NSSize(width: W, height: logicalH)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try png.write(to: URL(fileURLWithPath: outPath)) } catch { exit(1) }
