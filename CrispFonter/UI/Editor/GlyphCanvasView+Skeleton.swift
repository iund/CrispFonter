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
            selection = (hn.pathID, hn.nodeID)
            drag = .moveNode(pathID: hn.pathID, nodeID: hn.nodeID)
            needsDisplay = true
            return
        }
        startPath(at: gp)
    }

    func handleDoubleClick(_ event: NSEvent, _ px: CGPoint) {
        if drawingPathID != nil { finishDrawing(); return }
        if editor.mode == .thicken { thickenDoubleClick(px) }
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

    func deleteSelection() {
        guard editor.mode == .skeleton, drawingPathID == nil, let sel = selection else { return }
        mutateWorking { g in g.deleteNode(sel.pathID, sel.nodeID) }
        selection = nil
        commit("Delete Node")
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

    func dragMoveNode(_ pathID: UUID, _ nodeID: UUID, _ gp: GridPoint) {
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                let dx = gp.x - nd.p.x, dy = gp.y - nd.p.y
                nd.p = gp
                if let c = nd.cIn { nd.cIn = GridPoint(c.x + dx, c.y + dy) }
                if let c = nd.cOut { nd.cOut = GridPoint(c.x + dx, c.y + dy) }
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
