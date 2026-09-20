import Foundation

/// The `prep` program (build spec §6): dropout control, and disabling instructions above the
/// hint cut-off ppem (`if MPPEM > hintCutoffPPEM then INSTCTRL off`).
enum PrepProgram {
    static func compile(project: FontProject) -> Data {
        var p = Program()
        p.push(4); p.scanctrl()   // dropout control: always apply rules 1-3
        p.push(2); p.scantype()   // enable stub handling

        p.push(project.export.hintCutoffPPEM)
        p.mppem()
        p.gt()
        p.ifOp()
        p.push([1, 1]) // value = 1 (off), selector = 1 (instructing)
        p.instctrl()
        p.eif()
        return p.data
    }
}
