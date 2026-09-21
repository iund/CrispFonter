import SwiftUI
import UniformTypeIdentifiers

struct ExportSheetView: View {
    @ObservedObject var doc: ProjectDocument
    @Environment(\.dismiss) private var dismiss
    @State private var options: ExportOptions
    @State private var errorMessage: String?

    init(doc: ProjectDocument) {
        self.doc = doc
        _options = State(initialValue: doc.project.export)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export TrueType Font").font(.headline)

            Form {
                TextField("Family name", text: $options.familyName)
                TextField("Style name", text: $options.styleName)
                Toggle("Include hints", isOn: $options.includeHints)
                Stepper("1-bit threshold: \(options.gaspMonoThreshold) ppem", value: $options.gaspMonoThreshold, in: 0...99)
                Stepper("Hint cut-off: \(options.hintCutoffPPEM) ppem", value: $options.hintCutoffPPEM, in: 1...400)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Export…") { export() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ttf") ?? .data]
        panel.nameFieldStringValue = "\(options.familyName)-\(options.styleName).ttf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var project = doc.project
        project.export = options
        CrashLogger.breadcrumb("export start: \(project.glyphs.count) glyphs, includeHints=\(options.includeHints)")
        let data = TrueTypeWriter.write(project: project)
        CrashLogger.breadcrumb("export TrueTypeWriter.write done: \(data.count) bytes")
        do {
            try data.write(to: url)
            CrashLogger.breadcrumb("export write to disk done")
            dismiss()
        } catch {
            CrashLogger.breadcrumb("export write to disk failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}
