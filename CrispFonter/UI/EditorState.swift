import Foundation

enum EditorMode: String { case skeleton, thicken, hint }

/// Transient, per-window UI state that doesn't belong in the saved document:
/// current tool, current glyph, view flags. Canvas-internal interaction state
/// (drag, hover, in-progress path) lives inside GlyphCanvasView itself.
final class EditorState: ObservableObject {
    @Published var mode: EditorMode = .skeleton
    @Published var currentScalar: UInt32 = UInt32(Character("a").asciiValue!)
    @Published var showFill = true
    @Published var showSkel = true
    @Published var showPix = false
    @Published var pixPpem: Double = 11
    @Published var halfSnap = false
    @Published var hintMessage = ""
    @Published var cursorPosText = "—"

    func selectGlyph(_ scalar: UInt32) {
        currentScalar = scalar
    }

    func setMode(_ m: EditorMode) {
        mode = m
        hintMessage = ""
        if m == .hint && !showPix { showPix = true }
    }
}
