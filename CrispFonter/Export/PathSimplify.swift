import Foundation

/// Douglas-Peucker simplification for exported outlines — see `ExportOptions.simplifyPaths`.
/// `SkeletonGeometry` flattens every curve to a dense polyline (24 samples per segment), which is
/// fine for the live fill preview but bloats `glyf` and shows up as slightly jagged, over-detailed
/// joins on a non-straight open-stroke end cap. This thins the redundant interior points back out.
enum PathSimplify {
    /// Simplifies a closed polygon's points, treating every index in `protected` as an immovable
    /// breakpoint — those are the ones a compiled hint instruction may reference by index, so they
    /// can never be removed or renumbered out from under it. Points are only ever thinned *between*
    /// two protected points, never merged across one.
    static func simplify(_ points: [GridPoint], protected: Set<Int>, tolerance: Double) -> (points: [GridPoint], keptIndices: [Int]) {
        let n = points.count
        guard n > 2 else { return (points, Array(points.indices)) }
        let breakpoints = protected.union([0]).sorted()
        var kept = Set(breakpoints)
        for i in 0..<breakpoints.count {
            let start = breakpoints[i]
            let end = breakpoints[(i + 1) % breakpoints.count]
            let segment = end > start ? Array(start...end) : Array(start..<n) + Array(0...end)
            guard segment.count > 2 else { continue }
            thin(points, segment, tolerance, &kept)
        }
        let keptIndices = (0..<n).filter { kept.contains($0) }
        return (keptIndices.map { points[$0] }, keptIndices)
    }

    private static func thin(_ points: [GridPoint], _ segment: [Int], _ tol: Double, _ kept: inout Set<Int>) {
        guard segment.count > 2 else { return }
        let a = points[segment.first!], b = points[segment.last!]
        var maxDist = 0.0, maxAt = -1
        for k in 1..<(segment.count - 1) {
            let d = perpendicularDistance(points[segment[k]], a, b)
            if d > maxDist { maxDist = d; maxAt = k }
        }
        guard maxAt >= 0, maxDist > tol else { return }
        kept.insert(segment[maxAt])
        thin(points, Array(segment[0...maxAt]), tol, &kept)
        thin(points, Array(segment[maxAt...]), tol, &kept)
    }

    private static func perpendicularDistance(_ p: GridPoint, _ a: GridPoint, _ b: GridPoint) -> Double {
        let d = GridPoint(b.x - a.x, b.y - a.y)
        let len2 = d.x * d.x + d.y * d.y
        guard len2 > 1e-12 else { return (p - a).length }
        let t = ((p.x - a.x) * d.x + (p.y - a.y) * d.y) / len2
        let proj = GridPoint(a.x + t * d.x, a.y + t * d.y)
        return (p - proj).length
    }
}
