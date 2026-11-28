// Original fullscreen Space monitoring by Richard Kunkli.
// Kıyı also handles borderless fullscreen games without AX or screen capture access.
import AppKit
import Combine
import Defaults
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var monitorTask: Task<Void, Never>?
    private var samplingTask: Task<Void, Never>?
    private var spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo] = []
    private var borderlessScreens: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    private let samplingQueue = DispatchQueue(label: "local.kayra.adanotch.fullscreen", qos: .utility)

    private init() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                self.spaces = spaces
                publishStatus()
            }
        }
        Defaults.publisher(.hideNotchOption).sink { [weak self] _ in
            self?.publishStatus()
        }.store(in: &cancellables)
        MusicManager.shared.$bundleIdentifier.removeDuplicates().sink { [weak self] _ in
            // @Published emits before the new value is stored.
            Task { @MainActor in self?.publishStatus() }
        }.store(in: &cancellables)
        // Workspace events make app/Space changes immediate; periodic sampling also
        // catches games switching modes without creating a native fullscreen Space.
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in await self?.sampleWindows() }
            }.store(in: &cancellables)
        }
        samplingTask = Task { @MainActor in
            while !Task.isCancelled {
                await sampleWindows()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    deinit {
        monitorTask?.cancel()
        samplingTask?.cancel()
    }

    private func sampleWindows() async {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let displays = NSScreen.screens.compactMap { screen -> (String, CGRect)? in
            guard let uuid = screen.displayUUID,
                  let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (uuid, CGDisplayBounds(id.uint32Value))
        }
        let covered: Set<String> = await withCheckedContinuation { continuation in
            samplingQueue.async {
                continuation.resume(returning: KiyiFullscreenWindows.coveredDisplays(pid: pid, displays: displays))
            }
        }
        // A completed query for the previous app must never hide the new app.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        borderlessScreens = covered
        publishStatus()
    }

    private func publishStatus() {
        let media = MusicManager.shared.bundleIdentifier
        let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var result: [String: Bool] = [:]
        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID else { continue }
            let native = spaces.filter { $0.screenUUID == uuid }
            let borderless = borderlessScreens.contains(uuid)
            let containsMedia = media.map { bundle in
                native.contains { $0.runningApps.contains(bundle) } || (borderless && frontmostBundle == bundle)
            } ?? false
            result[uuid] = KiyiFullscreenPolicy.shouldHide(
                mode: Defaults[.hideNotchOption].rawValue, nativeFullscreen: !native.isEmpty,
                borderlessFullscreen: borderless, containsMedia: containsMedia)
        }
        if result != fullscreenStatus { fullscreenStatus = result }
    }
}
