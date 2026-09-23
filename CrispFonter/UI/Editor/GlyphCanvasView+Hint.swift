import AppKit

extension GlyphCanvasView {
    func hintDown(_ event: NSEvent, _ px: CGPoint) {
        if let hn = hitNode(px) {
            selection = (hn.pathID, hn.nodeID)
            drag = .hint(pathID: hn.pathID, nodeID: hn.nodeID, index: hn.index, start: px, was: glyph.hints[hn.nodeID], inserted: false, moved: false)
            return
        }
        guard let hs = hitSegment(px) else { return }
        var newID = UUID()
        let mode = hintNearestMode()
        mutateWorking { g in
            newID = g.insertNode(pathID: hs.pathID, index: hs.index, t: hs.t, isLine: hs.isLine)
            guard let pi = g.pathIndex(hs.pathID), let ni = g.nodeIndex(hs.pathID, newID) else { return }
            g.hints[newID] = Hinting.defaultHint(g.paths[pi], ni, mode: mode)
        }
        selection = (hs.pathID, newID)
        editor.hintMessage = "Node inserted on the stroke and hinted — drag it to push toward a pixel edge"
        drag = .hint(pathID: hs.pathID, nodeID: newID, index: 0, start: px, was: nil, inserted: true, moved: false)
    }

    /// Whether the "nearest"-setting hint actions (cycle, ⇧-axis set, ⇧-drag, segment-insert) use
    /// round-outward instead of round-nearest right now — read live at the moment of the action, so
    /// holding ⌥ through a click/drag/keypress is all it takes, no separate mode toggle needed.
    private func hintNearestMode() -> SnapMode { NSEvent.modifierFlags.contains(.option) ? .outward : .nearest }

    /// Click or Space cycles the selected node's hint through nearest (both axes) → vertical-only
    /// → horizontal-only → none; arrow keys (or dragging the point, identically) set a push
    /// direction per axis, held/moved together for diagonals; backspace clears it. ⇧ variants set
    /// a specific axis to nearest directly instead: ⇧←/→ horizontal, ⇧↑/↓ vertical, ⇧space both.
    /// Holding ⌥ on any of the "nearest"-setting actions (cycle, ⇧-axis-set, ⇧-drag) uses
    /// round-outward instead — don't hold it for plain round-nearest.
    func hintKeyDown(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        switch event.keyCode {
        case KeyCode.space:
            if flags.contains(.shift) { setAxisHint(x: true, y: true) } else { cycleHintTypeForSelection() }
        case KeyCode.backspace, KeyCode.forwardDelete: removeSelectedHint()
        case KeyCode.left, KeyCode.right:
            if flags.contains(.shift) { setAxisHint(x: true, y: false) } else { setDirectionalHintFromHeldArrows() }
        case KeyCode.up, KeyCode.down:
            if flags.contains(.shift) { setAxisHint(x: false, y: true) } else { setDirectionalHintFromHeldArrows() }
        case KeyCode.esc:
            selection = nil
            needsDisplay = true
        default: break
        }
    }

    /// ⇧←/→/↑/↓/space: sets that axis (or both, for space) to nearest (or outward, with ⌥)
    /// directly, leaving the other axis as it was — a quick, non-cycling way to reach the common case.
    private func setAxisHint(x: Bool, y: Bool) {
        guard let sel = selection else { return }
        let mode = hintNearestMode()
        mutateWorking { g in
            var h = g.hints[sel.nodeID] ?? HintPoint(x: nil, y: nil)
            if x { h.x = mode }
            if y { h.y = mode }
            g.hints[sel.nodeID] = h
        }
        commit("Set Hint Axis")
    }

    private func cycleHintTypeForSelection() {
        guard let sel = selection, let idx = glyph.nodeIndex(sel.pathID, sel.nodeID) else { return }
        cycleHintType(pathID: sel.pathID, nodeID: sel.nodeID, index: idx)
    }

    /// Cycles nearest/outward(x&y) → vertical-only → horizontal-only → none → …, by which axes are
    /// *set* rather than their exact mode — so a directional push (or a mix of nearest/outward from
    /// switching whether ⌥ was held between clicks) still advances through the same four stages
    /// instead of falling through to "none".
    private func cycleHintType(pathID: UUID, nodeID: UUID, index: Int) {
        let mode = hintNearestMode()
        mutateWorking { g in
            guard let pi = g.pathIndex(pathID) else { return }
            let cur = g.hints[nodeID]
            let next: HintPoint?
            switch (cur?.x != nil, cur?.y != nil) {
            case (false, false): next = Hinting.defaultHint(g.paths[pi], index, mode: mode)
            case (true, true): next = HintPoint(x: nil, y: mode)
            case (false, true): next = HintPoint(x: mode, y: nil)
            case (true, false): next = nil
            }
            g.hints[nodeID] = next
        }
        commit("Cycle Hint Type")
    }

    private func removeSelectedHint() {
        guard let sel = selection else { return }
        mutateWorking { g in g.hints[sel.nodeID] = nil }
        commit("Remove Hint")
    }

    private func setDirectionalHintFromHeldArrows() {
        guard let sel = selection else { return }
        var h = HintPoint(x: nil, y: nil)
        if heldArrowKeys.contains("right") { h.x = .positive } else if heldArrowKeys.contains("left") { h.x = .negative }
        if heldArrowKeys.contains("up") { h.y = .positive } else if heldArrowKeys.contains("down") { h.y = .negative }
        guard h.x != nil || h.y != nil else { return }
        mutateWorking { g in g.hints[sel.nodeID] = h }
        commit("Directional Hint")
    }

    /// Dragging a hint point sets the same directional push as holding arrow keys would — sign of
    /// the drag per axis, both axes independently for diagonals — just driven by the mouse instead.
    /// ⇧-drag instead sets *only* whichever axis dominates the drag direction to nearest, matching
    /// ⇧←/→/↑/↓'s "set that axis" commands but picked by direction instead of by key.
    func dragHint(_ pathID: UUID, _ nodeID: UUID, _ index: Int, _ start: CGPoint, _ was: HintPoint?, _ inserted: Bool, _ px: CGPoint) {
        let dx = Double(px.x - start.x), dy = Double(-(px.y - start.y))
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 12 else { return }
        if case .hint(let p, let n, let i, let s, let w, let ins, _) = drag {
            drag = .hint(pathID: p, nodeID: n, index: i, start: s, was: w, inserted: ins, moved: true)
        }
        if NSEvent.modifierFlags.contains(.shift) {
            let mode = hintNearestMode()
            var h = glyph.hints[nodeID] ?? HintPoint(x: nil, y: nil)
            if abs(dx) >= abs(dy) { h.x = mode } else { h.y = mode }
            mutateWorking { g in g.hints[nodeID] = h }
        } else {
            var h = HintPoint(x: nil, y: nil)
            if dx > 0 { h.x = .positive } else if dx < 0 { h.x = .negative }
            if dy > 0 { h.y = .positive } else if dy < 0 { h.y = .negative }
            mutateWorking { g in g.hints[nodeID] = h }
        }
        editor.hintMessage = hintPushMessage(glyph.hints[nodeID])
    }

    /// A plain click (no real drag) on an existing, un-inserted node cycles its hint type instead.
    func finishHintClick(_ pathID: UUID, _ nodeID: UUID, _ index: Int, _ was: HintPoint?) {
        cycleHintType(pathID: pathID, nodeID: nodeID, index: index)
    }

    private func hintPushMessage(_ h: HintPoint?) -> String {
        guard let h else { return "" }
        var parts: [String] = []
        if h.x == .positive { parts.append("right") } else if h.x == .negative { parts.append("left") }
        if h.y == .positive { parts.append("up") } else if h.y == .negative { parts.append("down") }
        return "Push " + (parts.isEmpty ? "—" : parts.joined(separator: " + "))
    }
}
