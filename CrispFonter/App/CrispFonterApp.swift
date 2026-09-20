import SwiftUI

@main
struct CrispFonterApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { ProjectDocument() }) { file in
            ContentView(doc: file.document)
        }
    }
}
