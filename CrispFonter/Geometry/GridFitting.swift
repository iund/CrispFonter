import Foundation

/// Port of the prototype's `buildMap` / `stemAnchors` / `fitOutline`. Build spec §6.
enum GridFitting {

    struct Anchor { var src: Double; var dst: Double }

    /// A monotone piecewise-linear map built from {src, dst} anchors, sorted by src, dropping any
    /// anchor that would break monotonicity. Values outside the anchors shift by the nearest anchor's delta.
    static func buildMap(_ anchors: [Anchor]) -> (Double) -> Double {
        let sorted = anchors.sorted { $0.src < $1.src }
        var clean: [Anchor] = []
        for a in sorted {
            if clean.isEmpty || (a.src > clean[clean.count - 1].src + 1e-6 && a.dst >= clean[clean.count - 1].dst) {
                clean.append(a)
            }
        }
        guard !clean.isEmpty else { return { $0 } }
        return { v in
            if v <= clean[0].src { return v + (clean[0].dst - clean[0].src) }
            let last = clean[clean.count - 1]
            if v >= last.src { return v + (last.dst - last.src) }
            for i in 0..<(clean.count - 1) {
                let a = clean[i], b = clean[i + 1]
                if v >= a.src && v <= b.src {
                    return a.dst + (b.dst - a.dst) * ((v - a.src) / (b.src - a.src))
                }
            }
            return v
        }
    }

    static func stemAnchors(_ stems: [Hinting.Stem], s: Double, zoneAnchors: [Anchor]?, darkenAmount: Double = 0) -> [Anchor] {
        var anchors: [Anchor] = []
        for st in stems {
            let lo = st.lo * s, hi = st.hi * s
            // Same flat, un-tapered stem-darkening bump as `CVTBuilder.darkenedWidth` — only for a
            // stem that's 3 grid-units wide or thinner, in the same grid-unit terms (converted to
            // pixels here since everything else in this function already is).
            let gridWidth = st.hi - st.lo
            let bump = gridWidth <= 3 ? darkenAmount * s : 0
            let w = max(1, (hi - lo + bump).rounded())
            func near(_ v: Double) -> Anchor? { zoneAnchors?.first { abs($0.src - v) < 0.6 * s } }
            let zl = near(lo), zh = near(hi)
            var loP: Double, hiP: Double
            if st.mode == .positive { hiP = Hinting.snapPx(hi, .positive); loP = hiP - w }
            else if st.mode == .negative { loP = Hinting.snapPx(lo, .negative); hiP = loP + w }
            else if st.mode == .outward {
                // Both edges round away from the stem's own center — floor the low edge, ceil the
                // high one — so the stem only ever grows, never rounds itself down to nothing at
                // small sizes. Unlike the other modes, the width isn't pinned to `w`: outward can
                // (and often will) end up a pixel wider than plain nearest-rounding would.
                loP = Hinting.snapPx(lo, .negative)
                hiP = Hinting.snapPx(hi, .positive)
            }
            else if let zl { loP = zl.dst; hiP = loP + w }
            else if let zh { hiP = zh.dst; loP = hiP - w }
            else { loP = lo.rounded(); hiP = loP + w }
            anchors.append(Anchor(src: lo, dst: loP))
            anchors.append(Anchor(src: hi, dst: hiP))
        }
        return anchors
    }

    struct Fit { var contours: [[GridPoint]]; var advance: Double }

    /// Scale the outline to pixels and grid-fit it per the renderer model's hinting flags — also
    /// reflecting whichever of `ExportOptions`' hinting toggles apply to a live preview (all but
    /// `includeHints`/`hintCutoffPPEM`, which are about *whether/when* hinting runs, not what it
    /// does — see each toggle's own doc comment for what "reflecting it" means here).
    static func fitOutline(glyph: Glyph, project: FontProject, ppem: Double, hintX: Bool, hintY: Bool) -> Fit {
        let s = ppem / Double(project.gridDivisions)
        let bias = project.verticalBias
        let opts = project.export
        var d = Hinting.derivedHints(glyph, weight: project.defaultWeight, diagonalAware: opts.hintDiagonalStems)
        d.h = d.h.map { Hinting.Stem(lo: $0.lo + bias, hi: $0.hi + bias, mode: $0.mode) }
        d.py = d.py.map { Hinting.PointAnchor(at: $0.at + bias, mode: $0.mode) }
        let outline = SkeletonGeometry.outline(of: glyph, weight: project.defaultWeight)
        let contours: [[GridPoint]] = outline.contours.map { c in c.allPoints.map { GridPoint($0.x * s, ($0.y + bias) * s) } }

        var fx: (Double) -> Double = { $0 }
        var fy: (Double) -> Double = { $0 }
        if hintY {
            let za = project.metrics.zones.map { Anchor(src: $0 * s, dst: ($0 * s).rounded()) }
            var anchors = za
            anchors += stemAnchors(d.h, s: s, zoneAnchors: za, darkenAmount: opts.stemDarkenAmount)
            // Overshoot suppression: a lone point anchor within tolerance of a zone snaps flush to
            // it (same target the zone itself maps to) instead of just nearest-rounding in place.
            let overshootTolerance = opts.suppressOvershoot ? 0.3 : 0.05
            anchors += d.py.map { pa in
                // Compares the (already bias-shifted) point anchor straight against the zones'
                // own un-shifted values, same convention `stemAnchors`'s `near()` and the export
                // compiler's `zoneCVTIndex` both already use.
                if let z = project.metrics.zones.first(where: { abs($0 - pa.at) < overshootTolerance }) {
                    return Anchor(src: pa.at * s, dst: (z * s).rounded())
                }
                return Anchor(src: pa.at * s, dst: Hinting.snapPx(pa.at * s, pa.mode))
            }
            fy = buildMap(anchors)
        }
        if hintX {
            var anchors = stemAnchors(d.v, s: s, zoneAnchors: nil, darkenAmount: opts.stemDarkenAmount)
            anchors += d.px.map { Anchor(src: $0.at * s, dst: Hinting.snapPx($0.at * s, $0.mode)) }
            if opts.hintSideBearings, let minX = outline.contours.flatMap({ $0.allPoints }).map({ $0.x }).min() {
                anchors.append(Anchor(src: minX * s, dst: (minX * s).rounded()))
            }
            fx = buildMap(anchors)
        }
        let fitted = contours.map { c in c.map { GridPoint(fx($0.x), fy($0.y)) } }
        return Fit(contours: fitted, advance: Double(project.advance(of: glyph)) * s)
    }
}
