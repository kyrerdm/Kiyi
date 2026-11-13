import AppKit

@main
struct DragContentChecks {
    static func main() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        func check(_ entries: [(NSPasteboard.PasteboardType, String)], expected: Bool, _ scenario: String) {
            board.clearContents()
            let item = NSPasteboardItem()
            for (type, value) in entries { item.setString(value, forType: type) }
            board.writeObjects([item])
            precondition(DragDetector.hasFileContent(on: board) == expected, scenario)
        }
        check([(.string, "Browser tab"), (.URL, "https://example.com")], expected: false, "Tab URL/text must not open the shelf")
        check([(.string, "Selected text")], expected: false, "Text is only an explicit drop")
        check([(.fileURL, "file:///tmp/example%20file.pdf"), (.string, "example file.pdf")], expected: true, "Finder file must open the shelf")
        check([(.fileURL, "https://example.com")], expected: false, "Non-file URL cannot masquerade as file")
        check([(.fileURL, "")], expected: false, "Empty file promise is not ready")
        board.clearContents()
        precondition(!DragDetector.hasFileContent(on: board), "Old file state must not survive a new empty drag")
        print("PASS: tab/text rejection, real file acceptance, invalid and stale payload rejection")
    }
}
