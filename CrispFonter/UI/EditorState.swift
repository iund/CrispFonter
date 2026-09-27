import AppKit
import SwiftUI

/// `combo` merges the old separate Skeleton (pen/curve) and Thicken (thickness/cap handle) modes
/// into one — draw and adjust weight without switching tools.
enum EditorMode: String, CaseIterable { case metrics, combo, hint }

/// Transient, per-window UI state that doesn't belong in the saved document:
/// current tool, current glyph, view flags. Canvas-internal interaction state
/// (drag, hover, in-progress path, node/metric selection) lives inside GlyphCanvasView itself.
final class EditorState: ObservableObject {
    @Published var mode: EditorMode = .combo
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
    /// The skeleton (and its handles) can be hidden — the fill alone is always shown, growing
    /// more opaque when the skeleton's hidden so it reads clearly without the overlay competing
    /// with it. See `fillColor` and `GlyphCanvasView+Draw.drawFill`.
    @Published var showSkel = true
    /// Hides the fill entirely (e.g. to inspect the skeleton/handles/hint overlay on their own).
    @Published var showFill = true
    /// User-chosen fill color, shown at 50% alpha while the skeleton's visible and fully opaque
    /// once it's hidden.
    @Published var fillColor: Color = .purple
    @Published var showPix = false
    @Published var pixPpem: Double = 11
    /// Grid-snap granularity, as an index into `snapDenominators` (32nd ... whole). Replaces the
    /// old binary half-grid toggle with a graduated step size, adjustable via the toolbar slider
    /// or ⌘,/⌘. — index 5 (whole grid) matches the old `halfSnap == false` default.
    static let snapDenominators = [32, 16, 8, 4, 2, 1]
    @Published var snapStepIndex = 5
    var snapDenominator: Int { Self.snapDenominators[snapStepIndex] }
    var snapStep: Double { 1.0 / Double(snapDenominator) }
    @Published var hintMessage = ""
    @Published var cursorPosText = "—"
    /// When on, the vertical-bias slider (sidebar) snaps to whole pixels at `pixPpem`.
    @Published var snapBiasToPixel = false
    /// Persistent toggle (bottom-bar checkbox, or ⌃Space) for the reference-font glyph overlay;
    /// holding ⌃ shows it momentarily regardless of this.
    @Published var showReferenceGlyph = false
    /// Whichever of Metrics/Draw was active before Caps Lock switched to Hint, so turning it back
    /// off restores that instead of always landing on Draw.
    private var preHintMode: EditorMode = .combo

    func selectGlyph(_ scalar: UInt32) {
        CrashLogger.breadcrumb("selectGlyph U+\(String(format: "%04X", scalar))")
        currentScalar = scalar
        if let canvas = canvasView { canvas.window?.makeFirstResponder(canvas) }
    }

    func setMode(_ m: EditorMode) {
        CrashLogger.breadcrumb("setMode \(mode) -> \(m)")
        if mode != .hint { preHintMode = mode }
        mode = m
        hintMessage = ""
        if m == .hint && !showPix { showPix = true }
    }

    /// Caps Lock on/off, from `GlyphCanvasView.flagsChanged`.
    func capsLockChanged(on: Bool) {
        setMode(on ? .hint : preHintMode)
    }

    /// ⌥Tab/⇧⌥Tab (global — see ContentView.GlobalShortcuts): cycles Metrics → Draw → Hint →
    /// Metrics, or backwards.
    func cycleMode(backward: Bool = false) {
        let all = EditorMode.allCases
        let idx = all.firstIndex(of: mode) ?? 0
        setMode(all[(idx + (backward ? -1 : 1) + all.count) % all.count])
    }
}
