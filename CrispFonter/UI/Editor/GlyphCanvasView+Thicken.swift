import AppKit

extension GlyphCanvasView {
    func thickenDown(_ event: NSEvent, _ px: CGPoint) {
        if event.clickCount >= 2 { handleDoubleClick(event, px); return }
        if let ch = hitCap(px) {
            drag = .cap(pathID: ch.pathID, nodeID: ch.node.id, out: ch.out)
        } else if let th = hitThickness(px) {
            if event.modifierFlags.contains(.option) {
                drag = .angle(pathID: th.pathID, nodeID: th.node.id, dir0: th.dir0)
            } else {
                drag = .thickness(pathID: th.pathID, nodeID: th.node.id, side: th.side, dir: th.dir, both: event.modifierFlags.contains(.command))
            }
        }
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
                var deg = atan2(dir0.x * v.y - dir0.y * v.x, dir0.x * v.x + dir0.y * v.y) * 180 / .pi
                deg = (deg / 15).rounded() * 15
                nd.angle = max(-75, min(75, deg))
            }
        }
    }

    func dragCap(_ pathID: UUID, _ nodeID: UUID, _ out: GridPoint, _ raw: GridPoint) {
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                let v = GridPoint(raw.x - nd.p.x, raw.y - nd.p.y)
                nd.cap = max(0, ((v.x * out.x + v.y * out.y) * 4).rounded() / 4)
            }
        }
    }
}
