import AppKit
// Optional private SkyLight interface. Resolving symbols can fail after an OS update.
// The panel never becomes key or main; macOS retains keyboard and authentication control.
final class LockBridge {
    typealias Connection = @convention(c) () -> Int32
    typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias Level = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias Show = @convention(c) (Int32, CFArray) -> Int32
    typealias Move = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: Int32
    private let showSpaces: Show
    private let move: Move
    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let a = dlsym(h, "SLSMainConnectionID"), let b = dlsym(h, "SLSSpaceCreate"),
              let c = dlsym(h, "SLSSpaceSetAbsoluteLevel"), let d = dlsym(h, "SLSShowSpaces"),
              let e = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        handle = h
        connection = unsafeBitCast(a, to: Connection.self)()
        space = unsafeBitCast(b, to: Create.self)(connection, 1, 0)
        showSpaces = unsafeBitCast(d, to: Show.self); move = unsafeBitCast(e, to: Move.self)
        guard unsafeBitCast(c, to: Level.self)(connection, space, 400) == 0 else { return nil }
    }
    func show(_ window: NSWindow) -> Bool {
        guard showSpaces(connection, [NSNumber(value: space)] as CFArray) == 0 else { return false }
        return move(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7) == 0
    }
}
