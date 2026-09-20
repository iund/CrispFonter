import AppKit

/// The Hint-mode right-click context menu: exact horizontal/vertical snap settings, remove hint, delete node.
extension GlyphCanvasView {
    func hideHintMenu() { menu?.cancelTracking() }

    func showHintMenu(for hit: NodeHit, at event: NSEvent) {
        let cur = glyph.hints[hit.nodeID] ?? HintPoint(x: nil, y: nil)
        let m = NSMenu()
        m.addItem(header("Horizontal (x)"))
        m.addItem(hintItem("Off", cur.x == nil) { self.setHint(hit, axis: \.x, mode: nil) })
        m.addItem(hintItem("Nearest pixel edge", cur.x == .nearest) { self.setHint(hit, axis: \.x, mode: .nearest) })
        m.addItem(hintItem("Push left", cur.x == .negative) { self.setHint(hit, axis: \.x, mode: .negative) })
        m.addItem(hintItem("Push right", cur.x == .positive) { self.setHint(hit, axis: \.x, mode: .positive) })
        m.addItem(.separator())
        m.addItem(header("Vertical (y)"))
        m.addItem(hintItem("Off", cur.y == nil) { self.setHint(hit, axis: \.y, mode: nil) })
        m.addItem(hintItem("Nearest pixel edge", cur.y == .nearest) { self.setHint(hit, axis: \.y, mode: .nearest) })
        m.addItem(hintItem("Push down", cur.y == .negative) { self.setHint(hit, axis: \.y, mode: .negative) })
        m.addItem(hintItem("Push up", cur.y == .positive) { self.setHint(hit, axis: \.y, mode: .positive) })
        m.addItem(.separator())
        m.addItem(actionItem("Remove hint") { self.removeHint(hit) })
        m.addItem(actionItem("Delete node") { self.deleteNode(hit) })
        self.menu = m
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func hintItem(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action)
        item.state = on ? .on : .off
        return item
    }
    private func actionItem(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, action)
    }

    private func setHint(_ hit: NodeHit, axis: WritableKeyPath<HintPoint, SnapMode?>, mode: SnapMode?) {
        mutateWorking { g in
            var h = g.hints[hit.nodeID] ?? HintPoint(x: nil, y: nil)
            h[keyPath: axis] = mode
            g.hints[hit.nodeID] = (h.x == nil && h.y == nil) ? nil : h
        }
        commit("Hint")
    }
    private func removeHint(_ hit: NodeHit) {
        mutateWorking { g in g.hints[hit.nodeID] = nil }
        commit("Remove Hint")
    }
    private func deleteNode(_ hit: NodeHit) {
        mutateWorking { g in g.deleteNode(hit.pathID, hit.nodeID) }
        commit("Delete Node")
    }
}

/// A tiny NSMenuItem subclass that runs a closure instead of needing a target/selector.
final class ClosureMenuItem: NSMenuItem {
    private let onSelect: () -> Void
    init(title: String, _ onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { onSelect() }
}
