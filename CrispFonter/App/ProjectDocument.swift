import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let crispProject = UTType(exportedAs: "com.crispfonter.project", conformingTo: .json)
}

/// Document wrapper. All model edits go through `mutate` so they are undoable.
final class ProjectDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = FontProject

    @Published var project: FontProject
    /// Incremented on every mutation; used to invalidate bitmap caches.
    @Published private(set) var revision: Int = 0

    static var readableContentTypes: [UTType] { [.crispProject] }

    init() {
        var p = FontProject.newDocument()
        SampleGlyphs.seed(into: &p)
        project = p
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        project = try JSONDecoder().decode(FontProject.self, from: data)
    }

    func snapshot(contentType: UTType) throws -> FontProject { project }

    func fileWrapper(snapshot: FontProject, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }

    /// Apply an undoable change. `actionName` shows up in the Edit menu.
    func mutate(_ actionName: String? = nil, undoManager: UndoManager?, _ body: (inout FontProject) -> Void) {
        let before = project
        body(&project)
        guard project != before else { return }
        revision &+= 1
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.mutate(actionName, undoManager: undoManager) { $0 = before }
        }
        if let actionName { undoManager?.setActionName(actionName) }
    }

    /// Convenience for editing one glyph.
    func mutateGlyph(_ scalar: UInt32, _ actionName: String? = nil, undoManager: UndoManager?, _ body: (inout Glyph) -> Void) {
        mutate(actionName, undoManager: undoManager) { p in
            var g = p.glyph(for: scalar)
            body(&g)
            p.glyphs[scalar] = g
        }
    }
}
