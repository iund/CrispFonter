import CoreGraphics
import AppKit

/// Turns a `GlyphBitmap` into on-screen images, mirroring the prototype's `bitmapCanvas` / `zoomCanvas`.
enum BitmapImages {

    /// Actual-size image on white: pixel colour = per-channel remaining light (1 - coverage).
    static func actualSize(_ bmp: GlyphBitmap) -> CGImage? {
        guard bmp.w > 0, bmp.h > 0 else { return nil }
        var data = [UInt8](repeating: 255, count: bmp.w * bmp.h * 4)
        let W3 = bmp.w * 3
        for y in 0..<bmp.h {
            for x in 0..<bmp.w {
                let i = (y * bmp.w + x) * 4
                data[i]     = UInt8(clamping: Int((255 * (1 - bmp.sub[y * W3 + x * 3])).rounded()))
                data[i + 1] = UInt8(clamping: Int((255 * (1 - bmp.sub[y * W3 + x * 3 + 1])).rounded()))
                data[i + 2] = UInt8(clamping: Int((255 * (1 - bmp.sub[y * W3 + x * 3 + 2])).rounded()))
                data[i + 3] = 255
            }
        }
        return makeImage(data, bmp.w, bmp.h)
    }

    /// Zoomed "macro photo": each device pixel as three lit RGB stripes (or grey blocks when subpixel is off).
    static func zoomed(_ bmp: GlyphBitmap, lcd: Bool) -> CGImage? {
        let W3 = bmp.w * 3
        guard W3 > 0, bmp.h > 0 else { return nil }
        var data = [UInt8](repeating: 255, count: W3 * bmp.h * 4)
        for y in 0..<bmp.h {
            for x in 0..<W3 {
                let i = (y * W3 + x) * 4
                let light = UInt8(clamping: Int((255 * (1 - bmp.sub[y * W3 + x])).rounded()))
                if lcd {
                    data[i]     = x % 3 == 0 ? light : 0
                    data[i + 1] = x % 3 == 1 ? light : 0
                    data[i + 2] = x % 3 == 2 ? light : 0
                } else {
                    data[i] = light; data[i + 1] = light; data[i + 2] = light
                }
                data[i + 3] = 255
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
