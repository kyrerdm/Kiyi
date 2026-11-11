import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IOKit.ps

final class Shelf: ObservableObject {
    static let shared = Shelf()
    @Published var files: [URL] = []
    func add(_ urls: [URL]) { for url in urls where url.isFileURL && !files.contains(url) { if files.count < 30 { files.append(url) } } }
    func choose() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true
        if p.runModal() == .OK { add(p.urls) }
    }
    func accept(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in guard let url = url else { return }; DispatchQueue.main.async { self.add([url]) } }
        }
        return true
    }
}
struct ShelfView: View {
    @ObservedObject var shelf = Shelf.shared
    @State private var targeted = false
    var body: some View {
        HStack(spacing: 10) {
            AirDropZone()
            VStack(spacing: 8) {
            if shelf.files.isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                Text("Dosyaları buraya bırak").font(.system(size: 12, weight: .medium))
                Text("Dosyalar taşınmaz veya kopyalanmaz.").font(.system(size: 9)).foregroundStyle(.secondary)
                Button("Dosya seç…") { shelf.choose() }.controlSize(.small)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(shelf.files, id: \.self) { url in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                                Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                                Spacer()
                                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }.help("Finder’da göster")
                                Button { AirDropShare.shared.present([url]) } label: { Image(systemName: "airplayaudio") }.help("AirDrop")
                                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                Button { shelf.files.removeAll { $0 == url } } label: { Image(systemName: "xmark") }.help("Raftan kaldır")
                            }.buttonStyle(.plain).padding(6).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        }
                    }
                }
                HStack { Text("\(shelf.files.count) dosya").font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Ekle…") { shelf.choose() }.controlSize(.mini) }
            }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 5])))
        }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(targeted ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .onDrop(of: [.fileURL], isTargeted: $targeted, perform: shelf.accept)
    }
}
struct LyricLine: Identifiable { let id: Int; let time: Double; let text: String }
final class Lyrics: ObservableObject {
    @Published var lines: [LyricLine] = []
    @Published var status = "Sözler kapalı"
    private var key = ""
    private var task: URLSessionDataTask?
    private var cache: [String: [LyricLine]] = [:]
    private var blockedUntil = Date.distantPast
    static func parse(_ value: String) -> [LyricLine] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var found: [(Double, String)] = []
        for raw in value.components(separatedBy: .newlines) {
            let text = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: text.length))
            guard let last = matches.last else { continue }
            let lyric = text.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let t = (Double(text.substring(with: m.range(at: 1))) ?? 0) * 60 + (Double(text.substring(with: m.range(at: 2))) ?? 0)
                found.append((t, lyric))
            }
        }
        return found.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
    func load(title: String, artist: String, duration: Double, enabled: Bool) {
        let next = enabled ? "\(title)|\(artist)" : ""
        guard next != key else { return }
        task?.cancel(); key = next; lines = []
        guard enabled else { status = "Sözleri Ayarlar → Müzik’ten açabilirsin."; return }
        if let cached = cache[next] { lines = cached; status = cached.isEmpty ? "Bu şarkı için söz bulunamadı." : ""; return }
        guard duration > 0 else { status = "Bir şarkı başlat."; key = ""; return }
        guard Date() > blockedUntil else { status = "Söz sağlayıcısı dinleniyor. Biraz sonra tekrar dene."; return }
        status = "Sözler yükleniyor…"
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "duration", value: String(Int(duration)))]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 15
        request.setValue("Ada/0.3 (personal macOS lyrics client)", forHTTPHeaderField: "User-Agent")
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.key == next else { return }
                guard error == nil else { self.status = "Söz bağlantısı kurulamadı."; return }
                let http = response as? HTTPURLResponse
                if http?.statusCode == 429 || http?.statusCode == 503 {
                    self.blockedUntil = Date().addingTimeInterval(Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
                    self.status = "Söz sağlayıcısı meşgul."; return
                }
                guard http?.statusCode == 200, let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { self.status = "Bu şarkı için söz bulunamadı."; self.cache[next] = []; return }
                if let synced = json["syncedLyrics"] as? String { self.lines = Self.parse(synced) }
                if self.lines.isEmpty, let plain = json["plainLyrics"] as? String { self.lines = plain.components(separatedBy: .newlines).enumerated().map { LyricLine(id: $0.offset, time: -1, text: $0.element) } }
                if self.cache.count > 40 { self.cache.removeAll() }; self.cache[next] = self.lines
                self.status = self.lines.isEmpty ? "Bu şarkı için söz bulunamadı." : ""
            }
        }; task?.resume()
    }
}
struct LyricsView: View {
    @ObservedObject var media: Spotify
    @EnvironmentObject var prefs: Preferences
    @StateObject private var lyrics = Lyrics()
    var body: some View {
        Group {
            if lyrics.lines.isEmpty { Text(lyrics.status).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding() }
            else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let current = lyrics.lines.last(where: { $0.time <= media.elapsed(context.date) })?.id ?? 0
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(lyrics.lines) { line in
                                    Text(line.text.isEmpty ? "♪" : line.text).font(.system(size: 14, weight: line.id == current ? .semibold : .regular))
                                        .foregroundStyle(line.id == current ? .primary : .secondary).id(line.id)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.onChange(of: current) { _, value in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) } }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: load).onChange(of: media.title) { _, _ in load() }.onChange(of: prefs.value.lyricsEnabled) { _, _ in load() }
    }
    func load() { lyrics.load(title: media.title, artist: media.artist, duration: media.duration, enabled: prefs.value.lyricsEnabled) }
}
final class PowerStatus: ObservableObject {
    static let shared = PowerStatus()
    @Published var percent = 0
    @Published var charging = false
    private var source: CFRunLoopSource?
    init() {
        refresh()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerStatus>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { monitor.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source = source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }
    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let current = d[kIOPSCurrentCapacityKey] as? Int, let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            percent = current * 100 / maximum; charging = d[kIOPSIsChargingKey] as? Bool ?? false
        }
    }
}
struct IslandFooter: View {
    @ObservedObject var state: IslandState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var power = PowerStatus.shared
    var body: some View {
        HStack(spacing: 14) {
            page("music", "music.note", "Müzik")
            if prefs.value.shelfEnabled { page("shelf", "tray", "Dosya rafı") }
            page("lyrics", "quote.bubble", "Şarkı sözleri")
            Spacer()
            if prefs.value.powerEnabled { Label("\(power.percent)%", systemImage: power.charging ? "battery.100.bolt" : "battery.75").font(.system(size: 9)).foregroundStyle(.secondary) }
            Button { state.settings?() } label: { Image(systemName: "gearshape").font(.system(size: 11)) }.buttonStyle(.plain).help("Ayarlar")
            Button { state.close?() } label: { Image(systemName: "chevron.up").font(.system(size: 10)) }.buttonStyle(.plain).help("Kapat")
        }.padding(.horizontal, 16).frame(height: 24)
    }
    func page(_ name: String, _ icon: String, _ label: String) -> some View {
        Button { state.page = name } label: { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(state.page == name ? prefs.accent : .secondary) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct IslandHeader: View {
    @ObservedObject var state: IslandState
    @ObservedObject var power = PowerStatus.shared
    @EnvironmentObject var prefs: Preferences
    var notch: CGFloat
    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                tab("music", "house.fill", "Müzik")
                if prefs.value.shelfEnabled { tab("shelf", "tray.fill", "Dosya rafı") }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notch)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button { state.settings?() } label: { Image(systemName: "gearshape").font(.system(size: 10)) }.buttonStyle(.plain).help("Ayarlar")
                if prefs.value.powerEnabled && geometry.size.width - notch > 140 { Text("\(power.percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit() }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 12).frame(height: geometry.size.height)
        }
    }
    func tab(_ value: String, _ icon: String, _ label: String) -> some View {
        Button { state.page = value } label: { Image(systemName: icon).font(.system(size: 11)).frame(width: 19, height: 21).background(state.page == value ? .white.opacity(0.08) : .clear, in: Capsule()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
final class AirDropShare {
    static let shared = AirDropShare()
    private var service: NSSharingService?
    func present(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            let alert = NSAlert(); alert.messageText = "AirDrop kullanılamıyor"; alert.informativeText = "Wi-Fi ve Bluetooth bağlantısını kontrol et."; alert.runModal(); return
        }
        self.service = service; service.perform(withItems: urls)
    }
    func choose() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { present(panel.urls) }
    }
    func accept(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup(); var urls: [URL] = []; let lock = NSLock()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                lock.lock(); if let url = url { urls.append(url) }; lock.unlock(); group.leave()
            }
        }
        group.notify(queue: .main) { self.present(urls) }; return true
    }
}
struct AirDropZone: View {
    @State private var targeted = false
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .light)).frame(width: 40, height: 40).background(.primary.opacity(0.05), in: Circle())
            Text("AirDrop").font(.system(size: 11, weight: .medium))
        }.frame(width: 82).frame(maxHeight: .infinity)
            .background(targeted ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 5])))
            .contentShape(Rectangle()).onTapGesture { AirDropShare.shared.choose() }
            .onDrop(of: [.fileURL], isTargeted: $targeted, perform: AirDropShare.shared.accept)
            .help("Tıkla veya dosya bırak; ardından AirDrop alıcısını seç")
    }
}
