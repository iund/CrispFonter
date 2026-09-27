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
        let bias = project.verticalBias

        var contours: [[(Int, Int)]] = []
        var pointForNode: NodePointIndex = [:]
        var globalIndex = 0
        for (ci, contour) in outline.contours.enumerated() {
            var allPoints = contour.allPoints
            var contourTags = tags[ci]
            if project.export.simplifyPaths {
                let protectedIndices = Set(contourTags.indices.filter { contourTags[$0] != nil })
                let (simplified, kept) = PathSimplify.simplify(allPoints, protected: protectedIndices, tolerance: 0.01)
                allPoints = simplified
                contourTags = kept.map { contourTags[$0] }
            }
            var pts: [(Int, Int)] = []
            for (pi, point) in allPoints.enumerated() {
                pts.append((Int((point.x * upc).rounded()), Int(((point.y + bias) * upc).rounded())))
                if let tag = contourTags[pi] {
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
