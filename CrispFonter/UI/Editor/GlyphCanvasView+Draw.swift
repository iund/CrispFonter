import AppKit

enum EditorTheme {
    static let dot = NSColor.tertiaryLabelColor
    static let guide = NSColor.systemBlue.withAlphaComponent(0.75)
    static let guideStrong = NSColor.systemBlue
    static let skeleton = NSColor.systemPurple
    static let skeletonFill = NSColor.systemPurple.withAlphaComponent(0.18)
    static let handle = NSColor.systemTeal
    static let thick = NSColor.systemOrange
    static let thickBg = NSColor.systemOrange.withAlphaComponent(0.14)
    static let pixelGrid = NSColor.systemOrange.withAlphaComponent(0.3)
    static let lineHeightOutside = NSColor.systemBlue.withAlphaComponent(0.12)
    static let metricSelected = NSColor.systemBlue
}

extension GlyphCanvasView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, doc != nil else { return }
        NSColor.controlBackgroundColor.setFill(); dirtyRect.fill()
        updateTransform()
        drawDots(ctx)
        if editor.mode == .metrics { drawLineHeightFill(ctx) }
        if editor.showPix { drawPixelGrid(ctx) }
        drawGuides(ctx)
        if editor.mode == .metrics { drawMetricHandles(ctx) }
        if editor.mode == .hint { drawDerivedStems(ctx) }
        if editor.showFill { drawFill(ctx) }
        if editor.showSkel { drawSkeletonAndModeOverlays(ctx) }
    }

    /// Metrics mode: shade the space outside this glyph's own line box translucent blue. A line's
    /// box runs from the ascender down `lineHeight` grid units — i.e. the first baseline sits
    /// `ascender` below the box's top, matching how the text preview lays out successive lines.
    private func drawLineHeightFill(_ ctx: CGContext) {
        let m = doc.project.metrics
        let top = toPx(GridPoint(0, Double(m.ascender)), biased: false).y
        let bottom = toPx(GridPoint(0, Double(m.ascender - m.lineHeight)), biased: false).y
        ctx.setFillColor(EditorTheme.lineHeightOutside.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: top))
        ctx.fill(CGRect(x: 0, y: bottom, width: bounds.width, height: bounds.height - bottom))
    }

    /// A small draggable diamond on each adjustable guide, highlighted when selected for keyboard
    /// adjustment (tab/⇧tab cycles them, ↑/↓/←/→ adjusts).
    private func drawMetricHandles(_ ctx: CGContext) {
        let m = doc.project.metrics
        let horizontals: [(MetricsGuide, Int)] = [(.ascender, m.ascender), (.capHeight, m.capHeight), (.xHeight, m.xHeight), (.descender, m.descender)]
        for (g, v) in horizontals {
            let p = toPx(GridPoint(0, Double(v)), biased: false)
            drawDiamond(ctx, at: CGPoint(x: 24, y: p.y), selected: g == selectedMetric)
        }
        let advX = toPx(GridPoint(Double(doc.project.advance(of: glyph)), 0), biased: false).x
        drawDiamond(ctx, at: CGPoint(x: advX, y: 24), selected: selectedMetric == .advance)
    }

    private func drawDiamond(_ ctx: CGContext, at p: CGPoint, selected: Bool) {
        let r: CGFloat = selected ? 7 : 5
        ctx.setFillColor((selected ? EditorTheme.metricSelected : EditorTheme.guide).cgColor)
        ctx.move(to: CGPoint(x: p.x, y: p.y - r)); ctx.addLine(to: CGPoint(x: p.x + r, y: p.y))
        ctx.addLine(to: CGPoint(x: p.x, y: p.y + r)); ctx.addLine(to: CGPoint(x: p.x - r, y: p.y))
        ctx.closePath(); ctx.fillPath()
    }

    private func drawDots(_ ctx: CGContext) {
        let g0 = toGrid(CGPoint(x: 0, y: 0), biased: false), g1 = toGrid(CGPoint(x: bounds.width, y: bounds.height), biased: false)
        let x0 = Int(floor(min(g0.x, g1.x))), x1 = Int(ceil(max(g0.x, g1.x)))
        let y0 = Int(floor(min(g0.y, g1.y))), y1 = Int(ceil(max(g0.y, g1.y)))
        ctx.setFillColor(EditorTheme.dot.cgColor)
        for x in x0...max(x0, x1) {
            for y in y0...max(y0, y1) {
                let p = toPx(GridPoint(Double(x), Double(y)), biased: false)
                let r: CGFloat = (x % 4 == 0 && y % 4 == 0) ? 1.8 : 1.1
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    private func drawPixelGrid(_ ctx: CGContext) {
        let pxCell = CGFloat(doc.project.gridDivisions) / CGFloat(editor.pixPpem) * cell
        guard pxCell > 0.5 else { return }
        ctx.setStrokeColor(EditorTheme.pixelGrid.cgColor); ctx.setLineWidth(1)
        var x = originX
        while x < bounds.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); x += pxCell }
        x = originX - pxCell
        while x > 0 { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); x -= pxCell }
        var y = originY
        while y < bounds.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)); y += pxCell }
        y = originY - pxCell
        while y > 0 { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)); y -= pxCell }
        ctx.strokePath()
    }

    private func drawGuides(_ ctx: CGContext) {
        let m = doc.project.metrics
        let guides: [(String, Int, Bool)] = [("ascender", m.ascender, false), ("cap height", m.capHeight, true), ("x-height", m.xHeight, false), ("baseline", 0, false), ("descender", m.descender, false)]
        for (name, gy, dashed) in guides {
            let y = toPx(GridPoint(0, Double(gy)), biased: false).y
            ctx.setStrokeColor((gy == 0 ? EditorTheme.guideStrong : EditorTheme.guide).cgColor)
            ctx.setLineWidth(gy == 0 ? 1.5 : 1)
            ctx.setLineDash(phase: 0, lengths: dashed ? [4, 4] : [])
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)); ctx.strokePath()
            drawLabel(name, at: CGPoint(x: 6, y: y - 12), color: EditorTheme.guide)
        }
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(EditorTheme.guide.cgColor); ctx.setLineWidth(1)
        for gx in [0, doc.project.advance(of: glyph)] {
            let x = toPx(GridPoint(Double(gx), 0)).x
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); ctx.strokePath()
        }
        let title = "\(glyphTitle())  ·  advance \(doc.project.advance(of: glyph))"
        drawLabel(title, at: CGPoint(x: toPx(GridPoint(Double(doc.project.advance(of: glyph)), 0)).x + 8, y: 8), color: .tertiaryLabelColor)
    }

    private func glyphTitle() -> String {
        let s = editor.currentScalar
        if s == Glyph.notdefScalar { return ".notdef" }
        if s == 0x20 { return "space  U+0020" }
        let ch = String(UnicodeScalar(s) ?? " ")
        return "\(ch)  U+\(String(format: "%04X", s))"
    }

    private func drawLabel(_ text: String, at p: CGPoint, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: color]
        text.draw(at: p, withAttributes: attrs)
    }

    private func drawDerivedStems(_ ctx: CGContext) {
        let d = Hinting.derivedHints(glyph, weight: weight)
        ctx.setLineDash(phase: 0, lengths: [5, 3]); ctx.setLineWidth(1)
        for st in d.v {
            let x0 = toPx(GridPoint(st.lo, 0)).x, x1 = toPx(GridPoint(st.hi, 0)).x
            ctx.setFillColor(EditorTheme.thickBg.cgColor); ctx.fill(CGRect(x: x0, y: 0, width: x1 - x0, height: bounds.height))
            ctx.setStrokeColor(EditorTheme.thick.cgColor)
            ctx.move(to: CGPoint(x: x0, y: 0)); ctx.addLine(to: CGPoint(x: x0, y: bounds.height))
            ctx.move(to: CGPoint(x: x1, y: 0)); ctx.addLine(to: CGPoint(x: x1, y: bounds.height))
            ctx.strokePath()
        }
        for st in d.h {
            let y0 = toPx(GridPoint(0, st.hi)).y, y1 = toPx(GridPoint(0, st.lo)).y
            ctx.setFillColor(EditorTheme.thickBg.cgColor); ctx.fill(CGRect(x: 0, y: y0, width: bounds.width, height: y1 - y0))
            ctx.setStrokeColor(EditorTheme.thick.cgColor)
            ctx.move(to: CGPoint(x: 0, y: y0)); ctx.addLine(to: CGPoint(x: bounds.width, y: y0))
            ctx.move(to: CGPoint(x: 0, y: y1)); ctx.addLine(to: CGPoint(x: bounds.width, y: y1))
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawFill(_ ctx: CGContext) {
        ctx.setFillColor(EditorTheme.skeletonFill.cgColor)
        let path = CGMutablePath()
        for c in SkeletonGeometry.outline(of: glyph, weight: weight).contours {
            let pts = c.allPoints
            guard let first = pts.first else { continue }
            path.move(to: toPx(first))
            for p in pts.dropFirst() { path.addLine(to: toPx(p)) }
            path.closeSubpath()
        }
        ctx.addPath(path); ctx.fillPath(using: .winding)
    }
}
