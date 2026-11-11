import AppKit
import SwiftUI
import Combine
import ServiceManagement

struct Configuration: Codable, Equatable {
    var expandedWidth = 320.0
    var expandedHeight = 200.0
    var wingWidth = 38.0
    var collapsedHeight = 34.0
    var cornerRadius = 24.0
    var verticalOffset = 0.0
    var horizontalOffset = 0.0
    var transparency = 0.65
    var glass = true
    var theme = "system"
    var accentMode = "system"
    var red = 0.30
    var green = 0.85
    var blue = 0.72
    var textScale = 1.0
    var coverSize = 42.0
    var showArtwork = true
    var showArtist = true
    var showProgress = true
    var showTime = true
    var showVisualizer = true
    var animateVisualizer = true
    var hoverEnabled = true
    var hoverDelay = 0.0
    var collapseDelay = 0.0
    var clickPins = true
    var animations = true
    var spring = false
    var animationSpeed = 1.0
    var screenID = "auto"
    var lockEnabled = false
    var lockArtwork = true
    var lockArtworkSize = 200.0
    var lockWidth = 330.0
    var lockOffset = 0.0
    var lockOpacity = 0.75
    var refreshInterval = 3.0
    var mediaSource = "system"
    var lyricsEnabled = false
    var shelfEnabled = true
    var powerEnabled = true
    var airpodsEnabled = true
    var hudEnabled = true
    var replaceSystemHUD = false
    mutating func validate() {
        expandedWidth = clamp(expandedWidth, 280, 560); expandedHeight = clamp(expandedHeight, 180, 340)
        wingWidth = clamp(wingWidth, 28, 90); collapsedHeight = clamp(collapsedHeight, 28, 60)
        cornerRadius = clamp(cornerRadius, 8, 42); verticalOffset = clamp(verticalOffset, 0, 80); horizontalOffset = clamp(horizontalOffset, -300, 300)
        transparency = clamp(transparency, 0, 0.95); textScale = clamp(textScale, 0.85, 1.25); coverSize = clamp(coverSize, 28, 64)
        red = clamp(red, 0, 1); green = clamp(green, 0, 1); blue = clamp(blue, 0, 1)
        hoverDelay = clamp(hoverDelay, 0, 1.5); collapseDelay = clamp(collapseDelay, 0, 3)
        animationSpeed = clamp(animationSpeed, 0.5, 2); lockArtworkSize = clamp(lockArtworkSize, 100, 300)
        lockWidth = clamp(lockWidth, 280, 480); lockOffset = clamp(lockOffset, -140, 140)
        lockOpacity = clamp(lockOpacity, 0.15, 1); refreshInterval = clamp(refreshInterval, 1, 10)
        if !["system", "dark", "light"].contains(theme) { theme = "system" }
        if !["system", "spotify"].contains(mediaSource) { mediaSource = "system" }
        if !["system", "custom"].contains(accentMode) { accentMode = "system" }
    }
    private func clamp(_ n: Double, _ low: Double, _ high: Double) -> Double { n.isFinite ? min(high, max(low, n)) : low }
}
final class Preferences: ObservableObject {
    @Published var value: Configuration { didSet { save(); onChange?() } }
    var onChange: (() -> Void)?
    static let key = "Ada.configuration.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), var decoded = try? JSONDecoder().decode(Configuration.self, from: data) {
            decoded.validate(); value = decoded
        } else { value = Configuration(); value.lockEnabled = defaults.bool(forKey: "lockEnabled") }
    }
    func applyRefinementDefaults() {
        guard !defaults.bool(forKey: "Ada.refinement.v3") else { return }
        var c = value; c.hoverDelay = 0; c.collapseDelay = 0; c.spring = false
        if c.expandedWidth == 340 { c.expandedWidth = 320 }
        if c.expandedHeight == 218 { c.expandedHeight = 200 }
        value = c; defaults.set(true, forKey: "Ada.refinement.v3")
    }
    func save() { if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) } }
    var scheme: ColorScheme? { value.theme == "system" ? nil : (value.theme == "light" ? .light : .dark) }
    var accent: Color { value.accentMode == "system" ? .accentColor : Color(red: value.red, green: value.green, blue: value.blue) }
    var customColor: Color {
        get { Color(red: value.red, green: value.green, blue: value.blue) }
        set { if let color = NSColor(newValue).usingColorSpace(.sRGB) { value.red = color.redComponent; value.green = color.greenComponent; value.blue = color.blueComponent } }
    }
    func reset() { value = Configuration() }
    func exportFile() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Ada-ayarlar.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(value).write(to: url, options: .atomic) }
        catch { showError(error.localizedDescription) }
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { var config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url)); config.validate(); value = config }
        catch { showError("Ayar dosyası okunamadı: \(error.localizedDescription)") }
    }
    func showError(_ message: String) { let alert = NSAlert(); alert.messageText = "Ada"; alert.informativeText = message; alert.runModal() }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var media: Spotify
    @State private var selection = "Görünüm"
    @State private var resetAlert = false
    let preview: () -> Void
    let reveal: () -> Void
    let pages = [("Görünüm", "paintpalette"), ("Boyut ve konum", "arrow.up.left.and.arrow.down.right"), ("Davranış", "cursorarrow.motionlines"), ("Müzik", "music.note"), ("Kilit ekranı", "lock"), ("Sistem kontrolleri", "slider.horizontal.3"), ("Genel", "gearshape")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Ada", systemImage: "waveform.path").font(.system(size: 24, weight: .semibold)).padding(.horizontal, 12).padding(.bottom, 4)
                Text("Sana göre, anında.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 18)
                ForEach(pages, id: \.0) { page in
                    Button { selection = page.0 } label: {
                        Label(page.0, systemImage: page.1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                            .background(selection == page.0 ? prefs.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("Ada 0.3 · Kişisel çentik alanın").font(.caption2).foregroundStyle(.secondary).padding(10)
            }.padding(16).frame(width: 200).background(.thinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text(selection).font(.title2.bold()); Text("Değişiklikler anında uygulanır ve otomatik kaydedilir.").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Button("Ada’yı göster", action: reveal)
                }.padding(24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if selection == "Görünüm" { appearance }
                        if selection == "Boyut ve konum" { geometry }
                        if selection == "Davranış" { behavior }
                        if selection == "Müzik" { music }
                        if selection == "Kilit ekranı" { lock }
                        if selection == "Genel" { general }
                        if selection == "Sistem kontrolleri" { system }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }.frame(maxWidth: .infinity)
        }.frame(minWidth: 800, minHeight: 610)
        .tint(prefs.accent).preferredColorScheme(prefs.scheme)
        .alert("Tüm ayarlar sıfırlansın mı?", isPresented: $resetAlert) { Button("İptal", role: .cancel) {}; Button("Sıfırla", role: .destructive) { prefs.reset() } } message: { Text("Boyut, görünüm, davranış ve kilit ekranı tercihleri varsayılana döner.") }
    }
    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox { VStack(alignment: .leading, spacing: 16, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(10) } label: { Text(title).font(.headline) }
    }
    func slider(_ title: String, _ path: WritableKeyPath<Configuration, Double>, _ range: ClosedRange<Double>, suffix: String = "", step: Double = 1) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(String(format: step < 1 ? "%.2f%@" : "%.0f%@", prefs.value[keyPath: path], suffix)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: Binding(get: { prefs.value[keyPath: path] }, set: { prefs.value[keyPath: path] = $0 }), in: range, step: step).accessibilityLabel(title)
        }
    }
    var appearance: some View {
        VStack(spacing: 18) {
            card("Tema ve renk") {
                Picker("Tema", selection: $prefs.value.theme) { Text("Sistemle eşitle").tag("system"); Text("Koyu").tag("dark"); Text("Açık").tag("light") }.pickerStyle(.segmented)
                Picker("Vurgu rengi", selection: $prefs.value.accentMode) { Text("macOS vurgu rengi").tag("system"); Text("Özel renk").tag("custom") }.pickerStyle(.segmented)
                if prefs.value.accentMode == "custom" { ColorPicker("Renk seç", selection: Binding(get: { prefs.customColor }, set: { prefs.customColor = $0 }), supportsOpacity: false) }
                Text("Tema ve vurgu rengi hem adada hem bu ayarlar penceresinde kullanılır. Çentiğin üst bölümü siyah kalır.").font(.caption).foregroundStyle(.secondary)
            }
            card("Cam ve köşeler") {
                Toggle("Arka planı bulanıklaştıran cam yüzey", isOn: $prefs.value.glass)
                slider("Şeffaflık", \.transparency, 0...0.95, step: 0.01)
                slider("Alt köşe yuvarlaklığı", \.cornerRadius, 8...42, suffix: " pt")
                slider("Yazı ölçeği", \.textScale, 0.85...1.25, suffix: "×", step: 0.05)
            }
        }
    }
    var geometry: some View {
        VStack(spacing: 18) {
            card("Hazır boyutlar") { HStack {
                Button("Kompakt") { prefs.value.expandedWidth = 320; prefs.value.expandedHeight = 200; prefs.value.coverSize = 36; prefs.value.wingWidth = 32 }
                Button("Dengeli") { prefs.value.expandedWidth = 360; prefs.value.expandedHeight = 230; prefs.value.coverSize = 44; prefs.value.wingWidth = 40 }
                Button("Geniş") { prefs.value.expandedWidth = 420; prefs.value.expandedHeight = 270; prefs.value.coverSize = 54; prefs.value.wingWidth = 50 }
            } }
            card("Açık ada") { slider("Genişlik", \.expandedWidth, 280...560, suffix: " pt"); slider("Yükseklik", \.expandedHeight, 180...340, suffix: " pt") }
            card("Kapalı ada") { slider("Çentiğin her yanındaki alan", \.wingWidth, 28...90, suffix: " pt"); slider("Yükseklik", \.collapsedHeight, 28...60, suffix: " pt"); Text("Fiziksel çentik yüksekliği alt sınırdır.").font(.caption).foregroundStyle(.secondary) }
            card("Ekran ve konum") {
                Picker("Ekran", selection: $prefs.value.screenID) {
                    Text("Çentikli ekranı otomatik seç").tag("auto")
                    ForEach(NSScreen.screens, id: \.localizedName) { screen in Text(screen.localizedName).tag(screenID(screen)) }
                }
                slider("Aşağı kaydır", \.verticalOffset, 0...80, suffix: " pt")
                slider("Yatay kaydır", \.horizontalOffset, -300...300, suffix: " pt")
            }
        }
    }
    var behavior: some View {
        VStack(spacing: 18) {
            card("Açılma ve kapanma") {
                Toggle("Üzerine gelince aç", isOn: $prefs.value.hoverEnabled)
                slider("Açılma gecikmesi", \.hoverDelay, 0...1.5, suffix: " sn", step: 0.05)
                slider("Kapanma gecikmesi", \.collapseDelay, 0...3, suffix: " sn", step: 0.05)
                Toggle("Tıklayınca açık tut", isOn: $prefs.value.clickPins)
            }
            card("Animasyon") {
                Toggle("Geçiş animasyonları", isOn: $prefs.value.animations)
                Toggle("Hafif yaylanma", isOn: $prefs.value.spring)
                slider("Animasyon hızı", \.animationSpeed, 0.5...2, suffix: "×", step: 0.1)
                Text("macOS Hareketi Azalt açıksa geçişler animasyonsuz uygulanır.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var music: some View {
        VStack(spacing: 18) {
            card("Medya kaynağı") {
                Picker("Kaynak", selection: $prefs.value.mediaSource) { Text("Sistem — tüm Now Playing uygulamaları").tag("system"); Text("Yalnız Spotify").tag("spotify") }
                Text("Sistem kaynağı, macOS’un etkin oynatıcısını izler. Yardımcı kullanılamazsa Spotify yedeğine geçer.").font(.caption).foregroundStyle(.secondary)
            }
            card("Oynatıcı içeriği") {
                Toggle("Albüm kapağı", isOn: $prefs.value.showArtwork)
                slider("Kapak boyutu", \.coverSize, 28...64, suffix: " pt")
                Toggle("Sanatçı adı", isOn: $prefs.value.showArtist)
                Toggle("İlerleme çubuğu", isOn: $prefs.value.showProgress)
                Toggle("Geçen ve kalan süre", isOn: $prefs.value.showTime)
                Toggle("Ses çubukları", isOn: $prefs.value.showVisualizer)
                Toggle("Çubukları hareketlendir", isOn: $prefs.value.animateVisualizer)
                Text("Çubuklar oynatma durumunu temsil eder; gerçek ses analizi yapmaz.").font(.caption).foregroundStyle(.secondary)
            }
            card("Ek özellikler") {
                Toggle("Dosya rafını göster", isOn: $prefs.value.shelfEnabled)
                Toggle("Pil durumunu göster", isOn: $prefs.value.powerEnabled)
                Toggle("Şarkı sözleri (LRCLIB)", isOn: $prefs.value.lyricsEnabled)
                Text("Sözler açıkken şarkı adı ve sanatçı LRCLIB’e gönderilir. Sözler bulunamayabilir. Dosya rafı bu oturum boyunca dosya referanslarını tutar.").font(.caption).foregroundStyle(.secondary)
            }
            card("Bağlantı") {
                slider("Yedek bilgi yenileme aralığı", \.refreshInterval, 1...10, suffix: " sn")
                Text(media.message ?? "Spotify bilgisi: \(media.title)").font(.caption).foregroundStyle(.secondary)
                Button("Şimdi yenile") { media.refresh() }
            }
        }
    }
    var lock: some View {
        VStack(spacing: 18) {
            card("Kilit ekranı kartı") {
                Toggle("Kilit ekranında göster (deneysel)", isOn: $prefs.value.lockEnabled)
                Toggle("Büyük albüm kapağı", isOn: $prefs.value.lockArtwork)
                slider("Kapak boyutu", \.lockArtworkSize, 100...300, suffix: " pt")
                slider("Kart genişliği", \.lockWidth, 280...480, suffix: " pt")
                slider("Dikey konum", \.lockOffset, -140...140, suffix: " pt")
                slider("Kart koyuluğu", \.lockOpacity, 0.15...1, step: 0.05)
                Button("Masaüstünde 10 saniye önizle", action: preview)
                Text("Açık kullanıcı oturumu kilitlendiğinde çalışmak üzere tasarlandı. Yeniden başlatma/FileVault girişinde çalışmaz. macOS özel API desteğine bağlıdır; gerçek kilit ve uyandırma testi henüz tamamlanmadı.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var system: some View {
        VStack(spacing: 18) {
            card("Ses, parlaklık ve AirPods") {
                Toggle("Ada üzerinde ses/parlaklık göstergesi", isOn: $prefs.value.hudEnabled)
                Toggle("AirPods ve kulaklık bilgisi", isOn: $prefs.value.airpodsEnabled)
                Toggle("Sistem HUD yerine ada (Erişilebilirlik izni gerekir)", isOn: $prefs.value.replaceSystemHUD)
                Text("Sistem kontrollerine adada sağ tık menüsünden ulaşılır. Pil değerleri macOS tarafından raporlanıyorsa gösterilir; bağlı olmayan kulaklığın pil değeri tahmin edilmez.").font(.caption).foregroundStyle(.secondary)
                SystemControlsView().environmentObject(prefs).frame(height: 270)
            }
        }
    }
    var general: some View {
        VStack(spacing: 18) {
            card("Sistem") {
                Toggle("Oturum açınca başlat", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; prefs.objectWillChange.send() }
                    catch { prefs.showError(error.localizedDescription) }
                }))
            }
            card("Tercih dosyası") {
                HStack { Button("Dışa aktar…") { prefs.exportFile() }; Button("İçe aktar…") { prefs.importFile() } }
                Button("Tüm ayarları sıfırla…", role: .destructive) { resetAlert = true }
                Text("Ayarlar bu Mac’te saklanır. İçe aktarılan sayılar desteklenen aralığa sınırlandırılır.").font(.caption).foregroundStyle(.secondary)
            }
            card("Ada hakkında") { Text("Sürüm 0.3.0").font(.headline); Text("Spotify masaüstü için kişisel çentik oynatıcısı. Kapaklar dışında medya bilgileri yerel olarak okunur. Ayrı bir sunucu veya Spotify API anahtarı gerekmez.").font(.callout).foregroundStyle(.secondary) }
        }
    }
}
func screenID(_ screen: NSScreen) -> String { String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }

extension Configuration {
    enum CodingKeys: String, CodingKey { case expandedWidth, expandedHeight, wingWidth, collapsedHeight, cornerRadius, verticalOffset, horizontalOffset, transparency, glass, theme, accentMode, red, green, blue, textScale, coverSize, showArtwork, showArtist, showProgress, showTime, showVisualizer, animateVisualizer, hoverEnabled, hoverDelay, collapseDelay, clickPins, animations, spring, animationSpeed, screenID, lockEnabled, lockArtwork, lockArtworkSize, lockWidth, lockOffset, lockOpacity, refreshInterval, mediaSource, lyricsEnabled, shelfEnabled, powerEnabled, airpodsEnabled, hudEnabled, replaceSystemHUD }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expandedWidth = try c.decodeIfPresent(Double.self, forKey: .expandedWidth) ?? expandedWidth
        expandedHeight = try c.decodeIfPresent(Double.self, forKey: .expandedHeight) ?? expandedHeight
        wingWidth = try c.decodeIfPresent(Double.self, forKey: .wingWidth) ?? wingWidth
        collapsedHeight = try c.decodeIfPresent(Double.self, forKey: .collapsedHeight) ?? collapsedHeight
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        verticalOffset = try c.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? verticalOffset
        horizontalOffset = try c.decodeIfPresent(Double.self, forKey: .horizontalOffset) ?? horizontalOffset
        transparency = try c.decodeIfPresent(Double.self, forKey: .transparency) ?? transparency
        glass = try c.decodeIfPresent(Bool.self, forKey: .glass) ?? glass
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? theme
        accentMode = try c.decodeIfPresent(String.self, forKey: .accentMode) ?? accentMode
        red = try c.decodeIfPresent(Double.self, forKey: .red) ?? red
        green = try c.decodeIfPresent(Double.self, forKey: .green) ?? green
        blue = try c.decodeIfPresent(Double.self, forKey: .blue) ?? blue
        textScale = try c.decodeIfPresent(Double.self, forKey: .textScale) ?? textScale
        coverSize = try c.decodeIfPresent(Double.self, forKey: .coverSize) ?? coverSize
        showArtwork = try c.decodeIfPresent(Bool.self, forKey: .showArtwork) ?? showArtwork
        showArtist = try c.decodeIfPresent(Bool.self, forKey: .showArtist) ?? showArtist
        showProgress = try c.decodeIfPresent(Bool.self, forKey: .showProgress) ?? showProgress
        showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? showTime
        showVisualizer = try c.decodeIfPresent(Bool.self, forKey: .showVisualizer) ?? showVisualizer
        animateVisualizer = try c.decodeIfPresent(Bool.self, forKey: .animateVisualizer) ?? animateVisualizer
        hoverEnabled = try c.decodeIfPresent(Bool.self, forKey: .hoverEnabled) ?? hoverEnabled
        hoverDelay = try c.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? hoverDelay
        collapseDelay = try c.decodeIfPresent(Double.self, forKey: .collapseDelay) ?? collapseDelay
        clickPins = try c.decodeIfPresent(Bool.self, forKey: .clickPins) ?? clickPins
        animations = try c.decodeIfPresent(Bool.self, forKey: .animations) ?? animations
        spring = try c.decodeIfPresent(Bool.self, forKey: .spring) ?? spring
        animationSpeed = try c.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? animationSpeed
        screenID = try c.decodeIfPresent(String.self, forKey: .screenID) ?? screenID
        lockEnabled = try c.decodeIfPresent(Bool.self, forKey: .lockEnabled) ?? lockEnabled
        lockArtwork = try c.decodeIfPresent(Bool.self, forKey: .lockArtwork) ?? lockArtwork
        lockArtworkSize = try c.decodeIfPresent(Double.self, forKey: .lockArtworkSize) ?? lockArtworkSize
        lockWidth = try c.decodeIfPresent(Double.self, forKey: .lockWidth) ?? lockWidth
        lockOffset = try c.decodeIfPresent(Double.self, forKey: .lockOffset) ?? lockOffset
        lockOpacity = try c.decodeIfPresent(Double.self, forKey: .lockOpacity) ?? lockOpacity
        refreshInterval = try c.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? refreshInterval
        mediaSource = try c.decodeIfPresent(String.self, forKey: .mediaSource) ?? mediaSource
        lyricsEnabled = try c.decodeIfPresent(Bool.self, forKey: .lyricsEnabled) ?? lyricsEnabled
        shelfEnabled = try c.decodeIfPresent(Bool.self, forKey: .shelfEnabled) ?? shelfEnabled
        powerEnabled = try c.decodeIfPresent(Bool.self, forKey: .powerEnabled) ?? powerEnabled
        airpodsEnabled = try c.decodeIfPresent(Bool.self, forKey: .airpodsEnabled) ?? airpodsEnabled
        hudEnabled = try c.decodeIfPresent(Bool.self, forKey: .hudEnabled) ?? hudEnabled
        replaceSystemHUD = try c.decodeIfPresent(Bool.self, forKey: .replaceSystemHUD) ?? replaceSystemHUD
    }
}
