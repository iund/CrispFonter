import AppKit

extension GlyphCanvasView {
    func hintDown(_ event: NSEvent, _ px: CGPoint) {
        hideHintMenu()
        if let hn = hitNode(px) {
            if event.modifierFlags.contains(.option) {
                mutateWorking { g in
                    guard let pi = g.pathIndex(hn.pathID) else { return }
                    g.hints[hn.nodeID] = Hinting.defaultHint(g.paths[pi], hn.index)
                }
                editor.hintMessage = "Reset to nearest"
                commit("Reset Hint")
                return
            }
            drag = .hint(pathID: hn.pathID, nodeID: hn.nodeID, index: hn.index, start: px, was: glyph.hints[hn.nodeID], inserted: false, moved: false)
            return
        }
        guard let hs = hitSegment(px) else { return }
        var newID = UUID()
        mutateWorking { g in
            newID = g.insertNode(pathID: hs.pathID, index: hs.index, t: hs.t, isLine: hs.isLine)
            guard let pi = g.pathIndex(hs.pathID), let ni = g.nodeIndex(hs.pathID, newID) else { return }
            g.hints[newID] = Hinting.defaultHint(g.paths[pi], ni)
        }
        editor.hintMessage = "Node inserted on the stroke and hinted — drag it to push toward a pixel edge"
        drag = .hint(pathID: hs.pathID, nodeID: newID, index: 0, start: px, was: nil, inserted: true, moved: false)
    }

    func dragHint(_ pathID: UUID, _ nodeID: UUID, _ index: Int, _ start: CGPoint, _ was: HintPoint?, _ inserted: Bool, _ px: CGPoint) {
        let dx = Double(px.x - start.x), dy = Double(-(px.y - start.y))
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 12 else { return }
        if case .hint(let p, let n, let i, let s, let w, let ins, _) = drag {
            drag = .hint(pathID: p, nodeID: n, index: i, start: s, was: w, inserted: ins, moved: true)
        }
        mutateWorking { g in
            guard let pi = g.pathIndex(pathID) else { return }
            var h = was ?? Hinting.defaultHint(g.paths[pi], index)
            if abs(dx) > 0.4 * distance { h.x = dx > 0 ? .positive : .negative }
            if abs(dy) > 0.4 * distance { h.y = dy > 0 ? .positive : .negative }
            g.hints[nodeID] = h
        }
        editor.hintMessage = hintPushMessage(glyph.hints[nodeID])
    }

    func finishHintClick(_ pathID: UUID, _ nodeID: UUID, _ index: Int, _ was: HintPoint?) {
        mutateWorking { g in
            guard let pi = g.pathIndex(pathID) else { return }
            if was != nil {
                g.hints[nodeID] = nil
                editor.hintMessage = "Hint removed"
            } else {
                g.hints[nodeID] = Hinting.defaultHint(g.paths[pi], index)
                editor.hintMessage = "Hint added (nearest pixel edge) — drag to push it up/down/left/right, right-click for options"
            }
        }
    }

    private func hintPushMessage(_ h: HintPoint?) -> String {
        guard let h else { return "" }
        var parts: [String] = []
        if h.x == .positive { parts.append("right") } else if h.x == .negative { parts.append("left") }
        if h.y == .positive { parts.append("up") } else if h.y == .negative { parts.append("down") }
        return "Push " + (parts.isEmpty ? "—" : parts.joined(separator: " + ")) + "  ·  ⌥-click resets to nearest"
    }
}
