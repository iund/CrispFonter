import AppKit

extension GlyphCanvasView {
    func skeletonDown(_ event: NSEvent, _ px: CGPoint) {
        if event.clickCount >= 2 { handleDoubleClick(event, px); return }
        let gp = snap(toGrid(px), fine: event.modifierFlags.contains(.shift))

        if drawingPathID == nil, let hh = hitHandle(px) {
            drag = .handle(pathID: hh.pathID, nodeID: hh.nodeID, key: hh.key, alt: event.modifierFlags.contains(.option))
            return
        }
        if let pathID = drawingPathID {
            continuePath(pathID, px, gp)
            return
        }
        if let hn = hitNode(px) {
            // ⌘-click toggles this node in/out of the multi-selection, so several nodes can be
            // dragged or arrow-nudged together — same idea as ⌘-click in a Finder list.
            if event.modifierFlags.contains(.command) {
                toggleMultiSelect(hn.pathID, hn.nodeID)
                return
            }
            // ⌥-dragging directly on a smooth node whose other handle is already pulled out but
            // this side is still sitting unset (i.e. at the node) grabs and drags *that* missing
            // handle out, instead of moving the node — the handle's normally-invisible resting
            // spot is exactly on top of the node, so there'd be nothing else to click otherwise.
            if event.modifierFlags.contains(.option), let key = missingHandleKey(hn.pathID, hn.nodeID) {
                selection = (hn.pathID, hn.nodeID)
                multiSelection = []
                drag = .handle(pathID: hn.pathID, nodeID: hn.nodeID, key: key, alt: true)
                return
            }
            // Plain click on a node already part of the multi-selection keeps the whole group
            // selected, so dragging it moves all of them together; clicking any other node starts
            // a fresh single selection.
            let ref = NodeRef(pathID: hn.pathID, nodeID: hn.nodeID)
            if !multiSelection.contains(ref) { multiSelection = [] }
            selection = (hn.pathID, hn.nodeID)
            drag = .moveNode(pathID: hn.pathID, nodeID: hn.nodeID)
            needsDisplay = true
            return
        }
        // Clicking a stroke (not a node) inserts a node there, same as a segment click in Hint
        // mode — and starts dragging it immediately, so a click-drag both inserts and positions
        // the new node in one motion instead of two separate gestures.
        if let hs = hitSegment(px) {
            var newID = UUID()
            mutateWorking { g in newID = g.insertNode(pathID: hs.pathID, index: hs.index, t: hs.t, isLine: hs.isLine) }
            selection = (hs.pathID, newID)
            multiSelection = []
            drag = .moveNode(pathID: hs.pathID, nodeID: newID)
            needsDisplay = true
            return
        }
        // ⇧-drag from empty space starts a marquee selection instead of a new stroke.
        if event.modifierFlags.contains(.shift) {
            drag = .marquee(start: px)
            return
        }
        startPath(at: gp)
    }

    /// ⌘-click a node: add it to the multi-selection, folding in the current single selection
    /// first if there wasn't already a set — or remove it if it's already in there. Falls back to
    /// the plain single-`selection` scheme once the set drops to 0–1 members.
    private func toggleMultiSelect(_ pathID: UUID, _ nodeID: UUID) {
        if multiSelection.isEmpty, let sel = selection {
            multiSelection = [NodeRef(pathID: sel.pathID, nodeID: sel.nodeID)]
        }
        let ref = NodeRef(pathID: pathID, nodeID: nodeID)
        if multiSelection.contains(ref) {
            multiSelection.remove(ref)
            selection = multiSelection.first.map { ($0.pathID, $0.nodeID) }
        } else {
            multiSelection.insert(ref)
            selection = (pathID, nodeID)
        }
        if multiSelection.count <= 1 { multiSelection = [] }
        needsDisplay = true
    }

    /// Finishes a marquee drag: every node whose on-screen position falls inside the rectangle
    /// becomes the multi-selection (replacing whatever was selected before).
    func finishMarquee(start: CGPoint, end: CGPoint) {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard rect.width > 2 || rect.height > 2 else {
            selection = nil; multiSelection = []
            return
        }
        var refs: Set<NodeRef> = []
        for path in glyph.paths {
            for nd in path.nodes where rect.contains(toPx(nd.p)) { refs.insert(NodeRef(pathID: path.id, nodeID: nd.id)) }
        }
        multiSelection = refs.count > 1 ? refs : []
        selection = refs.first.map { ($0.pathID, $0.nodeID) }
    }

    /// The nodes a "move" command (drag or plain-arrow nudge) applies to: the whole multi-selection
    /// if one exists and includes `anchor`, otherwise just `anchor` on its own.
    private func moveGroup(anchor: NodeRef) -> [NodeRef] {
        multiSelection.contains(anchor) ? Array(multiSelection) : [anchor]
    }

    func selectAllNodes() {
        let refs = Set(glyph.paths.flatMap { path in path.nodes.map { NodeRef(pathID: path.id, nodeID: $0.id) } })
        multiSelection = refs.count > 1 ? refs : []
        selection = refs.first.map { ($0.pathID, $0.nodeID) }
        needsDisplay = true
    }

    private func clearSelection() {
        guard selection != nil || !multiSelection.isEmpty else { return }
        selection = nil
        multiSelection = []
        needsDisplay = true
    }

    private func missingHandleKey(_ pathID: UUID, _ nodeID: UUID) -> HandleKey? {
        guard let pi = glyph.pathIndex(pathID), let ni = glyph.nodeIndex(pathID, nodeID) else { return nil }
        let nd = glyph.paths[pi].nodes[ni]
        guard nd.kind == .smooth else { return nil }
        if nd.cIn == nil && nd.cOut != nil { return .cIn }
        if nd.cOut == nil && nd.cIn != nil { return .cOut }
        return nil
    }

    func handleDoubleClick(_ event: NSEvent, _ px: CGPoint) {
        if drawingPathID != nil { finishDrawing(); return }
        switch editor.mode {
        case .metrics: break
        case .skeleton: skeletonDoubleClick(px)
        case .thicken: thickenDoubleClick(px)
        case .hint: break
        }
    }

    /// Double-click a node to toggle corner ↔ smooth; double-click a segment to insert a node
    /// there, splitting it without changing the shape.
    private func skeletonDoubleClick(_ px: CGPoint) {
        if let hn = hitNode(px) {
            mutateWorking { g in g.toggleNodeKind(hn.pathID, hn.nodeID) }
            commit("Toggle Node Kind")
            return
        }
        if let hs = hitSegment(px) {
            mutateWorking { g in g.insertNode(pathID: hs.pathID, index: hs.index, t: hs.t, isLine: hs.isLine) }
            commit("Insert Node")
        }
    }

    private func startPath(at gp: GridPoint) {
        var newPathID = UUID(), newNodeID = UUID()
        mutateWorking { g in
            let nd = Node(gp)
            newNodeID = nd.id
            let path = SkeletonPath(nodes: [nd], closed: false)
            newPathID = path.id
            g.paths.append(path)
        }
        drawingPathID = newPathID
        selection = (newPathID, newNodeID)
        drag = .pen(pathID: newPathID, nodeID: newNodeID, start: gp)
    }

    private func continuePath(_ pathID: UUID, _ px: CGPoint, _ gp: GridPoint) {
        guard let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last else { drawingPathID = nil; return }
        let nodes = glyph.paths[pi].nodes
        if let hn = hitNode(px), hn.nodeID == nodes[0].id, nodes.count > 2 {
            mutateWorking { g in g.paths[g.pathIndex(pathID)!].closed = true }
            finishDrawing()
            return
        }
        // Ending a new line on an existing line's endpoint joins them into one path, so extending
        // a stroke is just "start elsewhere, draw up to its end" rather than a separate step.
        if let hn = hitNode(px), hn.pathID != pathID, let isLast = glyph.endpointIsLast(hn.pathID, hn.nodeID) {
            mutateWorking { g in g.joinDrawingPath(pathID, intoEndpointOf: hn.pathID, isLastEndpoint: isLast) }
            drawingPathID = nil
            selection = nil
            commit("Join Paths")
            return
        }
        if last.p.x == gp.x && last.p.y == gp.y { finishDrawing(); return }
        var newID = UUID()
        mutateWorking { g in
            let nd = Node(gp)
            newID = nd.id
            g.paths[g.pathIndex(pathID)!].nodes.append(nd)
        }
        drag = .pen(pathID: pathID, nodeID: newID, start: gp)
    }

    func finishDrawing() {
        if let pathID = drawingPathID {
            if let pi = glyph.pathIndex(pathID), glyph.paths[pi].nodes.count < 2 {
                mutateWorking { g in g.paths.removeAll { $0.id == pathID } }
            }
        }
        drawingPathID = nil
        if working != nil { commit("Draw Path") }
        needsDisplay = true
    }

    /// Esc while drawing discards the whole in-progress path — not just trims/finishes it — so
    /// starting a stroke you don't want is cheap to back out of.
    func abortDrawing() {
        guard let pathID = drawingPathID else { return }
        working = nil
        doc.mutateGlyph(editor.currentScalar, "Abort Stroke", undoManager: undoManager) { g in g.paths.removeAll { $0.id == pathID } }
        drawingPathID = nil
        selection = nil
        needsDisplay = true
    }

    func deleteSelection() {
        guard editor.mode == .skeleton, drawingPathID == nil, let sel = selection else { return }
        mutateWorking { g in g.deleteNode(sel.pathID, sel.nodeID) }
        selection = nil
        commit("Delete Node")
    }

    /// ⌫/⌦ while mid-stroke undoes the most recently placed node instead of trying to delete a
    /// (stale) selection — same idea as backspacing text you just typed. Backspacing the stroke's
    /// only node aborts it entirely, same as esc.
    private func deleteLastDrawnNode() {
        guard let pathID = drawingPathID, let pi = glyph.pathIndex(pathID) else { return }
        guard glyph.paths[pi].nodes.count > 1 else { abortDrawing(); return }
        mutateWorking { g in g.paths[g.pathIndex(pathID)!].nodes.removeLast() }
        commit("Delete Node")
    }

    func skeletonKeyDown(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        switch event.keyCode {
        case KeyCode.space:
            // Mid-stroke, space places the next node (same as clicking) rather than toggling —
            // `selection` still points at whatever was last selected before drawing started, not
            // the node being drawn, so "is there a selection" isn't the right test while drawing.
            if let pathID = drawingPathID {
                // Placed relative to the just-created node, not the mouse's (possibly stale, or
                // never-set) hover position — otherwise repeated presses without moving the mouse
                // all land on the same point and the path stalls after one node (identical
                // consecutive points make `continuePath` finish the stroke instead of extending it).
                guard let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last else { return }
                let step = flags.contains(.shift) || editor.halfSnap ? 0.5 : 1.0
                let gp = GridPoint(last.p.x + step, last.p.y)
                continuePath(pathID, toPx(gp), gp)
                // continuePath's default branch (plain "add a node") only sets up a .pen drag for
                // a mouse gesture to later commit on mouseUp; there's no such follow-up event from
                // the keyboard, so commit right away. A no-op if a branch (close/join/finish)
                // already committed internally.
                commit("Draw Path")
            } else if let sel = selection {
                mutateWorking { g in g.toggleNodeKind(sel.pathID, sel.nodeID) }
                commit("Toggle Node Kind")
            } else {
                let m = doc.project.metrics
                let fallback = GridPoint(Double(doc.project.advance(of: glyph)) / 2, Double(m.xHeight) / 2)
                startPath(at: snap(hover ?? fallback, fine: flags.contains(.shift)))
            }
        case KeyCode.enter:
            finishDrawing()
        case KeyCode.esc:
            if drawingPathID != nil { abortDrawing() } else { clearSelection() }
        case KeyCode.backspace, KeyCode.forwardDelete:
            if drawingPathID != nil { deleteLastDrawnNode() } else { deleteSelection() }
        case KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down:
            let (ddx, ddy) = Self.arrowDelta(event.keyCode)
            let step = editor.halfSnap ? 0.5 : 1.0
            let dx = ddx * step, dy = ddy * step
            if flags.contains(.shift), let t = currentEditableNode() {
                setSymmetricCurve(t.pathID, t.nodeID, dx: dx, dy: dy)
            } else if Self.isLeftOption(flags) { nudgeSelectedNode(dx: dx, dy: dy, handle: .cIn) }
            else if Self.isRightOption(flags) { nudgeSelectedNode(dx: dx, dy: dy, handle: .cOut) }
            else { nudgeSelectedNode(dx: dx, dy: dy, handle: nil) }
        default: break
        }
    }

    /// The node keyboard commands act on: the one being drawn right now if a stroke is in
    /// progress (its last node — `selection` is stale during drawing, still pointing at whatever
    /// was selected before), otherwise the explicit selection.
    private func currentEditableNode() -> (pathID: UUID, nodeID: UUID)? {
        if let pathID = drawingPathID, let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last {
            return (pathID, last.id)
        }
        return selection
    }

    /// Nudge the selected node — or, with ⌥, one of its curve handles — one grid step (half a step
    /// with half-grid snap on). A handle with no position yet (nil, resting at the node) starts
    /// from the node itself. Uses `currentEditableNode()`, not the raw selection, so the node just
    /// placed by Space mid-stroke (where `selection` is stale) can be nudged onto a grid point
    /// without touching the mouse. A plain move (`handle == nil`) carries the whole multi-selection
    /// along together if the node being nudged is part of one.
    private func nudgeSelectedNode(dx: Double, dy: Double, handle: HandleKey?) {
        guard let sel = currentEditableNode() else { return }
        let anchor = NodeRef(pathID: sel.pathID, nodeID: sel.nodeID)
        let refs = handle == nil ? moveGroup(anchor: anchor) : [anchor]
        mutateWorking { g in
            for ref in refs {
                g.withNode(ref.pathID, ref.nodeID) { nd in
                    switch handle {
                    case nil:
                        nd.p = GridPoint(nd.p.x + dx, nd.p.y + dy)
                        if let c = nd.cIn { nd.cIn = GridPoint(c.x + dx, c.y + dy) }
                        if let c = nd.cOut { nd.cOut = GridPoint(c.x + dx, c.y + dy) }
                    case .cIn:
                        let base = nd.cIn ?? nd.p
                        nd.cIn = GridPoint(base.x + dx, base.y + dy)
                    case .cOut:
                        let base = nd.cOut ?? nd.p
                        nd.cOut = GridPoint(base.x + dx, base.y + dy)
                    }
                }
            }
        }
        commit("Nudge")
    }

    /// ⇧-arrow: curve the node symmetrically toward that direction, the same shape a click-drag
    /// in that direction would produce — works both on a finished, selected node and (per
    /// `currentEditableNode`) on the node being placed right now while drawing. Extends from the
    /// handles' current position (not always the node itself), so repeated presses keep pulling
    /// the curve further out, the same way plain-arrow nudging accumulates one grid step at a time.
    /// The result is re-snapped to the grid rather than just offset by a whole step, since an
    /// existing handle may already sit off-grid (e.g. rotated via a mouse drag).
    private func setSymmetricCurve(_ pathID: UUID, _ nodeID: UUID, dx: Double, dy: Double) {
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                nd.kind = .smooth
                let baseOut = nd.cOut ?? nd.p
                let baseIn = nd.cIn ?? nd.p
                nd.cOut = snap(GridPoint(baseOut.x + dx, baseOut.y + dy), fine: false)
                nd.cIn = snap(GridPoint(baseIn.x - dx, baseIn.y - dy), fine: false)
            }
        }
        commit("Curve Node")
    }

    func dragPen(_ pathID: UUID, _ nodeID: UUID, _ start: GridPoint, _ gp: GridPoint, alt: Bool) {
        let dx = gp.x - start.x, dy = gp.y - start.y
        let distance = (dx * dx + dy * dy).squareRoot()
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                if distance >= 0.5 {
                    nd.kind = .smooth
                    nd.cOut = gp
                    if !alt { nd.cIn = GridPoint(2 * nd.p.x - gp.x, 2 * nd.p.y - gp.y) }
                } else {
                    nd.kind = .corner; nd.cOut = nil; nd.cIn = nil
                }
            }
        }
    }

    /// Drags the node to `gp`; if it's part of the multi-selection, every other member moves by
    /// the same (grid-snapped, so whole-unit) delta instead of also snapping individually to `gp`
    /// — which would collapse the whole group onto a single point.
    func dragMoveNode(_ pathID: UUID, _ nodeID: UUID, _ gp: GridPoint) {
        guard let anchor = glyph.node(pathID, nodeID) else { return }
        let dx = gp.x - anchor.p.x, dy = gp.y - anchor.p.y
        let refs = moveGroup(anchor: NodeRef(pathID: pathID, nodeID: nodeID))
        mutateWorking { g in
            for ref in refs {
                g.withNode(ref.pathID, ref.nodeID) { nd in
                    nd.p = GridPoint(nd.p.x + dx, nd.p.y + dy)
                    if let c = nd.cIn { nd.cIn = GridPoint(c.x + dx, c.y + dy) }
                    if let c = nd.cOut { nd.cOut = GridPoint(c.x + dx, c.y + dy) }
                }
            }
        }
    }

    func dragHandle(_ pathID: UUID, _ nodeID: UUID, _ key: HandleKey, _ gp: GridPoint, alt: Bool) {
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                switch key {
                case .cIn: nd.cIn = gp
                case .cOut: nd.cOut = gp
                }
                guard nd.kind == .smooth, !alt else { return }
                switch key {
                case .cOut:
                    guard let cin = nd.cIn else { return }
                    let len = hypot(cin.x - nd.p.x, cin.y - nd.p.y)
                    let dir = GridPoint(nd.p.x - gp.x, nd.p.y - gp.y).normalized
                    nd.cIn = GridPoint(nd.p.x + dir.x * len, nd.p.y + dir.y * len)
                case .cIn:
                    guard let cout = nd.cOut else { return }
                    let len = hypot(cout.x - nd.p.x, cout.y - nd.p.y)
                    let dir = GridPoint(nd.p.x - gp.x, nd.p.y - gp.y).normalized
                    nd.cOut = GridPoint(nd.p.x + dir.x * len, nd.p.y + dir.y * len)
                }
            }
        }
    }
}
