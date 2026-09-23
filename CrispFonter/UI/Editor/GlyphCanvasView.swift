import AppKit

/// Identifies one node in the glyph independent of any transient selection scheme — used for the
/// Skeleton-mode multi-selection set (⌘-click / marquee), which can span multiple paths.
struct NodeRef: Hashable { let pathID: UUID; let nodeID: UUID }

/// The one custom view in the app: the glyph editor canvas. Pen tool (skeleton), thickness/cap
/// handles (thicken), and hint points (hint). Port of the prototype's canvas interaction code.
final class GlyphCanvasView: NSView {
    var doc: ProjectDocument!
    var editor: EditorState!

    /// A path currently being drawn (persists across the multiple click gestures of the pen tool).
    var drawingPathID: UUID?
    /// Selected node, for delete / skeleton highlighting. When `multiSelection` has 2+ members
    /// this still tracks the most-recently-clicked one, e.g. for commands that only make sense on
    /// a single node.
    var selection: (pathID: UUID, nodeID: UUID)?
    /// Skeleton-mode multi-selection (⌘-click to add/remove, or marquee-select) — empty unless 2+
    /// nodes are selected together, in which case dragging or arrow-nudging any of them moves the
    /// whole set in unison.
    var multiSelection: Set<NodeRef> = []
    /// Live end point of an in-progress marquee-select drag, in view pixels; nil when not marquee-selecting.
    var marqueeCurrent: CGPoint?
    /// Selected metric guide, in Metrics mode — keyboard up/down/left/right adjusts it.
    var selectedMetric: MetricsGuide?
    /// Arrow keys currently held down, for Hint mode's diagonal directional-hint shortcut.
    var heldArrowKeys: Set<String> = []
    var hover: GridPoint?
    var drag: Drag?
    /// Uncommitted edits for the in-progress gesture; committed to `doc` on mouseUp.
    var working: Glyph?
    /// Tracks each shift key's own down state (as opposed to the normalized, side-agnostic
    /// `.shift` flag), so a press is detected exactly once as a rising edge.
    private var leftShiftActive = false
    private var rightShiftActive = false
    /// Timestamp of each side's last rising edge, to detect a double-press (two presses within
    /// `doublePressWindow`) rather than acting on every single tap.
    private var leftShiftLastPress: TimeInterval = 0
    private var rightShiftLastPress: TimeInterval = 0
    private static let doublePressWindow: TimeInterval = 0.4
    /// Whether caps lock was down on the previous flagsChanged, so switching it on/off is an edge,
    /// not a level — it's a physical toggle key, so this fires once per flip either direction.
    private var capsLockActive = false

    // Live modifier state, for the momentary hold effects (skeleton hidden, handle highlights,
    // pan hint) — these are levels, not edges, so just mirror `flagsChanged` directly.
    var fnHeld = false
    var cmdHeld = false
    var shiftHeld = false
    var leftOptionHeld = false
    var rightOptionHeld = false
    /// Either ⌥ — used by Hint mode's round-outward preview, which (unlike cIn/cOut) has no
    /// left/right distinction.
    var optionHeld = false
    var leftCommandHeld = false
    var rightCommandHeld = false
    /// Momentarily shows the reference-font glyph while held (see `EditorState.showReferenceGlyph`
    /// for the persistent toggle).
    var ctrlHeld = false

    var cell: CGFloat = 30
    var originX: CGFloat = 0
    var originY: CGFloat = 0
    let hitRadius: CGFloat = 8

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Glyph access

    /// Anchor-resolved (see `Glyph.resolvingAnchors`) — every display/hit-testing use of a node's
    /// `p` should see the live thickness-edge position an anchored node tracks, not its last
    /// literally-stored coordinate. `mutateWorking`/`commit` still read and write the raw,
    /// unresolved stored data, so anchors themselves persist rather than getting baked in.
    var glyph: Glyph { (working ?? doc.project.glyph(for: editor.currentScalar)).resolvingAnchors(weight: weight) }
    var weight: Double { doc.project.defaultWeight }

    func mutateWorking(_ body: (inout Glyph) -> Void) {
        var g = working ?? doc.project.glyph(for: editor.currentScalar)
        body(&g)
        working = g
        needsDisplay = true
    }

    func commit(_ actionName: String) {
        guard let g = working else { return }
        working = nil
        doc.mutateGlyph(editor.currentScalar, actionName, undoManager: undoManager) { $0 = g }
    }

    // MARK: - Layout / transform

    override func layout() {
        super.layout()
        updateTransform()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self))
    }

    /// `editor.zoomCell` is the persistent zoom level (pixels per grid unit) — nil only until the
    /// first draw, when it's seeded with a one-time fit-to-view size and then left alone. Editing
    /// metrics (line height, ascender, etc.) no longer silently rescales the canvas; only
    /// `zoomToFit()`/`zoomBy()` (⌘0/⌘−/⌘=) touch it after that.
    func updateTransform() {
        guard doc != nil else { return }
        let m = doc.project.metrics
        let w = bounds.width, h = bounds.height
        if editor.zoomCell == nil {
            let spanY = CGFloat(m.ascender - m.descender) + 4
            let spanX = CGFloat(doc.project.advance(of: glyph)) + 6
            editor.zoomCell = max(10, min((h - 20) / max(spanY, 1), (w - 20) / max(spanX, 1)))
        }
        cell = editor.zoomCell!
        // While actively dragging a metric guide, `originX`/`originY` depend on the very value
        // being dragged (ascender/descender/advance) — recomputing every frame made the whole
        // canvas visibly re-center as you drag. Freeze the origin for the drag's duration; it
        // re-centers once, cleanly, the moment the drag ends (the next `updateTransform` after).
        if case .metric = drag { return }
        originX = ((w - CGFloat(doc.project.advance(of: glyph)) * cell) / 2).rounded() + editor.panOffset.x
        originY = (h / 2 + CGFloat(m.ascender + m.descender) / 2 * cell).rounded() + editor.panOffset.y
    }

    /// ⌘0: recompute a fresh fit-to-view zoom and clear any pan.
    func zoomToFit() {
        editor.zoomCell = nil
        editor.panOffset = .zero
        needsDisplay = true
    }

    /// ⌘−/⌘=: scale by `factor`, keeping the glyph's origin (left sidebearing at the baseline)
    /// visually fixed under the zoom rather than re-centering the whole canvas.
    func zoomBy(_ factor: CGFloat) {
        updateTransform()
        let anchor = GridPoint(0, 0)
        let before = toPx(anchor)
        editor.zoomCell = max(4, min(400, cell * factor))
        updateTransform()
        let after = toPx(anchor)
        editor.panOffset.x += before.x - after.x
        editor.panOffset.y += before.y - after.y
        updateTransform()
        needsDisplay = true
    }

    /// Grid-to-pixel and pixel-to-grid, for glyph geometry (`biased: true`, the default) or for
    /// metric guides (`biased: false`) — guides stay put at their true position; the glyph is what
    /// visually shifts against them when `verticalBias` is nonzero.
    func toPx(_ p: GridPoint, biased: Bool = true) -> CGPoint {
        let y = p.y + (biased ? doc.project.verticalBias : 0)
        return CGPoint(x: originX + CGFloat(p.x) * cell, y: originY - CGFloat(y) * cell)
    }
    func toGrid(_ px: CGPoint, biased: Bool = true) -> GridPoint {
        let y = Double((originY - px.y) / cell) - (biased ? doc.project.verticalBias : 0)
        return GridPoint(Double((px.x - originX) / cell), y)
    }
    func snap(_ p: GridPoint, fine: Bool) -> GridPoint {
        let q: Double = fine ? Double(max(editor.snapDenominator, 2)) : Double(editor.snapDenominator)
        return GridPoint((p.x * q).rounded() / q, (p.y * q).rounded() / q)
    }

    /// Double-pressing left ⇧ alone toggles the pixel-grid preview; double-pressing right ⇧ alone
    /// toggles between whole-grid and half-grid snap. Caps lock switches modes: on → Hint, off → Combo. Bare modifier taps
    /// don't generate `keyDown`, so these are caught via raw modifier-flag transitions instead —
    /// same left/right-distinguishing trick as `isLeftOption`/`isRightOption`.
    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags
        let leftNow = flags.contains(.shift) && (flags.rawValue & 0x2 != 0)
        let rightNow = flags.contains(.shift) && (flags.rawValue & 0x4 != 0)
        let now = event.timestamp
        if leftNow, !leftShiftActive {
            if now - leftShiftLastPress < Self.doublePressWindow { editor.showPix.toggle() }
            leftShiftLastPress = now
        }
        if rightNow, !rightShiftActive {
            if now - rightShiftLastPress < Self.doublePressWindow { editor.snapStepIndex = editor.snapStepIndex == 5 ? 4 : 5 }
            rightShiftLastPress = now
        }
        leftShiftActive = leftNow
        rightShiftActive = rightNow

        let capsNow = flags.contains(.capsLock)
        if capsNow != capsLockActive { editor.capsLockChanged(on: capsNow) }
        capsLockActive = capsNow

        fnHeld = flags.contains(.function)
        cmdHeld = flags.contains(.command)
        shiftHeld = flags.contains(.shift)
        leftOptionHeld = Self.isLeftOption(flags)
        rightOptionHeld = Self.isRightOption(flags)
        optionHeld = flags.contains(.option)
        leftCommandHeld = Self.isLeftCommand(flags)
        rightCommandHeld = Self.isRightCommand(flags)
        ctrlHeld = flags.contains(.control)
        needsDisplay = true

        super.flagsChanged(with: event)
    }

    /// Two-finger trackpad pan — moves the canvas the same direction the fingers move.
    override func scrollWheel(with event: NSEvent) {
        editor.panOffset.x += event.scrollingDeltaX
        editor.panOffset.y += event.scrollingDeltaY
        needsDisplay = true
    }

    /// Pinch-to-zoom — anchored at the glyph origin, same as ⌘−/⌘=, not the pinch center (a
    /// cursor-anchored pinch would need the event's location threaded through `zoomBy`).
    override func magnify(with event: NSEvent) {
        zoomBy(1 + event.magnification)
    }
}
