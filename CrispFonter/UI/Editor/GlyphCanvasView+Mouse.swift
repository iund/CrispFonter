import AppKit

extension GlyphCanvasView {
    func evPos(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let px = evPos(event)
        CrashLogger.breadcrumb("mouseDown mode=\(editor.mode) clicks=\(event.clickCount) glyph=U+\(String(format: "%04X", editor.currentScalar)) at=\(px)")
        switch editor.mode {
        case .metrics: metricsDown(event, px)
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
        case .cap(let pathID, let nodeID, let dir0): dragCap(pathID, nodeID, dir0, raw)
        case .hint(let pathID, let nodeID, let index, let start, let was, let inserted, _):
            dragHint(pathID, nodeID, index, start, was, inserted, px)
        case .metric(let guide):
            dragMetric(guide, toGrid(px, biased: false))
        case .marquee:
            marqueeCurrent = px
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        CrashLogger.breadcrumb("mouseUp drag=\(actionName(for: drag)) hadWorking=\(working != nil)")
        defer { drag = nil }
        if case .marquee(let start) = drag {
            finishMarquee(start: start, end: evPos(event))
            marqueeCurrent = nil
            needsDisplay = true
            return
        }
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

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if let name = Self.arrowName(event.keyCode) { heldArrowKeys.insert(name) }
        if editor.mode == .skeleton, event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAllNodes()
            return
        }
        if tryGlobalCharacterShortcut(event) { return }

        if event.keyCode == KeyCode.tab {
            let backward = event.modifierFlags.contains(.shift)
            if editor.mode == .metrics { cycleMetricSelection(backward: backward) } else { cycleSelection(backward: backward) }
            return
        }

        let flags = event.modifierFlags
        switch editor.mode {
        case .metrics: metricsKeyDown(event, flags)
        case .skeleton: skeletonKeyDown(event, flags)
        case .thicken: thickenKeyDown(event, flags)
        case .hint: hintKeyDown(event, flags)
        }
    }

    override func keyUp(with event: NSEvent) {
        if let name = Self.arrowName(event.keyCode) { heldArrowKeys.remove(name) }
    }

    /// Any plain character/number/symbol key (no ⌘/⌃, and not space) selects that glyph, the same
    /// as clicking it in the sidebar — as long as it's actually one of our drawable glyphs, which
    /// conveniently also excludes every special key (arrows, tab, return, delete, esc all produce
    /// non-printable/private-use scalars that never match `glyphOrder`).
    private func tryGlobalCharacterShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return false }
        guard ![KeyCode.enter, KeyCode.esc, KeyCode.tab, KeyCode.backspace, KeyCode.forwardDelete,
                 KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down].contains(event.keyCode) else { return false }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1, let ch = chars.first, ch != " " else { return false }
        guard let scalarValue = ch.unicodeScalars.first?.value else { return false }
        let scalar = UInt32(scalarValue)
        guard FontProject.glyphOrder.contains(scalar) else { return false }
        editor.selectGlyph(scalar)
        return true
    }

    enum KeyCode {
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let enter: UInt16 = 36
        static let esc: UInt16 = 53
        static let backspace: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    static func arrowName(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case KeyCode.left: return "left"
        case KeyCode.right: return "right"
        case KeyCode.down: return "down"
        case KeyCode.up: return "up"
        default: return nil
        }
    }

    static func arrowDelta(_ keyCode: UInt16) -> (dx: Double, dy: Double) {
        switch keyCode {
        case KeyCode.left: return (-1, 0)
        case KeyCode.right: return (1, 0)
        case KeyCode.down: return (0, -1)
        case KeyCode.up: return (0, 1)
        default: return (0, 0)
        }
    }

    /// Left vs right ⌥ isn't exposed by `NSEvent.ModifierFlags`' named cases, but the raw flags
    /// value still carries the old device-dependent bits (NX_DEVICELALTKEYMASK / RALTKEYMASK)
    /// alongside the normalized `.option` bit — a long-standing, if undocumented-in-Swift, trick.
    /// If this turns out unreliable on some keyboard, that's the seam to revisit.
    static func isLeftOption(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && (flags.rawValue & 0x20 != 0)
    }
    static func isRightOption(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && (flags.rawValue & 0x40 != 0)
    }

    func actionName(for drag: Drag?) -> String {
        guard let drag else { return "Edit" }
        switch drag {
        case .pen: return "Draw"
        case .moveNode: return "Move Node"
        case .handle: return "Adjust Curve"
        case .thickness: return "Thickness"
        case .angle: return "Rotate Terminal"
        case .cap: return "Cap"
        case .hint: return "Hint"
        case .metric: return "Adjust Metric"
        case .marquee: return "Select"
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
