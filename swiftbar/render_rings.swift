import AppKit

// Compact twin-ring gauge for the SwiftBar menu bar item, with the session
// reset countdown drawn LEFT of the rings and the week countdown RIGHT.
// args: sessUsed weekUsed sessLeft weekLeft outPath [stale]
//   sessUsed/weekUsed : 0-100 percentages USED
//   sessLeft/weekLeft : preformatted short countdowns ("2h", "45m", "6d")
//
// WIDTH BUDGET: on notched MacBooks macOS hides the leftmost status item
// when the bar tightens; an 89pt item got evicted, a 60pt one survived.
// This layout must stay ~<=70pt total. Keep fonts/rings small.
let a = CommandLine.arguments
guard a.count >= 6, let sess = Int(a[1]), let week = Int(a[2]) else {
    FileHandle.standardError.write("usage: render_rings <sessUsed> <weekUsed> <sessLeft> <weekLeft> <out.png> [stale]\n".data(using: .utf8)!)
    exit(1)
}
let sessLeft = a[3]
let weekLeft = a[4]
let outPath = a[5]
let stale = a.count >= 7 && a[6] == "stale"

let scale: CGFloat = 2.0
let logicalH: CGFloat = 22  // NSStatusBar.system.thickness — the OS ceiling
let ring: CGFloat = 18     // ring diameter (pt); 18 + stroke ≈ 21.5 of the 22
let lineW: CGFloat = 3.0
let gap: CGFloat = 3       // between the two rings
let textGap: CGFloat = 1.5 // between a countdown and its ring
let pad: CGFloat = 1

let grey = NSColor(srgbRed: 0x8A/255, green: 0x93/255, blue: 0xA0/255, alpha: 1)
func colorFor(_ used: Int) -> NSColor {
    if stale { return grey }
    if used >= 85 { return NSColor(srgbRed: 0xC4/255, green: 0x52/255, blue: 0x4F/255, alpha: 1) }      // red
    if used >= 60 { return NSColor(srgbRed: 0xD6/255, green: 0xC4/255, blue: 0x86/255, alpha: 1) }      // sand
    return NSColor(srgbRed: 0x8F/255, green: 0xBA/255, blue: 0xA0/255, alpha: 1)                        // sage
}

let sideFont = NSFont.monospacedSystemFont(ofSize: 7, weight: .semibold)
func sideAttrs(_ used: Int) -> [NSAttributedString.Key: Any] {
    [.font: sideFont, .foregroundColor: stale ? grey : colorFor(used)]
}
let sessStr = NSAttributedString(string: sessLeft, attributes: sideAttrs(sess))
let weekStr = NSAttributedString(string: weekLeft, attributes: sideAttrs(week))
let sessW = ceil(sessStr.size().width)
let weekW = ceil(weekStr.size().width)

let W = pad + sessW + textGap + ring + gap + ring + textGap + weekW + pad

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
    let fsize: CGFloat = s.count >= 3 ? 6.5 : 8.5
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: fsize, weight: .semibold),
        .foregroundColor: colorFor(clamped)
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: cx - sz.width/2, y: cy - sz.height/2))
}

func drawSide(_ str: NSAttributedString, x: CGFloat, cy: CGFloat) {
    let sz = str.size()
    str.draw(at: NSPoint(x: x, y: cy - sz.height/2))
}

let cy = logicalH/2
drawSide(sessStr, x: pad, cy: cy)
drawRing(cx: pad + sessW + textGap + ring/2, cy: cy, used: sess)
drawRing(cx: pad + sessW + textGap + ring + gap + ring/2, cy: cy, used: week)
drawSide(weekStr, x: pad + sessW + textGap + ring + gap + ring + textGap, cy: cy)

NSGraphicsContext.current = nil
guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
rep.size = NSSize(width: W, height: logicalH)   // point size -> Retina @2x
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try png.write(to: URL(fileURLWithPath: outPath)) } catch { exit(1) }
