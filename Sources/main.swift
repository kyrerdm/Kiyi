import AppKit
import SwiftUI
import Combine
import QuartzCore
import UniformTypeIdentifiers

final class Spotify: ObservableObject {
    @Published var title = "Spotify’ı aç ve bir şarkı çal"
    @Published var artist = "Müzik burada görünecek"
    @Published var playing = false
    @Published var artwork: NSImage?
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var message: String?
    private var artworkURL = ""
    private var timer: Timer?
    private var busy = false
    var stamp = Date()
    var sourceMode = "spotify"
    var streamHealthy = false
    var remoteProcess: Process?
    var remoteBuffer = Data()
    @Published var sourceIdentifier = "com.spotify.client"
    init() {
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }
    func setRefreshInterval(_ interval: Double) {
        timer?.invalidate()
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }; RunLoop.main.add(timer!, forMode: .common)
    }
    func elapsed(_ date: Date) -> Double { min(duration, max(0, position + (playing ? date.timeIntervalSince(stamp) : 0))) }
    func run(_ script: String, completion: @escaping (String, Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
            let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
            do {
                try p.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let error = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let ok = p.terminationStatus == 0
                let result = String(data: ok ? data : error, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(result.trimmingCharacters(in: .newlines), ok) }
            } catch { DispatchQueue.main.async { completion(error.localizedDescription, false) } }
        }
    }
    func refresh() {
        if sourceMode == "system" && streamHealthy { return }
        guard !busy else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty == false else {
            playing = false; title = "Spotify’ı aç ve bir şarkı çal"; artist = "Müzik burada görünecek"; artwork = nil; artworkURL = ""; duration = 0; message = nil; return
        }
        busy = true
        run("""
        tell application "Spotify"
          set t to current track
          set d to ASCII character 31
          return (name of t) & d & (artist of t) & d & (artwork url of t) & d & (player state as text) & d & (player position as text) & d & (duration of t as text)
        end tell
        """) { [weak self] value, ok in
            guard let self = self else { return }; self.busy = false
            guard ok else { self.message = value.contains("1743") ? "Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon’dan Spotify iznini aç." : "Spotify bilgisi bekleniyor. Bir şarkı başlat."; return }
            let parts = value.components(separatedBy: "\u{1f}")
            guard parts.count == 6 else { return }
            self.sourceIdentifier = "com.spotify.client"; self.message = nil; self.title = parts[0]; self.artist = parts[1]; self.playing = parts[3] == "playing"
            self.position = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            self.duration = (Double(parts[5]) ?? 0) / 1000; self.stamp = Date()
            if parts[2] != self.artworkURL {
                self.artworkURL = parts[2]; self.artwork = nil
                let expected = parts[2]
                if let url = URL(string: expected), url.scheme == "https" {
                    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                        guard let data = data, let image = NSImage(data: data) else { return }
                        DispatchQueue.main.async { if self?.artworkURL == expected { self?.artwork = image } }
                    }.resume()
                }
            }
        }
    }
    func command(_ command: String) {
        if sourceMode == "system" && streamHealthy && sourceIdentifier != "com.spotify.client" {
            let actions = ["playpause": "2", "next track": "4", "previous track": "5"]
            if let action = actions[command] { remoteCommand(["send", action]) }
            else if command.contains("shuffling") { remoteCommand(["shuffle", command.contains("true") ? "3" : "1"]) }
            else if command.contains("repeating") { remoteCommand(["repeat", command.contains("true") ? "3" : "1"]) }
            return
        }
        run("tell application \"Spotify\" to \(command)") { [weak self] _, _ in self?.refresh() }
    }
    func seek(_ value: Double) {
        if sourceMode == "system" && streamHealthy && sourceIdentifier != "com.spotify.client" { remoteCommand(["seek", String(Int(value * 1_000_000))]) }
        else { command("set player position to \(Int(value))") }
    }

}

struct Cover: View {
    @ObservedObject var media: Spotify
    @EnvironmentObject var prefs: Preferences
    var size: CGFloat
    var body: some View {
        Group {
            if let image = media.artwork { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { ZStack { Color.secondary.opacity(0.1); Image(systemName: "music.note").foregroundStyle(prefs.accent) } }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}
struct Bars: View {
    @EnvironmentObject var prefs: Preferences
    var playing: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !playing || !prefs.value.animateVisualizer || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) { context in
            HStack(spacing: 3) {
                ForEach(0..<5) { i in
                    Capsule().fill(prefs.accent).frame(width: 3, height: playing && prefs.value.animateVisualizer ? 5 + 15 * abs(sin(context.date.timeIntervalSinceReferenceDate * 3 + Double(i) * 1.1)) : 5)
                }
            }.frame(width: 28, height: 22)
        }.accessibilityLabel(playing ? "Çalıyor" : "Duraklatıldı")
    }
}
struct Player: View {
    @ObservedObject var media: Spotify
    @EnvironmentObject var prefs: Preferences
    @State private var dragging = false
    @State private var seek = 0.0
    @State private var shuffle = false
    @State private var repeatTrack = false
    var body: some View {
        GeometryReader { geometry in
            let c = prefs.value
            let cover = min(max(36, c.coverSize * 1.7), geometry.size.height - 8)
            HStack(alignment: .center, spacing: 14) {
                if c.showArtwork { Cover(media: media, size: cover).overlay(alignment: .bottomTrailing) {
                    Image(systemName: media.sourceIdentifier == "com.spotify.client" ? "music.note" : "play.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).padding(5).background(.green, in: Circle()).offset(x: 3, y: 3)
                } }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(media.title).font(.system(size: 13 * c.textScale, weight: .semibold)).lineLimit(1)
                            if c.showArtist { Text(media.artist).font(.system(size: 11 * c.textScale)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    if c.showProgress || c.showTime {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 1) {
                                if c.showProgress {
                                    Slider(value: Binding(get: { dragging ? seek : media.elapsed(context.date) }, set: { seek = $0 }), in: 0...max(1, media.duration), onEditingChanged: { editing in
                                        dragging = editing; if !editing { media.seek(seek) }
                                    }).tint(prefs.accent).controlSize(.mini).disabled(media.duration == 0).accessibilityLabel("Şarkı konumu")
                                }
                                if c.showTime { HStack { Text(time(media.elapsed(context.date))); Spacer(); Text(time(media.duration)) }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Button { shuffle.toggle(); media.command("set shuffling to " + (shuffle ? "true" : "false")) } label: { Image(systemName: "shuffle").foregroundStyle(shuffle ? prefs.accent : .secondary) }.buttonStyle(.plain).accessibilityLabel("Karıştır")
                        Spacer(minLength: 5)
                        control("backward.fill", "Önceki şarkı", "previous track")
                        Spacer(minLength: 5)
                        control(media.playing ? "pause.fill" : "play.fill", "Oynat / duraklat", "playpause", size: 21)
                        Spacer(minLength: 5)
                        control("forward.fill", "Sonraki şarkı", "next track")
                        Spacer(minLength: 5)
                        Button { repeatTrack.toggle(); media.command("set repeating to " + (repeatTrack ? "true" : "false")) } label: { Image(systemName: "repeat").foregroundStyle(repeatTrack ? prefs.accent : .secondary) }.buttonStyle(.plain).accessibilityLabel("Tekrarla")
                    }.font(.system(size: 12)).frame(height: 27)
                    if let message = media.message { Text(message).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2) }
                }.frame(maxWidth: .infinity)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    func control(_ icon: String, _ label: String, _ action: String, size: Double = 15) -> some View {
        Button { media.command(action) } label: { Image(systemName: icon).font(.system(size: size)).frame(minWidth: 20, minHeight: 27).contentShape(Rectangle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    func time(_ value: Double) -> String { let n = Int(max(0, value)); return String(format: "%d:%02d", n / 60, n % 60) }
}
struct HUDValue { let title: String; let icon: String; let value: Double }
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var page = "music"
    @Published var hud: HUDValue?
    @Published var notch: CGFloat = 160
    @Published var notchHeight: CGFloat = 34
    var hover: ((Bool) -> Void)?
    var settings: (() -> Void)?
    var activate: (() -> Void)?
    var close: (() -> Void)?
}
struct FrostedSurface: NSViewRepresentable {
    var dark: Bool
    var clarity: Double = 0
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); view.alphaValue = 1 - clarity * 0.75 }
}
struct Island: View {
    @ObservedObject var media: Spotify
    @ObservedObject var state: IslandState
    @EnvironmentObject var prefs: Preferences
    @Environment(\.colorScheme) var scheme
    @State private var dropTarget = false
    var notch: CGFloat
    var notchHeight: CGFloat
    var body: some View {
        ZStack {
            if state.expanded {
                VStack(spacing: 0) {
                    IslandHeader(state: state, notch: notch).frame(height: max(30, notchHeight))
                    Group {
                        if state.page == "shelf" && prefs.value.shelfEnabled { ShelfView() }
                        else if state.page == "controls" { SystemControlsView() }
                        else if state.page == "lyrics" { LyricsView(media: media) }
                        else { Player(media: media).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.transition(.opacity)
            } else {
                VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Group { if prefs.value.showArtwork { Cover(media: media, size: min(23, prefs.value.wingWidth - 8)) } else { Color.clear.frame(width: 23, height: 23) } }.frame(maxWidth: .infinity)
                    Color.clear.frame(width: notch)
                    Group { if prefs.value.showVisualizer { Bars(playing: media.playing) } else { Color.clear.frame(width: 23, height: 23) } }.frame(maxWidth: .infinity)
                }.frame(height: max(30, notchHeight))
                if let hud = state.hud { HStack(spacing: 8) { Image(systemName: hud.icon); Text(hud.title).lineLimit(1); Spacer(); ProgressView(value: hud.value).frame(width: 65); Text("\(Int(hud.value * 100))%").monospacedDigit() }.font(.system(size: 10)).foregroundStyle(.white).padding(.horizontal, 20).frame(height: 28) }
                }.transition(.opacity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .top) {
                if state.expanded {
                    let color: Color = scheme == .dark ? .black : .white
                    if prefs.value.glass { FrostedSurface(dark: scheme == .dark, clarity: prefs.value.transparency) }
                    color.opacity(1 - prefs.value.transparency)
                    prefs.accent.opacity(prefs.value.accentMode == "custom" ? 0.045 : 0)
                    LinearGradient(colors: [.black, .black, color.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: notchHeight + 36)
                } else { Color.black }
            }
        }.clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: state.expanded ? prefs.value.cornerRadius : 13))
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            guard prefs.value.shelfEnabled else { return false }
            state.page = "shelf"; state.activate?(); return Shelf.shared.accept(providers)
        }
        .onChange(of: dropTarget) { _, active in
            if active && prefs.value.shelfEnabled { state.page = "shelf"; state.activate?(); state.pinned = true }
        }
        .contentShape(Rectangle())
        .onHover { state.hover?($0) }
        .onTapGesture { if !state.expanded { state.activate?() } }
        .contextMenu {
            Button("Ses, parlaklık ve AirPods") { state.page = "controls"; state.activate?() }
            Button("Şarkı sözleri") { state.page = "lyrics"; state.activate?() }
            Button("Ayarlar…") { state.settings?() }
            Button(state.pinned ? "Sabitlemeyi kaldır" : "Açık tut") { state.pinned.toggle() }
            Button("Kapat") { state.close?() }
        }
    }
}
struct IslandRoot: View {
    @ObservedObject var media: Spotify
    @ObservedObject var state: IslandState
    @ObservedObject var prefs: Preferences
    var body: some View {
        Island(media: media, state: state, notch: state.notch, notchHeight: state.notchHeight)
            .environmentObject(prefs).preferredColorScheme(prefs.scheme)
    }
}
struct LockCard: View {
    @ObservedObject var media: Spotify
    @EnvironmentObject var prefs: Preferences
    @Environment(\.colorScheme) var scheme
    var body: some View {
        VStack(spacing: 16) {
            if prefs.value.lyricsEnabled { LyricsView(media: media).frame(width: prefs.value.lockWidth, height: 110) }
            if prefs.value.lockArtwork { Cover(media: media, size: prefs.value.lockArtworkSize) }
            Player(media: media).padding(18).frame(width: prefs.value.lockWidth, height: 190)
                .background { ZStack { FrostedSurface(dark: scheme == .dark); (scheme == .dark ? Color.black : Color.white).opacity(prefs.value.lockOpacity) } }
                .clipShape(RoundedRectangle(cornerRadius: prefs.value.cornerRadius))
        }.padding(20)
    }
}
final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let media = Spotify(); let state = IslandState(); let prefs = Preferences(defaults: CommandLine.arguments.contains("--verify-ui") ? UserDefaults(suiteName: "Ada.UIVerification")! : .standard)
    var settingsWindow: NSWindow?
    var subscriptions = Set<AnyCancellable>()
    var hoverWork: DispatchWorkItem?
    var previewHide: DispatchWorkItem?
    var panel: PassivePanel!; var lockPanel: PassivePanel?; var previewPanel: PassivePanel?
    var item: NSStatusItem!; var collapse: DispatchWorkItem?
    var hudDismiss: DispatchWorkItem?
    var resizeTimer: Timer?
    var targetFrame = NSRect.zero
    var locked = false
    var lockEnabled: Bool { prefs.value.lockEnabled }
    var lockBridge: LockBridge?
    var notchWidth: CGFloat = 160
    var islandHost: NSHostingView<IslandRoot>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Ada")
        prefs.applyRefinementDefaults()
        rebuildMenu()
        panel = makePanel(); panel.level = .statusBar
        updateGeometry()
        state.hover = { [weak self] entered in
            guard let self = self else { return }; self.collapse?.cancel(); self.hoverWork?.cancel()
            if entered {
                guard self.prefs.value.hoverEnabled || self.state.pinned else { return }
                let work = DispatchWorkItem { [weak self] in self?.expand(true) }; self.hoverWork = work
                if self.state.pinned || self.prefs.value.hoverDelay == 0 { self.expand(true) } else { DispatchQueue.main.asyncAfter(deadline: .now() + self.prefs.value.hoverDelay, execute: work) }
            } else if !self.state.pinned {
                let work = DispatchWorkItem { [weak self] in self?.expand(false) }; self.collapse = work; if self.prefs.value.collapseDelay == 0 { self.expand(false) } else { DispatchQueue.main.asyncAfter(deadline: .now() + self.prefs.value.collapseDelay, execute: work) }
            }
        }
        state.close = { [weak self] in self?.state.pinned = false; self?.expand(false) }
        state.settings = { [weak self] in self?.showSettings() }
        state.activate = { [weak self] in guard let self = self else { return }; self.state.pinned = self.prefs.value.clickPins; self.expand(true) }
        SystemControls.shared.hud = { [weak self] title, icon, value in self?.showHUD(title, icon, value) }
        SystemControls.shared.configureInterceptor(prefs.value.replaceSystemHUD)
        media.setSourceMode(prefs.value.mediaSource)
        media.setRefreshInterval(prefs.value.refreshInterval)
        prefs.onChange = { [weak self] in DispatchQueue.main.async { self?.applyPreferences() } }
        panel.orderFrontRegardless()
        if CommandLine.arguments.contains("--verify-ui") { verifyUI() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.updateGeometry() }
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(true) }
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(false) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.locked else { return }; for delay in [0.2, 0.6, 1.2, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, self.locked, self.lockEnabled else { return }; self.presentLock()
                }
            }
        }
    }
    func showHUD(_ title: String, _ icon: String, _ value: Double) {
        guard prefs.value.hudEnabled, !locked else { return }
        state.hud = HUDValue(title: title, icon: icon, value: value)
        if !state.expanded { expand(false) }
        hudDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.state.hud = nil; if self?.state.expanded == false { self?.expand(false) } }
        hudDismiss = work; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
    func applicationWillTerminate(_ notification: Notification) {
        media.sourceMode = "spotify"; media.remoteProcess?.terminationHandler = nil
        if media.remoteProcess?.isRunning == true { media.remoteProcess?.terminate() }
    }
    func makePanel() -> PassivePanel {
        let p = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]; p.isReleasedWhenClosed = false
        return p
    }
    func selectedScreen() -> NSScreen? {
        NSScreen.screens.first(where: { screenID($0) == prefs.value.screenID }) ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }
    func applyPreferences() {
        SystemControls.shared.configureInterceptor(prefs.value.replaceSystemHUD)
        media.setSourceMode(prefs.value.mediaSource)
        media.setRefreshInterval(prefs.value.refreshInterval)
        settingsWindow?.appearance = prefs.scheme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua)! }
        rebuildMenu(); updateGeometry()
        if !lockEnabled { lockPanel?.orderOut(nil) }
        if locked && lockEnabled { presentLock() }
        if previewPanel?.isVisible == true { presentLock(preview: true) }
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.appearance = prefs.scheme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua)! }
            window.title = "Ada Ayarları"; window.minSize = NSSize(width: 820, height: 650); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(prefs: prefs, media: media, preview: { [weak self] in self?.presentLock(preview: true) }, reveal: { [weak self] in self?.state.pinned = true; self?.expand(true); self?.panel.orderFrontRegardless() }))
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func updateGeometry() {
        if let screen = selectedScreen() {
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { notchWidth = max(120, right.minX - left.maxX) }
        }
        state.notch = notchWidth
        state.notchHeight = max(0, selectedScreen()?.safeAreaInsets.top ?? 0)
        if islandHost == nil {
            let host = NSHostingView(rootView: IslandRoot(media: media, state: state, prefs: prefs))
            host.sizingOptions = []
            host.autoresizingMask = [.width, .height]
            islandHost = host; panel.contentView = host
        }

        expand(state.expanded, animated: false)
    }
    func expand(_ expanded: Bool, animated: Bool = true) {
        guard let screen = selectedScreen() else { return }
        let c = prefs.value
        let size = NSSize(width: min(screen.frame.width - 20, expanded ? max(c.expandedWidth, notchWidth + 2 * c.wingWidth) : notchWidth + 2 * c.wingWidth + (state.hud == nil ? 0 : 80)), height: expanded ? c.expandedHeight : max(c.collapsedHeight, screen.safeAreaInsets.top) + (state.hud == nil ? 0 : 28))
        let rect = NSRect(x: min(screen.frame.maxX - size.width, max(screen.frame.minX, screen.frame.midX - size.width / 2 + c.horizontalOffset)), y: screen.frame.maxY - size.height - c.verticalOffset - (screen.safeAreaInsets.top > 0 ? 0 : 5), width: size.width, height: size.height)
        if animated && state.expanded == expanded && targetFrame == rect { return }
        targetFrame = rect
        withAnimation(animated && c.animations ? .easeOut(duration: 0.12 / c.animationSpeed) : nil) { state.expanded = expanded }
        resizeTimer?.invalidate()
        guard animated && c.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { panel.setFrame(rect, display: true); return }
        let start = panel.frame; let began = Date()
        resizeTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(began) * c.animationSpeed
            let k: Double = elapsed >= 0.28 ? 1 : (c.spring ? 1 - exp(-24 * elapsed) * (cos(6 * elapsed) + 4 * sin(6 * elapsed)) : 1 - pow(1 - min(1, elapsed / 0.22), 3))
            let width = start.width + (rect.width - start.width) * k
            let height = start.height + (rect.height - start.height) * k
            self.panel.setFrame(NSRect(x: rect.midX - width / 2, y: rect.maxY - height, width: width, height: height), display: true)
            if elapsed >= 0.28 { timer.invalidate() }
        }
        if let timer = resizeTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    func rebuildMenu() {
        let menu = NSMenu()
        for (title, action) in [("Ayarlar…", #selector(showSettings)), ("Ada’yı aç / kapat", #selector(showIsland)), ("Spotify’ı aç", #selector(openSpotify)), ("Kilit ekranı kartı (deneysel)", #selector(toggleLock)), ("Kilit kartını önizle", #selector(previewLock)), ("Çıkış", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self
            if action == #selector(toggleLock) { entry.state = lockEnabled ? .on : .off }
            menu.addItem(entry)
        }
        item.menu = menu
    }
    @objc func showIsland() { state.pinned.toggle(); expand(state.pinned); panel.orderFrontRegardless() }
    @objc func openSpotify() { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) } }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func toggleLock() { prefs.value.lockEnabled.toggle() }
    @objc func previewLock() { presentLock(preview: true) }
    func setLocked(_ value: Bool) { locked = value; if value { previewPanel?.orderOut(nil); panel.orderOut(nil); if lockEnabled { presentLock() } } else { lockPanel?.orderOut(nil); panel.orderFrontRegardless() } }
    func presentLock(preview: Bool = false) {
        guard let screen = selectedScreen() else { return }
        if preview { if previewPanel == nil { previewPanel = makePanel() } }
        else { if lockPanel == nil { lockPanel = makePanel() } }
        guard let p = preview ? previewPanel : lockPanel else { return }
        p.contentView = NSHostingView(rootView: LockCard(media: media).environmentObject(prefs).preferredColorScheme(prefs.scheme))
        let c = prefs.value
        let width = max(c.lockWidth, c.lockArtwork ? c.lockArtworkSize : 0) + 40
        let height = 230 + (c.lockArtwork ? c.lockArtworkSize + 16 : 0) + (c.lyricsEnabled ? 126 : 0)
        let y = min(screen.frame.maxY - height - 100, max(screen.frame.minY + 120, screen.frame.midY - height / 2 + c.lockOffset))
        p.setFrame(NSRect(x: screen.frame.midX - width / 2, y: y, width: width, height: height), display: true)
        if !preview {
            if lockBridge == nil { lockBridge = LockBridge() }
            guard lockBridge?.show(p) == true else { NSLog("Ada: Lock screen API unavailable"); return }
            p.canBecomeVisibleWithoutLogin = true
        } else { p.level = .floating }
        p.orderFrontRegardless()
        if preview {
            previewHide?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.previewPanel?.orderOut(nil) }; previewHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        }
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
