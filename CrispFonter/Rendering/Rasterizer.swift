import Foundation
import CoreGraphics

/// A rasterized glyph bitmap: subpixel (RGB stripe) coverage and grey coverage.
/// Port of the prototype's `rasterize`. Build spec §6.
struct GlyphBitmap {
    var w: Int
    var h: Int
    var base: Int
    /// Per-subpixel coverage, row-major, width = w*3.
    var sub: [Float]
    /// Per-pixel grey coverage, row-major, width = w.
    var cov: [Float]
    var advance: Double
}

enum Rasterizer {
    /// Vertical supersamples per pixel; horizontal supersamples per *subpixel* (so 3*SS per pixel).
    static let SS = 4
    /// FreeType's default LCD filter taps.
    static let FIR: [Float] = [8, 77, 86, 77, 8].map { $0 / 256 }

    static func rasterize(glyph: Glyph, project: FontProject, ppem: Double, renderer: RendererModel, lcdOn: Bool, gasp: Double) -> GlyphBitmap {
        let s = ppem / Double(project.gridDivisions)
        let m = project.metrics
        let fit = GridFitting.fitOutline(glyph: glyph, project: project, ppem: ppem, hintX: renderer.hintsX, hintY: renderer.hintsY)
        let base = Int((Double(m.ascender) * s).rounded()) + 1
        let h = base + Int((-Double(m.descender) * s).rounded(.up)) + 2
        let w = Int((Double(project.advance(of: glyph)) * s).rounded(.up)) + 3

        let W3 = w * 3
        let cw = W3 * SS, ch = h * SS
        guard cw > 0, ch > 0 else {
            return GlyphBitmap(w: w, h: h, base: base, sub: [Float](repeating: 0, count: W3 * h), cov: [Float](repeating: 0, count: w * h), advance: 0)
        }

        var pixels = [UInt8](repeating: 0, count: cw * ch)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw,
                                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.setStrokeColor(gray: 1, alpha: 1)
            let path = CGMutablePath()
            for c in fit.contours {
                guard let first = c.first else { continue }
                let scaleX = Double(3 * SS)
                path.move(to: CGPoint(x: (first.x + 1) * scaleX, y: Double(ch) - (Double(base) * SS.d - first.y * SS.d)))
                for p in c.dropFirst() {
                    path.addLine(to: CGPoint(x: (p.x + 1) * scaleX, y: Double(ch) - (Double(base) * SS.d - p.y * SS.d)))
                }
                path.closeSubpath()
            }
            ctx.addPath(path)
            ctx.fillPath(using: .winding)
            if renderer.dilation > 0 {
                ctx.addPath(path)
                ctx.setLineWidth(renderer.dilation * 2 * Double(SS))
                ctx.setLineJoin(.round)
                ctx.strokePath()
            }
        }

        var raw = [Float](repeating: 0, count: W3 * h)
        pixels.withUnsafeBufferPointer { buf in
            for y in 0..<h {
                for x in 0..<W3 {
                    var sum: Int = 0
                    for yy in 0..<SS {
                        let rowBase = (y * SS + yy) * cw + x * SS
                        for xx in 0..<SS { sum += Int(buf[rowBase + xx]) }
                    }
                    raw[y * W3 + x] = Float(sum) / Float(SS * SS * 255)
                }
            }
        }

        let useLCD = lcdOn && renderer.supportsLCD
        let mono = !lcdOn && renderer.supportsMono && ppem < gasp
        var sub = [Float](repeating: 0, count: W3 * h)
        var cov = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let grey = (raw[y * W3 + x * 3] + raw[y * W3 + x * 3 + 1] + raw[y * W3 + x * 3 + 2]) / 3
                cov[y * w + x] = mono ? (grey >= 0.5 ? 1 : 0) : grey
            }
            for x in 0..<W3 {
                if !useLCD {
                    sub[y * W3 + x] = cov[y * w + x / 3]
                    continue
                }
                var v: Float = 0
                for k in -2...2 {
                    let xx = min(W3 - 1, max(0, x + k))
                    v += raw[y * W3 + xx] * FIR[k + 2]
                }
                sub[y * W3 + x] = v
            }
        }

        let advance = (renderer.hintsX || !renderer.fractionalAdvance) ? fit.advance.rounded() : fit.advance
        return GlyphBitmap(w: w, h: h, base: base, sub: sub, cov: cov, advance: advance)
    }
}

private extension Int { var d: Double { Double(self) } }
