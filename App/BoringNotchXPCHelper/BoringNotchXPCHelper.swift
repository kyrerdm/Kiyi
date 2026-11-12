//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import AppKit
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    
    @objc func spotifyFavorite(_ track: String, with reply: @escaping (NSNumber?) -> Void) {
        Task { reply(await SpotifyFavoriteBridge.readFavorite(track: track).map { NSNumber(value: $0) }) }
    }

    @objc func setSpotifyFavorite(_ favorite: Bool, track: String, with reply: @escaping (NSNumber?) -> Void) {
        Task { reply(await SpotifyFavoriteBridge.setFavorite(favorite, track: track).map { NSNumber(value: $0) }) }
    }

    @objc func audioAccessories(with reply: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler"); p.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            var result: [[String: String]] = []
            do {
                try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reports = json["SPBluetoothDataType"] as? [[String: Any]] {
                    for report in reports {
                        for kind in ["device_connected", "device_not_connected"] {
                            for entry in report[kind] as? [[String: [String: Any]]] ?? [] {
                                for (name, info) in entry where name.localizedCaseInsensitiveContains("airpod") || ["Headphones", "Headset"].contains(info["device_minorType"] as? String ?? "") {
                                    var item = ["name": name, "connected": kind == "device_connected" ? "true" : "false"]
                                    for key in ["Left", "Right", "Main", "Case"] { if let value = info["device_batteryLevel" + key] as? String { item[key] = value } }
                                    result.append(item)
                                }
                            }
                        }
                    }
                }
            } catch {}
            let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("[]".utf8)
            reply(String(data: data, encoding: .utf8) ?? "[]")
        }
    }

    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

// Keep Accessibility IPC off the UI thread. Only Spotify's current-track group is
// inspected; library and playlist buttons must never be mistaken for this control.
private enum SpotifyFavoriteBridge {
    private static let queue = DispatchQueue(label: "local.kiyi.spotify-favorite", qos: .userInitiated)

    static func readFavorite(track: String) async -> Bool? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: currentControl(track: track)?.saved) }
        }
    }

    static func setFavorite(_ favorite: Bool, track: String) async -> Bool? {
        let sent: Bool = await withCheckedContinuation { continuation in
            queue.async {
                guard let control = currentControl(track: track) else {
                    continuation.resume(returning: false)
                    return
                }
                if control.saved == favorite {
                    continuation.resume(returning: true)
                    return
                }
                if favorite {
                    continuation.resume(returning: AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success)
                } else {
                    // Spotify's documented Like/Dislike shortcut. Target Spotify
                    // directly so Kıyı never steals focus or types into another app.
                    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 11, keyDown: true),
                          let up = CGEvent(keyboardEventSource: nil, virtualKey: 11, keyDown: false) else {
                        continuation.resume(returning: false)
                        return
                    }
                    down.flags = [.maskAlternate, .maskShift]
                    up.flags = [.maskAlternate, .maskShift]
                    down.postToPid(control.pid)
                    up.postToPid(control.pid)
                    continuation.resume(returning: true)
                }
            }
        }
        guard sent else { return nil }
        // Publish only the state confirmed by Spotify, including asynchronous UI updates.
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(150))
            if let saved = await readFavorite(track: track), saved == favorite { return saved }
        }
        return await readFavorite(track: track)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func label(_ element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            .compactMap { attribute(element, $0) as? String }.joined(separator: " ").lowercased()
    }

    private static func currentControl(track: String) -> (element: AXUIElement, saved: Bool, pid: pid_t)? {
        guard AXIsProcessTrusted(), !track.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        let playingLabels = ["şu anda çalan:", "now playing:", "aktuelle wiedergabe:", "wird abgespielt:"]
        let unsavedLabels = ["beğenilen şarkılar çalma listesine ekle", "add to liked songs", "zu lieblingssongs hinzufügen"]
        let savedLabels = ["çalma listesine ekle", "add to playlist", "zur playlist hinzufügen", "zu einer playlist hinzufügen", "remove from liked songs", "aus lieblingssongs entfernen"]
        while let (element, depth) = pending.popLast(), visited < 2500 {
            visited += 1
            let text = label(element)
            if playingLabels.contains(where: { text.contains($0) }), text.contains(track.lowercased()) {
                let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                for child in children {
                    guard attribute(child, kAXRoleAttribute) as? String == kAXButtonRole else { continue }
                    let buttonLabel = label(child)
                    if unsavedLabels.contains(where: { buttonLabel.contains($0) }) { return (child, false, app.processIdentifier) }
                    if savedLabels.contains(where: { buttonLabel.contains($0) }) { return (child, true, app.processIdentifier) }
                }
            }
            if depth < 30 {
                let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return nil
    }
}
