import Foundation
import CoreGraphics

/// Window metadata only. No window titles, images, AX calls or capture permission.
enum KiyiFullscreenWindows {
    static func coveredDisplays(pid: Int32, displays: [(String, CGRect)]) -> Set<String> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = windows.compactMap { entry -> CGRect? in
            guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        return Set(displays.compactMap { uuid, display in
            frames.contains { KiyiFullscreenPolicy.coversDisplay(window: $0, display: display) } ? uuid : nil
        })
    }
}
