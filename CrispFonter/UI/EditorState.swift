import AppKit

enum EditorMode: String, CaseIterable { case metrics, skeleton, thicken, hint }

/// Transient, per-window UI state that doesn't belong in the saved document:
/// current tool, current glyph, view flags. Canvas-internal interaction state
/// (drag, hover, in-progress path, node/metric selection) lives inside GlyphCanvasView itself.
final class EditorState: ObservableObject {
    @Published var mode: EditorMode = .skeleton
    /// So the ⌘1–4 mode-switch shortcuts (which fire as window-wide button actions, not on the
    /// canvas) can also hand keyboard focus back to it — otherwise switching mode from a menu/
    /// button leaves focus wherever it was, and the mode's keyboard commands go nowhere.
    weak var canvasView: GlyphCanvasView?
    /// Persistent canvas zoom (pixels per grid unit) — nil until the canvas seeds it with an
    /// initial fit-to-view size on first draw; after that only ⌘0/⌘−/⌘= change it, not metric edits.
    var zoomCell: CGFloat?
    /// Pan offset (in view pixels) applied on top of the canvas's normal centering, so ⌘−/⌘= can
    /// keep a fixed point under the cursor/anchor instead of always re-centering.
    var panOffset: CGPoint = .zero
    @Published var currentScalar: UInt32 = UInt32(Character("a").asciiValue!)
    @Published var showFill = true
    @Published var showSkel = true
    @Published var showPix = false
    @Published var pixPpem: Double = 11
    @Published var halfSnap = false
    @Published var hintMessage = ""
    @Published var cursorPosText = "—"
    /// When on, the vertical-bias slider (sidebar) snaps to whole pixels at `pixPpem`.
    @Published var snapBiasToPixel = false

    func selectGlyph(_ scalar: UInt32) {
        CrashLogger.breadcrumb("selectGlyph U+\(String(format: "%04X", scalar))")
        currentScalar = scalar
        if let canvas = canvasView { canvas.window?.makeFirstResponder(canvas) }
    }

    func setMode(_ m: EditorMode) {
        CrashLogger.breadcrumb("setMode \(mode) -> \(m)")
        mode = m
        hintMessage = ""
        if m == .hint && !showPix { showPix = true }
    }
}
