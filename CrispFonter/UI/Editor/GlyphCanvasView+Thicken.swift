import AppKit

extension GlyphCanvasView {
    func thickenDown(_ event: NSEvent, _ px: CGPoint) {
        if event.clickCount >= 2 { handleDoubleClick(event, px); return }
        if let ch = hitCap(px) {
            selection = (ch.pathID, ch.node.id)
            drag = .cap(pathID: ch.pathID, nodeID: ch.node.id, dir0: ch.dir0)
        } else if let th = hitThickness(px) {
            selection = (th.pathID, th.node.id)
            if event.modifierFlags.contains(.option) {
                drag = .angle(pathID: th.pathID, nodeID: th.node.id, dir0: th.dir0)
            } else {
                drag = .thickness(pathID: th.pathID, nodeID: th.node.id, side: th.side, dir: th.dir, both: event.modifierFlags.contains(.command))
            }
        }
    }

    /// Up/down adjusts the selected node's "outer" (left) thickness, left/right its "inner"
    /// (right) thickness; ⇧ applies the same delta to every node in the glyph at once; ⌥←/→
    /// rotates the terminal's cross-section instead of touching thickness.
    func thickenKeyDown(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        switch event.keyCode {
        case KeyCode.up: adjustThickness(.left, delta: 0.25, allNodes: flags.contains(.shift))
        case KeyCode.down: adjustThickness(.left, delta: -0.25, allNodes: flags.contains(.shift))
        case KeyCode.right:
            if flags.contains(.option) { rotateSelected(delta: 15) }
            else { adjustThickness(.right, delta: 0.25, allNodes: flags.contains(.shift)) }
        case KeyCode.left:
            if flags.contains(.option) { rotateSelected(delta: -15) }
            else { adjustThickness(.right, delta: -0.25, allNodes: flags.contains(.shift)) }
        default: break
        }
    }

    private func adjustThickness(_ side: Side, delta: Double, allNodes: Bool) {
        if allNodes {
            mutateWorking { g in
                for pi in g.paths.indices {
                    for ni in g.paths[pi].nodes.indices {
                        switch side {
                        case .left: g.paths[pi].nodes[ni].left = max(0, (g.paths[pi].nodes[ni].left ?? 1) + delta)
                        case .right: g.paths[pi].nodes[ni].right = max(0, (g.paths[pi].nodes[ni].right ?? 1) + delta)
                        }
                    }
                }
            }
            commit("Adjust All Thickness")
        } else {
            guard let sel = selection else { return }
            mutateWorking { g in
                g.withNode(sel.pathID, sel.nodeID) { nd in
                    switch side {
                    case .left: nd.left = max(0, (nd.left ?? 1) + delta)
                    case .right: nd.right = max(0, (nd.right ?? 1) + delta)
                    }
                }
            }
            commit("Adjust Thickness")
        }
    }

    private func rotateSelected(delta: Double) {
        guard let sel = selection else { return }
        mutateWorking { g in g.withNode(sel.pathID, sel.nodeID) { nd in nd.angle = normalizeAngle(nd.angle + delta) } }
        commit("Rotate Terminal")
    }

    /// Wraps to (-180, 180] instead of clamping — rotation is unconstrained, this just keeps the
    /// stored value from growing without bound as repeated ⌥-arrow presses wrap around.
    private func normalizeAngle(_ deg: Double) -> Double {
        var a = deg.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a <= -180 { a += 360 }
        return a
    }

    func thickenDoubleClick(_ px: CGPoint) {
        if let ch = hitCap(px) {
            mutateWorking { g in g.withNode(ch.pathID, ch.node.id) { $0.cap = 0 } }
            commit("Reset Cap")
        } else if let th = hitThickness(px) {
            mutateWorking { g in g.withNode(th.pathID, th.node.id) { nd in nd.left = nil; nd.right = nil; nd.angle = 0 } }
            commit("Reset Thickness")
        }
    }

    func dragThickness(_ pathID: UUID, _ nodeID: UUID, _ side: Side, _ dir: GridPoint, _ both: Bool, _ raw: GridPoint) {
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                let v = GridPoint(raw.x - nd.p.x, raw.y - nd.p.y)
                let t = max(0, ((v.x * dir.x + v.y * dir.y) * 4).rounded() / 4)
                let ratio = t / (weight / 2)
                switch side {
                case .left: nd.left = ratio; if both { nd.right = ratio }
                case .right: nd.right = ratio; if both { nd.left = ratio }
                }
            }
        }
    }

    func dragAngle(_ pathID: UUID, _ nodeID: UUID, _ dir0: GridPoint, _ raw: GridPoint) {
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                let v = GridPoint(raw.x - nd.p.x, raw.y - nd.p.y)
                nd.angle = atan2(dir0.x * v.y - dir0.y * v.x, dir0.x * v.x + dir0.y * v.y) * 180 / .pi
            }
        }
    }

    /// Dragging the cap handle both points it — rotating the terminal's angle to face the cursor,
    /// freely, same as ⌥-dragging a thickness handle — and sets how far it bulges, so you can aim
    /// and size the end of a stroke in one intuitive gesture instead of two. The drag is measured
    /// from the handle's own anchor (the stroke's visual tip), not the skeleton node, so it tracks
    /// the cursor 1:1 from wherever it actually sits.
    func dragCap(_ pathID: UUID, _ nodeID: UUID, _ dir0: GridPoint, _ raw: GridPoint) {
        mutateWorking { g in
            guard let pi = g.pathIndex(pathID), let ni = g.nodeIndex(pathID, nodeID) else { return }
            let anchor = capAnchor(g.paths[pi], ni)
            var nd = g.paths[pi].nodes[ni]
            let v = GridPoint(raw.x - anchor.x, raw.y - anchor.y)
            if v.length > 0.05 {
                nd.angle = atan2(dir0.x * v.y - dir0.y * v.x, dir0.x * v.x + dir0.y * v.y) * 180 / .pi
            }
            let rotatedDir = dir0.rotated(degrees: nd.angle)
            let proj = v.x * rotatedDir.x + v.y * rotatedDir.y
            nd.cap = max(0, (proj * 4).rounded() / 4)
            g.paths[pi].nodes[ni] = nd
        }
    }
}
