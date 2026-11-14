// Dock hover observation adapted from WinMin (MIT).
// Copyright (c) 2025 WinMin Contributors. See WinMin-LICENSE.txt.
import AppKit
import ApplicationServices
import OSLog

/// Dock click-to-minimize. Eligible clicks are handled once, without a competing
/// native Dock activation. A drag is returned to Dock as a native mouse-down;
/// modifier/right clicks and ineligible applications pass through unchanged.
final class KiyiGelgit {
    private struct Click {
        let point: CGPoint
        let pid: pid_t
        let windows: [AXUIElement]
        let restoring: Bool
        let generation: Int
        let timestamp: CGEventTimestamp
        let originalDown: CGEvent
    }
    private final class EventLoop {
        var runLoop: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
    }
    private let stateLock = NSRecursiveLock()
    private var eventLoop: EventLoop?
    private let log = Logger(subsystem: "local.kayra.adanotch", category: "Gelgit")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var dockObserver: AXObserver?
    private var dockList: AXUIElement?
    private var hoveredApplication: NSRunningApplication?
    private var hoveredFrame: CGRect = .null
    private var click: Click?
    private var minimizedGroups: [pid_t: [AXUIElement]] = [:]
    private var generation = 0
    private var allWindows = false
    private var includeFinder = true
    private var foregroundPID: pid_t = 0
    private var preparedApplications = Set<pid_t>()

    func configure(enabled: Bool, allWindows: Bool, includeFinder: Bool, frontmostPID: Int32) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if self.allWindows != allWindows || self.includeFinder != includeFinder {
            generation += 1
            click = nil
        }
        self.allWindows = allWindows
        self.includeFinder = includeFinder
        self.foregroundPID = frontmostPID
        guard enabled, AXIsProcessTrusted() else { stop(); return false }
        if frontmostPID > 0 && !preparedApplications.contains(frontmostPID) {
            let app = AXUIElementCreateApplication(frontmostPID)
            AXUIElementSetMessagingTimeout(app, 0.1)
            // Chromium/Electron expose their windows lazily. Request their AX
            // interface on activation, before a later Dock click needs it.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            preparedApplications.insert(frontmostPID)
        }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return CGEvent.tapIsEnabled(tap: tap)
        }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context {
                    if Unmanaged<KiyiGelgit>.fromOpaque(context).takeUnretainedValue().handle(type, event) { return nil }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { log.error("Dock click monitoring unavailable"); return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source else { stop(); return false }
        // NSXPCListener services use dispatch_main, not an AppKit run loop.
        // A CGEvent source on their main CFRunLoop never receives mouse events.
        let loop = EventLoop()
        eventLoop = loop
        let installObserver: () -> Void = { [weak self] in self?.installDockObserver() }
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            loop.runLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            loop.ready.signal()
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, installObserver)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        thread.name = "Kiyi.Gelgit.Events"
        thread.start()
        guard loop.ready.wait(timeout: .now() + 1) == .success else { stop(); return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        log.info("Dock click monitoring enabled")
        return true
    }

    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        generation += 1
        click = nil
        minimizedGroups.removeAll()
        preparedApplications.removeAll()
        if let observer = dockObserver, let list = dockList {
            AXObserverRemoveNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString)
            if let runLoop = eventLoop?.runLoop {
                CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
        dockObserver = nil
        dockList = nil
        hoveredApplication = nil
        hoveredFrame = .null
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoop = eventLoop?.runLoop { CFRunLoopStop(runLoop) }
        eventLoop = nil
        tap = nil
        source = nil
    }
    deinit { stop() }

    static func isPlainClick(from start: CGPoint, to end: CGPoint, clickCount: Int64, flags: CGEventFlags) -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        return clickCount == 1 && flags.intersection(modifiers).isEmpty
            && hypot(end.x - start.x, end.y - start.y) <= 5
    }

    private static let replayTag: Int64 = 0x4B49594947454C

    static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > 5
    }

    /// true consumes a click owned by Gelgit; false preserves the native event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayTag { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            click = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .leftMouseDragged {
            guard let pending = click, Self.isDrag(from: pending.point, to: event.location) else { return click != nil }
            click = nil
            // Dock has not seen the captured down. Deliver it instead of the
            // threshold-crossing drag; later drag events and release are native.
            event.type = .leftMouseDown
            event.location = pending.point
            event.flags = pending.originalDown.flags
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            return false
        }
        if type == .leftMouseDown {
            generation += 1
            click = nil
            guard Self.isPlainClick(from: event.location, to: event.location,
                      clickCount: event.getIntegerValueField(.mouseEventClickState), flags: event.flags),
                  !isLocked(), let original = event.copy(),
                  let app = dockApplication(at: event.location),
                  includeFinder || app.bundleIdentifier != "com.apple.finder" else { return false }
            let pid = app.processIdentifier
            let frontmostPID = currentFrontmostPID()
            if let group = minimizedGroups[pid] {
                let existing = group.filter { attribute($0, kAXRoleAttribute) as? String == kAXWindowRole }
                if !existing.isEmpty {
                    click = Click(point: event.location, pid: pid, windows: existing, restoring: true,
                                  generation: generation, timestamp: event.timestamp, originalDown: original)
                    return true
                }
                minimizedGroups.removeValue(forKey: pid)
            }
            guard pid == frontmostPID else { return false }
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.1)
            let focused = attribute(root, kAXFocusedWindowAttribute) ?? attribute(root, kAXMainWindowAttribute)
            let all = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            let target: AXUIElement?
            if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                target = unsafeBitCast(focused, to: AXUIElement.self)
            } else {
                target = all.first(where: isMinimizable)
            }
            guard let window = target, isMinimizable(window) else { return false }
            let windows = allWindows ? all.filter(isMinimizable) : [window]
            guard !windows.isEmpty else { return false }
            click = Click(point: event.location, pid: pid, windows: windows, restoring: false,
                          generation: generation, timestamp: event.timestamp, originalDown: original)
            return true
        }
        if type == .leftMouseUp, let candidate = click {
            click = nil
            guard Self.isPlainClick(from: candidate.point, to: event.location, clickCount: 1, flags: event.flags),
                  event.timestamp >= candidate.timestamp,
                  event.timestamp - candidate.timestamp < 450_000_000,
                  dockApplication(at: event.location)?.processIdentifier == candidate.pid else {
                replayNativeClick(candidate, up: event)
                return true
            }
            DispatchQueue.main.async { [weak self] in self?.apply(candidate, attempt: 0) }
            return true
        }
        return false
    }

    private func replayNativeClick(_ candidate: Click, up: CGEvent) {
        guard let down = candidate.originalDown.copy(), let release = up.copy() else { return }
        down.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
        release.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
        down.post(tap: .cghidEventTap)
        release.post(tap: .cghidEventTap)
    }

    private func apply(_ candidate: Click, attempt: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard tap != nil, generation == candidate.generation, !isLocked() else { return }
        if candidate.restoring {
            NSRunningApplication(processIdentifier: candidate.pid)?.activate(options: [.activateAllWindows])
        } else if currentFrontmostPID() != candidate.pid { return }
        var changed: [AXUIElement] = []
        var pending: [AXUIElement] = []
        for window in candidate.windows {
            if attribute(window, kAXMinimizedAttribute) as? Bool == !candidate.restoring {
                changed.append(window)
                continue
            }
            if !candidate.restoring && !isMinimizable(window) { continue }
            let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                candidate.restoring ? kCFBooleanFalse : kCFBooleanTrue)
            if result == .success { changed.append(window) }
            else { pending.append(window) }
        }
        if candidate.restoring {
            if pending.isEmpty { minimizedGroups.removeValue(forKey: candidate.pid) }
            if let window = changed.last { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
        } else if !changed.isEmpty {
            var group = minimizedGroups[candidate.pid] ?? []
            for window in changed where !group.contains(where: { CFEqual($0, window) }) { group.append(window) }
            minimizedGroups[candidate.pid] = group
        }
        log.info("Dock action restoring=\(candidate.restoring), windows=\(changed.count), pending=\(pending.count)")
        if !pending.isEmpty && attempt < 2 {
            let retry = Click(point: candidate.point, pid: candidate.pid, windows: pending, restoring: candidate.restoring,
                              generation: candidate.generation, timestamp: candidate.timestamp, originalDown: candidate.originalDown)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.apply(retry, attempt: attempt + 1) }
        }
    }

    private func currentFrontmostPID() -> pid_t? {
        // The GUI process relays NSWorkspace activation notifications. An XPC
        // service has neither a live AppKit activation cache nor reliable focus
        // attributes while Dock temporarily owns the click.
        foregroundPID > 0 ? foregroundPID : nil
    }

    private func isLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func isMinimizable(_ window: AXUIElement) -> Bool {
        guard attribute(window, kAXRoleAttribute) as? String == kAXWindowRole,
              ![kAXDialogSubrole, kAXSystemDialogSubrole].contains(attribute(window, kAXSubroleAttribute) as? String ?? ""),
              attribute(window, kAXMinimizedAttribute) as? Bool == false,
              attribute(window, "AXFullScreen") as? Bool != true,
              attribute(window, kAXModalAttribute) as? Bool != true,
              !(attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains(where: {
                  attribute($0, kAXRoleAttribute) as? String == kAXSheetRole
              }) else { return false }
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue
    }
    private func installDockObserver() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard tap != nil, dockObserver == nil,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let list = (attribute(root, kAXChildrenAttribute) as? [AXUIElement])?.first(where: {
            attribute($0, kAXRoleAttribute) as? String == kAXListRole
        }) else { log.error("Dock application list unavailable"); return }
        var observer: AXObserver?
        guard AXObserverCreate(dock.processIdentifier, { _, _, _, context in
            guard let context else { return }
            Unmanaged<KiyiGelgit>.fromOpaque(context).takeUnretainedValue().updateHoveredApplication()
        }, &observer) == .success, let observer else { return }
        let result = AXObserverAddNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        guard result == .success else { log.error("Dock hover observation failed: \(result.rawValue)"); return }
        dockList = list
        dockObserver = observer
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        updateHoveredApplication()
        log.info("Dock hover observation enabled")
    }

    private func updateHoveredApplication() {
        stateLock.lock()
        defer { stateLock.unlock() }
        hoveredApplication = nil
        hoveredFrame = .null
        guard let list = dockList,
              let item = (attribute(list, kAXSelectedChildrenAttribute) as? [AXUIElement])?.first,
              attribute(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
              let app = application(forDockItem: item),
              let position = attribute(item, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(item, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return }
        hoveredApplication = app
        hoveredFrame = CGRect(origin: point, size: dimensions)
    }

    private func application(forDockItem item: AXUIElement) -> NSRunningApplication? {
        guard let nsURL = attribute(item, kAXURLAttribute) as? NSURL,
              let identifier = Bundle(url: nsURL as URL)?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { !$0.isTerminated }
    }

    private func dockApplication(at point: CGPoint) -> NSRunningApplication? {
        if hoveredFrame.contains(point), let app = hoveredApplication, !app.isTerminated { return app }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let root = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 0.1)
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit)
        guard result == .success else {
            log.debug("Dock hit test failed: \(result.rawValue)")
            return nil
        }
        for _ in 0..<4 {
            guard let element = hit else { break }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            guard pid == dock.processIdentifier else { return nil }
            if attribute(element, kAXSubroleAttribute) as? String == "AXApplicationDockItem" {
                return application(forDockItem: element)
            }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            hit = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return nil
    }
}
