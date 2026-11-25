import AppKit
@main struct GelgitChecks {
    static func main() {
        let point = CGPoint(x: 100, y: 100)
        precondition(KiyiGelgit.isPlainClick(from: point, to: point, clickCount: 1, flags: []))
        for modifier: CGEventFlags in [.maskCommand, .maskAlternate, .maskControl, .maskShift] {
            precondition(!KiyiGelgit.isPlainClick(from: point, to: point, clickCount: 1, flags: modifier))
        }
        precondition(!KiyiGelgit.isPlainClick(from: point, to: point, clickCount: 2, flags: []))
        precondition(!KiyiGelgit.isPlainClick(from: point, to: CGPoint(x: 108, y: 100), clickCount: 1, flags: []))
        precondition(!KiyiGelgit.isDrag(from: point, to: CGPoint(x: 103, y: 102)), "Click jitter must not become a drag")
        precondition(KiyiGelgit.isDrag(from: point, to: CGPoint(x: 110, y: 100)), "A real icon drag must stay native")
        var late = GelgitOperationGate(generation: 1, deadline: 200)
        precondition(late.expire(now: 200))
        precondition(!late.claim(now: 5000, generation: 1), "A delayed AX reply must not act after native fallback")
        precondition(!late.expire(now: 5000), "Only one native fallback may be emitted")
        var unexpiredCallback = GelgitOperationGate(generation: 1, deadline: 200)
        precondition(!unexpiredCallback.claim(now: 5000, generation: 1), "A late reply is rejected even if the watchdog has not run yet")
        var superseded = GelgitOperationGate(generation: 1, deadline: 200)
        precondition(!superseded.claim(now: 50, generation: 2), "Old click must not act on a new gesture")
        var committed = GelgitOperationGate(generation: 3, deadline: 200)
        precondition(committed.claim(now: 20, generation: 3))
        precondition(!committed.expire(now: 300), "Native fallback must not compete with an accepted window action")
        precondition(!committed.claim(now: 30, generation: 3), "Each click must commit exactly once")
        precondition(GelgitWindowAction.choose(restoreRequested: true, hasMinimizedWindows: false, targetFocused: true) == .native,
                     "An already restored window must never be minimized by a restore click")
        precondition(GelgitWindowAction.choose(restoreRequested: true, hasMinimizedWindows: true, targetFocused: false) == .restore)
        precondition(GelgitWindowAction.choose(restoreRequested: false, hasMinimizedWindows: false, targetFocused: false) == .native,
                     "A different foreground app must not be minimized")
        precondition(GelgitWindowAction.choose(restoreRequested: false, hasMinimizedWindows: false, targetFocused: true) == .minimize)
        var sequence = GelgitClickSequence()
        sequence.record(pid: 42, timestamp: 100)
        precondition(sequence.isFollowup(pid: 42, clickCount: 2, timestamp: 150, interval: 100))
        precondition(!sequence.isFollowup(pid: 43, clickCount: 2, timestamp: 150, interval: 100))
        precondition(!sequence.isFollowup(pid: 42, clickCount: 1, timestamp: 150, interval: 100), "Separate single clicks remain available")
        precondition(!sequence.isFollowup(pid: 42, clickCount: 2, timestamp: 250, interval: 100))
        precondition(!sequence.isFollowup(pid: 42, clickCount: 2, timestamp: 90, interval: 100))
        // A stalled AX worker cannot stall the independent fallback deadline.
        let worker = DispatchQueue(label: "test.slow.ax")
        let blocker = DispatchSemaphore(value: 0)
        let complete = DispatchSemaphore(value: 0)
        let mutex = NSLock()
        let start = DispatchTime.now().uptimeNanoseconds
        var slow = GelgitOperationGate(generation: 4, deadline: start + 30_000_000)
        var lateAction = true
        var fellBack = false
        worker.async {
            blocker.wait()
            mutex.lock()
            lateAction = slow.claim(now: DispatchTime.now().uptimeNanoseconds, generation: 4)
            mutex.unlock()
            complete.signal()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(40)) {
            mutex.lock()
            fellBack = slow.expire(now: DispatchTime.now().uptimeNanoseconds)
            mutex.unlock()
            blocker.signal()
        }
        precondition(complete.wait(timeout: .now() + 1) == .success)
        precondition(fellBack && !lateAction, "A slow worker must not perform a late window operation")
        print("PASS: clicks, jitter, drag, modifiers, exactly-once commit, superseded and late replies; blocked-worker fallback")
    }
}
