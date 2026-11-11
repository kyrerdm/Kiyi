//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    let updaterController: SPUStandardUpdaterController?
    @State private var page = KiyiSettingsPage.appearance
    @State private var query = ""
    @Default(.kiyiLanguage) private var languageCode
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var calendars = CalendarManager.shared
    @ObservedObject private var shares = QuickShareService.shared
    @Default(.mediaController) private var source
    @Default(.hideNotchOption) private var fullscreen
    @Default(.minimumHoverDuration) private var hoverDelay
    @Default(.gestureSensitivity) private var sensitivity
    @Default(.quickShareProvider) private var shareProvider
    @Default(.adaLockCoverSize) private var lockCover
    @Default(.adaLockCardWidth) private var lockWidth
    @Default(.adaLockOpacity) private var lockOpacity
    @Default(.notchHeightMode) private var notchMode
    @Default(.nonNotchHeightMode) private var plainMode
    @Default(.notchHeight) private var notchHeight
    @Default(.nonNotchHeight) private var plainHeight
    @Default(.sliderColor) private var sliderColor
    @Default(.mirrorShape) private var mirrorShape
    @Default(.optionKeyAction) private var optionAction
    @Default(.waitInterval) private var idleDelay
    @Default(.useCustomAccentColor) private var customColor
    @State private var accent = Color.effectiveAccent

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image("logo2").resizable().frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kıyı").font(.system(size: 23, weight: .bold, design: .rounded))
                        Text("Sana göre şekillenir.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
                TextField("Ayarlarda ara", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Ayarlar arasında ara")
                VStack(spacing: 5) {
                    ForEach(KiyiSettingsPage.allCases.filter { query.isEmpty || $0.search.localizedCaseInsensitiveContains(query) }) { item in
                        Button { page = item } label: {
                            HStack(spacing: 11) {
                                Image(systemName: item.symbol).frame(width: 20)
                                Text(KiyiL(item.rawValue)).fontWeight(page == item ? .semibold : .regular)
                                Spacer()
                                if page == item { Circle().fill(Color.effectiveAccent).frame(width: 5, height: 5) }
                            }
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .foregroundStyle(page == item ? Color.primary : Color.secondary)
                            .background(page == item ? Color.effectiveAccent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 11))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                    }
                    if !query.isEmpty && !KiyiSettingsPage.allCases.contains(where: { $0.search.localizedCaseInsensitiveContains(query) }) {
                        Text("Eşleşen bölüm yok").foregroundStyle(.secondary).padding()
                    }
                }
                Spacer()
                Text("kyrerdm · Kıyı").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            }
            .padding(22).frame(width: 224)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(KiyiL(page.rawValue)).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(KiyiL(page.subtitle)).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 6)
                    content
                    Text("Değişiklikler otomatik kaydedilir.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }.padding(30).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .id(page)
        }
        .frame(minWidth: 880, minHeight: 640)
        .environment(\.locale, Locale(identifier: languageCode))
        .font(.system(size: 13))
        .tint(.effectiveAccent)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await shares.discoverAvailableProviders() }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .appearance:
            card("Boyut, yüzey ve kapak", "rectangle.topthird.inset.filled") { AdaAppearanceSettings() }
            card("Renk ve ayrıntılar", "paintpalette") {
                Toggle("Sistem yerine kendi vurgu rengimi kullan", isOn: $customColor)
                if customColor {
                    ColorPicker("Vurgu rengi", selection: $accent, supportsOpacity: false)
                        .onChange(of: accent) { _, color in
                            Defaults[.customAccentColorData] = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(color), requiringSecureCoding: false)
                            NotificationCenter.default.post(name: NSNotification.Name("AccentColorChanged"), object: nil)
                        }
                }
                Defaults.Toggle(key: .enableShadow) { Text("Panel gölgesi") }
                Defaults.Toggle(key: .cornerRadiusScaling) { Text("Açık panelde yuvarlak köşeler") }
                Defaults.Toggle(key: .settingsIconInNotch) { Text("Çentikte ayarlar düğmesi") }
                Defaults.Toggle(key: .playerColorTinting) { Text("Albüm rengine uygun oynatıcı") }
                Defaults.Toggle(key: .lightingEffect) { Text("Kapak arkasında yumuşak ışık") }
                Defaults.Toggle(key: .coloredSpectrogram) { Text("Renkli ses animasyonu") }
                Picker("Oynatıcı çubuğu rengi", selection: $sliderColor) {
                    Text("Beyaz").tag(SliderColorEnum.white)
                    Text("Albüm kapağı").tag(SliderColorEnum.albumArt)
                    Text("Vurgu rengi").tag(SliderColorEnum.accent)
                }
                Toggle("Ana ekran ve raf sekmelerini göster", isOn: $coordinator.alwaysShowTabs)
            }
        case .general:
            card("Dil", "globe") {
                Picker("Uygulama dili", selection: $languageCode) {
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Deutsch").tag("de")
                }
                .onChange(of: languageCode) { _, code in
                    UserDefaults.standard.set([code], forKey: "AppleLanguages")
                    NotificationCenter.default.post(name: Notification.Name("kiyi.languageChanged"), object: nil)
                }
                Text("Dil değişince Kıyı yeniden açılır; ayarların korunur.").font(.callout).foregroundStyle(.secondary)
            }
            card("Mac ile birlikte", "desktopcomputer") {
                LaunchAtLogin.Toggle { Text("Oturum açınca Kıyı’yı başlat") }
                Defaults.Toggle(key: .menubarIcon) { Text("Menü çubuğunda Kıyı simgesi") }
                Defaults.Toggle(key: .showOnAllDisplays) { Text("Tüm ekranlarda göster") }
                Defaults.Toggle(key: .automaticallySwitchDisplay) { Text("Etkin ekranı takip et") }
                Picker("Tercih edilen ekran", selection: $coordinator.preferredScreenUUID) {
                    ForEach(NSScreen.screens, id: \.displayUUID) { screen in
                        Text(screen.localizedName).tag(screen.displayUUID)
                    }
                }
                Text("Ayarlar açıkken Dock simgesi görünür. ⌘Q ayarları kapatır; tam çıkış menü çubuğundandır.").foregroundStyle(.secondary).font(.callout)
            }
            card("Etkileşim", "hand.draw") {
                Defaults.Toggle(key: .openNotchOnHover) { Text("Fareyle üzerine gelince aç") }
                Slider(value: $hoverDelay, in: 0...1, step: 0.05) { Text("Açılma beklemesi · \(hoverDelay.formatted(.number.locale(Locale(identifier: languageCode)))) sn") }
                Defaults.Toggle(key: .enableHaptics) { Text("Dokunsal geri bildirim") }
                Defaults.Toggle(key: .enableGestures) { Text("Trackpad hareketleri") }
                Defaults.Toggle(key: .closeGestureEnabled) { Text("Yukarı kaydırınca kapat") }
                Slider(value: $sensitivity, in: 50...500) { Text("Hareket eşiği") }
                Picker("Tam ekranda", selection: $fullscreen) {
                    Text("Daima gizle").tag(HideNotchOption.always)
                    Text("Medya uygulamasında gizle").tag(HideNotchOption.nowPlayingOnly)
                    Text("Görünür kalsın").tag(HideNotchOption.never)
                }
                Defaults.Toggle(key: .hideFromScreenRecording) { Text("Ekran kaydında paneli gizle") }
                Defaults.Toggle(key: .hideTitleBar) { Text("Üst pencere başlık alanını koru") }
            }
            card("Ekrana uyum", "display") {
                Picker("Çentikli ekran yüksekliği", selection: $notchMode) {
                    Text("Fiziksel çentik").tag(WindowHeightMode.matchRealNotchSize)
                    Text("Menü çubuğu").tag(WindowHeightMode.matchMenuBar)
                    Text("Özel").tag(WindowHeightMode.custom)
                }
                Slider(value: $notchHeight, in: 20...50) { Text("Özel çentik yüksekliği") }
                Picker("Çentiksiz ekran yüksekliği", selection: $plainMode) {
                    Text("Menü çubuğu").tag(WindowHeightMode.matchMenuBar)
                    Text("Özel").tag(WindowHeightMode.custom)
                }
                Slider(value: $plainHeight, in: 20...50) { Text("Özel çentiksiz yükseklik") }
            }
        case .music:
            card("Oynatma", "music.note") {
                Picker("Müzik kaynağı", selection: $source) {
                    Text("Spotify").tag(MediaControllerType.spotify)
                    Text("Apple Music").tag(MediaControllerType.appleMusic)
                    if !MusicManager.shared.isNowPlayingDeprecated { Text("Sistem oynatıcısı").tag(MediaControllerType.nowPlaying) }
                    Text("YouTube Music").tag(MediaControllerType.youtubeMusic)
                }.onChange(of: source) { _, _ in NotificationCenter.default.post(name: .mediaControllerChanged, object: nil) }
                Toggle("Kapalı adada müzik bilgisi", isOn: $coordinator.musicLiveActivityEnabled)
                Defaults.Toggle(key: .enableSneakPeek) { Text("Şarkı değişiminde bildirim kartı") }
                Defaults.Toggle(key: .enableLyrics) { Text("Şarkı sözleri") }
                Slider(value: $idleDelay, in: 0...10, step: 1) {
                    Text("Duraklatınca gizleme beklemesi · \(Int(idleDelay)) sn")
                }
                Text("Bildirim boyutları ve şeffaflığı Görünüm bölümünde ayarlanır. Şarkı sözleri kaynağın ve parçanın desteğine bağlıdır.").font(.callout).foregroundStyle(.secondary)
            }
            card("Oynatıcı düğmeleri", "slider.horizontal.3") { MusicSlotConfigurationView() }
            card("Klavye kestirmeleri", "keyboard") {
                KeyboardShortcuts.Recorder("Adanın açılıp kapanması", name: .toggleNotchOpen)
                KeyboardShortcuts.Recorder("Şarkı bilgisini göster", name: .toggleSneakPeek)
            }
        case .system:
            card("Ses ve parlaklık", "sun.max") {
                Defaults.Toggle(key: .hudReplacement) { Text("Sistem göstergelerini Kıyı’da göster") }
                HStack {
                    Label(KiyiL(MediaKeyInterceptor.shared.isAuthorized ? "Erişim izni verilmiş" : "Erişim izni gerekli"), systemImage: MediaKeyInterceptor.shared.isAuthorized ? "checkmark.circle" : "lock")
                    Spacer()
                    Button("İzni yönet") { MediaKeyInterceptor.shared.requestAccessibilityAuthorization() }
                }
                Defaults.Toggle(key: .inlineHUD) { Text("Göstergeyi çentiğin iki yanında göster") }
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) { Text("Kapalı adada yüzde") }
                Defaults.Toggle(key: .showOpenNotchHUD) { Text("Açık panelde göster") }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) { Text("Açık panelde yüzde") }
                Defaults.Toggle(key: .enableGradient) { Text("Geçişli dolgu") }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) { Text("Dolguya vurgu rengini uygula") }
                Defaults.Toggle(key: .systemEventIndicatorShadow) { Text("Hafif parlama") }
                Picker("Option tuşuyla ses/parlaklık", selection: $optionAction) {
                    Text("Sistem Ayarları’nı aç").tag(OptionKeyAction.openSettings)
                    Text("Göstergeyi aç").tag(OptionKeyAction.showHUD)
                    Text("İşlem yapma").tag(OptionKeyAction.none)
                }
            }
            card("Pil", "battery.100") {
                Defaults.Toggle(key: .showBatteryIndicator) { Text("Pil simgesi") }
                Defaults.Toggle(key: .showBatteryPercentage) { Text("Pil yüzdesi") }
                Defaults.Toggle(key: .showPowerStatusIcons) { Text("Şarj durumu simgeleri") }
                Defaults.Toggle(key: .showPowerStatusNotifications) { Text("Şarja takılınca bildirim") }
            }
        case .lock:
            card("Kilit ekranındaki müzik", "lock") {
                Defaults.Toggle(key: .adaLockMusic) { Text("Kilit ekranında kartı göster") }
                Defaults.Toggle(key: .adaLockHideIdle) { Text("Parça yokken kartı gizle") }
                Defaults.Toggle(key: .adaLockArtwork) { Text("Albüm kapağı") }
                Defaults.Toggle(key: .adaLockArtworkBackdrop) { Text("Kapak büyüyünce bulanık arka plan") }
                Defaults.Toggle(key: .adaLockLyrics) { Text("Şarkı sözleri") }
                AdaSettingSlider("Kapak boyutu", value: $lockCover, range: 120...280, step: 5)
                AdaSettingSlider("Kart genişliği", value: $lockWidth, range: 300...480, step: 5)
                AdaSettingSlider("Kart koyuluğu", value: $lockOpacity, range: 0...1, step: 0.05, percent: true)
                Button("Masaüstünde önizle") { AdaLockScreen.shared.preview() }.buttonStyle(.bordered)
                Text("Kullanıcı oturumu kilitlendiğinde çalışır. Kapağa tıklayarak büyük görünümü açabilirsin.").font(.callout).foregroundStyle(.secondary)
            }
        case .shelf:
            card("Dosyalar ve paylaşım", "tray") {
                Defaults.Toggle(key: .boringShelf) { Text("Dosya rafını aç") }
                Defaults.Toggle(key: .openShelfByDefault) { Text("Dosya varsa doğrudan rafı aç") }
                Defaults.Toggle(key: .shelfTapToOpen) { Text("Dokununca dosyayı aç") }
                Defaults.Toggle(key: .copyOnDrag) { Text("Sürüklerken kopyala") }
                Defaults.Toggle(key: .autoRemoveShelfItems) { Text("Sürükleme sonrası raftan kaldır") }
                Defaults.Toggle(key: .expandedDragDetection) { Text("Geniş sürükleme algılama alanı") }
                    .onChange(of: Defaults[.expandedDragDetection]) { _, _ in NotificationCenter.default.post(name: .expandedDragDetectionChanged, object: nil) }
                Picker("Hızlı paylaşım", selection: $shareProvider) {
                    ForEach(shares.availableProviders, id: \.id) { provider in Text(provider.id).tag(provider.id) }
                }
                Text("AirDrop ve diğer paylaşım hedefleri macOS paylaşım menüsünden seçilir.").font(.callout).foregroundStyle(.secondary)
            }
        case .extras:
            card("Kulaklıklar", "airpodspro") { AdaAirPodsView() }
            card("Takvim ve hatırlatıcılar", "calendar") {
                Defaults.Toggle(key: .showCalendar) { Text("Takvimi adada göster") }
                Defaults.Toggle(key: .hideCompletedReminders) { Text("Tamamlanan hatırlatıcıları gizle") }
                Defaults.Toggle(key: .hideAllDayEvents) { Text("Tüm gün etkinliklerini gizle") }
                Defaults.Toggle(key: .autoScrollToNextEvent) { Text("Sıradaki etkinliğe kaydır") }
                Defaults.Toggle(key: .showFullEventTitles) { Text("Etkinlik başlığını tam göster") }
                Button("Takvim ve hatırlatıcı izinlerini iste") {
                    Task { await calendars.checkCalendarAuthorization(); await calendars.checkReminderAuthorization() }
                }
                ForEach(calendars.eventCalendars + calendars.reminderLists, id: \.id) { calendar in
                    Toggle(calendar.title, isOn: Binding(get: { calendars.getCalendarSelected(calendar) }, set: { value in Task { await calendars.setCalendarSelected(calendar, isSelected: value) } }))
                }
            }
            card("Ayna", "web.camera") {
                Defaults.Toggle(key: .showMirror) { Text("Kamera aynasını göster") }
                Picker("Ayna şekli", selection: $mirrorShape) {
                    Text("Dikdörtgen").tag(MirrorShapeEnum.rectangle)
                    Text("Daire").tag(MirrorShapeEnum.circle)
                }
                Text("Ayna için macOS kamera izni gerekir. Kamera yalnız ayna açıldığında kullanılır.").font(.callout).foregroundStyle(.secondary)
            }
        case .about:
            card("Kıyı", "water.waves") {
                HStack(spacing: 18) {
                    Image("logo2").resizable().frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ekranının kıyısında.").font(.system(size: 21, weight: .semibold, design: .rounded))
                        Text("Tasarım ve geliştirme · kyrerdm").foregroundStyle(.secondary)
                        Text("Sürüm \(appVersion)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Link("kyrerdm / Kiyi · Kaynak kodu", destination: URL(string: "https://github.com/kyrerdm/Kiyi")!)
                Link("GitHub · kyrerdm", destination: URL(string: "https://github.com/kyrerdm")!)
            }
            card("Açık kaynak ve lisanslar", "curlybraces") {
                Text("Kıyı, TheBoredTeam / Boring Notch kaynak kodu üzerine geliştirilmiştir. Kıyı’ya ait arayüz ve ek özellikler kyrerdm tarafından hazırlanır. Özgün katkı sahiplerinin telif bildirimleri ve GPL-3.0 lisansı korunur.")
                    .foregroundStyle(.secondary).textSelection(.enabled)
                Link("Boring Notch · Özgün proje", destination: URL(string: "https://github.com/TheBoredTeam/boring.notch")!)
                Link("Kıyı lisansı ve kaynak bildirimleri", destination: URL(string: "https://github.com/kyrerdm/Kiyi/blob/main/LICENSE")!)
            }
        }
    }

    private func card<C: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(KiyiL(title), systemImage: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.effectiveAccent)
            VStack(alignment: .leading, spacing: 15, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .toggleStyle(KiyiSettingsToggleStyle())
        .onAppear { accent = .effectiveAccent }
    }
}

private enum KiyiSettingsPage: String, CaseIterable, Identifiable {
    case appearance = "Görünüm", general = "Davranış", music = "Müzik", system = "Sistem", lock = "Kilit ekranı", shelf = "Dosya rafı", extras = "Bağlantılar", about = "Kıyı hakkında"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .appearance: "paintbrush.pointed"
        case .general: "cursorarrow.motionlines"
        case .music: "music.note"
        case .system: "slider.horizontal.3"
        case .lock: "lock"
        case .shelf: "tray"
        case .extras: "square.stack.3d.up"
        case .about: "water.waves"
        }
    }
    var subtitle: String {
        switch self {
        case .appearance: "Boyutları, yüzeyi ve bildirimlerini kendi ritmine uyarla."
        case .general: "Kıyı’nın ne zaman ve nasıl görüneceğini belirle."
        case .music: "Şarkıların, oynatıcın ve elinin altındaki kontroller."
        case .system: "Ses, parlaklık ve pil bilgisi; ihtiyacın olduğunda."
        case .lock: "Müziğin kilit ekranında da seninle."
        case .shelf: "Dosyalarını kısa süreliğine bırak, sürükle ve paylaş."
        case .extras: "Kulaklıklarını, takvimini ve kameranı Kıyı’ya bağla."
        case .about: "kyrerdm tarafından geliştirilen kişisel macOS yardımcı uygulaması."
        }
    }
    var search: String { KiyiL(rawValue) + " " + KiyiL(subtitle) + (self == .general ? " language Sprache dil " : "") + (self == .system ? " ses parlaklık pil izin" : self == .appearance ? " renk tema şeffaflık kapak bildirim" : self == .extras ? " airpods takvim kamera" : "") }
}



private struct KiyiSettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 18) {
            configuration.label.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
