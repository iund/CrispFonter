import AppKit

/// Metrics mode: drag the blue guides (or the advance-width edge) to set them directly on the
/// canvas, snapped to the grid — an alternative to the sidebar's metric sliders.
extension GlyphCanvasView {
    func metricsDown(_ event: NSEvent, _ px: CGPoint) {
        guard let g = hitMetricsGuide(px) else { return }
        selectedMetric = g
        drag = .metric(g)
        needsDisplay = true
    }

    func hitMetricsGuide(_ px: CGPoint) -> MetricsGuide? {
        let m = doc.project.metrics
        let threshold: CGFloat = 6
        let horizontals: [(MetricsGuide, Int)] = [(.ascender, m.ascender), (.capHeight, m.capHeight), (.xHeight, m.xHeight), (.descender, m.descender)]
        for (g, v) in horizontals {
            let y = toPx(GridPoint(0, Double(v)), biased: false).y
            if abs(y - px.y) < threshold { return g }
        }
        let advX = toPx(GridPoint(Double(doc.project.advance(of: glyph)), 0), biased: false).x
        if abs(advX - px.x) < threshold { return .advance }
        return nil
    }

    /// `rawUnbiased` is grid-space with no vertical-bias offset applied — metric guides are the
    /// font's true reference points, not glyph geometry, so they must ignore the bias entirely.
    func dragMetric(_ g: MetricsGuide, _ rawUnbiased: GridPoint) {
        switch g {
        case .ascender: setMetric("Adjust Ascender") { $0.ascender = Int(rawUnbiased.y.rounded()) }
        case .capHeight: setMetric("Adjust Cap Height") { $0.capHeight = Int(rawUnbiased.y.rounded()) }
        case .xHeight: setMetric("Adjust x-height") { $0.xHeight = Int(rawUnbiased.y.rounded()) }
        case .descender: setMetric("Adjust Descender") { $0.descender = Int(rawUnbiased.y.rounded()) }
        case .advance: setMetric("Adjust Advance Width") { $0.defaultAdvance = Int(rawUnbiased.x.rounded()) }
        }
    }

    private func setMetric(_ name: String, _ body: (inout Metrics) -> Void) {
        doc.mutate(name, undoManager: undoManager) { body(&$0.metrics) }
        needsDisplay = true
    }

    // MARK: - Keyboard (Metrics mode)

    func cycleMetricSelection(backward: Bool) {
        let all = MetricsGuide.allCases
        let idx = selectedMetric.flatMap { all.firstIndex(of: $0) } ?? (backward ? 0 : all.count - 1)
        selectedMetric = all[(idx + (backward ? -1 : 1) + all.count) % all.count]
        needsDisplay = true
    }

    func adjustSelectedMetric(_ delta: Int) {
        guard let g = selectedMetric else { return }
        switch g {
        case .ascender: setMetric("Adjust Ascender") { $0.ascender += delta }
        case .capHeight: setMetric("Adjust Cap Height") { $0.capHeight += delta }
        case .xHeight: setMetric("Adjust x-height") { $0.xHeight += delta }
        case .descender: setMetric("Adjust Descender") { $0.descender += delta }
        case .advance: setMetric("Adjust Advance Width") { $0.defaultAdvance += delta }
        }
    }

    func adjustAdvanceWidth(_ delta: Int) {
        setMetric("Adjust Advance Width") { $0.defaultAdvance += delta }
    }

    func adjustLineHeight(_ delta: Int) {
        setMetric("Adjust Line Height") { $0.lineHeight += delta }
    }

    func adjustGridDivisions(_ delta: Int) {
        doc.mutate("Adjust Grid Spacing", undoManager: undoManager) { $0.gridDivisions = max(2, $0.gridDivisions + delta) }
        needsDisplay = true
    }

    func adjustVerticalBias(_ delta: Double) {
        // `magnitude` is always positive; the actual step's sign comes from `delta` alone, once —
        // re-deriving it a second time from `delta`'s own sign after already folding it into
        // `step` was flipping the sign for the unsnapped case.
        let magnitude = editor.snapBiasToPixel ? Double(doc.project.gridDivisions) / editor.pixPpem : abs(delta)
        doc.mutate("Vertical Bias", undoManager: undoManager) { $0.verticalBias += (delta < 0 ? -magnitude : magnitude) }
        needsDisplay = true
    }

    func toggleGlyphComplete() {
        doc.mutateGlyph(editor.currentScalar, "Toggle Complete", undoManager: undoManager) { $0.complete.toggle() }
    }

    /// ⌘+arrow pans the canvas by the current grid-snap step — Metrics-mode-only (there's no
    /// equivalent in Draw, where ⌘+arrow already means something else: nudging a fill handle).
    private func panCanvas(_ event: NSEvent) -> Bool {
        guard let (dx, dy) = Self.arrowName(event.keyCode) != nil ? Self.arrowDelta(event.keyCode) : nil else { return false }
        let step = editor.snapStep
        editor.panOffset.x += CGFloat(dx * step) * cell
        editor.panOffset.y -= CGFloat(dy * step) * cell
        needsDisplay = true
        return true
    }

    func metricsKeyDown(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        if flags.contains(.command), panCanvas(event) { return }
        switch event.keyCode {
        case KeyCode.space: editor.showPix.toggle()
        case KeyCode.enter: toggleGlyphComplete()
        case KeyCode.up:
            if flags.contains(.shift) { adjustVerticalBias(0.25) }
            else if flags.contains(.option) { adjustLineHeight(1) }
            else { adjustSelectedMetric(1) }
        case KeyCode.down:
            if flags.contains(.shift) { adjustVerticalBias(-0.25) }
            else if flags.contains(.option) { adjustLineHeight(-1) }
            else { adjustSelectedMetric(-1) }
        case KeyCode.right:
            if flags.contains(.option) { adjustGridDivisions(1) } else { adjustAdvanceWidth(1) }
        case KeyCode.left:
            if flags.contains(.option) { adjustGridDivisions(-1) } else { adjustAdvanceWidth(-1) }
        default: break
        }
    }
}
