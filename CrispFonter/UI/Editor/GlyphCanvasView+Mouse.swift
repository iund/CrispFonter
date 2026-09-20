import AppKit

extension GlyphCanvasView {
    func evPos(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let px = evPos(event)
        switch editor.mode {
        case .skeleton: skeletonDown(event, px)
        case .thicken: thickenDown(event, px)
        case .hint: hintDown(event, px)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let px = evPos(event)
        let raw = toGrid(px)
        let gp = snap(raw, fine: event.modifierFlags.contains(.shift))
        hover = gp
        editor.cursorPosText = "(\(fmt(gp.x)), \(fmt(gp.y)))"
        guard let d = drag else { needsDisplay = true; return }
        switch d {
        case .pen(let pathID, let nodeID, let start): dragPen(pathID, nodeID, start, gp, alt: event.modifierFlags.contains(.option))
        case .moveNode(let pathID, let nodeID): dragMoveNode(pathID, nodeID, gp)
        case .handle(let pathID, let nodeID, let key, let alt): dragHandle(pathID, nodeID, key, gp, alt: alt)
        case .thickness(let pathID, let nodeID, let side, let dir, let both): dragThickness(pathID, nodeID, side, dir, both, raw)
        case .angle(let pathID, let nodeID, let dir0): dragAngle(pathID, nodeID, dir0, raw)
        case .cap(let pathID, let nodeID, let out): dragCap(pathID, nodeID, out, raw)
        case .hint(let pathID, let nodeID, let index, let start, let was, let inserted, _):
            dragHint(pathID, nodeID, index, start, was, inserted, px)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        if case .hint(let pathID, let nodeID, let index, _, let was, let inserted, let moved) = drag, !moved, !inserted {
            finishHintClick(pathID, nodeID, index, was)
        }
        if working != nil { commit(actionName(for: drag)) } else { needsDisplay = true }
    }

    override func mouseMoved(with event: NSEvent) {
        let gp = snap(toGrid(evPos(event)), fine: event.modifierFlags.contains(.shift))
        hover = gp
        editor.cursorPosText = "(\(fmt(gp.x)), \(fmt(gp.y)))"
        if drawingPathID != nil { needsDisplay = true }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard editor.mode == .hint, let hit = hitNode(evPos(event)) else { return }
        showHintMenu(for: hit, at: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "1": editor.setMode(.skeleton)
        case "2": editor.setMode(.thicken)
        case "3": editor.setMode(.hint)
        case String(UnicodeScalar(NSEvent.SpecialKey.enter.rawValue)!), "\r", "\u{1b}":
            finishDrawing()
        default: break
        }
        if event.keyCode == 51 || event.keyCode == 117 { // backspace / delete
            deleteSelection()
        }
    }

    private func actionName(for drag: Drag?) -> String {
        guard let drag else { return "Edit" }
        switch drag {
        case .pen: return "Draw"
        case .moveNode: return "Move Node"
        case .handle: return "Adjust Curve"
        case .thickness: return "Thickness"
        case .angle: return "Rotate Terminal"
        case .cap: return "Cap"
        case .hint: return "Hint"
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
