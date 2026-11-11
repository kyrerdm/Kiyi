import AppKit
import SwiftUI

extension AppDelegate {
    func verifyUI() {
        // Uses an isolated preference domain, never the user's current settings.
        state.pinned = true
        var cases: [(String, (inout Configuration) -> Void)] = [
            ("compact", { $0 = Configuration(); $0.animations = false; $0.expandedWidth = 320; $0.expandedHeight = 200; $0.theme = "dark" }),
            ("wide-light", { $0.expandedWidth = 480; $0.expandedHeight = 280; $0.theme = "light" }),
            ("transparent-purple", { $0.transparency = 0.93; $0.accentMode = "custom"; $0.red = 0.7; $0.green = 0.2; $0.blue = 0.9 }),
            ("minimal", { $0.showArtwork = false; $0.showArtist = false; $0.showProgress = false; $0.showTime = false; $0.showVisualizer = false }),
            ("system-controls", { $0 = Configuration(); $0.animations = false; $0.theme = "dark"; $0.expandedHeight = 290 }),
            ("shelf", { $0.shelfEnabled = true }),
            ("smallest", { $0.expandedWidth = 280; $0.expandedHeight = 180; $0.theme = "dark"; $0.transparency = 0; $0.showArtwork = true; $0.showArtist = true; $0.showProgress = true; $0.showTime = true; $0.showVisualizer = true })
        ]
        let output = URL(fileURLWithPath: CommandLine.arguments.last ?? NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var results: [String] = []
        let system = SystemControls.shared
        system.readBrightness(); system.readVolume()
        let volume = system.volume; let brightness = system.brightness
        if system.volumeSupported { system.changeVolume(volume); results.append(abs(system.volume - volume) < 0.02 ? "PASS CoreAudio volume read/write unchanged level" : "FAIL CoreAudio volume") }
        if system.brightnessSupported { system.changeBrightness(brightness); results.append(abs(system.brightness - brightness) < 0.02 ? "PASS DisplayServices brightness read/write unchanged level" : "FAIL DisplayServices brightness") }
        results.append("INFO AirPods hardware test deferred by user; no fabricated battery values")
        let initialHost = islandHost
        func next() {
            guard !cases.isEmpty else {
                let success = !results.contains(where: { $0.hasPrefix("FAIL") })
                try? results.joined(separator: "\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                if !success { NSLog("UI verification failed") }
                return
            }
            let (name, change) = cases.removeFirst()
            self.state.page = name == "shelf" ? "shelf" : (name == "system-controls" ? "controls" : "music")
            var config = prefs.value; change(&config); prefs.value = config
            expand(true, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let expectedWidth = max(config.expandedWidth, self.notchWidth + 2 * config.wingWidth)
                let valid = abs(self.panel.frame.width - expectedWidth) < 1 && abs(self.panel.frame.height - config.expandedHeight) < 1 && self.islandHost === initialHost
                results.append("\(valid ? "PASS" : "FAIL") \(name): \(self.panel.frame.width)×\(self.panel.frame.height), stable hosting view")
                if let host = self.islandHost {
                    host.layoutSubtreeIfNeeded()
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: output.appendingPathComponent(name + ".png")) }
                    }
                }
                next()
            }
        }
        next()
    }
}
