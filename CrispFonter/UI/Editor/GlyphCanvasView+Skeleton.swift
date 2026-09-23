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
        // Empty space: with something already selected, a plain click/drag deselects or re-picks
        // via marquee instead of drawing — ⌘ always means select/marquee (additively), regardless
        // of what's currently selected. With nothing selected, a plain click/drag starts a new
        // stroke instead (a drag immediately pulls out curve handles, same as the pen tool always
        // did) — the canvas is idle, so there's nothing to accidentally deselect by clicking.
        let hasSelection = selection != nil || !multiSelection.isEmpty
        if event.modifierFlags.contains(.command) || hasSelection {
            drag = .marquee(start: px, additive: event.modifierFlags.contains(.command))
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
    /// becomes the multi-selection — added to whatever was already selected if `additive` (⌘ was
    /// held), replacing it otherwise. A plain click (too small to count as a drag) deselects
    /// everything unless `additive`, in which case it's a no-op — there's nothing to add.
    func finishMarquee(start: CGPoint, end: CGPoint, additive: Bool) {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard rect.width > 2 || rect.height > 2 else {
            if !additive { selection = nil; multiSelection = [] }
            return
        }
        var refs: Set<NodeRef> = []
        for path in glyph.paths {
            for nd in path.nodes where rect.contains(toPx(nd.p)) { refs.insert(NodeRef(pathID: path.id, nodeID: nd.id)) }
        }
        if additive {
            refs.formUnion(multiSelection)
            if let sel = selection { refs.insert(NodeRef(pathID: sel.pathID, nodeID: sel.nodeID)) }
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
        selectNodes(refs)
    }

    /// Selects every node of one path — used once a stroke finishes drawing, so its whole shape is
    /// immediately ready for a group edit (⌫ to delete it, arrows to nudge it, etc.) without having
    /// to marquee it first.
    private func selectAllNodes(inPath pathID: UUID) {
        guard let path = glyph.paths.first(where: { $0.id == pathID }) else { return }
        selectNodes(Set(path.nodes.map { NodeRef(pathID: pathID, nodeID: $0.id) }))
    }

    private func selectNodes(_ refs: Set<NodeRef>) {
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
        case .combo: skeletonDoubleClick(px)
        case .hint: break
        }
    }

    /// Double-click a node to toggle corner ↔ smooth; double-click a segment to insert a node
    /// there, splitting it without changing the shape. (Thicken's own double-click-to-reset a
    /// handle doesn't carry over into Combo mode — this is the only double-click behavior there.)
    func skeletonDoubleClick(_ px: CGPoint) {
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

    /// `checkOnly` runs just the close/join hit-tests and skips placing a node — used by Space
    /// (see `skeletonKeyDown`) to check whether the last node's *current* position (which arrow
    /// keys may have nudged onto a target) already closes or joins the path, before falling back
    /// to its normal fixed-step placement. Returns whether it closed, joined, finished, or placed
    /// a node — i.e. whether the caller should treat this as handled.
    @discardableResult
    private func continuePath(_ pathID: UUID, _ px: CGPoint, _ gp: GridPoint, checkOnly: Bool = false) -> Bool {
        guard let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last else { drawingPathID = nil; return false }
        let nodes = glyph.paths[pi].nodes
        if let hn = hitNode(px), hn.nodeID == nodes[0].id, nodes.count > 2 {
            mutateWorking { g in g.paths[g.pathIndex(pathID)!].closed = true }
            finishDrawing()
            return true
        }
        // Ending a new line on an existing line's endpoint joins them into one path, so extending
        // a stroke is just "start elsewhere, draw up to its end" rather than a separate step.
        if let hn = hitNode(px), hn.pathID != pathID, let isLast = glyph.endpointIsLast(hn.pathID, hn.nodeID) {
            let targetPathID = hn.pathID
            mutateWorking { g in g.joinDrawingPath(pathID, intoEndpointOf: hn.pathID, isLastEndpoint: isLast) }
            drawingPathID = nil
            commit("Join Paths")
            selectAllNodes(inPath: targetPathID)
            return true
        }
        guard !checkOnly else { return false }
        if last.p.x == gp.x && last.p.y == gp.y { finishDrawing(); return true }
        var newID = UUID()
        mutateWorking { g in
            let nd = Node(gp)
            newID = nd.id
            g.paths[g.pathIndex(pathID)!].nodes.append(nd)
        }
        drag = .pen(pathID: pathID, nodeID: newID, start: gp)
        return true
    }

    /// A path left with just one node isn't discarded — it's kept and drawn as a dot (see
    /// `SkeletonGeometry.outlineWithTags`), for punctuation and diacritics (the dot on i/j, ".",
    /// ":", etc). Its size is the node's thickness ("outer"/⌘↑↓ or the thickness handle drag).
    ///
    /// Selects every node of the just-finished stroke — ready for an immediate group edit (⌫ to
    /// delete the whole thing, arrows to nudge it) without having to marquee it first; Esc clears
    /// it, Tab/⇧Tab step to the next/previous node as usual.
    func finishDrawing() {
        let pathID = drawingPathID
        drawingPathID = nil
        if working != nil { commit("Draw Path") }
        if let pathID { selectAllNodes(inPath: pathID) }
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
        guard editor.mode == .combo, drawingPathID == nil, let sel = selection else { return }
        let anchor = NodeRef(pathID: sel.pathID, nodeID: sel.nodeID)
        let refs = moveGroup(anchor: anchor)
        mutateWorking { g in
            for ref in refs { g.deleteNode(ref.pathID, ref.nodeID) }
        }
        selection = nil
        multiSelection = []
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
                guard let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last else { return }
                // Check close/join against the last node's *current* position first — arrow keys
                // may have nudged it onto the path's own start (close) or another path's endpoint
                // (join), the same targets a mouse click would detect there.
                if continuePath(pathID, toPx(last.p), last.p, checkOnly: true) { return }
                // Otherwise place a new node relative to the just-created one, not the mouse's
                // (possibly stale, or never-set) hover position — otherwise repeated presses
                // without moving the mouse all land on the same point and the path stalls after
                // one node (identical consecutive points make `continuePath` finish the stroke
                // instead of extending it).
                let step = flags.contains(.shift) ? min(editor.snapStep, 0.5) : editor.snapStep
                let gp = GridPoint(last.p.x + step, last.p.y)
                continuePath(pathID, toPx(gp), gp)
                // continuePath's default branch (plain "add a node") only sets up a .pen drag for
                // a mouse gesture to later commit on mouseUp; there's no such follow-up event from
                // the keyboard, so commit right away. A no-op if a branch (close/join/finish)
                // already committed internally.
                commit("Draw Path")
            } else if let sel = selection {
                let refs = moveGroup(anchor: NodeRef(pathID: sel.pathID, nodeID: sel.nodeID))
                mutateWorking { g in
                    for ref in refs { g.toggleNodeKind(ref.pathID, ref.nodeID) }
                }
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
            let step = editor.snapStep
            let dx = ddx * step, dy = ddy * step
            // Nothing selected and no stroke in progress: arrows move the "phantom" cursor
            // (`hover`, the same point the dashed preview line and Space's placement already use)
            // instead of nudging a node — so you can position where the next Space-placed node
            // will land using only the keyboard, the same way clicking there would.
            if currentEditableNode() == nil {
                let base = hover ?? GridPoint(0, 0)
                hover = GridPoint(base.x + dx, base.y + dy)
                needsDisplay = true
            } else if flags.contains(.shift), let t = currentEditableNode() {
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
    func currentEditableNode() -> (pathID: UUID, nodeID: UUID)? {
        if let pathID = drawingPathID, let pi = glyph.pathIndex(pathID), let last = glyph.paths[pi].nodes.last {
            return (pathID, last.id)
        }
        return selection
    }

    /// Nudge the selected node — or, with ⌥, one of its curve handles — one grid step (half a step
    /// with half-grid snap on). A handle with no position yet (nil, resting at the node) starts
    /// from the node itself. Uses `currentEditableNode()`, not the raw selection, so the node just
    /// placed by Space mid-stroke (where `selection` is stale) can be nudged onto a grid point
    /// without touching the mouse. Applies to the whole multi-selection if the node being nudged
    /// is part of one, same as a plain move.
    private func nudgeSelectedNode(dx: Double, dy: Double, handle: HandleKey?) {
        guard let sel = currentEditableNode() else { return }
        let anchor = NodeRef(pathID: sel.pathID, nodeID: sel.nodeID)
        let refs = moveGroup(anchor: anchor)
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
        let refs = moveGroup(anchor: NodeRef(pathID: pathID, nodeID: nodeID))
        mutateWorking { g in
            for ref in refs {
                g.withNode(ref.pathID, ref.nodeID) { nd in
                    nd.kind = .smooth
                    let baseOut = nd.cOut ?? nd.p
                    let baseIn = nd.cIn ?? nd.p
                    nd.cOut = snap(GridPoint(baseOut.x + dx, baseOut.y + dy), fine: false)
                    nd.cIn = snap(GridPoint(baseIn.x - dx, baseIn.y - dy), fine: false)
                }
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

    /// ⌥,/⌥./⌥;/⌥' — rotate or flip the selected node(s) as a rigid group, pivoting on the
    /// bounding-box center of their positions (a lone selected node pivots on itself, so only its
    /// own curve handles — skeleton and fill alike — turn or flip in place, not the node). Skeleton
    /// points (`p`, `cIn`, `cOut`) are absolute grid positions, so they transform around the pivot
    /// directly; a node's outer/inner fill-handle vectors are stored *relative* to it, so they
    /// transform as directions only, no pivot involved. Only the nodes actually selected move —
    /// an unselected neighbor sharing a segment with one keeps its own points where they are.
    func transformSelection(_ transform: NodeTransform) {
        guard let sel = selection else { return }
        let refs = moveGroup(anchor: NodeRef(pathID: sel.pathID, nodeID: sel.nodeID))
        guard !refs.isEmpty else { return }
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for ref in refs {
            guard let nd = glyph.node(ref.pathID, ref.nodeID) else { continue }
            minX = min(minX, nd.p.x); maxX = max(maxX, nd.p.x)
            minY = min(minY, nd.p.y); maxY = max(maxY, nd.p.y)
        }
        guard minX.isFinite else { return }
        let pivot = GridPoint((minX + maxX) / 2, (minY + maxY) / 2)
        func vec(_ v: GridPoint) -> GridPoint {
            switch transform {
            case .rotateCCW: return GridPoint(-v.y, v.x)
            case .rotateCW: return GridPoint(v.y, -v.x)
            case .flipHorizontal: return GridPoint(-v.x, v.y)
            case .flipVertical: return GridPoint(v.x, -v.y)
            }
        }
        func point(_ p: GridPoint) -> GridPoint {
            let d = vec(GridPoint(p.x - pivot.x, p.y - pivot.y))
            return GridPoint(pivot.x + d.x, pivot.y + d.y)
        }
        mutateWorking { g in
            for ref in refs {
                g.withNode(ref.pathID, ref.nodeID) { nd in
                    nd.p = point(nd.p)
                    if let c = nd.cIn { nd.cIn = point(c) }
                    if let c = nd.cOut { nd.cOut = point(c) }
                    if var fh = nd.outer {
                        fh.offset = vec(fh.offset)
                        if let c = fh.cIn { fh.cIn = vec(c) }
                        if let c = fh.cOut { fh.cOut = vec(c) }
                        nd.outer = fh
                    }
                    if var fh = nd.inner {
                        fh.offset = vec(fh.offset)
                        if let c = fh.cIn { fh.cIn = vec(c) }
                        if let c = fh.cOut { fh.cOut = vec(c) }
                        nd.inner = fh
                    }
                }
            }
        }
        commit("Transform Selection")
    }
}

/// Rigid transforms `transformSelection` can apply to the selected node(s).
enum NodeTransform { case rotateCCW, rotateCW, flipHorizontal, flipVertical }
