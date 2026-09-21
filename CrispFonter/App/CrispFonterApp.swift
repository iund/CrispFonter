import SwiftUI

@main
struct CrispFonterApp: App {
    init() { CrashLogger.install() }

    var body: some Scene {
        DocumentGroup(newDocument: { ProjectDocument() }) { file in
            ContentView(doc: file.document)
        }
    }
}
