import SwiftUI
import AppKit

struct RightPanelView: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    private let cache = GlyphBitmapCache()

    var glyph: Glyph { doc.project.glyph(for: editor.currentScalar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("RENDERERS · SAME OUTLINE, SAME HINTS").font(.caption2).foregroundStyle(.tertiary)
                RendererStripView(doc: doc, glyph: glyph, revision: doc.revision, cache: cache)
                ActualSizeRow(doc: doc, glyph: glyph, revision: doc.revision, cache: cache)
            }
            .padding(12)
            Divider()
            TextPreviewView(doc: doc, cache: cache)
                .padding(12)
        }
    }
}

private let previewSizes: [Double] = [9, 11, 13, 16]

private struct RendererStripView: View {
    @ObservedObject var doc: ProjectDocument
    let glyph: Glyph
    let revision: Int
    let cache: GlyphBitmapCache
    private let labelWidth: CGFloat = 96

    var body: some View {
        // Plain HStack/VStack rows with a fixed-width label column, rather than Grid/GridRow:
        // mixing an empty Text() header cell with VStack cells in later rows of the same column
        // is enough to make SwiftUI's Grid collapse the whole thing to zero size on some versions.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(previewSizes, id: \.self) { s in
                    Text("\(Int(s)) pt").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }
            }
            ForEach(RendererModel.allCases) { r in
                HStack(spacing: 8) {
                    rowLabel(Text(r.label.components(separatedBy: " (").first ?? r.label).font(.caption), sub(for: r))
                    ForEach(previewSizes, id: \.self) { s in cell(renderer: r, ppem: s).frame(maxWidth: .infinity) }
                }
            }
            HStack(spacing: 8) {
                rowLabel(Text("Reference").font(.caption), "browser rendering")
                ForEach(previewSizes, id: \.self) { s in referenceCell(ppem: s).frame(maxWidth: .infinity) }
            }
        }
    }

    private func rowLabel(_ title: Text, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            title
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(width: labelWidth, alignment: .leading)
    }

    private func sub(for r: RendererModel) -> String {
        switch r {
        case .freetype: "≈ Windows GDI · full hinting"
        case .chrome: "DirectWrite · vertical hinting"
        case .macos: "CoreText · unhinted, greyscale"
        }
    }

    private func cell(renderer: RendererModel, ppem: Double) -> some View {
        let bmp = cache.bitmap(glyph: glyph, project: doc.project, revision: revision, ppem: ppem, renderer: renderer, lcdOn: doc.project.previewLCD)
        let img = BitmapImages.nsImage(BitmapImages.zoomed(bmp, lcd: doc.project.previewLCD))
        let zoom = max(3, (72 / max(bmp.h, 1)) - (72 / max(bmp.h, 1)) % 3)
        return pixelImage(img, width: Double(bmp.w * 3) * Double(zoom) / 3, height: Double(bmp.h) * Double(zoom))
            .border(Color.secondary.opacity(0.3))
    }

    private func referenceCell(ppem: Double) -> some View {
        let m = doc.project.metrics, sc = ppem / Double(doc.project.gridDivisions)
        let base = Int((Double(m.ascender) * sc).rounded()) + 1
        let h = base + Int((-Double(m.descender) * sc).rounded(.up)) + 2
        let w = Int((Double(m.defaultAdvance) * sc).rounded(.up)) + 3
        let ch = String(UnicodeScalar(glyph.scalar) ?? UnicodeScalar(0xFFFD)!)
        let img = referenceImage(text: glyph.scalar == Glyph.notdefScalar ? "\u{FFFD}" : ch, font: doc.project.referenceFontName, size: ppem, w: w, h: h, base: base)
        let zoom = max(3, 72 / max(h, 1))
        return pixelImage(img, width: Double(w * zoom), height: Double(h * zoom))
            .border(Color.secondary.opacity(0.3))
    }

    private func referenceImage(text: String, font familyName: String, size: Double, w: Int, h: Int, base: Int) -> NSImage? {
        guard w > 0, h > 0 else { return nil }
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let font = NSFont(name: familyName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        text.draw(at: NSPoint(x: 1, y: Double(h) - Double(base) - font.descender), withAttributes: attrs)
        image.unlockFocus()
        return image
    }
}

private struct ActualSizeRow: View {
    @ObservedObject var doc: ProjectDocument
    let glyph: Glyph
    let revision: Int
    let cache: GlyphBitmapCache

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            Text("Actual size:").font(.caption).foregroundStyle(.secondary)
            ForEach(RendererModel.allCases) { r in
                HStack(spacing: 2) {
                    ForEach(previewSizes, id: \.self) { s in
                        let bmp = cache.bitmap(glyph: glyph, project: doc.project, revision: revision, ppem: s, renderer: r, lcdOn: doc.project.previewLCD)
                        pixelImage(BitmapImages.nsImage(BitmapImages.actualSize(bmp)), width: Double(bmp.w), height: Double(bmp.h))
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .cornerRadius(8)
    }
}

private struct TextPreviewView: View {
    @ObservedObject var doc: ProjectDocument
    let cache: GlyphBitmapCache
    var undoManager: UndoManager? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Size")
                Slider(value: Binding(get: { doc.project.previewSize }, set: { doc.project.previewSize = $0 }), in: 6...18, step: 0.5)
                    .frame(width: 100)
                Text("\(doc.project.previewSize, specifier: "%.1f") pt").monospacedDigit()
                Spacer()
                Picker("", selection: Binding(get: { doc.project.previewRenderer }, set: { doc.project.previewRenderer = $0 })) {
                    Text("FreeType v35").tag(RendererModel.freetype)
                    Text("Chrome (DirectWrite)").tag(RendererModel.chrome)
                    Text("macOS (CoreText)").tag(RendererModel.macos)
                }
                .labelsHidden()
                .frame(width: 180)
            }
            TextPreviewCanvas(doc: doc, cache: cache)
                .frame(height: 220)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            TextEditor(text: Binding(get: { doc.project.previewText }, set: { doc.project.previewText = $0 }))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Text("Drawn glyphs are used wherever they appear; other characters fall back to the reference font.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// Renders the glyph-mixed preview text. A native SwiftUI `Canvas` rather than an
/// `NSViewRepresentable`-wrapped `NSView`: mixing that representable as a sibling of the (pure
/// SwiftUI) renderer strip in the same stack reliably broke layout for the whole pane — direct
/// testing narrowed it to that specific representable's presence, not its size or content.
/// `Canvas` also draws with a plain top-down coordinate system, sidestepping the
/// flipped-view/CGImage-orientation class of bugs entirely.
private struct TextPreviewCanvas: View {
    @ObservedObject var doc: ProjectDocument
    let cache: GlyphBitmapCache

    var body: some View {
        Canvas { context, canvasSize in
            let project = doc.project
            let size = project.previewSize, m = project.metrics
            let sc = size / Double(project.gridDivisions)
            let lineH = (Double(m.lineHeight) * sc).rounded()
            let adv = (Double(m.defaultAdvance) * sc).rounded()
            let lines = project.previewText.components(separatedBy: "\n")
            var y = 8 + (Double(m.ascender) * sc).rounded()
            let refFont = NSFont(name: project.referenceFontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            for line in lines {
                var x = 8.0
                for ch in line {
                    let scalar = ch.unicodeScalars.first.map { UInt32($0.value) } ?? 0
                    let g = project.glyphs[scalar]
                    if let g, g.isDrawn {
                        let bmp = cache.bitmap(glyph: g, project: project, revision: doc.revision, ppem: size, renderer: project.previewRenderer, lcdOn: project.previewLCD)
                        if let cg = BitmapImages.actualSize(bmp) {
                            let rect = CGRect(x: x - 1, y: y - Double(bmp.base), width: Double(bmp.w), height: Double(bmp.h))
                            context.draw(Image(decorative: cg, scale: 1), in: rect)
                        }
                    } else if ch != " " {
                        let text = Text(String(ch)).font(Font(refFont)).foregroundColor(Color(white: 0.56))
                        context.draw(text, at: CGPoint(x: x, y: y - size * 0.7), anchor: .topLeading)
                    }
                    x += adv
                    if x > canvasSize.width - adv { break }
                }
                y += lineH
            }
        }
    }
}

private func pixelImage(_ image: NSImage?, width: Double, height: Double) -> some View {
    Group {
        if let image {
            Image(nsImage: image).interpolation(.none).resizable().frame(width: max(1, width), height: max(1, height))
        } else {
            Color.clear.frame(width: max(1, width), height: max(1, height))
        }
    }
}
