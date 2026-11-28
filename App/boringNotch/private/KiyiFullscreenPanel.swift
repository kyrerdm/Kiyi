import AppKit

/// Suppress the whole panel: transparent SwiftUI content alone still catches clicks.
class KiyiFullscreenPanel: NSPanel {
    private var fullscreenSuppressed = false
    private var restoreAfterFullscreen = false
    var fullscreenExempt = false {
        didSet { applyFullscreenVisibility() }
    }

    func setFullscreenSuppressed(_ hidden: Bool) {
        guard fullscreenSuppressed != hidden else { return }
        fullscreenSuppressed = hidden
        applyFullscreenVisibility()
    }

    private func applyFullscreenVisibility() {
        if fullscreenSuppressed && !fullscreenExempt {
            if isVisible { restoreAfterFullscreen = true }
            ignoresMouseEvents = true
            super.orderOut(nil)
        } else {
            ignoresMouseEvents = false
            if restoreAfterFullscreen {
                restoreAfterFullscreen = false
                super.orderFrontRegardless()
            }
        }
    }

    override func orderFrontRegardless() {
        guard !fullscreenSuppressed || fullscreenExempt else { return }
        super.orderFrontRegardless()
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard place == .out || !fullscreenSuppressed || fullscreenExempt else { return }
        super.order(place, relativeTo: otherWin)
    }
}
