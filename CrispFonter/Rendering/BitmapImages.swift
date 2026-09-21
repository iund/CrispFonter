import CoreGraphics
import AppKit
import SwiftUI

/// Turns a `GlyphBitmap` into on-screen images, mirroring the prototype's `bitmapCanvas` / `zoomCanvas`.
enum BitmapImages {
    /// Background/foreground to blend coverage against, so previews honor the app's current
    /// light/dark appearance instead of always compositing onto white.
    struct Theme { var bg: (UInt8, UInt8, UInt8); var fg: (UInt8, UInt8, UInt8)
        static let light = Theme(bg: (255, 255, 255), fg: (0, 0, 0))
        static let dark = Theme(bg: (30, 30, 30), fg: (235, 235, 235))
        static func of(_ dark: Bool) -> Theme { dark ? .dark : .light }
        var swiftUIColor: Color { Color(red: Double(bg.0) / 255, green: Double(bg.1) / 255, blue: Double(bg.2) / 255) }
        var nsColor: NSColor { NSColor(srgbRed: CGFloat(bg.0) / 255, green: CGFloat(bg.1) / 255, blue: CGFloat(bg.2) / 255, alpha: 1) }
        var nsForegroundColor: NSColor { NSColor(srgbRed: CGFloat(fg.0) / 255, green: CGFloat(fg.1) / 255, blue: CGFloat(fg.2) / 255, alpha: 1) }
    }

    private static func blend(_ t: Int, _ theme: Theme) -> (UInt8, UInt8, UInt8, UInt8) {
        (mix(theme.bg.0, theme.fg.0, t), mix(theme.bg.1, theme.fg.1, t), mix(theme.bg.2, theme.fg.2, t), 255)
    }
    private static func mix(_ a: UInt8, _ b: UInt8, _ t: Int) -> UInt8 {
        UInt8(clamping: (Int(a) * (255 - t) + Int(b) * t) / 255)
    }

    /// Actual-size image: each channel independently blended from background toward foreground by
    /// its own subpixel coverage — this is what real ClearType-style subpixel rendering actually
    /// looks like (color fringing at edges), as opposed to literal solid R/G/B stripes.
    static func actualSize(_ bmp: GlyphBitmap, theme: Theme = .light) -> CGImage? {
        guard bmp.w > 0, bmp.h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: bmp.w * bmp.h * 4)
        let W3 = bmp.w * 3
        for y in 0..<bmp.h {
            for x in 0..<bmp.w {
                let i = (y * bmp.w + x) * 4
                let tr = Int((255 * bmp.sub[y * W3 + x * 3]).rounded())
                let tg = Int((255 * bmp.sub[y * W3 + x * 3 + 1]).rounded())
                let tb = Int((255 * bmp.sub[y * W3 + x * 3 + 2]).rounded())
                data[i]     = mix(theme.bg.0, theme.fg.0, tr)
                data[i + 1] = mix(theme.bg.1, theme.fg.1, tg)
                data[i + 2] = mix(theme.bg.2, theme.fg.2, tb)
                data[i + 3] = 255
            }
        }
        return makeImage(data, bmp.w, bmp.h)
    }

    /// Zoomed "macro photo" at 3x horizontal (one column per subpixel), rendered in monochrome —
    /// shows the raw subpixel-filtered signal itself rather than how it'd look mapped onto a
    /// physical RGB-striped LCD panel.
    static func zoomed(_ bmp: GlyphBitmap, theme: Theme = .light) -> CGImage? {
        let W3 = bmp.w * 3
        guard W3 > 0, bmp.h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: W3 * bmp.h * 4)
        for y in 0..<bmp.h {
            for x in 0..<W3 {
                let i = (y * W3 + x) * 4
                let t = Int((255 * bmp.sub[y * W3 + x]).rounded())
                let (r, g, b, a) = blend(t, theme)
                data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = a
            }
        }
        return makeImage(data, W3, bmp.h)
    }

    private static func makeImage(_ data: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard w > 0, h > 0 else { return nil }
        var bytes = data
        return bytes.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    static func nsImage(_ cg: CGImage?) -> NSImage? {
        guard let cg else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
