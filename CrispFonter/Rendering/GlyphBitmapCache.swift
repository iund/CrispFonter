import Foundation

/// Caches rasterized bitmaps by (glyph revision, weight, ppem, renderer, lcd), as the spec asks.
/// Locked: it's read from both the main thread (renderer strip) and SwiftUI's async Canvas
/// rendering thread (text preview) — an unsynchronized Dictionary mutation from two threads is a
/// real crash, not a hypothetical one.
final class GlyphBitmapCache {
    private struct Key: Hashable {
        var revision: Int
        var scalar: UInt32
        var weight: Double
        var ppem: Double
        var renderer: RendererModel
        var aa: AAMode
        var gasp: Double
    }
    private var store: [Key: GlyphBitmap] = [:]
    private let lock = NSLock()

    func bitmap(glyph: Glyph, project: FontProject, revision: Int, ppem: Double, renderer: RendererModel, aa: AAMode) -> GlyphBitmap {
        let key = Key(revision: revision, scalar: glyph.scalar, weight: project.defaultWeight, ppem: ppem, renderer: renderer, aa: aa, gasp: Double(project.export.gaspMonoThreshold))
        lock.lock()
        if let hit = store[key] { lock.unlock(); return hit }
        lock.unlock()
        let bmp = Rasterizer.rasterize(glyph: glyph, project: project, ppem: ppem, renderer: renderer, aa: aa, gasp: Double(project.export.gaspMonoThreshold))
        lock.lock()
        store[key] = bmp
        lock.unlock()
        return bmp
    }

    func clear() {
        lock.lock(); store.removeAll(); lock.unlock()
    }
}
