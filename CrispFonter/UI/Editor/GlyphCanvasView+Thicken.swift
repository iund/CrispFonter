import AppKit

/// Fill-handle primitives, used by Combo mode's `comboDown`/`comboKeyDown`
/// (GlyphCanvasView+Combo.swift) alongside the Skeleton pen/curve controls. There's no rotation
/// concept anywhere here — a fill-boundary point is just a plain point with its own optional
/// curve handles, exactly like a skeleton node.
extension GlyphCanvasView {
    /// What an arrow-key nudge under ⌘ should move: the fill point itself, one of its curve
    /// handles, or both curve handles symmetrically (mirroring `setSymmetricCurve` for the
    /// skeleton's own curve handles).
    enum FillHandlePart { case point, cIn, cOut, symmetric }

    /// ⌘←/→/↑/↓ nudges a node's fill-boundary point directly: left-⌘ targets the inner (right)
    /// side, right-⌘ the outer (left) — same left/right-distinguishing trick as ⌥'s cIn/cOut, so a
    /// bare/ambiguous ⌘ falls back to outer. Adding ⌥ targets that side's own cIn/cOut instead of
    /// its point; adding ⇧ (no ⌥) moves both curve handles symmetrically, same as ⇧-arrow already
    /// does for the skeleton's handles.
    ///
    /// Holding *both* ⌘ keys at once targets both sides together, in the same direction — and with
    /// ⇧ added, in *opposing* directions instead (widen/narrow the stroke, or splay its curve
    /// handles apart, in one gesture). A node not yet touched on a side is lazily seeded from its
    /// derived (perpendicular-offset) position, so nothing jumps on the first nudge.
    func fillHandleKeyDown(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        guard let (ddx, ddy) = Self.arrowName(event.keyCode) != nil ? Self.arrowDelta(event.keyCode) : nil else { return }
        let step = editor.snapStep
        let dx = ddx * step, dy = ddy * step
        let bothCommand = Self.isLeftCommand(flags) && Self.isRightCommand(flags)
        let part: FillHandlePart
        if Self.isLeftOption(flags) { part = .cIn }
        else if Self.isRightOption(flags) { part = .cOut }
        else if flags.contains(.shift) && !bothCommand { part = .symmetric }
        else { part = .point }

        if bothCommand {
            let opposing = flags.contains(.shift)
            nudgeFillHandle([
                (side: .right, part: part, dx: dx, dy: dy),
                (side: .left, part: part, dx: opposing ? -dx : dx, dy: opposing ? -dy : dy),
            ])
        } else {
            let side: Side = Self.isLeftCommand(flags) ? .right : .left
            nudgeFillHandle([(side: side, part: part, dx: dx, dy: dy)])
        }
    }

    /// Applies every move to every node in the multi-selection at once if the selected node is
    /// part of one (same "move group" idea as dragging/arrow-nudging several nodes together),
    /// otherwise just the single selected node — all in one commit, even when `moves` covers both
    /// sides at once.
    private func nudgeFillHandle(_ moves: [(side: Side, part: FillHandlePart, dx: Double, dy: Double)]) {
        guard let sel = selection else { return }
        let anchor = NodeRef(pathID: sel.pathID, nodeID: sel.nodeID)
        let refs = multiSelection.contains(anchor) ? Array(multiSelection) : [anchor]
        let scale = weight / 2
        mutateWorking { g in
            for ref in refs {
                guard let (refPath, refIndex) = g.findNode(ref.nodeID) else { continue }
                g.withNode(ref.pathID, ref.nodeID) { nd in
                    // A curve handle's *seed* (see `seedFillHandle`) mirrors the skeleton's own
                    // cIn/cOut, which is often deliberately off-grid — so a nudge starting from
                    // one would otherwise carry that fractional offset forever. Snapping the
                    // result to the grid each time (same as a skeleton curve handle's own nudge
                    // does via `snap`) pulls it onto the grid instead.
                    func snappedRatio(_ v: GridPoint) -> GridPoint {
                        let abs = GridPoint(nd.p.x + v.x * scale, nd.p.y + v.y * scale)
                        let snapped = snap(abs, fine: false)
                        return GridPoint((snapped.x - nd.p.x) / scale, (snapped.y - nd.p.y) / scale)
                    }
                    for m in moves {
                        var fh = nd.fillHandle(m.side) ?? Self.seedFillHandle(nd, refPath, refIndex, m.side, weight)
                        // Every field here is a ratio of weight/2 (see FillHandle), so a grid-unit
                        // delta needs dividing by `scale` before it's added to any of them.
                        switch m.part {
                        case .point:
                            fh.offset = GridPoint(fh.offset.x + m.dx / scale, fh.offset.y + m.dy / scale)
                            // Moving the point drags any curve handles it already has along with
                            // it, same as moving a skeleton node drags its own cIn/cOut.
                            if let c = fh.cIn { fh.cIn = GridPoint(c.x + m.dx / scale, c.y + m.dy / scale) }
                            if let c = fh.cOut { fh.cOut = GridPoint(c.x + m.dx / scale, c.y + m.dy / scale) }
                        case .cIn:
                            let base = fh.cIn ?? fh.offset
                            fh.cIn = snappedRatio(GridPoint(base.x + m.dx / scale, base.y + m.dy / scale))
                        case .cOut:
                            let base = fh.cOut ?? fh.offset
                            fh.cOut = snappedRatio(GridPoint(base.x + m.dx / scale, base.y + m.dy / scale))
                        case .symmetric:
                            let outBase = fh.cOut ?? fh.offset
                            let inBase = fh.cIn ?? fh.offset
                            fh.cOut = snappedRatio(GridPoint(outBase.x + m.dx / scale, outBase.y + m.dy / scale))
                            fh.cIn = snappedRatio(GridPoint(inBase.x - m.dx / scale, inBase.y - m.dy / scale))
                        }
                        nd.setFillHandle(m.side, fh)
                    }
                }
            }
        }
        commit("Adjust Fill Handle")
    }

    /// A fresh fill handle seeded from the derived position/curve at the canonical weight of 2 —
    /// `FillHandle`'s reference scale (see `SkeletonGeometry.fillPoint`) — so the first nudge or
    /// drag on an untouched node doesn't jump or suddenly flatten a curve that was already there by
    /// default, and stays exactly on that same derived curve at *every* weight from then on, not
    /// just the one it happened to be touched at.
    private static func seedFillHandle(_ nd: Node, _ path: SkeletonPath, _ index: Int, _ side: Side, _ weight: Double) -> FillHandle {
        let ref = SkeletonGeometry.fillPoint(of: nd, path: path, index: index, side: side, weight: 2)
        let offset = GridPoint(ref.point.x - nd.p.x, ref.point.y - nd.p.y)
        let cIn = ref.cIn.map { GridPoint($0.x - nd.p.x, $0.y - nd.p.y) }
        let cOut = ref.cOut.map { GridPoint($0.x - nd.p.x, $0.y - nd.p.y) }
        return FillHandle(offset: offset, cIn: cIn, cOut: cOut)
    }

    /// The nodes a fill-handle side command (⌘⌫/⌘⏎) applies to: the whole multi-selection if the
    /// selected node is part of one, otherwise just the selected node.
    private func fillHandleTargets() -> [NodeRef] {
        guard let sel = selection else { return [] }
        let anchor = NodeRef(pathID: sel.pathID, nodeID: sel.nodeID)
        return multiSelection.contains(anchor) ? Array(multiSelection) : [anchor]
    }

    /// ⌘⌫ pins the targeted side's fill point onto the skeleton (zero thickness) and resets its
    /// curve handles back to default (auto) — "default" meaning the skeleton node's *own*
    /// cIn/cOut, unchanged, since a zero-offset point sitting exactly on the node should trace
    /// the skeleton curve itself, not flatten it to a corner. Unlike an arrow-key point nudge,
    /// this does *not* drag any existing explicit cIn/cOut along with it — left-⌘ = inner,
    /// right-⌘ = outer, both ⌘ = both.
    func zeroFillHandle(_ flags: NSEvent.ModifierFlags) {
        let refs = fillHandleTargets()
        guard !refs.isEmpty else { return }
        let sides: [Side] = Self.isLeftCommand(flags) && Self.isRightCommand(flags) ? [.left, .right] : [Self.isLeftCommand(flags) ? .right : .left]
        mutateWorking { g in
            for ref in refs {
                g.withNode(ref.pathID, ref.nodeID) { nd in
                    // No scale division: this makes the fill point's own reference *equal* the
                    // skeleton's anchor (see `fillPoint`'s lerp), which keeps it sitting exactly on
                    // the skeleton's curve at every weight, not just the one it was zeroed at.
                    let cIn = nd.cIn.map { GridPoint($0.x - nd.p.x, $0.y - nd.p.y) }
                    let cOut = nd.cOut.map { GridPoint($0.x - nd.p.x, $0.y - nd.p.y) }
                    for side in sides { nd.setFillHandle(side, FillHandle(offset: .zero, cIn: cIn, cOut: cOut)) }
                }
            }
        }
        commit("Zero Fill Handle")
    }

    /// ⌘⏎ clears the targeted side's explicit fill handle entirely, reverting it back to the plain
    /// derived (auto) position — left-⌘ = inner, right-⌘ = outer, both ⌘ = both sides.
    func resetFillHandle(_ flags: NSEvent.ModifierFlags) {
        let refs = fillHandleTargets()
        guard !refs.isEmpty else { return }
        let sides: [Side] = Self.isLeftCommand(flags) && Self.isRightCommand(flags) ? [.left, .right] : [Self.isLeftCommand(flags) ? .right : .left]
        mutateWorking { g in
            for ref in refs {
                g.withNode(ref.pathID, ref.nodeID) { nd in
                    for side in sides { nd.setFillHandle(side, nil) }
                }
            }
        }
        commit("Reset Fill Handle")
    }

    /// Dragging a fill-boundary handle just moves it straight to the cursor (¼-grid snapped),
    /// lazily seeding it from the derived position first if this is the first touch — same
    /// endpoint an arrow-key nudge would reach, just driven by the mouse. Any curve handles the
    /// point already has are dragged along with it, same as an arrow-key point nudge.
    func dragFillHandle(_ pathID: UUID, _ nodeID: UUID, _ side: Side, _ raw: GridPoint) {
        mutateWorking { g in
            guard let (path, index) = g.findNode(nodeID) else { return }
            g.withNode(pathID, nodeID) { nd in
                let scale = weight / 2
                var fh = nd.fillHandle(side) ?? Self.seedFillHandle(nd, path, index, side, weight)
                let oldPoint = GridPoint(nd.p.x + fh.offset.x * scale, nd.p.y + fh.offset.y * scale)
                let snapped = GridPoint((raw.x * 4).rounded() / 4, (raw.y * 4).rounded() / 4)
                let delta = GridPoint((snapped.x - oldPoint.x) / scale, (snapped.y - oldPoint.y) / scale)
                fh.offset = GridPoint((snapped.x - nd.p.x) / scale, (snapped.y - nd.p.y) / scale)
                if let c = fh.cIn { fh.cIn = GridPoint(c.x + delta.x, c.y + delta.y) }
                if let c = fh.cOut { fh.cOut = GridPoint(c.x + delta.x, c.y + delta.y) }
                nd.setFillHandle(side, fh)
            }
        }
    }
}
