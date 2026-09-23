import Foundation

/// Small mutation helpers for editing a `Glyph`'s paths by node/path id, shared by the editor's
/// pen, thicken and hint tools.
extension Glyph {
    func pathIndex(_ id: UUID) -> Int? { paths.firstIndex { $0.id == id } }
    func nodeIndex(_ pathID: UUID, _ nodeID: UUID) -> Int? { pathIndex(pathID).flatMap { paths[$0].nodes.firstIndex { $0.id == nodeID } } }
    func node(_ pathID: UUID, _ nodeID: UUID) -> Node? {
        guard let pi = pathIndex(pathID), let ni = nodeIndex(pathID, nodeID) else { return nil }
        return paths[pi].nodes[ni]
    }

    /// Finds a node by id alone, searching every path — an anchor's target can be in any stroke
    /// of the same glyph, not necessarily the anchored node's own path.
    func findNode(_ nodeID: UUID) -> (path: SkeletonPath, index: Int)? {
        for path in paths {
            if let i = path.nodes.firstIndex(where: { $0.id == nodeID }) { return (path, i) }
        }
        return nil
    }

    /// Replaces every anchored node's position with its target's current thickness-edge position
    /// at `weight` — anchors track that edge live rather than storing a fixed offset. Resolved in
    /// a few passes (not recursively) so a short chain of anchors settles; a cycle just stops
    /// changing after the pass limit rather than looping forever.
    func resolvingAnchors(weight: Double) -> Glyph {
        var g = self
        for _ in 0..<4 {
            var changed = false
            for pi in g.paths.indices {
                for ni in g.paths[pi].nodes.indices {
                    guard let anchor = g.paths[pi].nodes[ni].anchor,
                          let (targetPath, targetIndex) = g.findNode(anchor.targetNodeID) else { continue }
                    let edge = SkeletonGeometry.thicknessEdge(of: targetPath.nodes[targetIndex], path: targetPath, index: targetIndex, side: anchor.side, weight: weight)
                    if g.paths[pi].nodes[ni].p != edge {
                        g.paths[pi].nodes[ni].p = edge
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return g
    }

    mutating func withNode(_ pathID: UUID, _ nodeID: UUID, _ body: (inout Node) -> Void) {
        guard let pi = pathIndex(pathID), let ni = nodeIndex(pathID, nodeID) else { return }
        body(&paths[pi].nodes[ni])
    }

    /// Deleting a node down to one remaining leaves that node as a dot (see
    /// `SkeletonGeometry.outlineWithTags`) rather than discarding it — only an empty path is removed.
    mutating func deleteNode(_ pathID: UUID, _ nodeID: UUID) {
        guard let pi = pathIndex(pathID) else { return }
        paths[pi].nodes.removeAll { $0.id == nodeID }
        hints[nodeID] = nil
        if paths[pi].nodes.isEmpty { paths.remove(at: pi) }
    }

    /// Split segment `index` of the path at parameter `t` without changing the shape
    /// (de Casteljau split for curves; simple lerp for lines), inserting a new node.
    /// Returns the new node's id.
    @discardableResult
    mutating func insertNode(pathID: UUID, index: Int, t: Double, isLine: Bool) -> UUID {
        guard let pi = pathIndex(pathID) else { return UUID() }
        let n = paths[pi].nodes
        let a = n[index], b = n[(index + 1) % n.count]
        var newNode: Node
        if isLine {
            let p = GridPoint(a.p.x + (b.p.x - a.p.x) * t, a.p.y + (b.p.y - a.p.y) * t)
            newNode = Node(GridPoint((p.x * 4).rounded() / 4, (p.y * 4).rounded() / 4))
        } else {
            func lerp(_ u: GridPoint, _ v: GridPoint) -> GridPoint { GridPoint(u.x + (v.x - u.x) * t, u.y + (v.y - u.y) * t) }
            let p0 = a.p, p1 = a.cOut ?? a.p, p2 = b.cIn ?? b.p, p3 = b.p
            let q0 = lerp(p0, p1), q1 = lerp(p1, p2), q2 = lerp(p2, p3)
            let r0 = lerp(q0, q1), r1 = lerp(q1, q2), m = lerp(r0, r1)
            newNode = Node(m, kind: .smooth, cIn: r0, cOut: r1)
            paths[pi].nodes[index].cOut = q0
            paths[pi].nodes[(index + 1) % n.count].cIn = q2
        }
        paths[pi].nodes.insert(newNode, at: index + 1)
        return newNode.id
    }

    /// Toggle a node between corner (straight, square) and smooth (curved, circle): smoothing
    /// grows symmetric tangent handles from the neighboring nodes; going back to corner clears
    /// them — and also the *neighbors'* handles on those same shared segments. Clearing only this
    /// node's own cIn/cOut isn't enough to make a segment straight (a segment is a line only when
    /// *both* its endpoints have no handle); leaving the neighbor's handle in place keeps the
    /// segment curved but with a degenerate endpoint control point, which visibly distorts the
    /// curve and throws off the tangent used to orient a terminal's cap/thickness handles.
    mutating func toggleNodeKind(_ pathID: UUID, _ nodeID: UUID) {
        guard let pi = pathIndex(pathID), let ni = nodeIndex(pathID, nodeID) else { return }
        let n = paths[pi].nodes, closed = paths[pi].closed
        let prevIndex: Int? = (closed || ni > 0) ? (ni - 1 + n.count) % n.count : nil
        let nextIndex: Int? = (closed || ni < n.count - 1) ? (ni + 1) % n.count : nil
        var nd = n[ni]
        if nd.kind == .corner {
            nd.kind = .smooth
            let prev = prevIndex.map { n[$0] }
            let next = nextIndex.map { n[$0] }
            let dir: GridPoint
            switch (prev, next) {
            case let (.some(p), .some(q)): dir = GridPoint(q.p.x - p.p.x, q.p.y - p.p.y).normalized
            case let (.none, .some(q)): dir = GridPoint(q.p.x - nd.p.x, q.p.y - nd.p.y).normalized
            case let (.some(p), .none): dir = GridPoint(nd.p.x - p.p.x, nd.p.y - p.p.y).normalized
            default: dir = GridPoint(1, 0)
            }
            let len = 1.5
            nd.cOut = GridPoint(nd.p.x + dir.x * len, nd.p.y + dir.y * len)
            nd.cIn = GridPoint(nd.p.x - dir.x * len, nd.p.y - dir.y * len)
        } else {
            nd.kind = .corner
            nd.cIn = nil
            nd.cOut = nil
            if let pi2 = prevIndex { paths[pi].nodes[pi2].cOut = nil }
            if let ni2 = nextIndex { paths[pi].nodes[ni2].cIn = nil }
        }
        // Either direction reshapes the segments touching this node, so any explicit fill handle
        // here is reset back to automatic — it would otherwise keep following the *old* curve
        // shape instead of the new one.
        nd.outer = nil
        nd.inner = nil
        paths[pi].nodes[ni] = nd
    }

    /// Whether `nodeID` is the first or last node of its (open) path — nil if it's not an
    /// endpoint at all (a closed path, or a node in the middle).
    func endpointIsLast(_ pathID: UUID, _ nodeID: UUID) -> Bool? {
        guard let pi = pathIndex(pathID), !paths[pi].closed, !paths[pi].nodes.isEmpty else { return nil }
        if paths[pi].nodes.last?.id == nodeID { return true }
        if paths[pi].nodes.first?.id == nodeID { return false }
        return nil
    }

    /// Merge the in-progress `drawingPathID` onto an endpoint of an existing path, so drawing a
    /// new line up to another line's end just extends it instead of leaving two separate paths.
    mutating func joinDrawingPath(_ drawingPathID: UUID, intoEndpointOf targetPathID: UUID, isLastEndpoint: Bool) {
        guard let dpi = pathIndex(drawingPathID), let tpi = pathIndex(targetPathID), dpi != tpi else { return }
        let drawingNodes = paths[dpi].nodes
        if isLastEndpoint {
            paths[tpi].nodes.append(contentsOf: drawingNodes.reversed())
        } else {
            paths[tpi].nodes.insert(contentsOf: drawingNodes, at: 0)
        }
        paths.removeAll { $0.id == drawingPathID }
    }
}
