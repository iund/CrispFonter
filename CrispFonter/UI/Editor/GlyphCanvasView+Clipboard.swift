import AppKit

private let pathsPasteboardType = NSPasteboard.PasteboardType("com.crispfonter.paths")

/// Cut/copy/paste whole strokes (paths) via the system clipboard — not individual loose nodes,
/// since a node doesn't mean much detached from its path. Going through `NSPasteboard.general`
/// (rather than some in-app buffer) is what makes this work *between* glyphs and even between
/// separate open documents/windows, not just within the current canvas.
extension GlyphCanvasView {
    private func selectedPathIDs() -> Set<UUID> {
        if !multiSelection.isEmpty { return Set(multiSelection.map { $0.pathID }) }
        if let sel = selection { return [sel.pathID] }
        return []
    }

    @discardableResult
    func copySelection() -> Bool {
        let ids = selectedPathIDs()
        guard !ids.isEmpty else { return false }
        let paths = glyph.paths.filter { ids.contains($0.id) }
        guard let data = try? JSONEncoder().encode(paths) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: pathsPasteboardType)
        return true
    }

    @discardableResult
    func cutSelection() -> Bool {
        let ids = selectedPathIDs()
        guard copySelection() else { return false }
        mutateWorking { g in
            for path in g.paths where ids.contains(path.id) {
                for nd in path.nodes { g.hints[nd.id] = nil }
            }
            g.paths.removeAll { ids.contains($0.id) }
        }
        selection = nil
        multiSelection = []
        commit("Cut Strokes")
        return true
    }

    /// Pasted paths get fresh node/path ids (so pasting back into the *same* glyph doesn't
    /// collide with the originals) and land selected as a group, ready to drag or arrow-nudge into
    /// place. With `near`, the pasted group is also shifted so its centroid lands at that point
    /// (view pixels) — used by the right-click paste-near-pointer gesture; ⌘V (no `near`) keeps
    /// the copied position as-is.
    @discardableResult
    func pasteSelection(near px: CGPoint? = nil) -> Bool {
        guard let data = NSPasteboard.general.data(forType: pathsPasteboardType),
              var paths = try? JSONDecoder().decode([SkeletonPath].self, from: data), !paths.isEmpty else { return false }
        if let px {
            let pts = paths.flatMap { $0.nodes.map(\.p) }
            let centroid = GridPoint(pts.map(\.x).reduce(0, +) / Double(pts.count), pts.map(\.y).reduce(0, +) / Double(pts.count))
            let target = toGrid(px)
            let dx = target.x - centroid.x, dy = target.y - centroid.y
            for i in paths.indices {
                for j in paths[i].nodes.indices {
                    paths[i].nodes[j].p = GridPoint(paths[i].nodes[j].p.x + dx, paths[i].nodes[j].p.y + dy)
                    if let c = paths[i].nodes[j].cIn { paths[i].nodes[j].cIn = GridPoint(c.x + dx, c.y + dy) }
                    if let c = paths[i].nodes[j].cOut { paths[i].nodes[j].cOut = GridPoint(c.x + dx, c.y + dy) }
                }
            }
        }
        var refs: Set<NodeRef> = []
        for i in paths.indices {
            paths[i].id = UUID()
            for j in paths[i].nodes.indices { paths[i].nodes[j].id = UUID() }
            for nd in paths[i].nodes { refs.insert(NodeRef(pathID: paths[i].id, nodeID: nd.id)) }
        }
        mutateWorking { g in g.paths.append(contentsOf: paths) }
        multiSelection = refs.count > 1 ? refs : []
        selection = refs.first.map { ($0.pathID, $0.nodeID) }
        commit("Paste Strokes")
        return true
    }
}
