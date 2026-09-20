import Foundation

/// One glyph, ready for `glyf`: font-unit contour points plus its compiled hint program. Ties
/// together `SkeletonGeometry`'s tagged outline, `Hinting`'s derived stems and `GlyphHintProgram`.
struct HintedGlyph {
    var contours: [[(x: Int, y: Int)]] // font units, in glyf point order
    var instructions: Data
}

enum HintedGlyphBuilder {
    static func build(glyph: Glyph, project: FontProject, cvt: CVTTable) -> HintedGlyph {
        let (outline, tags) = SkeletonGeometry.outlineWithTags(of: glyph, weight: project.defaultWeight)
        let upc = project.unitsPerCell

        var contours: [[(Int, Int)]] = []
        var pointForNode: NodePointIndex = [:]
        var globalIndex = 0
        for (ci, contour) in outline.contours.enumerated() {
            var pts: [(Int, Int)] = []
            for (pi, point) in contour.allPoints.enumerated() {
                pts.append((Int((point.x * upc).rounded()), Int((point.y * upc).rounded())))
                if let tag = tags[ci][pi] {
                    var entry = pointForNode[tag.nodeID] ?? (nil, nil)
                    if tag.side == .left { entry.left = globalIndex } else { entry.right = globalIndex }
                    pointForNode[tag.nodeID] = entry
                }
                globalIndex += 1
            }
            contours.append(pts)
        }

        let instructions = project.export.includeHints
            ? GlyphHintProgram.compile(glyph: glyph, project: project, cvt: cvt, pointForNode: pointForNode)
            : Data()
        return HintedGlyph(contours: contours, instructions: instructions)
    }
}
