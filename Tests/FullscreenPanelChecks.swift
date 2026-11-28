import AppKit

@main
struct FullscreenPanelChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let panel = KiyiFullscreenPanel(contentRect: CGRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        precondition(panel.isVisible)
        for _ in 0..<10 {
            panel.setFullscreenSuppressed(true)
            precondition(!panel.isVisible && panel.ignoresMouseEvents)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.order(.above, relativeTo: 0)
            precondition(!panel.isVisible && panel.ignoresMouseEvents)
            panel.setFullscreenSuppressed(false)
            precondition(panel.isVisible && !panel.ignoresMouseEvents)
        }
        panel.orderOut(nil)
        panel.setFullscreenSuppressed(true)
        panel.setFullscreenSuppressed(false)
        precondition(!panel.isVisible, "An already hidden panel must stay hidden")
        panel.orderFrontRegardless()
        panel.setFullscreenSuppressed(true)
        panel.fullscreenExempt = true
        precondition(panel.isVisible && !panel.ignoresMouseEvents)
        panel.fullscreenExempt = false
        precondition(!panel.isVisible && panel.ignoresMouseEvents)
        panel.setFullscreenSuppressed(false)
        precondition(panel.isVisible)
        panel.close()
        // Exercise the production CGWindow metadata path with a real borderless window.
        guard let screen = NSScreen.screens.first,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            fatalError("A WindowServer display is required for runtime checks")
        }
        let display = CGDisplayBounds(number.uint32Value)
        let game = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        game.isReleasedWhenClosed = false
        game.isOpaque = false
        game.backgroundColor = .clear
        game.ignoresMouseEvents = true
        game.orderFrontRegardless()
        let pid = ProcessInfo.processInfo.processIdentifier
        // WindowServer geometry commits asynchronously after AppKit order/resize.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(KiyiFullscreenWindows.coveredDisplays(pid: pid, displays: [("test", display)]) == ["test"])
        game.setFrame(screen.visibleFrame.insetBy(dx: 40, dy: 40), display: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(KiyiFullscreenWindows.coveredDisplays(pid: pid, displays: [("test", display)]).isEmpty)
        game.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(KiyiFullscreenWindows.coveredDisplays(pid: pid, displays: [("test", display)]).isEmpty)
        print("PASS: actual NSPanel hiding, input pass-through, blocked reorder, restoration, lock-screen exemption and real borderless WindowServer detection")
    }
}
