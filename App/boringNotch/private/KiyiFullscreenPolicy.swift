import Foundation
import CoreGraphics

/// Pure geometry/policy shared by the detector and regression checks.
enum KiyiFullscreenPolicy {
    static func coversDisplay(window: CGRect, display: CGRect) -> Bool {
        guard display.width > 0, display.height > 0,
              window.width.isFinite, window.height.isFinite else { return false }
        let tolerance: CGFloat = 2
        return window.minX <= display.minX + tolerance
            && window.minY <= display.minY + tolerance
            && window.maxX >= display.maxX - tolerance
            && window.maxY >= display.maxY - tolerance
    }

    static func shouldHide(mode: String, nativeFullscreen: Bool,
                           borderlessFullscreen: Bool, containsMedia: Bool) -> Bool {
        guard nativeFullscreen || borderlessFullscreen else { return false }
        switch mode {
        case "always": return true
        case "nowPlayingOnly": return containsMedia
        default: return false
        }
    }
}
