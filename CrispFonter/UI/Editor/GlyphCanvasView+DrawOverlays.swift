import AppKit

extension GlyphCanvasView {
    func drawSkeletonAndModeOverlays(_ ctx: CGContext) {
        for path in glyph.paths {
            guard !path.nodes.isEmpty else { continue }
            drawSkeletonLine(ctx, path)
            if editor.mode == .skeleton { drawCurveHandles(ctx, path) }
            for (i, nd) in path.nodes.enumerated() { drawNode(ctx, path, nd, i) }
            if editor.mode == .thicken {
                drawThicknessHandles(ctx, path)
                drawCapHandles(ctx, path)
            }
        }
        if let pathID = drawingPathID, let hover, editor.mode == .skeleton, drag == nil,
           let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last {
            ctx.setStrokeColor(EditorTheme.skeleton.withAlphaComponent(0.4).cgColor)
            ctx.setLineDash(phase: 0, lengths: [4, 4]); ctx.setLineWidth(2)
            ctx.move(to: toPx(last.p)); ctx.addLine(to: toPx(hover)); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if case .marquee(let start)? = drag, let current = marqueeCurrent {
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                               width: abs(current.x - start.x), height: abs(current.y - start.y))
            ctx.setFillColor(EditorTheme.metricSelected.withAlphaComponent(0.1).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(EditorTheme.metricSelected.cgColor); ctx.setLineWidth(1)
            ctx.stroke(rect)
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

    private func drawNode(_ ctx: CGContext, _ path: SkeletonPath, _ nd: Node, _ index: Int) {
        let p = toPx(nd.p)
        let isSel = selection?.nodeID == nd.id || multiSelection.contains(NodeRef(pathID: path.id, nodeID: nd.id))
        let hinted = editor.mode == .hint ? glyph.hints[nd.id] : nil
        if let hinted {
            ctx.setFillColor(EditorTheme.thickBg.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26))
            ctx.setStrokeColor(EditorTheme.thick.cgColor); ctx.setLineWidth(1.5)
            if let x = hinted.x { drawArrow(ctx, p, dx: 1, dy: 0, len: 11, mode: x) }
            if let y = hinted.y { drawArrow(ctx, p, dx: 0, dy: -1, len: 11, mode: y) }
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
        // A hinted node is always orange regardless of selection, so on its own it can't show
        // selection the way an unhinted node does (purple fill vs hollow) — ring it instead. Ring
        // selection in Skeleton and Hint mode unconditionally (hinted or not), for consistency
        // with Thicken's always-ringed selected handle.
        if isSel, editor.mode == .skeleton || editor.mode == .hint {
            ctx.setStrokeColor(EditorTheme.metricSelected.cgColor); ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
        }
    }

    /// mode "nearest" = double-headed arrow; "positive"/"negative" = single head toward that axis direction.
    private func drawArrow(_ ctx: CGContext, _ p: CGPoint, dx: CGFloat, dy: CGFloat, len: CGFloat, mode: SnapMode) {
        let heads: [CGFloat] = mode == .nearest ? [1, -1] : mode == .positive ? [1] : [-1]
        let from: CGFloat = mode == .nearest ? -1 : 0
        let to: CGFloat = mode == .nearest ? 1 : 1.35
        ctx.move(to: CGPoint(x: p.x + dx * len * from, y: p.y + dy * len * from))
        ctx.addLine(to: CGPoint(x: p.x + dx * len * to, y: p.y + dy * len * to))
        ctx.strokePath()
        for s in heads {
            let L = mode == .nearest ? len : len * 1.35
            let tip = CGPoint(x: p.x + dx * L * s, y: p.y + dy * L * s)
            ctx.move(to: tip); ctx.addLine(to: CGPoint(x: tip.x - (dx * 4 + dy * 3) * s, y: tip.y - (dy * 4 - dx * 3) * s))
            ctx.move(to: tip); ctx.addLine(to: CGPoint(x: tip.x - (dx * 4 - dy * 3) * s, y: tip.y - (dy * 4 + dx * 3) * s))
            ctx.strokePath()
        }
    }

    private func drawThicknessHandles(_ ctx: CGContext, _ path: SkeletonPath) {
        for th in thicknessHandles(path) {
            let a = toPx(th.node.p), b = toPx(th.pos)
            let isSel = selection?.nodeID == th.node.id
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
            let overridden = (th.side == .left ? th.node.left : th.node.right) != nil || th.node.angle != 0
            if overridden {
                ctx.setStrokeColor((th.side == .left ? NSColor.controlBackgroundColor : EditorTheme.thick).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: b.x - 2.3, y: b.y - 2.3, width: 4.6, height: 4.6))
            }
            if isSel {
                ctx.setStrokeColor(EditorTheme.metricSelected.cgColor); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: b.x - (r + 3), y: b.y - (r + 3), width: (r + 3) * 2, height: (r + 3) * 2))
            }
        }
    }

    private func drawCapHandles(_ ctx: CGContext, _ path: SkeletonPath) {
        for ch in capHandles(path) {
            let a = toPx(ch.node.p), b = toPx(ch.pos)
            let isSel = selection?.nodeID == ch.node.id
            ctx.setStrokeColor(EditorTheme.thick.cgColor); ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [2, 2])
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setFillColor((ch.node.cap > 0 ? EditorTheme.thick : NSColor.controlBackgroundColor).cgColor)
            let rect = CGRect(x: b.x - 4.5, y: b.y - 4.5, width: 9, height: 9)
            ctx.fill(rect); ctx.stroke(rect)
            if isSel {
                ctx.setStrokeColor(EditorTheme.metricSelected.cgColor); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: b.x - 8, y: b.y - 8, width: 16, height: 16))
            }
        }
    }
}
