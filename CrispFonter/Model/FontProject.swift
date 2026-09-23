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

/// Which side of a node's cross-section a thickness handle (or an anchor) refers to.
enum ThicknessSide: String, Codable, Hashable {
    case left, right
}

/// Pins a node's position to another node's thickness edge instead of a fixed coordinate, so it
/// tracks that edge automatically as weight/thickness/rotation change — e.g. anchoring the end of
/// one stroke onto another stroke's already-thickened edge, so they stay joined when the weight
/// slider moves. Resolved by `Glyph.resolvingAnchors(weight:)`.
struct NodeAnchor: Codable, Hashable {
    var targetNodeID: UUID
    var side: ThicknessSide
}

/// One point on a fill-boundary "line" (the outer or inner edge of a stroke), attached to the
/// skeleton node it travels alongside. Every field here is relative to that skeleton node and
/// stored as a ratio of weight/2 — multiplying by the live weight reproduces the actual grid-unit
/// vector — the same convention `left`/`right` already use, so the whole point-and-curve moves
/// together as weight changes instead of the curve handles being left behind (tried storing
/// `cIn`/`cOut` as a fixed, unscaled offset instead — it left them anchored in place while the
/// point moved, visibly distorting the curve, so back to scaling everything together). No
/// rotation: a fill line is just a plain path of its own, positioned and shaped directly rather
/// than derived from an angle.
struct FillHandle: Codable, Hashable {
    var offset: GridPoint
    var cIn: GridPoint?
    var cOut: GridPoint?
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
    /// Thickness on the left of the travel direction as a ratio of the default half-weight —
    /// only used as the seed for `outer`'s position the first time it's touched (or, for a
    /// single-node "dot" path, as its radius). nil = 1. Negative values are allowed — they push
    /// the seed past the skeleton line to the opposite side.
    var left: Double?
    /// Same for the right side, seeding `inner`.
    var right: Double?
    /// If set, `p` is recomputed from another node's fill-boundary point rather than used directly
    /// — see `NodeAnchor`.
    var anchor: NodeAnchor?
    /// The left (outer) fill-boundary point attached to this node — nil until first touched, in
    /// which case it's derived from `left` and the local tangent (see `SkeletonGeometry`).
    var outer: FillHandle?
    /// Same for the right (inner) side, seeded from `right`.
    var inner: FillHandle?

    init(_ p: GridPoint, kind: NodeKind = .corner, cIn: GridPoint? = nil, cOut: GridPoint? = nil) {
        self.p = p; self.kind = kind; self.cIn = cIn; self.cOut = cOut
    }

    func fillHandle(_ side: ThicknessSide) -> FillHandle? { side == .left ? outer : inner }
    mutating func setFillHandle(_ side: ThicknessSide, _ handle: FillHandle?) {
        switch side {
        case .left: outer = handle
        case .right: inner = handle
        }
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
    /// Nearest pixel boundary (round to grid) — can round the stem narrower or wider.
    case nearest
    /// Push the low edge down/left to the previous pixel boundary (floor).
    case negative
    /// Push the high edge up/right to the next pixel boundary (ceil).
    case positive
    /// Both edges of the stem round away from its center (floor the low edge, ceil the high one)
    /// — the stem only ever grows, never disappears to anti-aliasing at small sizes. Set by
    /// holding ⌥ on any of the "nearest"-setting hint actions in place of plain `.nearest`.
    case outward
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
    /// Flags the exported font as fixed-pitch (`post.isFixedPitch` + PANOSE proportion) — some
    /// IDEs only list monospace fonts in their font picker, and check this rather than measuring.
    var monospace = true

    init() {}

    /// Decodes every field with `decodeIfPresent`, defaulting anything missing — a plain
    /// synthesized `Decodable` throws on a key added after a file was saved (a property's default
    /// value only applies to `init()`, not to decoding), which would make opening an
    /// older-schema `.crisp` file fail outright the moment any field here gains a new sibling.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeHints = try c.decodeIfPresent(Bool.self, forKey: .includeHints) ?? true
        gaspMonoThreshold = try c.decodeIfPresent(Int.self, forKey: .gaspMonoThreshold) ?? 12
        hintCutoffPPEM = try c.decodeIfPresent(Int.self, forKey: .hintCutoffPPEM) ?? 48
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName) ?? "Crisp Mono"
        styleName = try c.decodeIfPresent(String.self, forKey: .styleName) ?? "Regular"
        monospace = try c.decodeIfPresent(Bool.self, forKey: .monospace) ?? true
    }
}

struct FontProject: Codable, Equatable {
    var unitsPerEm: Int = 1000
    /// Grid cells per em.
    var gridDivisions: Int = 16
    var metrics = Metrics()
    /// Default stroke thickness (whole stroke, both sides) in grid units.
    var defaultWeight: Double = 1.5
    /// Global vertical nudge applied to every glyph's geometry (grid units), independent of the
    /// metrics zones — lets the whole font be realigned without touching any glyph's own points.
    var verticalBias: Double = 0
    var glyphs: [UInt32: Glyph] = [:]
    var referenceFontName: String = "Menlo"
    var previewText: String = FontProject.samplePreviewText
    /// Text preview size in points, 6–18 in 0.5 steps.
    var previewSize: Double = 12
    var previewRenderer: RendererModel = .freetype
    /// Pixel-grid overlay size in the editor, points.
    var pixelGridSize: Double = 11
    /// Sizes shown in the renderer strip.
    var previewSizes: [Double] = [8, 9, 10, 11, 12, 13, 14]
    var export = ExportOptions()

    init() {}

    /// Same defensive `decodeIfPresent` pattern as `ExportOptions.init(from:)` — this struct has
    /// gained new fields many times over; without this, opening a `.crisp` file saved before the
    /// newest one existed throws instead of just using that field's default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unitsPerEm = try c.decodeIfPresent(Int.self, forKey: .unitsPerEm) ?? 1000
        gridDivisions = try c.decodeIfPresent(Int.self, forKey: .gridDivisions) ?? 16
        metrics = try c.decodeIfPresent(Metrics.self, forKey: .metrics) ?? Metrics()
        defaultWeight = try c.decodeIfPresent(Double.self, forKey: .defaultWeight) ?? 1.5
        verticalBias = try c.decodeIfPresent(Double.self, forKey: .verticalBias) ?? 0
        glyphs = try c.decodeIfPresent([UInt32: Glyph].self, forKey: .glyphs) ?? [:]
        referenceFontName = try c.decodeIfPresent(String.self, forKey: .referenceFontName) ?? "Menlo"
        previewText = try c.decodeIfPresent(String.self, forKey: .previewText) ?? FontProject.samplePreviewText
        previewSize = try c.decodeIfPresent(Double.self, forKey: .previewSize) ?? 12
        previewRenderer = try c.decodeIfPresent(RendererModel.self, forKey: .previewRenderer) ?? .freetype
        pixelGridSize = try c.decodeIfPresent(Double.self, forKey: .pixelGridSize) ?? 11
        previewSizes = try c.decodeIfPresent([Double].self, forKey: .previewSizes) ?? [8, 9, 10, 11, 12, 13, 14]
        export = try c.decodeIfPresent(ExportOptions.self, forKey: .export) ?? ExportOptions()
    }

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
