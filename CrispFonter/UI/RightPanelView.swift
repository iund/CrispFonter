import SwiftUI
import AppKit

struct RightPanelView: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    @Environment(\.colorScheme) private var colorScheme
    private let cache = GlyphBitmapCache()

    var glyph: Glyph { doc.project.glyph(for: editor.currentScalar) }
    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("RENDERERS · SAME OUTLINE, SAME HINTS").font(.caption2).foregroundStyle(.tertiary)
                RendererStripView(doc: doc, glyph: glyph, revision: doc.revision, cache: cache, dark: dark)
                ActualSizeRow(doc: doc, glyph: glyph, revision: doc.revision, cache: cache, dark: dark)
            }
            .padding(12)
            Divider()
            TextPreviewView(doc: doc, cache: cache, dark: dark)
                .padding(12)
        }
    }
}

/// Traditional (non-Retina) pixel sizes — these are literal pixels-per-em, not points scaled for a
/// HiDPI display; the on-screen zoom factor below is purely a legibility magnification on top.
private let previewSizes: [Double] = [8, 9, 10, 11, 12, 13, 14]

/// One row of the renderer strip: a rendering engine + a forced antialiasing mode + how the result
/// is displayed. `colorDisplay` methods show the real blended-color image (plain grey, or, for
/// subpixel, the color fringing a genuine LCD/ClearType render produces); the one non-color method
/// instead shows the raw monochrome subpixel-filtered signal at 3x horizontal resolution, before
/// it'd be mapped onto a physical RGB-striped panel.
enum PreviewMethod: CaseIterable, Identifiable {
    case freetypeMono, freetypeGrey, freetypeSubpixelColor, macos, chrome, freetypeSubpixelSignal
    var id: Self { self }

    var engine: RendererModel {
        switch self {
        case .freetypeMono, .freetypeGrey, .freetypeSubpixelColor, .freetypeSubpixelSignal: .freetype
        case .macos: .macos
        case .chrome: .chrome
        }
    }
    var aa: AAMode {
        switch self {
        case .freetypeMono: .mono
        case .freetypeGrey: .greyscale
        case .freetypeSubpixelColor, .freetypeSubpixelSignal: .subpixel
        case .macos, .chrome: .greyscale
        }
    }
    var colorDisplay: Bool { self != .freetypeSubpixelSignal }

    var label: String {
        switch self {
        case .freetypeMono: "FreeType unaliased"
        case .freetypeGrey: "FreeType greyscale"
        case .freetypeSubpixelColor: "FreeType subpixel"
        case .macos: "macOS CoreText"
        case .chrome: "Chrome/Electron"
        case .freetypeSubpixelSignal: "Subpixel signal"
        }
    }
    var subtitle: String {
        switch self {
        case .freetypeMono: "1-bit, no AA · full hinting"
        case .freetypeGrey: "greyscale AA · full hinting"
        case .freetypeSubpixelColor: "LCD/ClearType-style AA · full hinting"
        case .macos: "unhinted — CoreText disregards gridfitting entirely"
        case .chrome: "Skia/DirectWrite, greyscale AA — subpixel AA has been off by default since ~2021"
        case .freetypeSubpixelSignal: "raw LCD-filtered signal, 3:1, before RGB stripe mapping"
        }
    }
}

private struct RendererStripView: View {
    @ObservedObject var doc: ProjectDocument
    let glyph: Glyph
    let revision: Int
    let cache: GlyphBitmapCache
    let dark: Bool
    private let labelWidth: CGFloat = 118

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
            ForEach(PreviewMethod.allCases) { method in
                HStack(spacing: 8) {
                    rowLabel(Text(method.label).font(.caption), method.subtitle)
                    ForEach(previewSizes, id: \.self) { s in cell(method: method, ppem: s).frame(maxWidth: .infinity) }
                }
            }
            HStack(spacing: 8) {
                rowLabel(Text("Reference").font(.caption), "system font, real OS rendering")
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

    @ViewBuilder
    private func cell(method: PreviewMethod, ppem: Double) -> some View {
        let bmp = cache.bitmap(glyph: glyph, project: doc.project, revision: revision, ppem: ppem, renderer: method.engine, aa: method.aa)
        let theme = BitmapImages.Theme.of(dark)
        let zoom = max(3, (72 / max(bmp.h, 1)) - (72 / max(bmp.h, 1)) % 3)
        if method.colorDisplay {
            let img = BitmapImages.nsImage(BitmapImages.actualSize(bmp, theme: theme))
            pixelImage(img, width: Double(bmp.w * zoom), height: Double(bmp.h * zoom))
                .background(theme.swiftUIColor)
                .border(Color.secondary.opacity(0.3))
        } else {
            let img = BitmapImages.nsImage(BitmapImages.zoomed(bmp, theme: theme))
            pixelImage(img, width: Double(bmp.w * 3) * Double(zoom) / 3, height: Double(bmp.h) * Double(zoom))
                .background(theme.swiftUIColor)
                .border(Color.secondary.opacity(0.3))
        }
    }

    private func referenceCell(ppem: Double) -> some View {
        let m = doc.project.metrics, sc = ppem / Double(doc.project.gridDivisions)
        let base = Int((Double(m.ascender) * sc).rounded()) + 1
        let h = base + Int((-Double(m.descender) * sc).rounded(.up)) + 2
        let w = Int((Double(m.defaultAdvance) * sc).rounded(.up)) + 3
        let ch = String(UnicodeScalar(glyph.scalar) ?? UnicodeScalar(0xFFFD)!)
        let theme = BitmapImages.Theme.of(dark)
        let img = referenceImage(text: glyph.scalar == Glyph.notdefScalar ? "\u{FFFD}" : ch, font: doc.project.referenceFontName, size: ppem, w: w, h: h, base: base, theme: theme)
        let zoom = max(3, 72 / max(h, 1))
        return pixelImage(img, width: Double(w * zoom), height: Double(h * zoom))
            .background(theme.swiftUIColor)
            .border(Color.secondary.opacity(0.3))
    }

    private func referenceImage(text: String, font familyName: String, size: Double, w: Int, h: Int, base: Int, theme: BitmapImages.Theme) -> NSImage? {
        guard w > 0, h > 0 else { return nil }
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        theme.nsColor.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let font = NSFont(name: familyName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.nsForegroundColor]
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
    let dark: Bool

    /// The subpixel-signal method has no meaningful "actual size" (its whole point is the 3x
    /// magnified breakdown), so it's left out of this row.
    private var methods: [PreviewMethod] { PreviewMethod.allCases.filter { $0.colorDisplay } }

    var body: some View {
        let theme = BitmapImages.Theme.of(dark)
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            Text("Actual size:").font(.caption).foregroundStyle(.secondary)
            ForEach(methods) { method in
                HStack(spacing: 2) {
                    ForEach(previewSizes, id: \.self) { s in
                        let bmp = cache.bitmap(glyph: glyph, project: doc.project, revision: revision, ppem: s, renderer: method.engine, aa: method.aa)
                        pixelImage(BitmapImages.nsImage(BitmapImages.actualSize(bmp, theme: theme)), width: Double(bmp.w), height: Double(bmp.h))
                    }
                }
            }
        }
        .padding(8)
        .background(theme.swiftUIColor)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .cornerRadius(8)
    }
}

private struct TextPreviewView: View {
    @ObservedObject var doc: ProjectDocument
    let cache: GlyphBitmapCache
    let dark: Bool
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
            TextPreviewCanvas(doc: doc, cache: cache, dark: dark)
                .frame(height: 220)
                .background(BitmapImages.Theme.of(dark).swiftUIColor)
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

/// Renders the glyph-mixed preview text as a plain `NSImage`, built synchronously on the main
/// thread and shown as an ordinary `Image` — the same rendering category as the renderer strip,
/// which has never had trouble. Two earlier approaches both broke here: an `NSViewRepresentable`
/// wrapping a custom `NSView` corrupted the whole pane's layout just by being a sibling of the
/// (pure SwiftUI) renderer strip; a SwiftUI `Canvas` hit a Metal "instanceCount(0)" validation
/// assert on its async rendering thread whenever a frame had nothing (or momentarily zero-sized
/// geometry) to draw, and patching around that kept finding new edge cases. Building an `NSImage`
/// avoids both classes of bug entirely: no representable in the stack, no Metal render pass tied
/// to this view's frame at all.
private struct TextPreviewCanvas: View {
    @ObservedObject var doc: ProjectDocument
    let cache: GlyphBitmapCache
    let dark: Bool

    var body: some View {
        GeometryReader { geo in
            Image(nsImage: Self.render(project: doc.project, revision: doc.revision, cache: cache, size: geo.size, theme: .of(dark)))
                .interpolation(.none)
        }
    }

    private static func render(project: FontProject, revision: Int, cache: GlyphBitmapCache, size: CGSize, theme: BitmapImages.Theme) -> NSImage {
        let w = max(1, Int(size.width)), h = max(1, Int(size.height))
        return NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
            theme.nsColor.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
            let previewSize = project.previewSize, m = project.metrics
            let sc = previewSize / Double(project.gridDivisions)
            let lineH = (Double(m.lineHeight) * sc).rounded()
            let adv = (Double(m.defaultAdvance) * sc).rounded()
            let lines = project.previewText.components(separatedBy: "\n")
            var y = 8 + (Double(m.ascender) * sc).rounded()
            let refFont = NSFont(name: project.referenceFontName, size: previewSize) ?? NSFont.monospacedSystemFont(ofSize: previewSize, weight: .regular)
            for line in lines {
                var x = 8.0
                for ch in line {
                    let scalar = ch.unicodeScalars.first.map { UInt32($0.value) } ?? 0
                    let g = project.glyphs[scalar]
                    if let g, g.isDrawn {
                        let bmp = cache.bitmap(glyph: g, project: project, revision: revision, ppem: previewSize, renderer: project.previewRenderer, aa: .auto)
                        if let img = BitmapImages.nsImage(BitmapImages.actualSize(bmp, theme: theme)) {
                            let rect = NSRect(x: x - 1, y: y - Double(bmp.base), width: Double(bmp.w), height: Double(bmp.h))
                            img.draw(in: rect)
                        }
                    } else if ch != " " {
                        let attrs: [NSAttributedString.Key: Any] = [.font: refFont, .foregroundColor: theme.nsForegroundColor.withAlphaComponent(0.56)]
                        String(ch).draw(at: NSPoint(x: x, y: y - previewSize), withAttributes: attrs)
                    }
                    x += adv
                    if x > Double(w) - adv { break }
                }
                y += lineH
            }
            return true
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
