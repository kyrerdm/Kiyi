// Ada personal fork extensions. Upstream copyright and GPL-3.0 notices remain in App/.
import AppKit
import SwiftUI
import Defaults
import Combine
import OSLog
import CoreImage
import IOKit.pwr_mgt
import QuartzCore

extension Defaults.Keys {
    static let kiyiLanguage = Key<String>("kiyiLanguage", default: "tr")
    static let kiyiNoticeWidth = Key<Double>("kiyiNoticeWidth", default: 320)
    static let kiyiNoticeCover = Key<Double>("kiyiNoticeCover", default: 56)
    static let kiyiNoticeDuration = Key<Double>("kiyiNoticeDuration", default: 2.4)
    static let kiyiNoticeText = Key<Double>("kiyiNoticeText", default: 12)
    static let kiyiNoticeGlow = Key<Bool>("kiyiNoticeGlow", default: true)
    static let kiyiNoticeAnimation = Key<Bool>("kiyiNoticeAnimation", default: true)

    static let adaWidth = Key<Double>("adaWidth", default: 460)
    static let adaHeight = Key<Double>("adaHeight", default: 190)
    static let kiyiCoverSize = Key<Double>("kiyiCoverSize", default: 60)
    static let kiyiCoverOnRight = Key<Bool>("kiyiCoverOnRight", default: false)
    static let adaTransparency = Key<Double>("adaTransparency", default: 0.24)
    static let adaAirPods = Key<Bool>("adaAirPods", default: true)
    static let adaLockMusic = Key<Bool>("adaLockMusic", default: true)
    static let kiyiLockPauseDelay = Key<Double>("kiyiLockPauseDelay", default: 15)
    static let kiyiLockDismissStyle = Key<String>("kiyiLockDismissStyle", default: "fade")
    static let kiyiLockAnimationMS = Key<Double>("kiyiLockAnimationMS", default: 280)
    static let kiyiLockVerticalOffset = Key<Double>("kiyiLockVerticalOffset", default: 0)
    static let kiyiLockHidePaused = Key<Bool>("kiyiLockHidePaused", default: true)
    static let kiyiLockKeepAwake = Key<Bool>("kiyiLockKeepAwake", default: true)
    static let adaLockHideIdle = Key<Bool>("adaLockHideIdle", default: true)
    static let adaLockArtwork = Key<Bool>("adaLockArtwork", default: true)
    static let adaLockArtworkBackdrop = Key<Bool>("adaLockArtworkBackdrop", default: true)
    static let adaLockLyrics = Key<Bool>("adaLockLyrics", default: false)
    static let adaLockCoverSize = Key<Double>("adaLockCoverSize", default: 210)
    static let adaLockCardWidth = Key<Double>("adaLockCardWidth", default: 320)
    static let adaLockOpacity = Key<Double>("adaLockOpacity", default: 0.18)
}

final class AdaPassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class AdaLockExpansion: ObservableObject {
    @Published var expanded = false
    @Published var dismissing = false
}

@MainActor final class AdaLockScreen {
    static let shared = AdaLockScreen()
    private let log = Logger(subsystem: "local.kayra.adanotch", category: "LockCard")
    private var panel: AdaPassivePanel?
    private var previewPanel: AdaPassivePanel?
    private var backdrop: AdaPassivePanel?
    private var previewBackdrop: AdaPassivePanel?
    private let expansion = AdaLockExpansion()
    private let previewExpansion = AdaLockExpansion()
    private var bridge: LockBridge?
    private var locked = false
    private var pausedPlayerHidden = false
    private var lockFadeToken: UUID?
    private var pauseTimeout: Task<Void, Never>?
    private var displayAssertion: IOPMAssertionID?
    private var wakeObserver: NSObjectProtocol?
    private var retry: Task<Void, Never>?
    private var previewTimeout: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    func start() {
        let music = MusicManager.shared
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.locked else { return }
                self.schedulePresentation()
            }
        }
        Defaults.publisher(keys: .adaLockMusic, .adaLockArtwork, .adaLockLyrics, .adaLockCoverSize,
                           .adaLockCardWidth, .adaLockHideIdle, .adaLockArtworkBackdrop, .hideFromScreenRecording,
                           .kiyiLockHidePaused, .kiyiLockKeepAwake, .kiyiLockVerticalOffset, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        music.$isPlaying.combineLatest(music.$songDuration)
            .map { ($0, $1.isFinite && $1 > 0) }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
            setLocked(true)
        }
    }

    func setLocked(_ value: Bool) {
        locked = value
        updatePlaybackPolicy()
        retry?.cancel()
        dismissPreview()
        if value {
            schedulePresentation()
        } else {
            dismissLockCard()
        }
    }

    func preview() {
        guard !locked else { return }
        if previewPanel?.isVisible == true {
            dismissPreview()
            return
        }
        present(preview: true)
        previewTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(18)) } catch { return }
            self?.dismissPreview()
        }
    }

    func refresh() {
        updatePlaybackPolicy()
        if locked { present(preview: false) }
        if previewPanel?.isVisible == true { present(preview: true) }
    }

    private func updatePlaybackPolicy() {
        let music = MusicManager.shared
        let active = locked && Defaults[.adaLockMusic]
        let keepDisplay = active && music.hasLockTrack && music.isPlaying && Defaults[.kiyiLockKeepAwake]
        if keepDisplay && displayAssertion == nil {
            var assertion: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Kiyi lock-screen music playback" as CFString, &assertion)
            if result == kIOReturnSuccess {
                displayAssertion = assertion
                log.info("Lock music display sleep prevention enabled")
            } else {
                log.error("Display sleep assertion failed: \(result)")
            }
        } else if !keepDisplay, let assertion = displayAssertion {
            IOPMAssertionRelease(assertion)
            displayAssertion = nil
            log.info("Lock music display sleep prevention released")
        }

        guard active, Defaults[.kiyiLockHidePaused], !music.isPlaying else {
            pauseTimeout?.cancel()
            pauseTimeout = nil
            pausedPlayerHidden = false
            return
        }
        // Metadata, artwork and wake refreshes must not restart the countdown.
        guard pauseTimeout == nil, !pausedPlayerHidden else { return }
        let delay = min(60, max(5, Defaults[.kiyiLockPauseDelay]))
        pauseTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.locked, Defaults[.adaLockMusic],
                  Defaults[.kiyiLockHidePaused], !MusicManager.shared.isPlaying else { return }
            self.pauseTimeout = nil
            self.pausedPlayerHidden = true
            self.dismissLockCard(animated: true)
        }
    }

    func previewDismissal() {
        guard !locked else { return }
        dismissPreview()
        present(preview: true)
        previewTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self, let window = self.previewPanel else { return }
            self.previewExpansion.dismissing = true
            let duration = self.dismissalDuration
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
                self.previewBackdrop?.animator().alphaValue = 0
            }, completionHandler: nil)
            do { try await Task.sleep(for: .seconds(duration + 0.05)) } catch { return }
            self.dismissPreview()
        }
    }

    private var dismissalDuration: Double {
        Defaults[.kiyiLockDismissStyle] == "none" ? 0 : min(650, max(180, Defaults[.kiyiLockAnimationMS])) / 1000
    }

    private func dismissPreview() {
        previewTimeout?.cancel()
        previewPanel?.orderOut(nil)
        previewPanel = nil
        previewExpansion.expanded = false
        previewExpansion.dismissing = false
        dismissBackdrop(preview: true)
    }

    private func dismissLockCard(animated: Bool = false) {
        if animated, dismissalDuration > 0, let window = panel, window.isVisible {
            let token = UUID()
            lockFadeToken = token
            expansion.dismissing = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = dismissalDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
                backdrop?.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.lockFadeToken == token, self.pausedPlayerHidden else { return }
                    self.dismissLockCard()
                }
            }
            return
        }
        lockFadeToken = nil
        if panel?.isVisible == true { log.info("Lock card dismissed") }
        panel?.orderOut(nil)
        panel = nil
        expansion.expanded = false
        expansion.dismissing = false
        dismissBackdrop(preview: false)
        bridge?.hide()
    }

    private func schedulePresentation() {
        MusicManager.shared.forceUpdate()
        retry?.cancel()
        retry = Task { [weak self] in
            self?.present(preview: false)
            // WindowServer can switch spaces after the lock and display-wake notifications.
            for delay in [150, 350, 800] {
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                self?.present(preview: false, reattach: true)
            }
        }
    }

    private func present(preview: Bool, reattach: Bool = false) {
        if !preview {
            guard locked, Defaults[.adaLockMusic],
                  !Defaults[.adaLockHideIdle] || MusicManager.shared.hasLockTrack else {
                dismissLockCard()
                return
            }
        }
        // A refresh during the fade must not destroy the window prematurely.
        if !preview && pausedPlayerHidden { return }
        guard let screen = NSScreen.screens.first else { return }

        let state = preview ? previewExpansion : expansion
        if !Defaults[.adaLockArtwork] { state.expanded = false }
        let cardWidth = Defaults[.adaLockCardWidth]
        let cover = Defaults[.adaLockArtwork] ? expandedCoverSize(Defaults[.adaLockCoverSize], cardWidth: cardWidth) + 12 : 0
        let width = max(cardWidth, cover) + 24
        let height: CGFloat = 126 + cover + (Defaults[.adaLockLyrics] ? 52 : 0) + (preview ? 22 : 0)
        let safeArea = CGRect(x: screen.frame.minX + 16, y: screen.frame.minY + screen.frame.height * 0.20,
                              width: max(1, screen.frame.width - 32), height: screen.frame.height * 0.60)
        let scale = min(1, safeArea.width / width, safeArea.height / height)
        let size = CGSize(width: width * scale, height: height * scale)
        let offset = min(160, max(-160, Defaults[.kiyiLockVerticalOffset]))
        let proposedY = safeArea.midY - size.height / 2 - offset
        let y = min(safeArea.maxY - size.height, max(safeArea.minY, proposedY))
        let frame = CGRect(x: safeArea.midX - size.width / 2, y: y,
                           width: size.width, height: size.height)

        let existing = preview ? previewPanel : panel
        let window = existing ?? makePanel(preview: preview)
        if !preview && lockFadeToken != nil {
            lockFadeToken = nil
            expansion.dismissing = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                backdrop?.animator().alphaValue = 1
            }
        }
        let root = AdaLockPresentation(preview: preview, width: width, height: height, scale: scale,
                                       expansion: state) { [weak self] in self?.toggleArtwork(preview: preview) }
        if let host = window.contentView as? NSHostingView<AdaLockPresentation> {
            if window.frame.size != frame.size || host.rootView.width != width || host.rootView.height != height {
                host.rootView = root
            }
        } else {
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            window.contentView = host
        }
        window.sharingType = Defaults[.hideFromScreenRecording] && !preview ? .none : .readOnly
        if window.frame != frame { window.setFrame(frame, display: true) }

        if preview {
            previewPanel = window
            window.orderFrontRegardless()
            updateBackdrop(preview: true, screen: screen, reattach: false)
            return
        }

        if bridge == nil { bridge = LockBridge() }
        guard let bridge else { return }
        if existing == nil || reattach {
            guard bridge.show(window) else {
                log.error("Lock card has no WindowServer window number")
                window.orderOut(nil)
                panel = nil
                bridge.hide()
                return
            }
            if existing == nil {
                window.orderFrontRegardless()
                log.info("Lock card presentation requested, window \(window.windowNumber)")
            }
        }
        panel = window
        updateBackdrop(preview: false, screen: screen, reattach: reattach)
    }

    private func toggleArtwork(preview: Bool) {
        guard preview ? !locked : locked else { return }
        let state = preview ? previewExpansion : expansion
        withAnimation(.easeInOut(duration: 0.22)) { state.expanded.toggle() }
        guard let screen = NSScreen.screens.first else { return }
        updateBackdrop(preview: preview, screen: screen, reattach: false, animate: true)
    }

    private func updateBackdrop(preview: Bool, screen: NSScreen, reattach: Bool, animate: Bool = false) {
        let state = preview ? previewExpansion : expansion
        guard state.expanded, Defaults[.adaLockArtworkBackdrop] else {
            dismissBackdrop(preview: preview, animate: animate)
            return
        }
        let existing = preview ? previewBackdrop : backdrop
        let window = existing ?? makePanel(preview: preview)
        if existing == nil {
            window.title = KiyiL(preview ? "Kıyı Kapak Önizleme Arka Planı" : "Kıyı Kapak Arka Planı")
            window.level = .init(rawValue: window.level.rawValue - 1)
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.contentView = makeBackdropContent()
            window.alphaValue = animate ? 0 : 1
        }
        window.sharingType = Defaults[.hideFromScreenRecording] && !preview ? .none : .readOnly
        if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
        if !preview && (existing == nil || reattach) {
            guard bridge?.show(window) == true else { return }
        }
        if existing == nil {
            window.orderFrontRegardless()
            if preview { previewBackdrop = window } else { backdrop = window }
            if animate { fade(window, to: 1) }
        }
    }

    private func makeBackdropContent() -> NSView {
        let content = NSView()
        let effect = NSVisualEffectView()
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.blendingMode = .behindWindow
        effect.material = .hudWindow
        effect.state = .active
        // Keep the clock and sign-in text legible while blurring the whole display.
        effect.maskImage = NSImage(size: NSSize(width: 4, height: 256), flipped: false) { rect in
            let edge = NSColor.white.withAlphaComponent(0.28)
            let center = NSColor.white.withAlphaComponent(0.76)
            let gradient = NSGradient(colorsAndLocations:
                (edge, 0), (edge, 0.12), (center, 0.38), (center, 0.62), (edge, 0.88), (edge, 1))
            gradient?.draw(in: rect, angle: 90)
            return true
        }
        content.addSubview(effect)
        let artwork = AdaLockArtworkBackdrop(frame: .zero)
        content.addSubview(artwork, positioned: .above, relativeTo: effect)
        for view in [effect as NSView, artwork] {
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                view.topAnchor.constraint(equalTo: content.topAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        return content
    }

    private func dismissBackdrop(preview: Bool, animate: Bool = false) {
        guard let window = preview ? previewBackdrop : backdrop else { return }
        if preview { previewBackdrop = nil } else { backdrop = nil }
        if animate {
            fade(window, to: 0) { window.orderOut(nil) }
        } else {
            window.orderOut(nil)
        }
    }

    private func fade(_ window: NSWindow, to opacity: CGFloat, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = opacity
        } completionHandler: {
            completion?()
        }
    }

    private func makePanel(preview: Bool) -> AdaPassivePanel {
        let window = AdaPassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        window.title = KiyiL(preview ? "Kıyı Kilit Kartı Önizleme" : "Kıyı Kilit Kartı")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = preview ? .floating : .init(rawValue: Int(Int32.max) - 2)
        window.collectionBehavior = preview ? [.moveToActiveSpace, .fullScreenAuxiliary] : [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.canBecomeVisibleWithoutLogin = !preview
        return window
    }
}

private final class AdaLockArtworkBackdrop: NSView {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let imageLayer = CALayer()
    private let visibility = CAGradientLayer()
    private let shade = CAGradientLayer()
    private var artworkSubscription: AnyCancellable?
    private var imageGeneration = UUID()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        visibility.startPoint = CGPoint(x: 0.5, y: 1)
        visibility.endPoint = CGPoint(x: 0.5, y: 0)
        visibility.locations = [0, 0.18, 0.35, 0.58, 0.73, 0.90, 1]
        // Let the real macOS clock and authentication controls remain visible.
        visibility.colors = [0.23, 0.23, 0.92, 1, 0.88, 0.18, 0.18]
            .map { NSColor.white.withAlphaComponent($0).cgColor }
        imageLayer.mask = visibility
        shade.startPoint = CGPoint(x: 0.5, y: 1)
        shade.endPoint = CGPoint(x: 0.5, y: 0)
        shade.colors = [0.04, 0.16, 0.08].map { NSColor.black.withAlphaComponent($0).cgColor }
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(shade)

        let music = MusicManager.shared
        artworkSubscription = music.$albumArt.combineLatest(music.$usingAppIconForArtwork)
            .map { artwork, isAppIcon in isAppIcon || artwork === defaultImage ? nil : artwork }
            .removeDuplicates { $0 === $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateArtwork($0) }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        visibility.frame = imageLayer.bounds
        shade.frame = bounds
        CATransaction.commit()
    }

    private func updateArtwork(_ artwork: NSImage?) {
        let generation = UUID()
        imageGeneration = generation
        guard let original = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageLayer.contents = nil
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scale = min(1, 640 / CGFloat(max(original.width, original.height)))
            let image = CIImage(cgImage: original).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 9).cropped(to: image.extent)
            let rendered = Self.imageContext.createCGImage(blurred, from: image.extent)
            DispatchQueue.main.async {
                guard let self, self.imageGeneration == generation else { return }
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.30
                self.imageLayer.add(transition, forKey: "albumChange")
                self.imageLayer.contents = rendered
            }
        }
    }
}

private struct AdaLockPresentation: View {
    @Default(.kiyiLockDismissStyle) private var dismissalStyle
    @Default(.kiyiLockAnimationMS) private var animationMS
    @Default(.kiyiLanguage) private var languageCode
    var preview: Bool
    var width: CGFloat
    var height: CGFloat
    var scale: CGFloat
    @ObservedObject var expansion: AdaLockExpansion
    var toggleArtwork: () -> Void

    var body: some View {
        AdaLockCard(preview: preview, expanded: expansion.expanded, toggleArtwork: toggleArtwork)
            .frame(width: width, height: height)
            .scaleEffect(scale)
            .frame(width: width * scale, height: height * scale)
            .scaleEffect(expansion.dismissing && dismissalStyle == "shrink" ? 0.94 : 1)
            .offset(y: expansion.dismissing && dismissalStyle == "slide" ? 14 : 0)
            .animation(.easeInOut(duration: expansion.dismissing ? min(650, max(180, animationMS)) / 1000 : 0.18), value: expansion.dismissing)
            .environment(\.locale, Locale(identifier: languageCode))
            .environment(\.colorScheme, .dark)
    }
}

private func expandedCoverSize(_ coverSize: CGFloat, cardWidth: CGFloat) -> CGFloat {
    max(coverSize, min(520, cardWidth * 1.40))
}

struct AdaLockCard: View {
    var preview: Bool
    var expanded: Bool
    var toggleArtwork: () -> Void
    @ObservedObject private var music = MusicManager.shared
    @Default(.adaLockArtwork) private var showArtwork
    @Default(.adaLockLyrics) private var showLyrics
    @Default(.adaLockCoverSize) private var coverSize
    @Default(.adaLockCardWidth) private var cardWidth
    @Default(.adaLockOpacity) private var opacity
    @Default(.useCustomAccentColor) private var useCustomAccent
    @Default(.customAccentColorData) private var customAccent
    @State private var isScrubbing = false
    @State private var draft: Double?

    private var hasTrack: Bool { music.hasLockTrack }
    private var demo: Bool { preview && !hasTrack }
    private var duration: Double { hasTrack ? music.songDuration : demo ? 225 : 0 }

    var body: some View {
        VStack(spacing: 12) {
            if preview {
                Label("Kilit ekranı önizlemesi", systemImage: "lock.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            }
            if showArtwork {
                Button(action: toggleArtwork) { artwork }
                    .buttonStyle(.plain)
                    .accessibilityLabel(KiyiL(expanded ? "Albüm kapağını küçült" : "Albüm kapağını büyüt"))
            }
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text(hasTrack ? music.songTitle : demo ? "Kıyı" : KiyiL("Müzik bekleniyor"))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(hasTrack ? music.artistName : demo ? KiyiL("Örnek parça") : KiyiL("Bir parça çaldığında burada görünür"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    AudioSpectrumView(isPlaying: .constant(demo || music.isPlaying))
                        .frame(width: 20, height: 12)
                        .accessibilityHidden(true)
                }
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let elapsed = playbackTime(at: context.date)
                    progress(elapsed: elapsed)
                    if showLyrics {
                        Text(demo ? KiyiL("Şarkı sözleri burada görünür")
                             : music.syncedLyrics.last(where: { $0.time <= elapsed })?.text
                               ?? KiyiL(music.isFetchingLyrics ? "Sözler yükleniyor…" : "Eşzamanlı söz bulunamadı"))
                            .font(.subheadline.weight(.medium)).lineLimit(2)
                            .multilineTextAlignment(.center).frame(height: 44)
                    }
                }
                HStack(spacing: 0) {
                    Button { music.toggleFavoriteTrack() } label: {
                        Image(systemName: music.isFavoriteTrack ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!music.canFavoriteTrack)
                    .opacity(music.canFavoriteTrack ? 0.75 : 0.28)
                    .accessibilityLabel("Beğen")
                    transport("Önceki parça", symbol: "backward.fill", action: music.previousTrack)
                    transport(music.isPlaying ? "Duraklat" : "Oynat",
                              symbol: music.isPlaying ? "pause.fill" : "play.fill", action: music.playPause)
                    transport("Sonraki parça", symbol: "forward.fill", action: music.nextTrack)
                    KiyiAudioOutputMenu().frame(maxWidth: .infinity)
                }
                .disabled(!hasTrack)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(width: cardWidth)
            .background {
                let shape = RoundedRectangle(cornerRadius: 21)
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(.black.opacity(opacity)) }
                    .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
        }
        .foregroundStyle(.white)
        .tint(useCustomAccent && customAccent != nil ? .effectiveAccent : .white)
        .onChange(of: music.songTitle) { _, _ in draft = nil }
    }

    private var artwork: some View {
        Group {
            if hasTrack && !music.usingAppIconForArtwork && music.albumArt !== defaultImage {
                Image(nsImage: music.albumArt).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.teal.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: 38, weight: .light))
                }
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
        .accessibilityHidden(true)
    }

    private var artworkSize: CGFloat { expanded ? expandedCoverSize(coverSize, cardWidth: cardWidth) : coverSize }

    private func playbackTime(at date: Date) -> Double {
        guard hasTrack else { return demo ? 82 : 0 }
        let advance = music.isPlaying ? max(0, date.timeIntervalSince(music.timestampDate)) * music.playbackRate : 0
        return min(duration, max(0, music.elapsedTime + advance))
    }

    private func progress(elapsed: Double) -> some View {
        let position = draft ?? elapsed
        return HStack(spacing: 6) {
            Text(formatTime(position)).frame(minWidth: 25, alignment: .leading)
            CustomSlider(value: Binding(get: { position }, set: { draft = $0 }),
                         range: 0...max(1, duration), allowsTrackpadSeeking: true, color: .white.opacity(0.82),
                         dragging: $isScrubbing, lastDragged: .constant(.distantPast),
                         onValueChange: { value in
                             music.seek(to: value)
                             draft = nil
                         })
                .id(music.songTitle + music.artistName)
                .frame(height: 10).disabled(!hasTrack)
                .accessibilityLabel("Oynatma konumu")
            Text("−" + formatTime(max(0, duration - position))).frame(minWidth: 29, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.43))
    }

    private func formatTime(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    private func transport(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct AdaLockSettings: View {
    @Default(.adaLockMusic) private var enabled
    @Default(.adaLockArtwork) private var artwork
    @Default(.adaLockArtworkBackdrop) private var artworkBackdrop
    @Default(.adaLockLyrics) private var lyrics
    @Default(.adaLockHideIdle) private var hideIdle
    @Default(.adaLockCoverSize) private var cover
    @Default(.adaLockCardWidth) private var width
    @Default(.adaLockOpacity) private var opacity

    var body: some View {
        Form {
            Section("Müzik kartı") {
                Toggle("Kilit ekranında göster", isOn: $enabled)
                Toggle("Parça yoksa kartı gizle", isOn: $hideIdle)
                Toggle("Eşzamanlı şarkı sözlerini göster", isOn: $lyrics)
            }
            Section("Görünüm") {
                Toggle("Albüm kapağını göster", isOn: $artwork)
                Toggle("Kapak büyüyünce arka planı bulanıklaştır", isOn: $artworkBackdrop).disabled(!artwork)
                AdaSettingSlider("Kapak boyutu", value: $cover, range: 120...280, step: 5).disabled(!artwork)
                AdaSettingSlider("Kart genişliği", value: $width, range: 300...480, step: 5)
                AdaSettingSlider("Kart koyuluğu", value: $opacity, range: 0...1, step: 0.05, percent: true)
            }
            Section {
                Button("Önizlemeyi aç veya kapat") { AdaLockScreen.shared.preview() }
            } footer: {
                Text("Kart, açık kullanıcı oturumu kilitlendiğinde çalışır. Önizleme 18 saniye açık kalır.")
            }
        }
        .formStyle(.grouped).navigationTitle("Kilit Ekranı")
    }
}

// Private WindowServer spaces provide the lock-screen layer for the current session.
private final class LockBridge {
    typealias Connection = @convention(c) () -> Int32
    typealias Create = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    typealias Level = @convention(c) (Int32, UInt64, Int32) -> Int32
    // On macOS 27 the visibility and move calls do not return a status.
    typealias ChangeVisibility = @convention(c) (Int32, CFArray) -> Void
    typealias Move = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    typealias Destroy = @convention(c) (Int32, UInt64) -> Void
    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: UInt64
    private let showSpaces: ChangeVisibility
    private let hideSpaces: ChangeVisibility
    private let move: Move
    private let destroy: Destroy?

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else { return nil }
        guard let getConnection = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let hide = dlsym(handle, "SLSHideSpaces"),
              let move = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            dlclose(handle)
            return nil
        }
        let connection = unsafeBitCast(getConnection, to: Connection.self)()
        let space = unsafeBitCast(create, to: Create.self)(connection, 1, nil)
        let destroy = dlsym(handle, "SLSSpaceDestroy").map { unsafeBitCast($0, to: Destroy.self) }
        let lockLevel = dlsym(handle, "kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock")?
            .assumingMemoryBound(to: Int32.self).pointee ?? 400
        guard space > 0, unsafeBitCast(level, to: Level.self)(connection, space, lockLevel) == 0 else {
            if space > 0 { destroy?(connection, space) }
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.connection = connection
        self.space = space
        showSpaces = unsafeBitCast(show, to: ChangeVisibility.self)
        hideSpaces = unsafeBitCast(hide, to: ChangeVisibility.self)
        self.move = unsafeBitCast(move, to: Move.self)
        self.destroy = destroy
    }

    deinit {
        hide()
        destroy?(connection, space)
        dlclose(handle)
    }

    func show(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0 else { return false }
        showSpaces(connection, [space] as CFArray)
        move(connection, space, [window.windowNumber] as CFArray, 7)
        return true
    }

    func hide() {
        hideSpaces(connection, [space] as CFArray)
    }
}

struct AdaNotchSurface: View {
    var open: Bool
    @Default(.adaTransparency) private var transparency

    var body: some View {
        ZStack {
            if open && transparency > 0 {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .allowsHitTesting(false)
                Color.black.opacity(pow(1 - min(1, max(0, transparency)), 2))
                LinearGradient(colors: [.black, .black.opacity(0.15), .clear],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
    }
}

struct AdaSettingSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var percent: Bool
    var unit: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, percent: Bool = false, unit: String = "pt") {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.percent = percent
        self.unit = unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(KiyiL(title))
                Spacer()
                Text(percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded())) \(KiyiL(unit))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step).labelsHidden()
                .accessibilityLabel(KiyiL(title))
        }
    }
}

struct AdaAppearanceSettings: View {
    @Default(.adaWidth) private var width
    @Default(.adaHeight) private var height
    @Default(.adaTransparency) private var transparency
    @Default(.kiyiCoverSize) private var coverSize
    @Default(.kiyiCoverOnRight) private var coverOnRight

    @Default(.kiyiNoticeWidth) private var noticeWidth
    @Default(.kiyiNoticeCover) private var noticeCover
    @Default(.kiyiNoticeDuration) private var noticeDuration
    @Default(.kiyiNoticeText) private var noticeText

    var body: some View {
        AdaSettingSlider("Açık genişlik", value: $width, range: 420...760, step: 5)
        AdaSettingSlider("Açık yükseklik", value: $height, range: 180...280, step: 5)
        AdaSettingSlider("Alt yüzey şeffaflığı", value: $transparency, range: 0...1, step: 0.05, percent: true)
        AdaSettingSlider("Müzik kapağı boyutu", value: $coverSize, range: 40...100, step: 2)
        Picker("Kapak konumu", selection: $coverOnRight) {
            Text("Sol").tag(false)
            Text("Sağ").tag(true)
        }
        Text("Şarkı değişimi bildirimi").font(.headline)
        Defaults.Toggle(key: .enableSneakPeek) { Text("Şarkı bildirimlerini göster") }
        AdaSettingSlider("Bildirim genişliği", value: $noticeWidth, range: 260...480, step: 10)
        AdaSettingSlider("Bildirim kapağı", value: $noticeCover, range: 40...80, step: 2)
        AdaSettingSlider("Bildirim yazı boyutu", value: $noticeText, range: 11...16, step: 1)
        Slider(value: $noticeDuration, in: 1...6, step: 0.2) {
            Text("Görünme süresi: \(noticeDuration.formatted(.number.locale(Locale(identifier: Defaults[.kiyiLanguage])).precision(.fractionLength(1)))) sn")
        }
        Defaults.Toggle(key: .kiyiNoticeGlow) { Text("Kapak altında hafif ışık") }
        Defaults.Toggle(key: .kiyiNoticeAnimation) { Text("Bildirim geçiş animasyonu") }
        Text("Bildirim şeffaflığı Alt yüzey şeffaflığı ile eşzamanlı değişir.")
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Button("Kompakt") { setSize(width: 460, height: 190, transparency: 0.24) }
            Button("Geniş") { setSize(width: 640, height: 220, transparency: 0.24) }
            Button("Mat siyah") { transparency = 0 }
        }.buttonStyle(.bordered)
    }

    private func setSize(width: Double, height: Double, transparency: Double) {
        self.width = width
        self.height = height
        self.transparency = transparency
    }
}

@MainActor final class AdaAirPods: ObservableObject {
    static let shared = AdaAirPods()
    @Published var devices: [[String: String]] = []
    @Published var refreshing = false
    @Published private(set) var connection: [String: String]?
    private var timer: Timer?
    private var dismissTask: Task<Void, Never>?
    private var preferenceSubscription: AnyCancellable?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        preferenceSubscription = Defaults.publisher(.adaAirPods, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if change.newValue { self?.refresh() } else { self?.dismissConnection() }
            }
    }

    func refresh() {
        guard Defaults[.adaAirPods], !refreshing else { return }
        refreshing = true
        Task {
            let result = await XPCHelperClient.shared.audioAccessories()
            refreshing = false
            guard let next = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [[String: String]] else { return }
            let previous = Set(devices.filter { $0["connected"] == "true" }.compactMap { $0["name"] })
            devices = next
            guard Defaults[.adaAirPods],
                  let connected = next.first(where: { $0["connected"] == "true" && !previous.contains($0["name"] ?? "") }) else { return }
            showConnection(connected)
        }
    }

    func dismissConnection() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.20)) { connection = nil }
    }

    func previewConnection() {
        showConnection(["name": KiyiL("AirPods Pro · Önizleme")])
    }

    private func showConnection(_ device: [String: String]) {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) { connection = device }
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            withAnimation(.easeOut(duration: 0.20)) { self?.connection = nil }
        }
    }
}

struct KiyiAirPodsConnection: View {
    let device: [String: String]
    @EnvironmentObject private var vm: BoringViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0

    private var symbol: String {
        let name = device["name"] ?? ""
        if name.localizedCaseInsensitiveContains("max") { return "airpodsmax" }
        return name.localizedCaseInsensitiveContains("pro") ? "airpodspro" : "airpods"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.28)
                .frame(width: 132)
                .accessibilityHidden(true)
            Color.clear.frame(width: max(0, vm.closedNotchSize.width - 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(device["name"] ?? "AirPods")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                Text(batteryText)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.leading, 6)
            .frame(width: 132, alignment: .leading)
        }
        .foregroundStyle(.white)
        .frame(height: max(30, vm.effectiveClosedNotchHeight + 2))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.7).repeatCount(2, autoreverses: false)) { angle = 360 }
        }
    }

    private var batteryText: String {
        let values = [("Main", ""), ("Left", KiyiL("Sol") + " "), ("Right", KiyiL("Sağ") + " ")]
            .compactMap { key, label in device[key].map { label + $0 } }
        return values.isEmpty ? KiyiL("Bağlandı") : values.joined(separator: " · ")
    }
}

struct AdaAirPodsView: View {
    @ObservedObject var monitor = AdaAirPods.shared
    @Default(.adaAirPods) var enabled
    var body: some View {
        Group {
            Toggle("AirPods bağlantı ve pil bilgisi", isOn: $enabled).onChange(of: enabled) { _, value in if value { monitor.refresh() } }
            ForEach(Array(monitor.devices.enumerated()), id: \.offset) { _, device in
                VStack(alignment: .leading, spacing: 4) {
                    Label(device["name"] ?? KiyiL("Kulaklık"), systemImage: "airpodspro")
                    Text(KiyiL(device["connected"] == "true" ? "Bağlı" : "Bağlı değil")).font(.caption).foregroundStyle(.secondary)
                    if device["connected"] == "true" { Text([("Left", KiyiL("Sol")), ("Right", KiyiL("Sağ")), ("Case", KiyiL("Kutu")), ("Main", KiyiL("Pil"))].compactMap { key, label in device[key].map { "\(label) \($0)" } }.joined(separator: " · ")).font(.caption) }
                }
            }
            Button(KiyiL(monitor.refreshing ? "Yenileniyor…" : "Cihazları yenile")) { monitor.refresh() }.disabled(monitor.refreshing)
            Button("Bağlantı animasyonunu önizle") { monitor.previewConnection() }
            Text("Pil değerleri macOS tarafından raporlanıyorsa gösterilir.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

func migrateKiyiPreferences() {
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: "kiyiTrackCardV1") {
        Defaults[.enableSneakPeek] = true
        Defaults[.sneakPeekStyles] = .standard
        defaults.set(true, forKey: "kiyiTrackCardV1")
    }
    if !defaults.bool(forKey: "kiyiCanopyLayoutV1") {
        let previous: [MusicControlButton] = [.favorite, .previous, .playPause, .next, .shuffle]
        if Defaults[.musicControlSlots] == previous {
            Defaults[.musicControlSlots] = MusicControlButton.defaultLayout
        }
        defaults.set(true, forKey: "kiyiCanopyLayoutV1")
    }
    if defaults.object(forKey: "adaWidth") == nil, let value = defaults.object(forKey: "ada.width") { defaults.set(value, forKey: "adaWidth") }
    if defaults.object(forKey: "adaHeight") == nil, let value = defaults.object(forKey: "ada.height") { defaults.set(value, forKey: "adaHeight") }
    if defaults.object(forKey: "adaTransparency") == nil, let value = defaults.object(forKey: "ada.transparency") { defaults.set(value, forKey: "adaTransparency") }
    if defaults.object(forKey: "adaAirPods") == nil, let value = defaults.object(forKey: "ada.airpods") { defaults.set(value, forKey: "adaAirPods") }
    if defaults.object(forKey: "adaLockMusic") == nil, let value = defaults.object(forKey: "ada.lock.music") { defaults.set(value, forKey: "adaLockMusic") }
    if defaults.object(forKey: "adaLockArtwork") == nil, let value = defaults.object(forKey: "ada.lock.artwork") { defaults.set(value, forKey: "adaLockArtwork") }
    if defaults.object(forKey: "adaLockLyrics") == nil, let value = defaults.object(forKey: "ada.lock.lyrics") { defaults.set(value, forKey: "adaLockLyrics") }
    if defaults.object(forKey: "adaLockCoverSize") == nil, let value = defaults.object(forKey: "ada.lock.coverSize") { defaults.set(value, forKey: "adaLockCoverSize") }
    if defaults.object(forKey: "adaLockCardWidth") == nil, let value = defaults.object(forKey: "ada.lock.cardWidth") { defaults.set(value, forKey: "adaLockCardWidth") }
    if defaults.object(forKey: "adaLockOpacity") == nil, let value = defaults.object(forKey: "ada.lock.opacity") { defaults.set(value, forKey: "adaLockOpacity") }
}

struct KiyiAudioOutputMenu: View {
    @State private var devices: [VolumeManager.OutputDevice] = []
    @State private var selected: UInt32 = 0
    @State private var selectionFailed = false

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    selectionFailed = !VolumeManager.shared.selectOutput(device.id)
                    reload()
                } label: {
                    if device.id == selected { Label(device.name, systemImage: "checkmark") }
                    else { Text(device.name) }
                }
            }
            if devices.isEmpty { Text("Ses çıkışı bulunamadı") }
            if selectionFailed { Text("Ses çıkışı değiştirilemedi") }
        } label: {
            Image(systemName: devices.first(where: { $0.id == selected })?.name.localizedCaseInsensitiveContains("airpod") == true
                  ? "airpodspro" : "airplay.audio")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.white.opacity(0.75))
        .fixedSize()
        .help("Ses çıkışını seç")
        .accessibilityLabel("Ses çıkışını seç")
        .onAppear(perform: reload)
        .onHover { hovering in if hovering { reload() } }
    }

    private func reload() {
        devices = VolumeManager.shared.outputDevices()
        selected = VolumeManager.shared.selectedOutputID
    }
}


struct KiyiTrackChangeCard: View {
    @ObservedObject private var music = MusicManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Default(.kiyiNoticeCover) private var cover
    @Default(.kiyiNoticeText) private var textSize
    @Default(.kiyiNoticeGlow) private var glow
    @Default(.kiyiNoticeAnimation) private var animated

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: music.albumArt)
                .resizable().scaledToFill()
                .frame(width: cover, height: cover)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color(nsColor: music.avgColor).opacity(glow ? 0.2 : 0), radius: 8, y: 3)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                .id(ObjectIdentifier(music.albumArt))
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 4) {
                Text(music.songTitle)
                    .font(.system(size: textSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(music.artistName)
                    .font(.system(size: max(10, textSize - 1)))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1).truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(music.songTitle + music.artistName)
            .transition(.opacity)
        }
        .padding(.top, 6)
        .animation(reduceMotion || !animated ? nil : .easeOut(duration: 0.18), value: music.songTitle + music.artistName)
        .animation(reduceMotion || !animated ? nil : .easeOut(duration: 0.18), value: ObjectIdentifier(music.albumArt))
        .accessibilityElement(children: .combine)
    }
}

// Explicit language selection is shared by SwiftUI and native strings.
// Explicit locale propagation updates the interface without terminating the app.
func KiyiL(_ key: String) -> String {
    let code = Defaults[.kiyiLanguage]
    guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

struct KiyiMenuBarPanel: View {
    @Default(.kiyiLanguage) private var languageCode
    var openSettings: () -> Void
    var quit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("logo2").resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kıyı").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Kıyı burada.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 6).padding(.top, 4)
            Divider()
            KiyiMenuAction(title: "Ayarlar…", icon: "slider.horizontal.3", shortcut: "⌘,") { dismiss(); openSettings() }
            Divider()
            KiyiMenuAction(title: "Kıyı’yı kapat", icon: "power") { dismiss(); quit() }
        }
        .padding(14).frame(width: 262)
        .id(languageCode)
        .environment(\.locale, Locale(identifier: languageCode))
    }
}

private struct KiyiMenuAction: View {
    var title: String
    var icon: String
    var shortcut: String = ""
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
                Text(KiyiL(title)).lineLimit(1).minimumScaleFactor(0.9)
                Spacer(minLength: 8)
                Text(shortcut).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 10)
            .background(hovered ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .accessibilityLabel(KiyiL(title))
    }
}


@MainActor func updateKiyiNativeMenuLanguage() {
    let topLevel = [
        "Edit": ["Edit", "Düzen", "Bearbeiten"],
        "View": ["View", "Görüntü", "Darstellung"],
        "Window": ["Window", "Pencere", "Fenster"],
        "Help": ["Help", "Yardım", "Hilfe"]
    ]
    let actions = ["copy:": "Copy", "cut:": "Cut", "paste:": "Paste", "selectAll:": "Select All", "undo:": "Undo", "redo:": "Redo", "performClose:": "Close", "performMiniaturize:": "Minimize", "performZoom:": "Zoom"]
    func update(_ menu: NSMenu) {
        for item in menu.items {
            if let action = item.action, let key = actions[NSStringFromSelector(action)] { item.title = KiyiL(key) }
            if let child = item.submenu { update(child) }
        }
    }
    if let menu = NSApp.mainMenu {
        for item in menu.items {
            if let key = topLevel.first(where: { $0.value.contains(item.title) })?.key {
                item.title = KiyiL(key)
                item.submenu?.title = item.title
            }
        }
        update(menu)
    }
}


// Listen only inside this slider, leaving vertical page scrolling and mouse drags alone.
struct KiyiTrackpadSeek: NSViewRepresentable {
    var active: Bool
    @Environment(\.isEnabled) private var enabled
    var onSeek: (Double) -> Void

    func makeNSView(context: Context) -> KiyiTrackpadSeekView { KiyiTrackpadSeekView() }
    func updateNSView(_ view: KiyiTrackpadSeekView, context: Context) {
        view.enabled = enabled && active
        view.onSeek = onSeek
    }
    static func dismantleNSView(_ view: KiyiTrackpadSeekView, coordinator: ()) { view.stop() }
}

final class KiyiTrackpadSeekView: NSView {
    var enabled = true
    var onSeek: ((Double) -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.enabled, let window = self.window, event.window === window,
                  event.hasPreciseScrollingDeltas,
                  self.bounds.insetBy(dx: 0, dy: -8).contains(self.convert(event.locationInWindow, from: nil)),
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.2,
                  abs(event.scrollingDeltaX) > 0.01 else { return event }
            // Do not continue seeking on inertia after the fingers leave the trackpad.
            guard event.momentumPhase.isEmpty else { return nil }
            let direction = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
            let seconds = max(-4, min(4, Double(event.scrollingDeltaX) * direction * 0.12))
            self.onSeek?(seconds)
            return nil
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    deinit { stop() }
}
