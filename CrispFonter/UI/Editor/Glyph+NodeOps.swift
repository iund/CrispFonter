import Foundation

/// Small mutation helpers for editing a `Glyph`'s paths by node/path id, shared by the editor's
/// pen, thicken and hint tools.
extension Glyph {
    func pathIndex(_ id: UUID) -> Int? { paths.firstIndex { $0.id == id } }
    func nodeIndex(_ pathID: UUID, _ nodeID: UUID) -> Int? { pathIndex(pathID).flatMap { paths[$0].nodes.firstIndex { $0.id == nodeID } } }

    mutating func withNode(_ pathID: UUID, _ nodeID: UUID, _ body: (inout Node) -> Void) {
        guard let pi = pathIndex(pathID), let ni = nodeIndex(pathID, nodeID) else { return }
        body(&paths[pi].nodes[ni])
    }

    mutating func deleteNode(_ pathID: UUID, _ nodeID: UUID) {
        guard let pi = pathIndex(pathID) else { return }
        paths[pi].nodes.removeAll { $0.id == nodeID }
        hints[nodeID] = nil
        if paths[pi].nodes.count < 2 { paths.remove(at: pi) }
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
}
