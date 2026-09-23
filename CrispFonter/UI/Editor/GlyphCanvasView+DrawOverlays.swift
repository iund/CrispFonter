import AppKit

extension GlyphCanvasView {
    func drawSkeletonAndModeOverlays(_ ctx: CGContext) {
        // Fn held: hide the skeleton/handles momentarily so the fill alone is visible — including
        // mid-drag, since Fn is a live modifier read on every redraw, not just at mouseDown.
        guard !fnHeld else { return }
        for path in glyph.paths {
            guard !path.nodes.isEmpty else { continue }
            drawSkeletonLine(ctx, path)
            if editor.mode == .combo {
                drawCurveHandles(ctx, path)
                drawThicknessHandles(ctx, path)
                drawFillCurveHandles(ctx, path)
            }
            // Nodes drawn last/on top — a thickness handle can sit exactly on its node (e.g. zero
            // outer thickness), and the node needs to stay visible and grabbable above it.
            for (i, nd) in path.nodes.enumerated() { drawNode(ctx, path, nd, i) }
        }
        if editor.mode == .combo { drawModifierHighlights(ctx) }
        if let pathID = drawingPathID, let hover, editor.mode == .combo, drag == nil,
           let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last {
            ctx.setStrokeColor(EditorTheme.skeleton.withAlphaComponent(0.4).cgColor)
            ctx.setLineDash(phase: 0, lengths: [4, 4]); ctx.setLineWidth(2)
            ctx.move(to: toPx(last.p)); ctx.addLine(to: toPx(hover)); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        let marqueeStart: CGPoint? = {
            if case .marquee(let s, _)? = drag { return s }
            if case .rightClick(let s)? = drag { return s }
            return nil
        }()
        if let start = marqueeStart, let current = marqueeCurrent {
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                               width: abs(current.x - start.x), height: abs(current.y - start.y))
            ctx.setFillColor(EditorTheme.metricSelected.withAlphaComponent(0.1).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(EditorTheme.metricSelected.cgColor); ctx.setLineWidth(1)
            ctx.stroke(rect)
        }
        // With nothing selected and no stroke in progress, arrow keys move `hover` as a phantom
        // cursor rather than the real pointer — draw it explicitly so there's something to see
        // while walking it into position with the keyboard.
        if editor.mode == .combo, drawingPathID == nil, selection == nil, multiSelection.isEmpty, let hover {
            let p = toPx(hover)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(1)
            let r: CGFloat = 4
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.fillEllipse(in: rect)
            ctx.strokeEllipse(in: rect)
        }
    }

    private func drawSkeletonLine(_ ctx: CGContext, _ path: SkeletonPath) {
        let n = path.nodes
        guard n.count >= 1 else { return }
        ctx.setStrokeColor(EditorTheme.skeleton.cgColor); ctx.setLineWidth(2)
        let p0 = toPx(n[0].p)
        ctx.move(to: p0)
        let count = path.closed ? n.count : n.count - 1
        guard count > 0 else { return }
        for i in 0..<count {
            let a = n[i], b = n[(i + 1) % n.count]
            if a.cOut == nil && b.cIn == nil {
                ctx.addLine(to: toPx(b.p))
            } else {
                ctx.addCurve(to: toPx(b.p), control1: toPx(a.cOut ?? a.p), control2: toPx(b.cIn ?? b.p))
            }
        }
        ctx.strokePath()
    }

    private func drawCurveHandles(_ ctx: CGContext, _ path: SkeletonPath) {
        ctx.setStrokeColor(EditorTheme.handle.cgColor); ctx.setFillColor(EditorTheme.handle.cgColor)
        ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [3, 3])
        for nd in path.nodes {
            for c in [nd.cIn, nd.cOut] {
                guard let c else { continue }
                let a = toPx(nd.p), b = toPx(c)
                ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
                ctx.fill(CGRect(x: b.x - 3, y: b.y - 3, width: 6, height: 6))
            }
            // One handle pulled out, the other still resting (invisibly) on the node: ring the
            // node to show there's a handle to grab there — ⌥-drag it out.
            if nd.kind == .smooth, (nd.cIn == nil) != (nd.cOut == nil) {
                let p = toPx(nd.p)
                ctx.strokeEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            }
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    /// A fill point's own `cIn`/`cOut`, drawn the same way a skeleton node's are (dashed line +
    /// small square), just in the fill-handle color so the two don't blur together — shown whether
    /// the point is explicit or still following its skeleton node's own curve handles by default.
    /// Hidden unless the corresponding ⌘ is held (left-⌘ reveals inner, right-⌘ outer, both reveal
    /// both) — otherwise they clutter the canvas on every node, most of which nobody's touching.
    private func drawFillCurveHandles(_ ctx: CGContext, _ path: SkeletonPath) {
        var sides: [Side] = []
        if leftCommandHeld { sides.append(.right) }
        if rightCommandHeld { sides.append(.left) }
        guard !sides.isEmpty else { return }
        ctx.setStrokeColor(EditorTheme.thick.cgColor); ctx.setFillColor(EditorTheme.thick.cgColor)
        ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [3, 3])
        for (i, nd) in path.nodes.enumerated() {
            for side in sides {
                let f = SkeletonGeometry.fillPoint(of: nd, path: path, index: i, side: side, weight: weight)
                for c in [f.cIn, f.cOut] {
                    guard let c else { continue }
                    let a = toPx(f.point), b = toPx(c)
                    ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
                    ctx.fill(CGRect(x: b.x - 3, y: b.y - 3, width: 6, height: 6))
                }
            }
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawNode(_ ctx: CGContext, _ path: SkeletonPath, _ nd: Node, _ index: Int) {
        let p = toPx(nd.p)
        let isSel = selection?.nodeID == nd.id || multiSelection.contains(NodeRef(pathID: path.id, nodeID: nd.id))
        let hinted = editor.mode == .hint ? glyph.hints[nd.id] : nil
        if let hinted {
            // Holding ⌥ previews what the "nearest"-setting hint actions would do to the
            // *selected* node's hints right now (round outward instead of nearest) — display only,
            // nothing is written unless an action actually fires (see `hintNearestMode()`).
            let preview: (SnapMode) -> SnapMode = { [self] mode in
                (isSel && optionHeld && mode == .nearest) ? .outward : mode
            }
            ctx.setFillColor(EditorTheme.thickBg.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26))
            ctx.setStrokeColor(EditorTheme.thick.cgColor); ctx.setLineWidth(1.5)
            if let x = hinted.x { drawArrow(ctx, p, dx: 1, dy: 0, len: 16, mode: preview(x)) }
            if let y = hinted.y { drawArrow(ctx, p, dx: 0, dy: -1, len: 16, mode: preview(y)) }
        }
        let fill = hinted != nil ? EditorTheme.thick : (isSel ? EditorTheme.skeleton : NSColor.controlBackgroundColor)
        let stroke = hinted != nil ? EditorTheme.thick : EditorTheme.skeleton
        ctx.setFillColor(fill.cgColor); ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(1.5)
        if nd.kind == .smooth {
            let r: CGFloat = 4.5
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.fillEllipse(in: rect); ctx.strokeEllipse(in: rect)
        } else {
            let rect = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            ctx.fill(rect); ctx.stroke(rect)
        }
        // An anchored node tracks another node's thickness edge (⌃-drag) — ring it in teal (the
        // same color as curve handles) so it's visually distinct from a plain, freely-positioned
        // node, since dragging it plainly no longer sticks (the anchor keeps winning on redraw).
        if nd.anchor != nil {
            ctx.setStrokeColor(EditorTheme.handle.cgColor); ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
        }
        // A hinted node is always orange regardless of selection, so on its own it can't show
        // selection the way an unhinted node does (purple fill vs hollow) — ring it instead. Ring
        // selection in Skeleton and Hint mode unconditionally (hinted or not), for consistency
        // with Thicken's always-ringed selected handle.
        if isSel, editor.mode == .combo || editor.mode == .hint {
            ctx.setStrokeColor(EditorTheme.metricSelected.cgColor); ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
        }
    }

    /// mode "nearest"/"outward" = double-headed arrow (both can move either way); "positive"/
    /// "negative" = single head toward that axis direction. "outward" additionally draws a small
    /// perpendicular bar at each tip — the pixel boundary each edge rounds all the way out to.
    private func drawArrow(_ ctx: CGContext, _ p: CGPoint, dx: CGFloat, dy: CGFloat, len: CGFloat, mode: SnapMode) {
        let isDouble = mode == .nearest || mode == .outward
        let heads: [CGFloat] = isDouble ? [1, -1] : mode == .positive ? [1] : [-1]
        let L = isDouble ? len : len * 1.35
        // The shaft has to reach toward whichever direction the single head actually points —
        // it was previously always drawn toward +dx/+dy regardless of sign, so a "negative"
        // (push left/down) hint drew its shaft one way and its arrowhead the opposite way.
        if isDouble {
            ctx.move(to: CGPoint(x: p.x - dx * L, y: p.y - dy * L))
            ctx.addLine(to: CGPoint(x: p.x + dx * L, y: p.y + dy * L))
        } else {
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x + dx * L * heads[0], y: p.y + dy * L * heads[0]))
        }
        ctx.strokePath()
        for s in heads {
            let tip = CGPoint(x: p.x + dx * L * s, y: p.y + dy * L * s)
            ctx.move(to: tip); ctx.addLine(to: CGPoint(x: tip.x - (dx * 4 + dy * 3) * s, y: tip.y - (dy * 4 - dx * 3) * s))
            ctx.move(to: tip); ctx.addLine(to: CGPoint(x: tip.x - (dx * 4 - dy * 3) * s, y: tip.y - (dy * 4 + dx * 3) * s))
            ctx.strokePath()
            // The bar marks "rounds hard to a pixel boundary here" — true of outward (both edges)
            // and of positive/negative (one edge), just not of nearest (which can go either way).
            if mode != .nearest {
                let perp = CGPoint(x: -dy, y: dx)
                ctx.move(to: CGPoint(x: tip.x + perp.x * 4, y: tip.y + perp.y * 4))
                ctx.addLine(to: CGPoint(x: tip.x - perp.x * 4, y: tip.y - perp.y * 4))
                ctx.strokePath()
            }
        }
    }

    private func drawThicknessHandles(_ ctx: CGContext, _ path: SkeletonPath) {
        for th in thicknessHandles(path) {
            let a = toPx(th.node.p), b = toPx(th.pos)
            let isSel = selection?.nodeID == th.node.id
            // A handle at (or very near) zero thickness sits right on top of its node — drawing
            // its orange dot there just haloes the node and hides whether it's a square (corner)
            // or circle (smooth). Skip the dot itself in that case; the connecting line (zero
            // length, so invisible) and selection ring, if any, still work normally.
            let coincidesWithNode = hypot(b.x - a.x, b.y - a.y) < 3
            if !coincidesWithNode {
                ctx.setStrokeColor(EditorTheme.thick.cgColor); ctx.setLineWidth(1.5)
                ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
                // Left = filled dot, right = hollow ring, so the two sides of a stroke are
                // distinguishable at a glance instead of two identical orange dots.
                let r: CGFloat = 5
                let dotRect = CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)
                if th.side == .left {
                    ctx.setFillColor(EditorTheme.thick.cgColor)
                    ctx.fillEllipse(in: dotRect)
                } else {
                    ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
                    ctx.fillEllipse(in: dotRect)
                    ctx.setStrokeColor(EditorTheme.thick.cgColor); ctx.setLineWidth(2)
                    ctx.strokeEllipse(in: dotRect)
                }
                if th.node.fillHandle(th.side) != nil {
                    // A ring marks a node whose fill point has been explicitly touched (vs. still
                    // tracking the derived perpendicular-offset position).
                    ctx.setStrokeColor((th.side == .left ? NSColor.controlBackgroundColor : EditorTheme.thick).cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.strokeEllipse(in: CGRect(x: b.x - 2.3, y: b.y - 2.3, width: 4.6, height: 4.6))
                }
            }
            if isSel {
                let r: CGFloat = 5
                ctx.setStrokeColor(EditorTheme.metricSelected.cgColor); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: b.x - (r + 3), y: b.y - (r + 3), width: (r + 3) * 2, height: (r + 3) * 2))
            }
        }
    }

    /// Modifier keys held (without a drag in progress overriding what they'd do) preview which
    /// handle the arrow keys would act on — purely visual, doesn't change any behavior.
    private func drawModifierHighlights(_ ctx: CGContext) {
        guard let sel = currentEditableNode(),
              let path = glyph.paths.first(where: { $0.id == sel.pathID }),
              let index = path.nodes.firstIndex(where: { $0.id == sel.nodeID }) else { return }
        let nd = path.nodes[index]
        func ring(_ target: GridPoint, _ color: NSColor) {
            let b = toPx(target)
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: CGRect(x: b.x - 9, y: b.y - 9, width: 18, height: 18))
        }
        // A node's actual fill-boundary point/curve handle for `side` — the same resolver
        // `fillHandleKeyDown` uses, so this preview always matches what a nudge would actually move.
        func fillPointAt(_ side: Side) -> GridPoint {
            SkeletonGeometry.fillPoint(of: nd, path: path, index: index, side: side, weight: weight).point
        }
        func fillControl(_ side: Side, out: Bool) -> GridPoint {
            let f = SkeletonGeometry.fillPoint(of: nd, path: path, index: index, side: side, weight: weight)
            return (out ? f.cOut : f.cIn) ?? f.point
        }
        if cmdHeld {
            // ⌘ (plus ⌥/⇧) now targets a fill handle, not the skeleton's own curve handles below.
            // Both ⌘ held together targets both sides at once (see `fillHandleKeyDown`).
            let bothCommand = leftCommandHeld && rightCommandHeld
            let sides: [Side] = bothCommand ? [.left, .right] : [leftCommandHeld ? .right : .left]
            for side in sides {
                if leftOptionHeld { ring(fillControl(side, out: false), EditorTheme.thick) }
                else if rightOptionHeld { ring(fillControl(side, out: true), EditorTheme.thick) }
                else if shiftHeld && !bothCommand {
                    ring(fillControl(side, out: true), EditorTheme.thick)
                    ring(fillControl(side, out: false), EditorTheme.thick)
                } else {
                    ring(fillPointAt(side), EditorTheme.thick)
                }
            }
            return
        }
        if leftOptionHeld { ring(nd.cIn ?? nd.p, EditorTheme.handle) }
        if rightOptionHeld { ring(nd.cOut ?? nd.p, EditorTheme.handle) }
        if shiftHeld {
            ring(nd.cIn ?? nd.p, EditorTheme.handle)
            ring(nd.cOut ?? nd.p, EditorTheme.handle)
        }
    }

}
