// Dock hover observation adapted from WinMin (MIT).
// Copyright (c) 2025 WinMin Contributors. See WinMin-LICENSE.txt.
import AppKit
import ApplicationServices
import OSLog

/// A late AX reply must never turn an old click into a new window action.
struct GelgitOperationGate {
    enum Phase { case reading, acting, finished }
    let generation: UInt64
    let deadline: UInt64
    private(set) var phase = Phase.reading
    mutating func claim(now: UInt64, generation current: UInt64) -> Bool {
        guard phase == .reading, now < deadline, generation == current else { return false }
        phase = .acting
        return true
    }
    mutating func expire(now: UInt64) -> Bool {
        guard phase == .reading, now >= deadline else { return false }
        phase = .finished
        return true
    }
}

// A restore click must never become a minimize when native Dock restoration
// or an animation has already changed the window's minimized state.
enum GelgitWindowAction {
    case restore, minimize, native
    static func choose(restoreRequested: Bool, hasMinimizedWindows: Bool, targetFocused: Bool) -> Self {
        if restoreRequested { return hasMinimizedWindows ? .restore : .native }
        return targetFocused ? .minimize : .native
    }
}

struct GelgitClickSequence {
    private var pid: pid_t?
    private var timestamp: UInt64 = 0
    mutating func record(pid: pid_t, timestamp: UInt64) { self.pid = pid; self.timestamp = timestamp }
    func isFollowup(pid: pid_t, clickCount: Int64, timestamp: UInt64, interval: UInt64) -> Bool {
        clickCount > 1 && self.pid == pid && timestamp >= self.timestamp && timestamp - self.timestamp <= interval
    }
}

/// The input callback only reads small cached values. All Accessibility IPC,
/// app activation and window mutations run on axQueue, without its state lock.
final class KiyiGelgit {
    private struct Hit { let pid: pid_t; let dockOwner: pid_t; let finder: Bool; let frame: CGRect }
    private struct Press {
        let id: UInt64
        let pid: pid_t
        let dockOwner: pid_t
        let point: CGPoint
        let original: CGEvent
        let allWindows: Bool
        let group: [AXUIElement]
        let restoreRequested: Bool
        let suppressOnly: Bool
    }
    private struct Work {
        let press: Press
        let up: CGEvent
        let started: UInt64
        var gate: GelgitOperationGate
    }
    private final class EventLoop {
        var runLoop: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
    }
    private let stateLock = NSLock()
    private var enabled = false
    private var allWindows = false
    private var includeFinder = true
    private var foregroundPID: pid_t = 0
    private var generation: UInt64 = 0
    private var hit: Hit?
    private var press: Press?
    private var work: [UInt64: Work] = [:]
    private var groups: [pid_t: [AXUIElement]] = [:]
    private var clickSequence = GelgitClickSequence()
    private var doubleClickInterval: UInt64 = 1_000_000_000
    private var refreshQueued = false
    private var tap: CFMachPort?
    private var eventLoop: EventLoop?

    // Only axQueue owns these objects; no AX call is made with stateLock held.
    private let axQueue = DispatchQueue(label: "local.kiyi.gelgit.accessibility", qos: .userInitiated)
    private var observer: AXObserver?
    private var dockList: AXUIElement?
    private var dockPID: pid_t?
    private var observerLoop: CFRunLoop?
    private var refreshTimer: DispatchSourceTimer?
    private var prepared = Set<pid_t>()
    private let log = Logger(subsystem: "local.kayra.adanotch", category: "Gelgit")
    private static let replayTag: Int64 = 0x4B49594947454C
    private static let decisionBudget: UInt64 = 200_000_000

    private func locked<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
    private var now: UInt64 { DispatchTime.now().uptimeNanoseconds }

    func configure(enabled: Bool, allWindows: Bool, includeFinder: Bool, frontmostPID: Int32) -> Bool {
        guard enabled, AXIsProcessTrusted() else { stop(); return false }
        let clickInterval = UInt64(max(0.15, NSEvent.doubleClickInterval) * 1_000_000_000)
        let changedPID = locked { () -> Bool in
            doubleClickInterval = clickInterval
            let changed = foregroundPID != frontmostPID
            if self.allWindows != allWindows || self.includeFinder != includeFinder {
                generation &+= 1
                press = nil
                work.removeAll()
            }
            self.enabled = true
            self.allWindows = allWindows
            self.includeFinder = includeFinder
            foregroundPID = frontmostPID
            return changed
        }
        if locked({ tap == nil }) { startEventLoop() }
        let loop = locked { eventLoop?.runLoop }
        axQueue.async { [weak self] in
            guard let self, self.locked({ self.enabled }) else { return }
            self.startAXMonitoring(loop: loop)
            if changedPID || !self.prepared.contains(frontmostPID) { self.prepareApplication(frontmostPID) }
        }
        return locked { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    }

    private func startEventLoop() {
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<KiyiGelgit>.fromOpaque(context).takeUnretainedValue()
                return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            log.error("Dock event tap unavailable")
            return
        }
        let loop = EventLoop()
        locked { tap = port; eventLoop = loop }
        let thread = Thread {
            loop.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop.runLoop, source, .commonModes)
            loop.ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop.runLoop, source, .commonModes)
        }
        thread.name = "Kiyi.Gelgit.Input"
        thread.start()
        if loop.ready.wait(timeout: .now() + 1) == .success {
            CGEvent.tapEnable(tap: port, enable: true)
            log.info("Nonblocking Dock input enabled")
        } else { stop() }
    }

    func stop() {
        let old = locked { () -> (CFMachPort?, CFRunLoop?) in
            enabled = false
            generation &+= 1
            press = nil
            hit = nil
            work.removeAll()
            groups.removeAll()
            clickSequence = GelgitClickSequence()
            let old = (tap, eventLoop?.runLoop)
            tap = nil
            eventLoop = nil
            return old
        }
        if let port = old.0 { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let loop = old.1 { CFRunLoopStop(loop) }
        axQueue.async { [weak self] in self?.stopAXMonitoring() }
    }
    deinit {
        if let tap { CFMachPortInvalidate(tap) }
        if let loop = eventLoop?.runLoop { CFRunLoopStop(loop) }
        refreshTimer?.cancel()
    }

    static func isPlainClick(from start: CGPoint, to end: CGPoint, clickCount: Int64, flags: CGEventFlags) -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        return clickCount == 1 && flags.intersection(modifiers).isEmpty && !isDrag(from: start, to: end)
    }
    static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool { hypot(end.x - start.x, end.y - start.y) > 5 }

    // This entire method is deliberately free of AX / NSWorkspace / activation calls.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayTag { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let port = locked { () -> CFMachPort? in press = nil; return tap }
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            log.error("Dock input tap recovered")
            return false
        }
        return locked {
            guard enabled else { return false }
            if type == .leftMouseDown {
                press = nil
                // Only suppress the remainder of a click sequence that *we* began.
                // Keep its mouse pair for the normal drag escape path below.
                let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
                if event.flags.intersection(modifiers).isEmpty, let hit,
                   hit.frame.contains(event.location),
                   clickSequence.isFollowup(pid: hit.pid, clickCount: event.getIntegerValueField(.mouseEventClickState),
                                            timestamp: event.timestamp, interval: doubleClickInterval),
                   let original = event.copy() {
                    clickSequence.record(pid: hit.pid, timestamp: event.timestamp)
                    press = Press(id: generation, pid: hit.pid, dockOwner: hit.dockOwner, point: event.location,
                                  original: original, allWindows: allWindows, group: [], restoreRequested: false, suppressOnly: true)
                    return true
                }
                generation &+= 1
                press = nil
                // Never execute the result of an earlier, superseded click.
                work = work.filter { $0.value.gate.phase == .acting }
                guard Self.isPlainClick(from: event.location, to: event.location,
                          clickCount: event.getIntegerValueField(.mouseEventClickState), flags: event.flags),
                      let hit, hit.frame.contains(event.location), includeFinder || !hit.finder,
                      foregroundPID == hit.pid || groups[hit.pid] != nil,
                      let original = event.copy() else { return false }
                press = Press(id: generation, pid: hit.pid, dockOwner: hit.dockOwner, point: event.location, original: original,
                              allWindows: allWindows, group: groups[hit.pid] ?? [],
                              restoreRequested: groups[hit.pid] != nil, suppressOnly: false)
                clickSequence.record(pid: hit.pid, timestamp: event.timestamp)
                return true
            }
            if type == .leftMouseDragged, let pending = press {
                guard Self.isDrag(from: pending.point, to: event.location) else { return true }
                press = nil
                event.type = .leftMouseDown
                event.location = pending.point
                event.flags = pending.original.flags
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                return false
            }
            if type == .leftMouseUp, let pending = press {
                press = nil
                if pending.suppressOnly { return true }
                guard let up = event.copy() else { return false }
                guard Self.isPlainClick(from: pending.point, to: event.location, clickCount: 1, flags: event.flags),
                      hit?.pid == pending.pid else {
                    DispatchQueue.global(qos: .userInteractive).async { Self.replay(pending, up: up) }
                    return true
                }
                let start = now
                work[pending.id] = Work(press: pending, up: up, started: start,
                    gate: GelgitOperationGate(generation: pending.id, deadline: start + Self.decisionBudget))
                // Independent watchdog: even an unresponsive app cannot hold a click for seconds.
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self] in
                    self?.expire(pending.id)
                }
                axQueue.async { [weak self] in self?.resolve(pending.id) }
                return true
            }
            return false
        }
    }

    private static func replay(_ pending: Press, up: CGEvent) {
        guard let down = pending.original.copy(), let release = up.copy() else { return }
        down.setIntegerValueField(.eventSourceUserData, value: replayTag)
        release.setIntegerValueField(.eventSourceUserData, value: replayTag)
        // A delayed fallback belongs to Dock, even if the pointer has since
        // moved over a different app. Never replay it into the global hit target.
        down.postToPid(pending.dockOwner)
        release.postToPid(pending.dockOwner)
    }
    private func expire(_ id: UInt64) {
        let expired: Work? = locked {
            guard var item = work[id], item.gate.expire(now: now) else { return nil }
            work.removeValue(forKey: id)
            return item
        }
        if let expired {
            Self.replay(expired.press, up: expired.up)
            log.info("Dock decision timed out; native click preserved")
        }
    }
    private func nativeFallback(_ id: UInt64) {
        let item: Work? = locked {
            guard let item = work[id], item.gate.phase == .reading else { return nil }
            work.removeValue(forKey: id)
            return item
        }
        if let item { Self.replay(item.press, up: item.up) }
    }

    private func resolve(_ id: UInt64) {
        guard let item = locked({ work[id] }), locked({ enabled && generation == id }) else { return }
        let deadline = item.gate.deadline - 50_000_000 // reserve a full AX mutation timeout
        let pid = item.press.pid
        var restoring = false
        var windows: [AXUIElement] = []
        if !item.press.group.isEmpty {
            windows = item.press.group.filter { read($0, kAXMinimizedAttribute, deadline: deadline) as? Bool == true }
            restoring = !windows.isEmpty
        }
        // Resolve focus off the input callback: the relayed foreground PID can
        // briefly lag behind a native Dock activation.
        var focusedPID: pid_t = 0
        if !item.press.restoreRequested,
           let focused = read(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute, deadline: deadline),
           CFGetTypeID(focused) == AXUIElementGetTypeID() {
            AXUIElementGetPid(unsafeBitCast(focused, to: AXUIElement.self), &focusedPID)
        }
        let action = GelgitWindowAction.choose(restoreRequested: item.press.restoreRequested,
            hasMinimizedWindows: restoring, targetFocused: focusedPID == pid)
        guard action != .native else {
            if item.press.restoreRequested && !restoring {
                locked { if generation == id { groups.removeValue(forKey: pid) } }
            }
            nativeFallback(id)
            return
        }
        if action == .minimize {
            guard locked({ foregroundPID == pid }) else { nativeFallback(id); return }
            let app = AXUIElementCreateApplication(pid)
            let focused = read(app, kAXFocusedWindowAttribute, deadline: deadline) ?? read(app, kAXMainWindowAttribute, deadline: deadline)
            let all = read(app, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] ?? []
            if item.press.allWindows {
                windows = all.filter { minimizable($0, deadline: deadline) }
            } else if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let window = unsafeBitCast(focused, to: AXUIElement.self)
                windows = minimizable(window, deadline: deadline) ? [window] : []
            } else { windows = Array(all.filter { minimizable($0, deadline: deadline) }.prefix(1)) }
        }
        guard !windows.isEmpty, now < deadline else { nativeFallback(id); return }
        let claimed = locked { () -> Bool in
            guard enabled, var current = work[id], current.gate.claim(now: now, generation: generation) else { return false }
            work[id] = current
            return true
        }
        guard claimed else { return }
        // No native replay after committing: it would compete with this window action.
        var changed: [AXUIElement] = []
        for window in windows {
            guard locked({ enabled && generation == id }) else { break }
            AXUIElementSetMessagingTimeout(window, 0.04)
            if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                           restoring ? kCFBooleanFalse : kCFBooleanTrue) == .success { changed.append(window) }
        }
        locked {
            if restoring { groups.removeValue(forKey: pid) }
            else if !changed.isEmpty { groups[pid] = changed }
            work.removeValue(forKey: id)
        }
        if restoring, let last = changed.last {
            // Do not put activation or AXRaise on the event loop or behind its lock.
            AXUIElementPerformAction(last, kAXRaiseAction as CFString)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.locked({ self.enabled && self.generation == id }) else { return }
                NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
            }
        }
        let milliseconds = Double(now - item.started) / 1_000_000
        log.info("Dock action restoring=\(restoring), windows=\(changed.count), elapsed_ms=\(milliseconds)")
    }

    private func read(_ element: AXUIElement, _ name: String, deadline: UInt64? = nil) -> CFTypeRef? {
        if let deadline, now >= deadline { return nil }
        AXUIElementSetMessagingTimeout(element, 0.04)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func minimizable(_ window: AXUIElement, deadline: UInt64) -> Bool {
        guard read(window, kAXRoleAttribute, deadline: deadline) as? String == kAXWindowRole,
              ![kAXDialogSubrole, kAXSystemDialogSubrole].contains(read(window, kAXSubroleAttribute, deadline: deadline) as? String ?? ""),
              read(window, kAXMinimizedAttribute, deadline: deadline) as? Bool == false,
              read(window, "AXFullScreen", deadline: deadline) as? Bool != true,
              read(window, kAXModalAttribute, deadline: deadline) as? Bool != true else { return false }
        let children = read(window, kAXChildrenAttribute, deadline: deadline) as? [AXUIElement] ?? []
        guard !children.contains(where: { read($0, kAXRoleAttribute, deadline: deadline) as? String == kAXSheetRole }), now < deadline else { return false }
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue
    }

    private func prepareApplication(_ pid: pid_t) {
        guard pid > 0, !prepared.contains(pid), locked({ enabled && foregroundPID == pid }) else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        prepared.insert(pid)
    }
    private func startAXMonitoring(loop: CFRunLoop?) {
        if refreshTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: axQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.refreshDock(loop: loop) }
            refreshTimer = timer
            timer.resume()
        }
        refreshDock(loop: loop)
    }
    private func stopAXMonitoring() {
        refreshTimer?.cancel()
        refreshTimer = nil
        removeDockObserver()
        prepared.removeAll()
        locked { refreshQueued = false }
    }
    private func removeDockObserver() {
        if let observer, let dockList {
            AXObserverRemoveNotification(observer, dockList, kAXSelectedChildrenChangedNotification as CFString)
            if let observerLoop { CFRunLoopRemoveSource(observerLoop, AXObserverGetRunLoopSource(observer), .commonModes) }
        }
        observer = nil
        dockList = nil
        dockPID = nil
        observerLoop = nil
    }
    private func requestDockRefresh() {
        let queued = locked { () -> Bool in
            guard enabled, !refreshQueued else { return false }
            refreshQueued = true
            return true
        }
        guard queued else { return }
        axQueue.async { [weak self] in
            guard let self else { return }
            self.locked { self.refreshQueued = false }
            self.refreshDock(loop: self.observerLoop)
        }
    }
    private func refreshDock(loop: CFRunLoop?) {
        guard let loop, locked({
            enabled && eventLoop?.runLoop.map { CFEqual($0, loop) } == true
        }) else { return }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        if dockPID != dock.processIdentifier || dockList == nil || observerLoop.map({ !CFEqual($0, loop) }) != false {
            removeDockObserver()
            let app = AXUIElementCreateApplication(dock.processIdentifier)
            guard let list = (read(app, kAXChildrenAttribute) as? [AXUIElement])?.first(where: { read($0, kAXRoleAttribute) as? String == kAXListRole }) else { return }
            var created: AXObserver?
            guard AXObserverCreate(dock.processIdentifier, { _, _, _, context in
                guard let context else { return }
                Unmanaged<KiyiGelgit>.fromOpaque(context).takeUnretainedValue().requestDockRefresh()
            }, &created) == .success, let created else { return }
            guard AXObserverAddNotification(created, list, kAXSelectedChildrenChangedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
            guard locked({ enabled && eventLoop?.runLoop.map { CFEqual($0, loop) } == true }) else {
                AXObserverRemoveNotification(created, list, kAXSelectedChildrenChangedNotification as CFString)
                return
            }
            observer = created
            observerLoop = loop
            dockPID = dock.processIdentifier
            dockList = list
            CFRunLoopAddSource(loop, AXObserverGetRunLoopSource(created), .commonModes)
        }
        var next: Hit?
        if let list = dockList, let item = (read(list, kAXSelectedChildrenAttribute) as? [AXUIElement])?.first,
           read(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
           let url = read(item, kAXURLAttribute) as? NSURL,
           let bundle = Bundle(url: url as URL)?.bundleIdentifier,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first(where: { !$0.isTerminated }),
           let position = read(item, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
           let size = read(item, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            if AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
               AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) {
                next = Hit(pid: app.processIdentifier, dockOwner: dock.processIdentifier, finder: bundle == "com.apple.finder", frame: CGRect(origin: point, size: dimensions))
            }
        }
        locked { if enabled { hit = next } }
    }
}
