import AppKit

/// Combo mode merges Skeleton (pen/curve) and Thicken (fill-handle) controls into one tool.
/// Node hit-testing takes priority over fill handles — a handle can sit exactly on top of its
/// node (e.g. a zero-offset fill point sits right at the node), and without this a click there
/// could only ever grab the handle, never the node underneath it.
extension GlyphCanvasView {
    func comboDown(_ event: NSEvent, _ px: CGPoint) {
        if event.clickCount < 2, drawingPathID == nil {
            let flags = event.modifierFlags
            if flags.contains(.control) {
                // ⌃-drag directly on a node starts an anchor drag — drop it on a fill handle (of a
                // *different* node) to pin it there, or anywhere else to move it plainly and clear
                // any existing anchor. Takes priority over the traditional-right-click substitute
                // below, so ⌃-clicking a node still means "anchor this node".
                if let hn = hitNode(px) {
                    selection = (hn.pathID, hn.nodeID)
                    multiSelection = []
                    drag = .anchorNode(pathID: hn.pathID, nodeID: hn.nodeID)
                    return
                }
                // Traditional macOS "hold ⌃ for a right click" substitute for everything else.
                drag = .rightClick(start: px)
                return
            }
            if hitNode(px) == nil, let th = hitThickness(px) {
                selection = (th.pathID, th.node.id)
                multiSelection = []
                drag = .fillHandle(pathID: th.pathID, nodeID: th.node.id, side: th.side)
                return
            }
        }
        skeletonDown(event, px)
    }

    /// Finishes a ⌃-drag on a node: anchor it to whatever thickness handle (of a different node)
    /// it was dropped on, or clear any existing anchor if it wasn't dropped on one.
    func finishAnchorDrag(_ pathID: UUID, _ nodeID: UUID, at px: CGPoint) {
        var target: ThicknessHandle?
        outer: for path in glyph.paths {
            for th in thicknessHandles(path) where th.node.id != nodeID {
                if dist(toPx(th.pos), px) < hitRadius { target = th; break outer }
            }
        }
        mutateWorking { g in
            g.withNode(pathID, nodeID) { nd in
                nd.anchor = target.map { NodeAnchor(targetNodeID: $0.node.id, side: $0.side) }
            }
        }
    }

    /// A right-click (or ⌃-click) that ends without dragging: copy-and-deselect if something was
    /// selected, otherwise paste near the pointer (selected, ready to drag with a plain click) —
    /// same idea as `Get-Clipboard`-free copy/paste-on-click in a Windows terminal.
    func finishRightClickTap(at px: CGPoint) {
        if selection != nil || !multiSelection.isEmpty {
            copySelection()
            selection = nil
            multiSelection = []
            needsDisplay = true
        } else {
            pasteSelection(near: px)
        }
    }

    /// ⌘ combos layer fill-handle/advance-width control on top of every Skeleton keyboard command
    /// (space, arrows, esc, ⌫, tab…), which all still work unmodified.
    func comboKeyDown(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        // ⇧Enter (mark complete) and ⌥Tab/⇧⌥Tab (cycle mode) are global now — handled by
        // window-wide buttons so they work regardless of focus, not here.
        if flags.contains(.command) {
            switch event.keyCode {
            case KeyCode.up, KeyCode.down, KeyCode.left, KeyCode.right:
                fillHandleKeyDown(event, flags)
                return
            case KeyCode.backspace, KeyCode.forwardDelete:
                zeroFillHandle(flags)
                return
            case KeyCode.enter:
                resetFillHandle(flags)
                return
            default: break
            }
            switch event.charactersIgnoringModifiers {
            case "[": adjustAdvanceWidth(-1); return
            case "]": adjustAdvanceWidth(1); return
            default: break
            }
        }
        // ⌥,/⌥./⌥;/⌥' rotate/flip the selected node(s) — `charactersIgnoringModifiers` reports the
        // base key regardless of ⌥ (which would otherwise produce a special character on most
        // layouts), same as the ⌘[/⌘] combo above.
        if flags.contains(.option), !flags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case ",": transformSelection(.rotateCCW); return
            case ".": transformSelection(.rotateCW); return
            case ";": transformSelection(.flipHorizontal); return
            case "'": transformSelection(.flipVertical); return
            default: break
            }
        }
        skeletonKeyDown(event, flags)
    }
}
