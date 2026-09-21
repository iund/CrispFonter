import Foundation

/// Catches uncaught NSExceptions and fatal signals, and keeps a rolling breadcrumb trail of recent
/// actions (mode switches, glyph selection, document mutations, mouse gestures). Everything is
/// appended to a plain-text log file, so a crash that happens outside Xcode's debugger — the whole
/// point of this being a real app, not just a debug session — still leaves something to diagnose.
enum CrashLogger {
    // A fixed, predictable path rather than NSTemporaryDirectory() (which resolves to a
    // per-session /var/folders/.../T/ directory that's awkward to find by hand).
    static let logURL = URL(fileURLWithPath: "/tmp/CrispFonter-crash.log")

    private static var breadcrumbs: [String] = []
    private static let lock = NSLock()

    static func install() {
        log("=== CrispFonter launched \(Date()) pid=\(ProcessInfo.processInfo.processIdentifier) — crash log at \(logURL.path) ===")

        NSSetUncaughtExceptionHandler { exception in
            CrashLogger.writeCrash(
                "Uncaught NSException: \(exception.name.rawValue): \(exception.reason ?? "no reason")",
                symbols: exception.callStackSymbols
            )
        }

        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP, SIGPIPE] {
            signal(sig) { signalValue in
                CrashLogger.writeCrash("Fatal signal \(signalValue)", symbols: Thread.callStackSymbols)
                signal(signalValue, SIG_DFL)
                raise(signalValue)
            }
        }
    }

    /// A short note about something the user just did — mode switch, glyph pick, a document edit,
    /// a mouse gesture starting. Cheap enough to sprinkle liberally; only the last 200 are kept.
    static func breadcrumb(_ message: @autoclosure () -> String) {
        let line = "\(timestamp()) \(message())"
        lock.lock()
        breadcrumbs.append(line)
        if breadcrumbs.count > 200 { breadcrumbs.removeFirst(breadcrumbs.count - 200) }
        lock.unlock()
    }

    static func log(_ message: String) {
        breadcrumb(message)
        append(message)
    }

    private static func writeCrash(_ header: String, symbols: [String]) {
        lock.lock()
        let trail = breadcrumbs.joined(separator: "\n")
        let count = breadcrumbs.count
        lock.unlock()
        let text = """

        ############ CRASH \(Date()) ############
        \(header)

        --- stack ---
        \(symbols.joined(separator: "\n"))

        --- last \(count) breadcrumbs (oldest first) ---
        \(trail)
        ##########################################

        """
        append(text)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private static func append(_ text: String) {
        let line = text.hasSuffix("\n") ? text : text + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
