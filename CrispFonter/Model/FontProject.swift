import Foundation

/// A point in grid units. The grid is `gridDivisions` cells per em; nodes usually
/// sit on whole, half or quarter grid coordinates.
struct GridPoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    static let zero = GridPoint(0, 0)

    static func + (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x + b.x, a.y + b.y) }
    static func - (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x - b.x, a.y - b.y) }
    static func * (a: GridPoint, s: Double) -> GridPoint { GridPoint(a.x * s, a.y * s) }
    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: GridPoint { let l = length; return l > 0 ? GridPoint(x / l, y / l) : GridPoint(0, 0) }
    /// Left-hand normal (rotate 90° counter-clockwise, y up).
    var leftNormal: GridPoint { GridPoint(-y, x) }
    func rotated(degrees: Double) -> GridPoint {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return GridPoint(x * c - y * s, x * s + y * c)
    }
    func distance(to p: GridPoint) -> Double { (self - p).length }
    func dot(_ p: GridPoint) -> Double { x * p.x + y * p.y }
    func cross(_ p: GridPoint) -> Double { x * p.y - y * p.x }
}

/// Font-wide vertical metrics, in grid units, relative to the baseline (0).
struct Metrics: Codable, Equatable {
    var ascender: Int = 12
    var capHeight: Int = 11
    var xHeight: Int = 8
    var descender: Int = -4
    var lineHeight: Int = 19
    /// Default advance width for every glyph (monospaced by default).
    var defaultAdvance: Int = 9

    /// Alignment zones (guides) used for hinting, in grid units.
    var zones: [Double] { [Double(descender), 0, Double(xHeight), Double(capHeight), Double(ascender)] }
}

enum NodeKind: String, Codable {
    case corner, smooth
}

/// One skeleton node. Curve handles are absolute grid positions.
struct Node: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var p: GridPoint
    var kind: NodeKind = .corner
    /// Handle controlling the curve arriving at this node (from the previous node).
    var cIn: GridPoint?
    /// Handle controlling the curve leaving this node (to the next node).
    var cOut: GridPoint?
    /// Thickness on the left of the travel direction as a ratio of the default half-weight.
    /// nil = 1. 0 pins the edge to the skeleton line and stays 0 whatever the weight.
    var left: Double?
    /// Same for the right side.
    var right: Double?
    /// Rotation of the stroke cross-section at this node, degrees (angled terminals). Blends out along neighbouring segments.
    var angle: Double = 0
    /// For the first/last node of an open path: how far the cap bulges beyond the node, grid units. 0 = flat.
    var cap: Double = 0

    init(_ p: GridPoint, kind: NodeKind = .corner, cIn: GridPoint? = nil, cOut: GridPoint? = nil) {
        self.p = p; self.kind = kind; self.cIn = cIn; self.cOut = cOut
    }
}

struct SkeletonPath: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var nodes: [Node] = []
    var closed: Bool = false

    /// Segment i runs from nodes[i] to nodes[i+1] (wrapping when closed).
    var segmentCount: Int { closed ? nodes.count : max(0, nodes.count - 1) }
}

/// How a hinted edge is snapped on one axis.
enum SnapMode: String, Codable {
    /// Nearest pixel boundary (round to grid).
    case nearest
    /// Push the low edge down/left to the previous pixel boundary (floor).
    case negative
    /// Push the high edge up/right to the next pixel boundary (ceil).
    case positive
}

/// A hint attached to a skeleton node: which axes snap and how.
struct HintPoint: Codable, Hashable {
    var x: SnapMode?
    var y: SnapMode?
    var isEmpty: Bool { x == nil && y == nil }
}

struct Glyph: Codable, Hashable, Identifiable {
    var id: UInt32 { scalar }
    /// Unicode scalar value; `Glyph.notdefScalar` (0) is the .notdef glyph.
    var scalar: UInt32
    /// Advance width override in grid units; nil = font default.
    var advance: Int?
    var paths: [SkeletonPath] = []
    /// Hints keyed by node id.
    var hints: [UUID: HintPoint] = [:]
    /// User-marked "done" (double-click in the glyph list).
    var complete: Bool = false

    static let notdefScalar: UInt32 = 0

    var isDrawn: Bool { paths.contains { $0.nodes.count >= 2 } }
    var label: String {
        if scalar == Glyph.notdefScalar { return "▯" }
        if scalar == 0x20 { return "␣" }
        return String(Character(Unicode.Scalar(scalar) ?? "?"))
    }
}

/// The rasteriser models shown in the preview strip.
enum RendererModel: String, Codable, CaseIterable, Identifiable {
    case freetype, chrome, macos
    var id: String { rawValue }
    var label: String {
        switch self {
        case .freetype: "FreeType v35 (≈ Windows GDI)"
        case .chrome: "Chrome on Windows (DirectWrite)"
        case .macos: "macOS (CoreText)"
        }
    }
    /// Snap x edges (full hinting).
    var hintsX: Bool { self == .freetype }
    /// Snap y edges.
    var hintsY: Bool { self != .macos }
    /// Subpixel (RGB) anti-aliasing when the LCD option is on.
    var supportsLCD: Bool { self != .macos }
    /// 1-bit below the gasp threshold (greyscale mode only).
    var supportsMono: Bool { self == .freetype }
    /// Outline dilation in pixels (CoreText stem darkening approximation).
    var dilation: Double { self == .macos ? 0.22 : 0 }
    /// Fractional advance widths.
    var fractionalAdvance: Bool { self != .freetype }
}

struct ExportOptions: Codable, Equatable {
    var includeHints = true
    /// Below this ppem the gasp table asks for grid-fitting without anti-aliasing.
    var gaspMonoThreshold = 12
    /// Above this ppem the prep program switches instructions off.
    var hintCutoffPPEM = 48
    var familyName = "Crisp Mono"
    var styleName = "Regular"
}

struct FontProject: Codable, Equatable {
    var unitsPerEm: Int = 1000
    /// Grid cells per em.
    var gridDivisions: Int = 16
    var metrics = Metrics()
    /// Default stroke thickness (whole stroke, both sides) in grid units.
    var defaultWeight: Double = 1.5
    var glyphs: [UInt32: Glyph] = [:]
    var referenceFontName: String = "Menlo"
    var previewText: String = FontProject.samplePreviewText
    /// Text preview size in points, 6–18 in 0.5 steps.
    var previewSize: Double = 12
    var previewRenderer: RendererModel = .freetype
    /// Show subpixel (RGB stripe) rendering in the strip and preview.
    var previewLCD: Bool = true
    /// Pixel-grid overlay size in the editor, points.
    var pixelGridSize: Double = 11
    /// Sizes shown in the renderer strip.
    var previewSizes: [Double] = [9, 11, 13, 16]
    var export = ExportOptions()

    /// Font units per grid cell.
    var unitsPerCell: Double { Double(unitsPerEm) / Double(gridDivisions) }

    /// Glyph list order: .notdef, space, a–z, A–Z, 0–9, punctuation.
    static let glyphOrder: [UInt32] = {
        var s: [UInt32] = [Glyph.notdefScalar, 0x20]
        s += (0x61...0x7A).map { UInt32($0) }        // a-z
        s += (0x41...0x5A).map { UInt32($0) }        // A-Z
        s += (0x30...0x39).map { UInt32($0) }        // 0-9
        for c in Array("{}[]()<>=;:,.+-*/\\|&!?'\"@#$%^_~`".unicodeScalars) { s.append(c.value) }
        return s
    }()

    static let samplePreviewText = """
    let area = radius * radius * 3.14159
    var name = "banana"; // aaa
    func add(a: Int, b: Int) -> Int { a + b }
    Ada and Alan ate apples at Aarhus. 0O 1lI| {}[]()
    """

    func glyph(for scalar: UInt32) -> Glyph { glyphs[scalar] ?? Glyph(scalar: scalar) }

    func advance(of glyph: Glyph) -> Int { glyph.advance ?? metrics.defaultAdvance }

    static func newDocument() -> FontProject { FontProject() }
}
