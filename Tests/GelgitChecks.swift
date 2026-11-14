import AppKit
@main struct GelgitChecks {
    static func main() {
        let point = CGPoint(x: 100, y: 100)
        precondition(KiyiGelgit.isPlainClick(from: point, to: point, clickCount: 1, flags: []))
        for modifier: CGEventFlags in [.maskCommand, .maskAlternate, .maskControl, .maskShift] {
            precondition(!KiyiGelgit.isPlainClick(from: point, to: point, clickCount: 1, flags: modifier))
        }
        precondition(!KiyiGelgit.isPlainClick(from: point, to: point, clickCount: 2, flags: []))
        precondition(!KiyiGelgit.isPlainClick(from: point, to: CGPoint(x: 108, y: 100), clickCount: 1, flags: []))
        precondition(!KiyiGelgit.isDrag(from: point, to: CGPoint(x: 103, y: 102)), "Click jitter must not become a drag")
        precondition(KiyiGelgit.isDrag(from: point, to: CGPoint(x: 110, y: 100)), "A real icon drag must stay native")
        print("PASS: ordinary click; modifier, double-click and movement exclusions")
    }
}
