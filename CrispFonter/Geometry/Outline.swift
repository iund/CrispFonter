import Foundation
import CoreGraphics

/// One closed contour made of lines and cubic Béziers, in grid units.
struct Contour: Equatable {
    enum Segment: Equatable {
        case line(GridPoint)
        case cubic(GridPoint, GridPoint, GridPoint)
        case quad(GridPoint, GridPoint)

        var end: GridPoint {
            switch self {
            case .line(let p): p
            case .cubic(_, _, let p): p
            case .quad(_, let p): p
            }
        }
    }

    var start: GridPoint
    var segments: [Segment]

    /// Every coordinate that participates in the contour (on- and off-curve).
    var allPoints: [GridPoint] {
        var pts = [start]
        for s in segments {
            switch s {
            case .line(let p): pts.append(p)
            case .cubic(let a, let b, let p): pts += [a, b, p]
            case .quad(let c, let p): pts += [c, p]
            }
        }
        return pts
    }

    /// Signed area of the control polygon; positive = counter-clockwise (y up).
    var signedArea: Double {
        let pts = allPoints
        guard pts.count > 2 else { return 0 }
        var a = 0.0
        for i in 0..<pts.count {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    var isClockwise: Bool { signedArea < 0 }

    func reversed() -> Contour {
        var rev = Contour(start: segments.last?.end ?? start, segments: [])
        // ends[i] is the start point of segment i.
        var ends: [GridPoint] = [start]
        for s in segments { ends.append(s.end) }
        for (i, s) in segments.enumerated().reversed() {
            let from = ends[i]
            switch s {
            case .line: rev.segments.append(.line(from))
            case .cubic(let a, let b, _): rev.segments.append(.cubic(b, a, from))
            case .quad(let c, _): rev.segments.append(.quad(c, from))
            }
        }
        return rev
    }

    /// Apply a point transform to every coordinate.
    func mapPoints(_ f: (GridPoint) -> GridPoint) -> Contour {
        Contour(start: f(start), segments: segments.map { s in
            switch s {
            case .line(let p): .line(f(p))
            case .cubic(let a, let b, let p): .cubic(f(a), f(b), f(p))
            case .quad(let c, let p): .quad(f(c), f(p))
            }
        })
    }

    func cgPath(transform: (GridPoint) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: transform(start))
        for s in segments {
            switch s {
            case .line(let p): path.addLine(to: transform(p))
            case .cubic(let a, let b, let p): path.addCurve(to: transform(p), control1: transform(a), control2: transform(b))
            case .quad(let c, let p): path.addQuadCurve(to: transform(p), control: transform(c))
            }
        }
        path.closeSubpath()
        return path
    }
}

/// The filled shape of a glyph: a set of closed contours in grid units.
struct Outline: Equatable {
    var contours: [Contour] = []

    var isEmpty: Bool { contours.isEmpty }

    var allPoints: [GridPoint] { contours.flatMap(\.allPoints) }

    var bounds: (min: GridPoint, max: GridPoint)? {
        let pts = allPoints
        guard let first = pts.first else { return nil }
        var lo = first, hi = first
        for p in pts {
            lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y)
            hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
        }
        return (lo, hi)
    }

    func mapPoints(_ f: (GridPoint) -> GridPoint) -> Outline {
        Outline(contours: contours.map { $0.mapPoints(f) })
    }

    func cgPath(transform: (GridPoint) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        for c in contours { path.addPath(c.cgPath(transform: transform)) }
        return path
    }
}
