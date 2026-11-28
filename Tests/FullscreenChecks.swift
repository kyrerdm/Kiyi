import Foundation
import CoreGraphics

@main
struct FullscreenChecks {
    static func main() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let secondary = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        precondition(KiyiFullscreenPolicy.coversDisplay(window: main, display: main))
        precondition(KiyiFullscreenPolicy.coversDisplay(window: secondary, display: secondary))
        precondition(!KiyiFullscreenPolicy.coversDisplay(window: main, display: secondary))
        precondition(!KiyiFullscreenPolicy.coversDisplay(window: CGRect(x: 0, y: 25, width: 1512, height: 900), display: main))
        precondition(!KiyiFullscreenPolicy.coversDisplay(window: CGRect(x: 20, y: 0, width: 1492, height: 982), display: main))
        precondition(!KiyiFullscreenPolicy.coversDisplay(window: .zero, display: .zero))
        precondition(KiyiFullscreenPolicy.coversDisplay(window: main.insetBy(dx: 1, dy: 1), display: main))
        precondition(KiyiFullscreenPolicy.coversDisplay(window: main.insetBy(dx: -200, dy: -200), display: main))
        for mode in ["always", "nowPlayingOnly", "never"] {
            for native in [false, true] {
                for borderless in [false, true] {
                    for media in [false, true] {
                        let expected = (native || borderless) && (mode == "always" || (mode == "nowPlayingOnly" && media))
                        precondition(KiyiFullscreenPolicy.shouldHide(mode: mode, nativeFullscreen: native,
                            borderlessFullscreen: borderless, containsMedia: media) == expected)
                    }
                }
            }
        }
        // Repeated enter/exit cycles, including an independent second display.
        for _ in 0..<100 {
            let states = [false, true, true, false, false]
            let result = states.map { KiyiFullscreenPolicy.shouldHide(mode: "always", nativeFullscreen: $0, borderlessFullscreen: false, containsMedia: false) }
            precondition(result == states)
            precondition(!KiyiFullscreenPolicy.shouldHide(mode: "always", nativeFullscreen: false, borderlessFullscreen: false, containsMedia: false))
        }
        print("PASS: fullscreen geometry, negative display origins, maximized exclusions, 24 visibility policies and enter/exit cycles")
    }
}
