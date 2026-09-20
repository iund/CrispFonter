import Foundation

/// Caches rasterized bitmaps by (glyph revision, weight, ppem, renderer, lcd), as the spec asks.
final class GlyphBitmapCache {
    private struct Key: Hashable {
        var revision: Int
        var scalar: UInt32
        var weight: Double
        var ppem: Double
        var renderer: RendererModel
        var lcd: Bool
        var gasp: Double
    }
    private var store: [Key: GlyphBitmap] = [:]

    func bitmap(glyph: Glyph, project: FontProject, revision: Int, ppem: Double, renderer: RendererModel, lcdOn: Bool) -> GlyphBitmap {
        let key = Key(revision: revision, scalar: glyph.scalar, weight: project.defaultWeight, ppem: ppem, renderer: renderer, lcd: lcdOn, gasp: Double(project.export.gaspMonoThreshold))
        if let hit = store[key] { return hit }
        let bmp = Rasterizer.rasterize(glyph: glyph, project: project, ppem: ppem, renderer: renderer, lcdOn: lcdOn, gasp: Double(project.export.gaspMonoThreshold))
        store[key] = bmp
        return bmp
    }

    func clear() { store.removeAll() }
}
